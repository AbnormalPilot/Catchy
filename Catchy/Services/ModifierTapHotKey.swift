import AppKit

/// Shortcuts made only of modifiers: tap two together and let go (⌥⌘ captures, ⌃⌘ listens).
///
/// Carbon hot keys need a letter key, so this listens to modifier changes with a listen-only
/// event tap instead. That requires Input Monitoring permission. Catchy never sees what you
/// type; only whether a key was pressed while the pair was down, which cancels the tap. So
/// ⌃⌘Q, ⌃⌘Space, ⌥⌘Esc and friends keep working.
final class ModifierTapHotKey {
    struct Shortcut {
        let modifiers: CGEventFlags
        let action: () -> Void
    }

    private let shortcuts: [Shortcut]
    /// Esc, seen even when Catchy isn't the active app (the capture overlay and dictation use it).
    var onEscape: () -> Void = {}
    private var tap: CFMachPort?
    private var retry: Timer?

    private var armed: (shortcut: Int, at: Date)?
    private var spoiled = false
    private static let watched: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]

    /// Whether the shortcut is live (Input Monitoring granted and the tap installed).
    var onStatusChange: (Bool) -> Void = { _ in }
    private(set) var isActive = false {
        didSet { if isActive != oldValue { onStatusChange(isActive) } }
    }

    init(_ shortcuts: [Shortcut]) {
        self.shortcuts = shortcuts
    }

    /// Installs the tap now if allowed; otherwise keeps checking, so granting access in
    /// System Settings turns the shortcut on without a relaunch.
    func start() {
        guard !installTap() else { return }
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.installTap() else { return }
                self.retry?.invalidate()
                self.retry = nil
            }
        }
    }

    private func installTap() -> Bool {
        guard tap == nil else { return true }
        guard InputMonitoringPermission.isGranted else { isActive = false; return false }
        let events: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let hotKey = Unmanaged<ModifierTapHotKey>.fromOpaque(userInfo).takeUnretainedValue()
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    // The run loop source is on the main run loop.
                    MainActor.assumeIsolated { hotKey.handle(type, flags: event.flags, keyCode: keyCode) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        isActive = true
        return true
    }

    private func handle(_ type: CGEventType, flags: CGEventFlags, keyCode: Int64) {
        if type == .keyDown, keyCode == 53 { onEscape() }  // Esc
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let held = flags.intersection(Self.watched)
            if held.isEmpty {
                // All let go: a quick, clean tap fires its shortcut.
                if let armed, !spoiled, Date.now.timeIntervalSince(armed.at) < 0.6 {
                    shortcuts[armed.shortcut].action()
                }
                armed = nil
            } else if let index = shortcuts.firstIndex(where: { $0.modifiers == held }) {
                if armed == nil {
                    armed = (index, .now)
                    spoiled = false
                } else if armed?.shortcut != index {
                    spoiled = true
                }
            } else if let armed, !held.isSubset(of: shortcuts[armed.shortcut].modifiers) {
                // A third modifier joined in: some other shortcut.
                spoiled = true
            }
        default:
            // The pair plus any key or click is some other shortcut.
            if armed != nil { spoiled = true }
        }
    }
}

enum InputMonitoringPermission {
    static var isGranted: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; after that, opens the right Settings pane.
    static func request() {
        if !CGRequestListenEventAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
    }
}
