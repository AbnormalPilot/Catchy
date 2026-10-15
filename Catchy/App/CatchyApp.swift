import SwiftUI

@main
struct CatchyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Catchy lives in the menu bar (see StatusItemController); this keeps SwiftUI happy
        // without opening a window.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: StatusItemController?
    private let clipboard = ClipboardWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(state: state)

        clipboard.onEventText = { [weak self] text in
            self?.state.catchText(text, from: .clipboard)
        }
        clipboard.start()

        state.prepare()
    }
}
