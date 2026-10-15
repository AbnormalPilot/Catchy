import UserNotifications

/// A Mac notification when something is added ("Added to Calendar"), with Undo and Open buttons.
/// The island tucks itself away after a few seconds; this stays in Notification Center.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onUndo: (SavedCatch) -> Void = { _ in }
    var onOpen: (_ reminders: Bool) -> Void = { _ in }

    private let center = UNUserNotificationCenter.current()
    private static let category = "catchy.saved"
    private static let undoAction = "undo"
    private static let openAction = "open"

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [
                UNNotificationAction(identifier: Self.undoAction, title: "Undo"),
                UNNotificationAction(identifier: Self.openAction, title: "Open", options: .foreground),
            ], intentIdentifiers: []),
        ])
    }

    func announce(_ saved: SavedCatch) {
        let content = UNMutableNotificationContent()
        let onlyReminders = saved.eventIDs.isEmpty
        if saved.count == 1 {
            content.title = onlyReminders ? "Added to Reminders" : "Added to Calendar"
            content.body = [saved.titles.first, when(saved)].compactMap { $0 }.joined(separator: " · ")
        } else {
            content.title = "Added \(saved.count) items"
            content.body = saved.titles.joined(separator: " · ")
        }
        if saved.syncsWithICloud { content.subtitle = "Syncing to your iPhone" }
        content.categoryIdentifier = Self.category
        content.userInfo = ["events": saved.eventIDs, "reminders": saved.reminderIDs]

        Task {
            // Asks the first time (macOS shows that as a notification itself).
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private func when(_ saved: SavedCatch) -> String? {
        guard let start = saved.firstStart else { return nil }
        return saved.firstIsAllDay
            ? start.formatted(.dateTime.weekday(.abbreviated).month().day())
            : start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
    }

    // Show it even while Catchy's island is up.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let events = info["events"] as? [String] ?? []
        let reminders = info["reminders"] as? [String] ?? []
        let action = response.actionIdentifier
        await MainActor.run {
            if action == Self.undoAction {
                onUndo(SavedCatch(eventIDs: events, reminderIDs: reminders))
            } else {
                onOpen(events.isEmpty)
            }
        }
    }
}
