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
        If no year is given, use the next upcoming occurrence.
        Leave a field empty when the text does not say it. Never invent details.
        OCR text can have broken lines and typos; read through them.
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
        let clipped = String(text.prefix(3000))
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

    static func draft(from generated: GeneratedItem, text: String, hints: DateHints, now: Date) -> EventDraft? {
        // Times are as written; read them in the zone the text names, if any.
        let hasTime = parseTime(generated.startTime) != nil
        let writtenZone = TimeZones.resolve(generated.timeZone)
            ?? hints.dates.first(where: { $0.hasTime && $0.timeZone != nil })?.timeZone
        let zone = hasTime ? writtenZone : nil
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

        let startTime = parseTime(generated.startTime)
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

    private static func parseTime(_ string: String) -> DateComponents? {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return DateComponents(hour: parts[0], minute: parts[1])
    }

    private static func tidyTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "!.")))
        return trimmed == trimmed.uppercased() ? trimmed.capitalized : trimmed
    }
}
