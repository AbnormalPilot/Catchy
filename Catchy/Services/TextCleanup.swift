import Foundation

/// Evens out how people write and say times before extraction, so "around 5.30" and
/// "at one" read like "around 5:30" and "at 1:00". Mostly matters for dictation.
enum TextCleanup {
    private static let numbers = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                  "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    private static let minutes = ["o'clock": 0, "oclock": 0, "fifteen": 15, "thirty": 30, "forty five": 45, "forty-five": 45]
    private static let prepositions = "at|around|about|by|till|until|from|before|after|between|to"

    static func normalized(_ text: String) -> String {
        var text = text
        // "around 5.30" / "at 9.15pm" → colon (only after a time word or before am/pm, so "v2.30" stays).
        text = replace(#"(?i)\b("# + prepositions + #")\s+(\d{1,2})\.(\d{2})\b"#, in: text) { "\($0[1]) \($0[2]):\($0[3])" }
        text = replace(#"(?i)\b(\d{1,2})\.(\d{2})\s*(am|pm|a\.m\.|p\.m\.)"#, in: text) { "\($0[1]):\($0[2]) \($0[3])" }
        // "half past five" → 5:30, "quarter to six" → 5:45, "quarter past six" → 6:15.
        let words = numbers.keys.joined(separator: "|")
        text = replace(#"(?i)\bhalf past ("# + words + #")\b"#, in: text) { "\(numbers[$0[1].lowercased()]!):30" }
        text = replace(#"(?i)\bquarter past ("# + words + #")\b"#, in: text) { "\(numbers[$0[1].lowercased()]!):15" }
        text = replace(#"(?i)\bquarter to ("# + words + #")\b"#, in: text) { match in
            let hour = numbers[match[1].lowercased()]!
            return "\(hour == 1 ? 12 : hour - 1):45"
        }
        // "at one", "around five thirty", "by six o'clock" → digits.
        let minuteWords = minutes.keys.map { $0.replacingOccurrences(of: " ", with: #"\s+"#) }.joined(separator: "|")
        text = replace(#"(?i)\b("# + prepositions + #")\s+("# + words + #")(?:\s+("# + minuteWords + #"))?\b"#, in: text) { match in
            let hour = numbers[match[2].lowercased()]!
            let minute = match[3].isEmpty ? 0 : (minutes[match[3].lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)] ?? 0)
            return "\(match[1]) \(hour):\(String(format: "%02d", minute))"
        }
        return text
    }

    /// The first clause of a spoken sentence without its filler: "So, I have to meet Ravi around"
    /// → "Meet Ravi". Harmless on written text.
    static func spokenTitle(_ text: String) -> String {
        var title = text
        // Afterthoughts: ", probably at …", ", maybe …".
        if let cut = title.range(of: #"(?i),\s*(probably|maybe|possibly|i think|i guess)\b"#, options: .regularExpression) {
            title = String(title[..<cut.lowerBound])
        }
        let fillers = [
            #"(?i)^\s*((so|okay|ok|uh+|um+|hmm+|like|hey|and|well|right)\b[\s,]*)+"#,
            #"(?i)\b(i|we)\s+(have|need|got|'ve got|ve got|gotta|want)\s+to\s+"#,
            #"(?i)\b(i|we)\s+(have|need|got|'ve got|ve got)\s+(a|an)\s+"#,
            #"(?i)\b(remind me to|don't forget to|dont forget to|there's a|there is a)\s+"#,
            #"(?i)\s+(around|about|at|by|on)\s*$"#,
        ]
        for pattern in fillers {
            title = title.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        title = title.replacingOccurrences(of: #"\s*,\s*,?"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // A trailing connector can be uncovered once the rest is gone.
        title = title.replacingOccurrences(of: #"(?i)\s+(around|about|at|by|on|in)$"#, with: "", options: .regularExpression)
        return title
    }

    /// "at the Starbucks in Bandra", "@ Blue Tokai" → the place, when no address was detected.
    static func spokenPlace(in text: String) -> (place: String, phrase: String)? {
        let pattern = #"(?:\bat|@)\s+(?:the\s+)?([A-Z][\w'&.-]*(?:\s+(?:in|on|near|by)\s+[A-Z][\w'&.-]*|\s+[A-Z][\w'&.-]*)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range, in: text), let place = Range(match.range(at: 1), in: text) else { return nil }
        // Keep "St." or "Ave." inside a name, but not the sentence's own full stop.
        let name = String(text[place]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        // "at 5", "at Noon" aren't places.
        guard name.rangeOfCharacter(from: .letters) != nil, !["Noon", "Midnight"].contains(name) else { return nil }
        return (name, String(text[whole]))
    }

    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let groups = (0..<match.numberOfRanges).map { index -> String in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            result.replaceSubrange(range, with: transform(groups))
        }
        return result
    }
}
