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

/// The alert Catchy puts on an event. EventKit doesn't apply a calendar's default alerts to
/// events created by apps, so without this there'd be no Calendar notification at all.
enum EventAlert: String, CaseIterable, Identifiable {
    case none, atStart, fiveMinutes, fifteenMinutes, thirtyMinutes, oneHour, oneDay

    var id: String { rawValue }

    /// All-day events get "9 AM on the day" or "9 AM the day before" instead of minute offsets.
    static func options(allDay: Bool) -> [EventAlert] {
        allDay ? [.none, .atStart, .oneDay] : allCases
    }

    /// Seconds relative to the event's start (midnight for all-day events), or nil for no alert.
    func offset(allDay: Bool) -> TimeInterval? {
        if allDay {
            switch self {
            case .none: return nil
            case .oneDay: return -15 * 3600  // 9 AM the day before
            default: return 9 * 3600         // 9 AM on the day
            }
        }
        switch self {
        case .none: return nil
        case .atStart: return 0
        case .fiveMinutes: return -5 * 60
        case .fifteenMinutes: return -15 * 60
        case .thirtyMinutes: return -30 * 60
        case .oneHour: return -3600
        case .oneDay: return -86_400
        }
    }

    func title(allDay: Bool) -> String {
        if allDay {
            switch self {
            case .none: return "None"
            case .oneDay: return "Day before, 9 AM"
            default: return "On the day, 9 AM"
            }
        }
        switch self {
        case .none: return "None"
        case .atStart: return "At start"
        case .fiveMinutes: return "5 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        case .oneDay: return "1 day before"
        }
    }

    /// For the small chip on the card.
    func shortTitle(allDay: Bool) -> String {
        if allDay {
            switch self {
            case .none: return "Off"
            case .oneDay: return "Day before"
            default: return "9 AM"
            }
        }
        switch self {
        case .none: return "Off"
        case .atStart: return "At start"
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .oneDay: return "1d"
        }
    }
}
