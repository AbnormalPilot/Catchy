import Foundation
import FoundationModels
import OSLog

@Generable
enum GeneratedKind {
    case event
    case task
}

@Generable(description: "One event or task found in the text")
struct GeneratedItem {
    @Guide(description: "event if it happens at a time or on a day; task if it is something to get done by a deadline")
    var kind: GeneratedKind

    @Guide(description: "Short, specific title a person would type into their calendar or to-do list, in normal capitalization, without the date or time")
    var title: String

    @Guide(description: "Start date as yyyy-MM-dd. For a task, the due date")
    var startDate: String

    @Guide(description: "Start time as 24-hour HH:mm, or empty if the text gives no time")
    var startTime: String

    @Guide(description: "End date as yyyy-MM-dd, or empty if it ends the same day or is unknown")
    var endDate: String

    @Guide(description: "End time as 24-hour HH:mm, or empty if unknown")
    var endTime: String

    @Guide(description: "The time zone written next to the time, such as ET, PST, GMT+1 or London, or empty if none is written. Times above stay as written in that zone")
    var timeZone: String

    @Guide(description: "Venue name and/or address, or empty")
    var location: String

    @Guide(description: "At most two short lines of useful details such as price, what to bring, or how to RSVP, or empty")
    var notes: String
}

@Generable(description: "Everything worth adding to a calendar or to-do list in a piece of text")
struct GeneratedCatch {
    @Guide(description: "Each separate event or task with its own date, the main one first. Empty if nothing in the text has a date", .maximumCount(8))
    var items: [GeneratedItem]
}

struct ExtractionResult {
    var drafts: [EventDraft]
    var usedOnDeviceModel: Bool
}

/// Turns raw text into `EventDraft`s using Apple's on-device Foundation Model,
/// falling back to `NSDataDetector` when Apple Intelligence isn't available.
final class EventExtractor {
    private static let instructions = """
        You turn messy text (flyers, chat messages, emails, schedules, OCR from screenshots) into calendar events and tasks.
        A flyer or invitation usually has one event: pick it, not side dates such as "RSVP by" or "tickets on sale".
        A schedule, agenda or syllabus lists several: return each one with its own date.
        Something to get done by a date ("submit the form by Friday", "rent due on the 1st") is a task.
        Titles are short and specific, like "Spring Fling Potluck" or "Dentist with Dr. Patel". Never write them in all caps.
        Resolve relative dates like "tomorrow" or "this Saturday" against today's date from the prompt.
        Write times exactly as the text gives them, and put any time zone the text names in timeZone. Don't convert.
        A length like "20 mins" or "for an hour" sets endTime to the start plus that length. "In 20 mins" is when it starts.
        If no year is given, use the next upcoming occurrence.
        Leave a field empty when the text does not say it. Never invent details.
        OCR text can have broken lines and typos; read through them.
        Text can also be spoken: filler words ("uh", "like"), numbers as words ("five thirty"), and
        self-corrections ("at five, no, six"). Use what the speaker finally meant. "Around five" in the
        evening context means 17:00. Write a clean title, not the speaker's words.
        """

    private let log = Logger(subsystem: "app.catchy.Catchy", category: "extractor")
    private var preparedSession: LanguageModelSession?

    var isModelAvailable: Bool { SystemLanguageModel.default.isAvailable }

    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is off, so Catchy used basic detection."
        case .unavailable(.modelNotReady): "The on-device model is still downloading, so Catchy used basic detection."
        case .unavailable(.deviceNotEligible): "This Mac can't run Apple Intelligence, so Catchy used basic detection."
        case .unavailable: "The on-device model isn't available, so Catchy used basic detection."
        }
    }

    /// Loads the model ahead of time so the first catch feels instant.
    func prewarm() {
        guard isModelAvailable, preparedSession == nil else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        preparedSession = session
    }

    func extract(from text: String, now: Date = .now) async -> ExtractionResult {
        // The model's context window is ~4k tokens; flyers never need more than this.
        let clipped = TextCleanup.normalized(String(text.prefix(3000)))
        let hints = DateHints(text: clipped)

        if isModelAvailable {
            do {
                let drafts = try await extractWithModel(clipped, hints: hints, now: now)
                return ExtractionResult(drafts: drafts, usedOnDeviceModel: true)
            } catch {
                log.error("Model extraction failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return ExtractionResult(drafts: hints.fallbackDrafts(from: clipped), usedOnDeviceModel: false)
    }

    private func extractWithModel(_ text: String, hints: DateHints, now: Date) async throws -> [EventDraft] {
        // A session keeps its transcript, so every catch gets a fresh one.
        let session = preparedSession ?? LanguageModelSession(instructions: Self.instructions)
        preparedSession = nil
        defer { prewarm() }

        let today = now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        let prompt = """
            Today is \(today). Time zone: \(TimeZone.current.identifier).
            \(hints.promptLines)

            Text:
            \"\"\"
            \(text)
            \"\"\"
            """
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedCatch.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return response.content.items.compactMap { Self.draft(from: $0, text: text, hints: hints, now: now) }
    }

    /// Applies a spoken change to a card. The on-device model handles any phrasing; without it,
    /// `VoiceEdit`'s rules cover the common ones.
    func edit(_ draft: EventDraft, by instruction: String, now: Date = .now) async -> VoiceEdit.Result {
        let fallback = VoiceEdit.apply(instruction, to: draft, now: now)
        guard isModelAvailable else { return fallback }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm"
        let kind = draft.kind == .event ? "event" : "task"
        let prompt = """
            Today is \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())).
            Current \(kind):
            title: \(draft.title)
            date: \(day.string(from: draft.start))
            start: \(draft.isAllDay ? "(all day)" : clock.string(from: draft.start))
            end: \(draft.isAllDay ? "(all day)" : "\(day.string(from: draft.end)) \(clock.string(from: draft.end))")
            location: \(draft.location)
            notes: \(draft.notes)

            Spoken change: "\(instruction)"
            Work out which field the change is about from its meaning: "make it at 10" or "push it an hour" is the
            time, "move it to Friday" the day, "at Starbucks" the place, "call it …" the title. Never put the
            spoken command into the title.
            An hour without am/pm means the reading closest to the current start time ("10" for a 21:00 event is 22:00).
            Return the whole \(kind) with only that change applied; keep everything else exactly the same.
            Times are local; leave timeZone empty.
            """
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: prompt, generating: GeneratedItem.self, options: GenerationOptions(sampling: .greedy))
            guard var updated = Self.draft(from: response.content, text: instruction, hints: DateHints(text: ""), now: now) else {
                return fallback
            }
            updated.url = draft.url
            updated.isIncluded = draft.isIncluded
            return VoiceEdit.Result(draft: updated, changed: Self.differences(from: draft, to: updated))
        } catch {
            log.error("Voice edit failed: \(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    private static func differences(from old: EventDraft, to new: EventDraft) -> [String] {
        var changed: [String] = []
        if old.kind != new.kind { changed.append("type") }
        if old.title != new.title { changed.append("title") }
        if !Calendar.current.isDate(old.start, inSameDayAs: new.start) { changed.append("day") }
        if old.start != new.start || old.isAllDay != new.isAllDay { changed.append("time") }
        else if old.end != new.end { changed.append("length") }
        if old.location != new.location { changed.append("place") }
        if old.notes != new.notes { changed.append("notes") }
        return changed
    }

    static func draft(from generated: GeneratedItem, text: String, hints: DateHints, now: Date) -> EventDraft? {
        // Times are as written; read them in the zone the model says the text names. If it gave none,
        // borrow one from the detector only when that zone's phrase has this exact day and time.
        // Otherwise a time the model already converted would be converted twice, and one line's zone
        // would leak onto another event.
        let startTime = parseTime(generated.startTime)
        let writtenZone = TimeZones.resolve(generated.timeZone)
            ?? startTime.flatMap { hints.zone(writtenAt: generated.startDate, $0) }
        let zone = startTime == nil ? nil : writtenZone
        var calendar = Calendar.current
        if let zone { calendar.timeZone = zone }

        guard var day = parseDay(generated.startDate, in: calendar.timeZone)
                ?? hints.dates.first.map({ calendar.startOfDay(for: $0.date) }) else {
            return nil
        }

        // Without an explicit year, a date in the past almost always means next year's.
        let textHasYear = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
        while !textHasYear && day < calendar.startOfDay(for: now).addingTimeInterval(-86_400 * 7),
              let next = calendar.date(byAdding: .year, value: 1, to: day) {
            day = next
        }

        let isAllDay = startTime == nil
        let start = startTime.flatMap { calendar.date(byAdding: $0, to: day) } ?? day

        var end: Date
        let endDay = parseDay(generated.endDate, in: calendar.timeZone) ?? day
        if let endTime = parseTime(generated.endTime), !isAllDay,
           let candidate = calendar.date(byAdding: endTime, to: endDay) {
            // "10pm – 2am" ends the next morning.
            end = candidate > start ? candidate : candidate.addingTimeInterval(86_400)
        } else if isAllDay {
            end = max(endDay, start)
        } else if let duration = hints.dates.first?.duration, duration > 0 {
            end = start.addingTimeInterval(duration)
        } else {
            end = start.addingTimeInterval(3600)
        }
        if end < start { end = start }

        let isTask = generated.kind == .task
        let location = generated.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return EventDraft(
            kind: isTask ? .task : .event,
            title: tidyTitle(generated.title),
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: isTask ? "" : (location.isEmpty ? (hints.address ?? "") : location),
            notes: generated.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            url: hints.url,
            sourceTimeZone: zone.flatMap { $0.secondsFromGMT(for: start) == TimeZone.current.secondsFromGMT(for: start) ? nil : $0 }
        )
    }

    private static func parseDay(_ string: String, in zone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string.trimmingCharacters(in: .whitespaces))
    }

    /// "15:00", and also what models sometimes write instead: "3:00 PM", "3pm", "15:00:00", "9.30".
    static func parseTime(_ string: String) -> DateComponents? {
        let text = string.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: " ", with: "")
        let pattern = #"^(\d{1,2})(?::(\d{2}))?(?::\d{2})?(am|pm|a|p)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              var hour = Int(text[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        if let suffixRange = Range(match.range(at: 3), in: text) {
            guard (1...12).contains(hour) else { return nil }
            let pm = text[suffixRange].hasPrefix("p")
            if pm && hour < 12 { hour += 12 }
            if !pm && hour == 12 { hour = 0 }
        } else if match.range(at: 2).location == NSNotFound {
            return nil  // a bare "3" is too ambiguous to be a time
        }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }

    private static func tidyTitle(_ title: String) -> String {
        DateHints.tidy(title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "!."))))
    }
}
