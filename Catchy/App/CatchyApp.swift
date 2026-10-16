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
    private var hotKey: ModifierTapHotKey?
    private let services = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(state: state)

        clipboard.onEventText = { [weak self] text, source in
            self?.state.catchText(text, from: source)
        }
        clipboard.isPaused = { [weak self] in self?.state.isPaused ?? false }
        clipboard.start()

        let hotKey = ModifierTapHotKey([
            .init(modifiers: [.maskCommand, .maskAlternate]) { [weak self] in self?.state.captureScreen() },
            .init(modifiers: [.maskCommand, .maskControl]) { [weak self] in self?.state.toggleListening() },
        ])
        hotKey.onStatusChange = { [weak self] active in self?.state.shortcutIsActive = active }
        hotKey.onEscape = { [weak self] in self?.state.escapePressed() }
        hotKey.start()
        self.hotKey = hotKey

        services.onText = { [weak self] text in
            self?.state.catchText(text, from: .service)
        }
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()

        state.prepare()

        if !state.hasSeenWelcome {
            // The status item needs a moment to land in the menu bar before anything can anchor to it.
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                state.showIsland()
            }
        }
    }
}
