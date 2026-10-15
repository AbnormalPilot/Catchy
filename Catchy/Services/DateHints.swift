import Foundation

/// Deterministic hints from `NSDataDetector`. They are fed to the language model as
/// already-resolved anchors (models are weak at date math), and are the whole
/// extraction when Apple Intelligence is unavailable.
struct DateHints {
    struct DateMatch {
        let date: Date
        let duration: TimeInterval
        let phrase: String
        let hasTime: Bool
    }

    let dates: [DateMatch]
    /// Every date/time phrase exactly as written, for stripping out of a guessed title.
    let phrases: [String]
    let address: String?
    let url: URL?

    init(text: String) {
        let types: NSTextCheckingResult.CheckingType = [.date, .address, .link]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            dates = []; phrases = []; address = nil; url = nil
            return
        }
        let range = NSRange(text.startIndex..., in: text)
        var dates: [DateMatch] = []
        var phrases: [String] = []
        var address: String?
        var url: URL?
        for match in detector.matches(in: text, range: range) {
            let phrase = Range(match.range, in: text).map { String(text[$0]) } ?? ""
            switch match.resultType {
            case .date:
                guard let date = match.date else { continue }
                phrases.append(phrase)
                let found = DateMatch(date: date, duration: match.duration, phrase: phrase, hasTime: Self.mentionsTime(phrase))
                // Flyers split "Sat, Oct 24 • 4pm - 9pm" into a date and a time; join them back up.
                if let previous = dates.last, !previous.hasTime, found.hasTime, Self.isTimeOnly(phrase),
                   let merged = Self.combine(day: previous.date, time: date) {
                    dates[dates.count - 1] = DateMatch(date: merged, duration: found.duration,
                                                       phrase: previous.phrase + " " + phrase, hasTime: true)
                } else {
                    dates.append(found)
                }
            case .address where address == nil:
                address = phrase.replacingOccurrences(of: "\n", with: ", ")
            case .link where url == nil:
                if let link = match.url, link.scheme?.hasPrefix("http") == true { url = link }
            default:
                break
            }
        }
        self.dates = dates
        self.phrases = phrases
        self.address = address
        self.url = url
    }

    /// Lines appended to the model prompt.
    var promptLines: String {
        guard !dates.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let lines = dates.prefix(6).map { match in
            formatter.dateFormat = match.hasTime ? "EEEE yyyy-MM-dd HH:mm" : "EEEE yyyy-MM-dd"
            return "- \"\(match.phrase)\" = \(formatter.string(from: match.date))"
        }
        return "Date phrases found in the text, already resolved:\n" + lines.joined(separator: "\n")
    }

    /// Best-effort draft without the language model.
    func fallbackDraft(from text: String) -> EventDraft? {
        guard let first = dates.first else { return nil }
        let calendar = Calendar.current
        let start = first.hasTime ? first.date : calendar.startOfDay(for: first.date)
        let end = first.duration > 0 ? start.addingTimeInterval(first.duration) : start.addingTimeInterval(3600)
        return EventDraft(
            title: Self.guessTitle(from: text, skipping: phrases),
            start: start,
            end: first.hasTime ? end : start,
            isAllDay: !first.hasTime,
            location: address ?? "",
            notes: "",
            url: url
        )
    }

    private static func mentionsTime(_ phrase: String) -> Bool {
        let lower = phrase.lowercased()
        if lower.contains("noon") || lower.contains("midnight") { return true }
        return lower.range(of: #"\d\s*(:\d{2}|am|pm|a\.m\.|p\.m\.|h\b)"#, options: .regularExpression) != nil
    }

    private static func isTimeOnly(_ phrase: String) -> Bool {
        let dayWords = #"(mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|today|tomorrow|tonight|\d+\s*/\s*\d+)"#
        return phrase.lowercased().range(of: dayWords, options: .regularExpression) == nil
    }

    private static func combine(day: Date, time: Date) -> Date? {
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day)
    }

    private static func guessTitle(from text: String, skipping phrases: [String]) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            var candidate = String(line)
            for phrase in phrases { candidate = candidate.replacingOccurrences(of: phrase, with: "") }
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if candidate.count >= 3 {
                let title = String(candidate.prefix(60))
                // Flyers shout; calendars don't.
                return title == title.uppercased() ? title.capitalized : title
            }
        }
        return ""
    }
}
