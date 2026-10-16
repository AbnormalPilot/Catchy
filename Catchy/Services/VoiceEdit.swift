import Foundation

/// Applies a spoken change ("make it 6 pm", "move it to Friday", "at the Starbucks in Bandra",
/// "call it Physics class") to a draft, without the language model. Only what's mentioned changes.
enum VoiceEdit {
    struct Result {
        var draft: EventDraft
        /// What changed, for the "Changed time and place" line.
        var changed: [String]
    }

    static func apply(_ utterance: String, to draft: EventDraft, now: Date = .now) -> Result {
        var draft = draft
        var changed: [String] = []
        let text = TextCleanup.normalized(utterance.trimmingCharacters(in: .whitespacesAndNewlines))
        let lower = text.lowercased()

        // Kind.
        if lower.range(of: #"\b(make|turn|change|set|switch)\b.*\b(reminder|task|to-?do)\b"#, options: .regularExpression) != nil {
            if draft.kind != .task { draft.kind = .task; changed.append("type") }
        } else if lower.range(of: #"\b(make|turn|change|set|switch)\b.*\b(event|meeting|calendar)\b"#, options: .regularExpression) != nil {
            if draft.kind != .event { draft.kind = .event; changed.append("type") }
        }

        // Title: "call it …", "rename it to …", "title is …".
        if let title = capture(#"(?i)\b(?:call it|name it|rename(?: it)?(?: to)?|change the (?:title|name) to|title(?: it| is)?)\s+(.+?)\s*(?:[.,;]|$)"#, in: text) {
            draft.title = DateHints.tidy(title)
            changed.append("title")
        }

        // Place: "location is …", "move it to …" (when it's not a day), or "at the Starbucks in Bandra".
        if let place = capture(#"(?i)\b(?:location(?: is| to)?|place(?: is)?|change the (?:location|place) to|venue(?: is)?)\s+(.+?)\s*(?:[.,;]|$)"#, in: text) {
            draft.location = place
            changed.append("place")
        } else if let place = TextCleanup.spokenPlace(in: text) {
            draft.location = place.place
            changed.append("place")
        }

        // Notes: "add a note …", "note: …".
        if let note = capture(#"(?i)\b(?:add (?:a )?note|note)\s*:?\s+(.+)$"#, in: text) {
            draft.notes = draft.notes.isEmpty ? note : draft.notes + "\n" + note
            changed.append("notes")
        }

        // All day on or off.
        if lower.contains("not all day") || lower.contains("not all-day") {
            if draft.isAllDay {
                draft.isAllDay = false
                draft.end = draft.start.addingTimeInterval(3600)
                changed.append("time")
            }
        } else if lower.contains("all day") || lower.contains("all-day") {
            if !draft.isAllDay {
                draft.isAllDay = true
                draft.start = Calendar.current.startOfDay(for: draft.start)
                draft.end = draft.start
                changed.append("time")
            }
        }

        // Day and time. A time alone keeps the day; a day alone keeps the time.
        let hints = DateHints(text: text, now: now)
        let length = DateHints.relativeTimes(in: text, now: now).duration
        // The date detector reads "for 2 hours" as "2 hours from now"; a length isn't a time here.
        // An empty phrase is DateHints' stand-in start for a bare length ("20 mins"); ignore it too.
        let lengthPattern = #"(?i)^(for\s+|in\s+)?(\d+|an?|half an?)\s*(hours?|hrs?|minutes?|mins?)$"#
        let moments = hints.dates.filter {
            !$0.phrase.isEmpty && $0.phrase.range(of: lengthPattern, options: .regularExpression) == nil
        }
        let dayMatch = moments.first { !DateHints.isTimeOnly($0.phrase) }
        let calendar = Calendar.current
        // The clock time, read here rather than by the detector, which skips a bare "at 10".
        // Without am/pm, the reading closest to the card's current time wins.
        var clock = clockTime(in: text, near: draft.isAllDay ? nil : draft.start)
        if clock == nil, let timed = dayMatch?.hasTime == true ? dayMatch : moments.first(where: { $0.hasTime }) {
            clock = calendar.dateComponents([.hour, .minute], from: timed.date)
        }
        if (clock != nil || dayMatch != nil), !lower.contains("all day") {
            let day = calendar.startOfDay(for: dayMatch?.date ?? draft.start)
            var span = draft.isAllDay ? 3600 : max(draft.end.timeIntervalSince(draft.start), 0)
            if let duration = moments.first?.duration, duration > 0 { span = duration }
            let time = clock ?? calendar.dateComponents([.hour, .minute], from: draft.start)
            if clock != nil, draft.isAllDay { draft.isAllDay = false }
            if let start = calendar.date(byAdding: time, to: day) {
                draft.start = start
                draft.end = draft.isAllDay ? start : start.addingTimeInterval(span)
                changed.append(dayMatch == nil ? "time" : (clock == nil ? "day" : "day and time"))
            }
        }

        // Length: "for two hours", "make it 30 minutes".
        if let length, !draft.isAllDay {
            draft.end = draft.start.addingTimeInterval(length.seconds)
            if !changed.contains(where: { $0.contains("time") }) { changed.append("length") }
        }

        // Nothing recognised: a short phrase is most likely a new name ("Physics class"), but never a
        // command or anything with numbers in it ("make it at 10" must not become the title).
        let soundsLikeACommand = lower.range(of: #"^\s*(make|change|move|set|put|push|shift|turn|switch|it's|its|at|to|from|on|in|for|by)\b"#,
                                             options: .regularExpression) != nil
        if changed.isEmpty, !soundsLikeACommand, text.rangeOfCharacter(from: .decimalDigits) == nil,
           text.split(separator: " ").count <= 6 {
            let title = TextCleanup.spokenTitle(text)
            if !title.isEmpty {
                draft.title = DateHints.tidy(title)
                changed.append("title")
            }
        }

        return Result(draft: draft, changed: changed)
    }

    /// "Changed time and place".
    static func summary(_ changed: [String]) -> String {
        let unique = changed.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !unique.isEmpty else { return "Didn't catch a change. Try \"make it 6 pm\"." }
        let list = unique.count == 1 ? unique[0] : unique.dropLast().joined(separator: ", ") + " and " + unique.last!
        return "Changed " + list
    }

    /// "at 10", "make it 10:30", "change it to 7", "10 pm" → hour and minute. Without am/pm the
    /// reading (morning or evening) nearest `reference` is used; for an all-day card, daytime.
    static func clockTime(in text: String, near reference: Date?) -> DateComponents? {
        let units = #"(?!\s*(?:hours?|hrs?|minutes?|mins?|days?|weeks?|months?|years?|people|guests|percent|%|st|nd|rd|th)\b)"#
        let meridiem = #"(am|pm|a\.m\.|p\.m\.)"#
        let patterns = [
            // After a trigger word: "at 10", "to 7:30", "make it 10", "around 6 pm".
            #"(?i)\b(?:at|to|it|by|around|about)\s+(\d{1,2})(?:[:.](\d{2}))?(?:\s*"# + meridiem + #")?\b"# + units,
            // Anywhere with am/pm: "10 pm", "7:30am".
            #"(?i)\b(\d{1,2})(?:[:.](\d{2}))?\s*"# + meridiem,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let hourRange = Range(match.range(at: 1), in: text), var hour = Int(text[hourRange]) else { continue }
            let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
            guard (0..<60).contains(minute), (0..<24).contains(hour) else { continue }
            if let suffix = Range(match.range(at: 3), in: text).map({ text[$0].lowercased() }) {
                guard (1...12).contains(hour) else { continue }
                hour = hour % 12 + (suffix.hasPrefix("p") ? 12 : 0)
            } else if (1...12).contains(hour) {
                hour = nearestReading(of: hour, minute: minute, to: reference)
            }
            return DateComponents(hour: hour, minute: minute)
        }
        return nil
    }

    private static func nearestReading(of hour: Int, minute: Int, to reference: Date?) -> Int {
        let morning = hour % 12, evening = hour % 12 + 12
        guard let reference else {
            // No current time to go by: 8–11 in the morning, 12 noon, 1–7 in the afternoon/evening.
            return (8...11).contains(hour) || hour == 12 ? (hour == 12 ? 12 : morning) : evening
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: reference)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        func distance(_ h: Int) -> Int {
            let difference = abs(h * 60 + minute - now)
            return min(difference, 24 * 60 - difference)
        }
        return distance(morning) <= distance(evening) ? morning : evening
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }
}
