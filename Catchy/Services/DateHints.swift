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
        /// Set when the text names a zone ("3pm ET"); `date` is already converted to absolute time.
        let timeZone: TimeZone?
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
                let found = DateMatch(date: date, duration: match.duration, phrase: phrase,
                                      hasTime: Self.mentionsTime(phrase), timeZone: match.timeZone)
                // Flyers split "Sat, Oct 24 • 4pm - 9pm" into a date and a time; join them back up.
                if let previous = dates.last, !previous.hasTime, found.hasTime, Self.isTimeOnly(phrase),
                   let merged = Self.combine(day: previous.date, time: date, timeZone: found.timeZone) {
                    dates[dates.count - 1] = DateMatch(date: merged, duration: found.duration,
                                                       phrase: previous.phrase + " " + phrase, hasTime: true,
                                                       timeZone: found.timeZone)
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
        let lines = dates.prefix(8).map { match in
            // Show zoned times in their own zone so they line up with what the text says.
            formatter.timeZone = match.timeZone ?? .current
            formatter.dateFormat = match.hasTime ? "EEEE yyyy-MM-dd HH:mm" : "EEEE yyyy-MM-dd"
            let zone = match.timeZone.map { " (time zone \($0.identifier))" } ?? ""
            return "- \"\(match.phrase)\" = \(formatter.string(from: match.date))\(zone)"
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
            url: url,
            sourceTimeZone: first.hasTime ? first.timeZone.flatMap {
                $0.secondsFromGMT(for: start) == TimeZone.current.secondsFromGMT(for: start) ? nil : $0
            } : nil
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

    /// The calendar day of `day` (as written, so local) at the clock time of `time` (in its own zone).
    private static func combine(day: Date, time: Date, timeZone: TimeZone?) -> Date? {
        var zoned = Calendar.current
        zoned.timeZone = timeZone ?? .current
        let clock = zoned.dateComponents([.hour, .minute], from: time)
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        parts.hour = clock.hour
        parts.minute = clock.minute
        return zoned.date(from: parts)
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
