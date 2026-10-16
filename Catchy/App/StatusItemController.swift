import AppKit

/// The menu bar icon. Clicking it opens or closes the notch island.
final class StatusItemController: NSObject {
    private let state: AppState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let island: IslandController

    init(state: AppState) {
        self.state = state
        island = IslandController(state: state)
        super.init()

        if let button = statusItem.button {
            button.image = Self.icon(for: state.phase)
            button.appearsDisabled = state.isPaused
            button.target = self
            button.action = #selector(toggleIsland)
        }

        state.showIsland = { [weak self] in self?.show() }
        state.hideIsland = { [weak self] in self?.island.hide() }
        state.islandIsOpen = { [weak self] in self?.island.isShown ?? false }
        island.onClose = { [weak self] in self?.islandDidClose() }
        observePhase()
    }

    @objc private func toggleIsland() {
        island.isShown ? island.hide() : show()
    }

    private func show() {
        state.calendar.refreshAccess()
        island.show()
    }

    private func islandDidClose() {
        state.hasSeenWelcome = true
        // A finished or failed catch shouldn't greet you next time.
        switch state.phase {
        case .saved, .failed, .nothingFound, .needsScreenAccess: state.reset()
        default: break
        }
    }

    private func observePhase() {
        withObservationTracking {
            _ = state.phase
            _ = state.isPaused
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem.button?.image = Self.icon(for: self.state.phase)
                self.statusItem.button?.appearsDisabled = self.state.isPaused
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
