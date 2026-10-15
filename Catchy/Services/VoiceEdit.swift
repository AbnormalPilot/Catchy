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
        let lengthPattern = #"(?i)^(for\s+|in\s+)?(\d+|an?|half an?)\s*(hours?|hrs?|minutes?|mins?)$"#
        // An empty phrase is DateHints' stand-in start for a bare length ("20 mins"); ignore it too.
        let moments = hints.dates.filter {
            !$0.phrase.isEmpty && $0.phrase.range(of: lengthPattern, options: .regularExpression) == nil
        }
        if let match = moments.first, !lower.contains("all day") {
            let calendar = Calendar.current
            let keepsDay = DateHints.isTimeOnly(match.phrase) && match.hasTime
            let day = calendar.startOfDay(for: keepsDay ? draft.start : match.date)
            var length = draft.isAllDay ? 3600 : max(draft.end.timeIntervalSince(draft.start), 0)
            if match.duration > 0 { length = match.duration }
            let clock: DateComponents
            if match.hasTime {
                clock = calendar.dateComponents([.hour, .minute], from: match.date)
                if draft.isAllDay { draft.isAllDay = false }
            } else {
                clock = calendar.dateComponents([.hour, .minute], from: draft.start)
            }
            if let start = calendar.date(byAdding: clock, to: day) {
                draft.start = start
                draft.end = draft.isAllDay ? start : start.addingTimeInterval(length)
                changed.append(keepsDay ? "time" : (match.hasTime ? "day and time" : "day"))
            }
        }

        // Length: "for two hours", "make it 30 minutes".
        if let length, !draft.isAllDay {
            draft.end = draft.start.addingTimeInterval(length.seconds)
            if !changed.contains(where: { $0.contains("time") }) { changed.append("length") }
        }

        // Nothing recognised: a short phrase is most likely a new name ("Physics class").
        if changed.isEmpty, text.split(separator: " ").count <= 6 {
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

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }
}
