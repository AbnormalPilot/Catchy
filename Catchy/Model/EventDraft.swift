import Foundation

/// An editable event shown on the card before it is saved to Calendar.
struct EventDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var url: URL?
    /// The zone the text was written in, when it isn't this Mac's ("3pm ET"). Times are stored absolute.
    var sourceTimeZone: TimeZone?

    /// A starting point when nothing usable was found: next whole hour, one hour long.
    static func blank(notes: String, now: Date = .now) -> EventDraft {
        let calendar = Calendar.current
        let nextHour = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        return EventDraft(
            title: "",
            start: nextHour,
            end: nextHour.addingTimeInterval(3600),
            isAllDay: false,
            location: "",
            notes: notes,
            url: nil
        )
    }
}

enum CaptureSource: String {
    case clipboard = "Clipboard"
    case screen = "Screen"

    var symbol: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .screen: "viewfinder"
        }
    }
}

/// What the "saved" confirmation shows.
struct SavedEvent: Equatable {
    let title: String
    let start: Date
    let isAllDay: Bool
    let calendarTitle: String
    let syncsWithICloud: Bool
}
