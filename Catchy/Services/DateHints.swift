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
        /// Which line of the text it came from, for pairing dates with titles in a schedule.
        let line: Int
    }

    let dates: [DateMatch]
    /// Every date/time phrase exactly as written, for stripping out of a guessed title.
    let phrases: [String]
    let address: String?
    let url: URL?
    private let lines: [String]

    init(text: String) {
        lines = text.components(separatedBy: .newlines)
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
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let phrase = String(text[swiftRange])
            switch match.resultType {
            case .date:
                guard let date = match.date else { continue }
                phrases.append(phrase)
                let line = text[..<swiftRange.lowerBound].reduce(0) { $1.isNewline ? $0 + 1 : $0 }
                let found = DateMatch(date: date, duration: match.duration, phrase: phrase,
                                      hasTime: Self.mentionsTime(phrase), timeZone: match.timeZone, line: line)
                // Flyers split "Sat, Oct 24 • 4pm - 9pm" into a date and a time; join them back up.
                if let previous = dates.last, !previous.hasTime, found.hasTime, Self.isTimeOnly(phrase),
                   line - previous.line <= 1,
                   let merged = Self.combine(day: previous.date, time: date, timeZone: found.timeZone) {
                    dates[dates.count - 1] = DateMatch(date: merged, duration: found.duration,
                                                       phrase: previous.phrase + " " + phrase, hasTime: true,
                                                       timeZone: found.timeZone, line: previous.line)
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

    /// Best-effort drafts without the language model: one per line that has its own date
    /// (a schedule), otherwise one for the whole text.
    func fallbackDrafts(from text: String) -> [EventDraft] {
        let distinctLines = Set(dates.map(\.line))
        if dates.count > 1, distinctLines.count == dates.count {
            return dates.prefix(8).map { match in
                let ownTitle = Self.titleCandidate(lines[match.line], skipping: phrases)
                return draft(for: match, title: ownTitle.isEmpty ? Self.guessTitle(from: text, skipping: phrases) : ownTitle,
                             isTask: Self.looksLikeTask(lines[match.line]))
            }
        }
        guard let first = dates.first else { return [] }
        return [draft(for: first, title: Self.guessTitle(from: text, skipping: phrases),
                      isTask: Self.looksLikeTask(lines[first.line]))]
    }

    private func draft(for match: DateMatch, title rawTitle: String, isTask: Bool) -> EventDraft {
        // "Lunch with Sam at Kala Ghoda Cafe" → title + location, when no address was detected.
        var title = rawTitle
        var location = address ?? ""
        if !isTask, location.isEmpty,
           let at = rawTitle.range(of: #"\s+at\s+(?=[A-Z0-9])"#, options: .regularExpression) {
            location = String(rawTitle[at.upperBound...])
            title = String(rawTitle[..<at.lowerBound])
        }
        let start = match.hasTime ? match.date : Calendar.current.startOfDay(for: match.date)
        let end = match.duration > 0 ? start.addingTimeInterval(match.duration) : start.addingTimeInterval(3600)
        return EventDraft(
            kind: isTask ? .task : .event,
            title: title,
            start: start,
            end: match.hasTime ? end : start,
            isAllDay: !match.hasTime,
            location: isTask ? "" : location,
            notes: "",
            url: url,
            sourceTimeZone: match.hasTime ? match.timeZone.flatMap {
                $0.secondsFromGMT(for: start) == TimeZone.current.secondsFromGMT(for: start) ? nil : $0
            } : nil
        )
    }

    /// "Submit the report by Friday", "rent due on the 1st", "renew passport before March".
    static func looksLikeTask(_ line: String) -> Bool {
        let pattern = #"\b(due|deadline|submit|pay|renew|expires?|apply|return|finish|send|by|before)\b"#
        return line.lowercased().range(of: pattern, options: .regularExpression) != nil
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
            let candidate = titleCandidate(String(line), skipping: phrases)
            if !candidate.isEmpty { return candidate }
        }
        return ""
    }

    private static func titleCandidate(_ line: String, skipping phrases: [String]) -> String {
        var candidate = line
        for phrase in phrases { candidate = candidate.replacingOccurrences(of: phrase, with: "") }
        candidate = candidate.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        // "Submit the report by [Friday]" → "Submit the report".
        candidate = candidate.replacingOccurrences(of: #"\s+(by|on|at|before|from|until|for|this|next)$"#, with: "",
                                                   options: [.regularExpression, .caseInsensitive])
        guard candidate.count >= 3 else { return "" }
        let title = String(candidate.prefix(60))
        // Flyers shout; calendars don't.
        return title == title.uppercased() ? title.capitalized : title
    }
}
