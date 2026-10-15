import Foundation
import FoundationModels
import OSLog

@Generable(description: "The single main calendar event described by a piece of text")
struct GeneratedEvent {
    @Guide(description: "True only if the text describes something that happens on a specific day")
    var containsEvent: Bool

    @Guide(description: "Short, specific title a person would type into their calendar, in normal capitalization, without the date or time")
    var title: String

    @Guide(description: "Start date as yyyy-MM-dd")
    var startDate: String

    @Guide(description: "Start time as 24-hour HH:mm, or empty if the text gives no time")
    var startTime: String

    @Guide(description: "End date as yyyy-MM-dd, or empty if it ends the same day or is unknown")
    var endDate: String

    @Guide(description: "End time as 24-hour HH:mm, or empty if unknown")
    var endTime: String

    @Guide(description: "Venue name and/or address, or empty")
    var location: String

    @Guide(description: "At most two short lines of useful details such as price, what to bring, or how to RSVP, or empty")
    var notes: String
}

struct ExtractionResult {
    var draft: EventDraft?
    var usedOnDeviceModel: Bool
}

/// Turns raw text into an `EventDraft` using Apple's on-device Foundation Model,
/// falling back to `NSDataDetector` when Apple Intelligence isn't available.
final class EventExtractor {
    private static let instructions = """
        You turn messy text (flyers, chat messages, emails, OCR from screenshots) into one calendar event.
        Pick the main event, not side dates such as "RSVP by" or "tickets on sale".
        The title should be short and specific, like "Spring Fling Potluck" or "Dentist with Dr. Patel". Never write it in all caps.
        Resolve relative dates like "tomorrow" or "this Saturday" against today's date from the prompt.
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
                let draft = try await extractWithModel(clipped, hints: hints, now: now)
                return ExtractionResult(draft: draft, usedOnDeviceModel: true)
            } catch {
                log.error("Model extraction failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return ExtractionResult(draft: hints.fallbackDraft(from: clipped), usedOnDeviceModel: false)
    }

    private func extractWithModel(_ text: String, hints: DateHints, now: Date) async throws -> EventDraft? {
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
            generating: GeneratedEvent.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return Self.draft(from: response.content, text: text, hints: hints, now: now)
    }

    static func draft(from generated: GeneratedEvent, text: String, hints: DateHints, now: Date) -> EventDraft? {
        let calendar = Calendar.current
        guard var day = parseDay(generated.startDate) ?? hints.dates.first.map({ calendar.startOfDay(for: $0.date) }) else {
            return nil
        }
        if !generated.containsEvent && hints.dates.isEmpty { return nil }

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
        let endDay = parseDay(generated.endDate) ?? day
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

        let location = generated.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return EventDraft(
            title: tidyTitle(generated.title),
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: location.isEmpty ? (hints.address ?? "") : location,
            notes: generated.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            url: hints.url
        )
    }

    private static func parseDay(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
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
