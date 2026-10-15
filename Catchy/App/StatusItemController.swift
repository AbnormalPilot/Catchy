import AppKit
import SwiftUI

/// Menu bar icon + popover.
///
/// SwiftUI's `MenuBarExtra` can't be opened from code, and Catchy has to pop its card
/// open when something is copied or captured. An `NSStatusItem` with an `NSPopover`
/// can, and on macOS 26 the popover gets the Liquid Glass material for free.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let state: AppState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(state: AppState) {
        self.state = state
        super.init()

        if let button = statusItem.button {
            button.image = Self.icon(for: state.phase)
            button.target = self
            button.action = #selector(togglePopover)
        }

        let hosting = NSHostingController(rootView: PopoverView(state: state))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        state.presentPopover = { [weak self] in self?.show() }
        state.closePopover = { [weak self] in self?.popover.performClose(nil) }
        observePhase()
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : show()
    }

    private func show() {
        guard let button = statusItem.button else { return }
        state.calendar.refreshAccess()
        // Plain activate() is only a request under cooperative activation, and a popover that
        // appears because you copied something wouldn't come forward; this one still does.
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            let anchor = anchorView(for: button)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    /// With an auto-hiding menu bar the status item's window sits above the top of the screen
    /// (`window.screen == nil`) and a popover shown from it lands in the screen's corner. Then we
    /// stand in an invisible window at the same x, right where the icon appears when revealed.
    private func anchorView(for button: NSStatusBarButton) -> NSView {
        guard let itemWindow = button.window, itemWindow.screen == nil else { return button }
        let x = itemWindow.frame.midX
        let screen = NSScreen.screens.first { $0.frame.minX <= x && x < $0.frame.maxX } ?? NSScreen.main
        guard let screen else { return button }

        let size = itemWindow.frame.size
        anchorWindow.setFrame(
            NSRect(x: itemWindow.frame.minX, y: screen.frame.maxY - size.height, width: size.width, height: size.height),
            display: false
        )
        anchorWindow.orderFrontRegardless()
        return anchorWindow.contentView ?? button
    }

    private lazy var anchorWindow: NSWindow = {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return window
    }()

    func popoverDidClose(_ notification: Notification) {
        anchorWindow.orderOut(nil)
        // A finished or failed catch shouldn't greet you next time.
        switch state.phase {
        case .saved, .failed, .nothingFound, .needsScreenAccess: state.reset()
        default: break
        }
    }

    private func observePhase() {
        withObservationTracking {
            _ = state.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem.button?.image = Self.icon(for: self.state.phase)
                self.observePhase()
            }
        }
    }

    private static func icon(for phase: AppState.Phase) -> NSImage? {
        let image = switch phase {
        case .reading: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Catchy is reading")
        case .saved: NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Event added")
        default: NSImage(resource: .menuBarIcon)
        }
        image?.isTemplate = true
        return image
    }
}
