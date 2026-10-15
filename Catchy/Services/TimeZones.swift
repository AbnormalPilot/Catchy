import Foundation

/// Turns the way people write time zones ("ET", "PST", "GMT+1", "London time") into a `TimeZone`.
enum TimeZones {
    static func resolve(_ written: String) -> TimeZone? {
        let trimmed = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/"), let zone = TimeZone(identifier: trimmed) { return zone }

        let key = trimmed.uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " TIME", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let identifier = names[key] { return TimeZone(identifier: identifier) }
        if let offset = utcOffset(key) { return TimeZone(secondsFromGMT: offset) }
        return TimeZone(abbreviation: key)
    }

    /// Short names in the zone that the event happens in, e.g. "3:00 PM EDT".
    static func label(_ date: Date, in zone: TimeZone) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        return "\(time) \(zone.abbreviation(for: date) ?? zone.identifier)"
    }

    /// "GMT+1", "UTC-05:30", "GMT +5:30".
    private static func utcOffset(_ key: String) -> Int? {
        guard key.hasPrefix("GMT") || key.hasPrefix("UTC") else { return nil }
        let rest = key.dropFirst(3).replacingOccurrences(of: " ", with: "")
        guard let sign = rest.first, sign == "+" || sign == "-" else { return rest.isEmpty ? 0 : nil }
        let parts = rest.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard let hours = parts.first, hours <= 14 else { return nil }
        let seconds = hours * 3600 + (parts.count > 1 ? parts[1] * 60 : 0)
        return sign == "-" ? -seconds : seconds
    }

    // Ambiguous abbreviations (IST, CST, BST) take their most common meaning in event listings.
    private static let names: [String: String] = [
        "ET": "America/New_York", "EST": "America/New_York", "EDT": "America/New_York", "EASTERN": "America/New_York",
        "NEW YORK": "America/New_York",
        "CT": "America/Chicago", "CST": "America/Chicago", "CDT": "America/Chicago", "CENTRAL": "America/Chicago",
        "MT": "America/Denver", "MST": "America/Denver", "MDT": "America/Denver", "MOUNTAIN": "America/Denver",
        "PT": "America/Los_Angeles", "PST": "America/Los_Angeles", "PDT": "America/Los_Angeles",
        "PACIFIC": "America/Los_Angeles", "SAN FRANCISCO": "America/Los_Angeles",
        "GMT": "GMT", "UTC": "UTC", "Z": "UTC",
        "BST": "Europe/London", "UK": "Europe/London", "LONDON": "Europe/London",
        "CET": "Europe/Paris", "CEST": "Europe/Paris", "PARIS": "Europe/Paris", "BERLIN": "Europe/Berlin",
        "IST": "Asia/Kolkata", "INDIA": "Asia/Kolkata",
        "GST": "Asia/Dubai", "DUBAI": "Asia/Dubai",
        "SGT": "Asia/Singapore", "SINGAPORE": "Asia/Singapore",
        "HKT": "Asia/Hong_Kong", "JST": "Asia/Tokyo", "TOKYO": "Asia/Tokyo", "KST": "Asia/Seoul",
        "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney", "SYDNEY": "Australia/Sydney",
        "NZST": "Pacific/Auckland", "NZDT": "Pacific/Auckland",
    ]
}
