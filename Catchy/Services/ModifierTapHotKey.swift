import AppKit

/// A shortcut made only of modifiers: tap ⌥ and ⌘ together and let go.
///
/// Carbon hot keys need a letter key, so this listens to modifier changes with a listen-only
/// event tap instead. That requires Input Monitoring permission. Catchy never sees what you
/// type; only whether a key was pressed while ⌥⌘ was down, which cancels the tap.
final class ModifierTapHotKey {
    private let action: () -> Void
    private var tap: CFMachPort?
    private var retry: Timer?

    private var armedAt: Date?
    private var spoiled = false

    /// Whether the shortcut is live (Input Monitoring granted and the tap installed).
    var onStatusChange: (Bool) -> Void = { _ in }
    private(set) var isActive = false {
        didSet { if isActive != oldValue { onStatusChange(isActive) } }
    }

    init(action: @escaping () -> Void) {
        self.action = action
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
                    // The run loop source is on the main run loop.
                    MainActor.assumeIsolated { hotKey.handle(type, flags: event.flags) }
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

    private func handle(_ type: CGEventType, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let held = flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
            if held == [.maskCommand, .maskAlternate] {
                if armedAt == nil { armedAt = .now; spoiled = false }
            } else if held.isEmpty {
                // Both let go: a quick, clean tap fires.
                if let armedAt, !spoiled, Date.now.timeIntervalSince(armedAt) < 0.6 { action() }
                armedAt = nil
            } else if !held.isDisjoint(with: [.maskShift, .maskControl]) {
                spoiled = true
            }
        default:
            // ⌥⌘ + any key or click is some other shortcut.
            if armedAt != nil { spoiled = true }
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
