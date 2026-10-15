import AppKit
import EventKit

/// Owns the EventKit store, the Calendar permission state, and saving.
@Observable
final class CalendarService {
    enum Access {
        case notDetermined, granted, writeOnly, denied
    }

    private let store = EKEventStore()
    private(set) var access: Access = CalendarService.currentAccess()

    /// Remembered across launches so the card defaults to the last calendar used.
    var selectedCalendarID: String? = UserDefaults.standard.string(forKey: "selectedCalendarID") {
        didSet { UserDefaults.standard.set(selectedCalendarID, forKey: "selectedCalendarID") }
    }

    var calendars: [EKCalendar] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
    }

    /// The selected calendar, else the default if it syncs through iCloud, else any iCloud calendar.
    var targetCalendar: EKCalendar? {
        if let id = selectedCalendarID, let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications {
            return calendar
        }
        if let fallback = store.defaultCalendarForNewEvents, Self.syncsWithICloud(fallback) { return fallback }
        return calendars.first(where: Self.syncsWithICloud) ?? store.defaultCalendarForNewEvents
    }

    func refreshAccess() {
        access = Self.currentAccess()
    }

    /// Shows the system prompt the first time; afterwards just reports the current state.
    func requestAccessIfNeeded() async -> Bool {
        if access == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
            refreshAccess()
        }
        return access == .granted || access == .writeOnly
    }

    func save(_ draft: EventDraft) throws -> SavedEvent {
        let event = EKEvent(eventStore: store)
        event.title = draft.title.isEmpty ? "New Event" : draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = max(draft.end, draft.start)
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.url = draft.url
        event.calendar = targetCalendar ?? store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)

        let calendar = event.calendar
        return SavedEvent(
            title: event.title,
            start: draft.start,
            isAllDay: draft.isAllDay,
            calendarTitle: calendar?.title ?? "Calendar",
            // Write-only access can't see the calendar's account, so don't promise sync we can't confirm.
            syncsWithICloud: calendar.map(Self.syncsWithICloud) ?? false
        )
    }

    func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    static func syncsWithICloud(_ calendar: EKCalendar) -> Bool {
        guard let source = calendar.source else { return false }
        return source.sourceType == .calDAV && source.title.localizedCaseInsensitiveContains("icloud")
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
