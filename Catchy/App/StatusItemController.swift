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
        NSApp.activate()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
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
