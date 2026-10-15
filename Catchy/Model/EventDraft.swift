import Foundation

enum CatchKind: Equatable {
    /// Happens at a time → Calendar.
    case event
    /// Something to do by a deadline → Reminders.
    case task
}

/// An editable event or task shown on the card before it is saved.
struct EventDraft: Equatable, Identifiable {
    let id = UUID()
    var kind: CatchKind = .event
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var url: URL?
    /// The zone the text was written in, when it isn't this Mac's ("3pm ET"). Times are stored absolute.
    var sourceTimeZone: TimeZone?
    /// Ticked in the list when several were caught at once.
    var isIncluded = true

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
    case image = "Image"
    case service = "Services"

    var symbol: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .screen: "viewfinder"
        case .image: "photo"
        case .service: "contextualmenu.and.cursorarrow"
        }
    }
}

/// What was just saved: enough for the confirmation and for Undo.
struct SavedCatch: Equatable {
    var eventIDs: [String] = []
    var reminderIDs: [String] = []
    var titles: [String] = []
    var firstStart: Date?
    var firstIsAllDay = false
    var destinations: [String] = []
    var syncsWithICloud = true

    var count: Int { eventIDs.count + reminderIDs.count }

    mutating func note(title: String, start: Date, isAllDay: Bool, destination: String, syncsWithICloud syncs: Bool) {
        titles.append(title)
        if firstStart == nil { firstStart = start; firstIsAllDay = isAllDay }
        if !destinations.contains(destination) { destinations.append(destination) }
        syncsWithICloud = syncsWithICloud && syncs
    }
}
