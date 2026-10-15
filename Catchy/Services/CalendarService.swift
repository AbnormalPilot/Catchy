import AppKit
import EventKit

/// Owns the EventKit store: Calendar and Reminders permission state, saving, clashes, and undo.
@Observable
final class CalendarService {
    enum Access {
        case notDetermined, granted, writeOnly, denied
    }

    private let store = EKEventStore()
    private(set) var eventAccess: Access = CalendarService.currentAccess(for: .event)
    private(set) var reminderAccess: Access = CalendarService.currentAccess(for: .reminder)

    /// Remembered across launches so the card defaults to the last calendar / list used.
    var selectedCalendarID: String? = UserDefaults.standard.string(forKey: "selectedCalendarID") {
        didSet { UserDefaults.standard.set(selectedCalendarID, forKey: "selectedCalendarID") }
    }
    var selectedReminderListID: String? = UserDefaults.standard.string(forKey: "selectedReminderListID") {
        didSet { UserDefaults.standard.set(selectedReminderListID, forKey: "selectedReminderListID") }
    }

    /// The alert added to saved events; remembered, like the calendar choice.
    var alert = EventAlert(rawValue: UserDefaults.standard.string(forKey: "eventAlert") ?? "") ?? .fifteenMinutes {
        didSet { UserDefaults.standard.set(alert.rawValue, forKey: "eventAlert") }
    }

    func access(for kind: CatchKind) -> Access {
        kind == .event ? eventAccess : reminderAccess
    }

    // MARK: Calendars and lists

    var calendars: [EKCalendar] { writableCalendars(for: .event) }
    var reminderLists: [EKCalendar] { writableCalendars(for: .reminder) }

    /// The selected calendar, else the default if it syncs through iCloud, else any iCloud calendar.
    var targetCalendar: EKCalendar? {
        target(selected: selectedCalendarID, default: store.defaultCalendarForNewEvents, among: calendars)
    }

    var targetReminderList: EKCalendar? {
        target(selected: selectedReminderListID, default: store.defaultCalendarForNewReminders(), among: reminderLists)
    }

    private func writableCalendars(for type: EKEntityType) -> [EKCalendar] {
        guard (type == .event ? eventAccess : reminderAccess) == .granted else { return [] }
        return store.calendars(for: type)
            .filter(\.allowsContentModifications)
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
    }

    private func target(selected id: String?, default fallback: EKCalendar?, among all: [EKCalendar]) -> EKCalendar? {
        if let id, let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications {
            return calendar
        }
        if let fallback, Self.syncsWithICloud(fallback) { return fallback }
        return all.first(where: Self.syncsWithICloud) ?? fallback
    }

    // MARK: Access

    func refreshAccess() {
        eventAccess = Self.currentAccess(for: .event)
        reminderAccess = Self.currentAccess(for: .reminder)
    }

    /// Shows the system prompt the first time for each kind; afterwards just reports the current state.
    func requestAccessIfNeeded(for kinds: Set<CatchKind>) async -> Bool {
        if kinds.contains(.event), eventAccess == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if kinds.contains(.task), reminderAccess == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        refreshAccess()
        return kinds.allSatisfy { access(for: $0) == .granted || access(for: $0) == .writeOnly }
    }

    // MARK: Clashes

    /// The first timed event already in the calendar that overlaps this one.
    func clash(for draft: EventDraft) -> EKEvent? {
        guard draft.kind == .event, !draft.isAllDay, eventAccess == .granted else { return nil }
        let predicate = store.predicateForEvents(withStart: draft.start, end: max(draft.end, draft.start.addingTimeInterval(60)), calendars: nil)
        return store.events(matching: predicate).first { !$0.isAllDay }
    }

    // MARK: Saving and undo

    func save(_ drafts: [EventDraft]) throws -> SavedCatch {
        var saved = SavedCatch()
        for draft in drafts {
            switch draft.kind {
            case .event:
                let event = makeEvent(from: draft)
                try store.save(event, span: .thisEvent, commit: false)
                saved.eventIDs.append(event.calendarItemIdentifier)
                saved.note(title: event.title, start: draft.start, isAllDay: draft.isAllDay, destination: event.calendar)
            case .task:
                let reminder = makeReminder(from: draft)
                try store.save(reminder, commit: false)
                saved.reminderIDs.append(reminder.calendarItemIdentifier)
                saved.note(title: reminder.title, start: draft.start, isAllDay: draft.isAllDay, destination: reminder.calendar)
            }
        }
        try store.commit()
        return saved
    }

    func undo(_ saved: SavedCatch) throws {
        for id in saved.eventIDs {
            if let event = store.calendarItem(withIdentifier: id) as? EKEvent {
                try store.remove(event, span: .thisEvent, commit: false)
            }
        }
        for id in saved.reminderIDs {
            if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
                try store.remove(reminder, commit: false)
            }
        }
        try store.commit()
    }

    private func makeEvent(from draft: EventDraft) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = draft.title.isEmpty ? "New Event" : draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = max(draft.end, draft.start)
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.url = draft.url
        event.calendar = targetCalendar ?? store.defaultCalendarForNewEvents
        if let offset = alert.effective(start: draft.start, allDay: draft.isAllDay).offset(allDay: draft.isAllDay) {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }
        return event
    }

    private func makeReminder(from draft: EventDraft) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title.isEmpty ? "New Reminder" : draft.title
        reminder.notes = draft.notes.isEmpty ? nil : draft.notes
        reminder.url = draft.url
        reminder.calendar = targetReminderList ?? store.defaultCalendarForNewReminders()
        let fields: Set<Calendar.Component> = draft.isAllDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
        reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: draft.start)
        if !draft.isAllDay { reminder.addAlarm(EKAlarm(absoluteDate: draft.start)) }
        return reminder
    }

    // MARK: Opening things

    func openCalendarApp() { openApp("com.apple.iCal") }
    func openRemindersApp() { openApp("com.apple.reminders") }

    func openPrivacySettings(for kind: CatchKind) {
        let pane = kind == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    static func syncsWithICloud(_ calendar: EKCalendar) -> Bool {
        guard let source = calendar.source else { return false }
        return source.sourceType == .calDAV && source.title.localizedCaseInsensitiveContains("icloud")
    }

    private static func currentAccess(for type: EKEntityType) -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

private extension SavedCatch {
    mutating func note(title: String, start: Date, isAllDay: Bool, destination calendar: EKCalendar?) {
        // Write-only access can't see the calendar's account, so don't promise sync we can't confirm.
        note(title: title, start: start, isAllDay: isAllDay, destination: calendar?.title ?? "Calendar",
             syncsWithICloud: calendar.map(CalendarService.syncsWithICloud) ?? false)
    }
}
