import AppKit
import Observation
import ServiceManagement

/// Drives the popover: what was caught, what the card shows, and saving it.
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case reading
        case review
        case nothingFound
        case needsScreenAccess
        case saved(SavedCatch)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var source: CaptureSource = .clipboard
    private(set) var rawText = ""
    private(set) var usedOnDeviceModel = true
    private(set) var isSaving = false
    /// Everything caught from one copy or capture. One shows as a card; several as a list.
    var drafts: [EventDraft] = []
    /// The draft open in the card. Nil while the list of several is showing.
    var selection: Int?

    /// The draft the card is editing.
    var draft: EventDraft {
        get { selection.flatMap { drafts.indices.contains($0) ? drafts[$0] : nil } ?? .blank(notes: "") }
        set { if let selection, drafts.indices.contains(selection) { drafts[selection] = newValue } }
    }

    var showsList: Bool { drafts.count > 1 && selection == nil }
    var includedDrafts: [EventDraft] { drafts.filter(\.isIncluded) }

    // MARK: Preferences that live in the ••• menu (no settings screen, by design)

    /// Stops automatic clipboard catching; the hotkey, Services and buttons still work.
    var isPaused = UserDefaults.standard.bool(forKey: "pauseCatching") {
        didSet { UserDefaults.standard.set(isPaused, forKey: "pauseCatching") }
    }

    /// The ⌥⌘ tap needs Input Monitoring; until then the island offers to turn it on.
    var shortcutIsActive = false

    var hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
        didSet { UserDefaults.standard.set(hasSeenWelcome, forKey: "hasSeenWelcome") }
    }

    var launchesAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchesAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                try launchesAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                launchesAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    let calendar = CalendarService()
    let extractor = EventExtractor()
    let notifier = Notifier()
    private let regionSelector = RegionSelector()

    /// Wired up by the status item controller.
    var showIsland: () -> Void = {}
    var hideIsland: () -> Void = {}

    private var work: Task<Void, Never>?

    func prepare() {
        extractor.prewarm()
        notifier.onUndo = { [weak self] saved in self?.undo(saved) }
        notifier.onOpen = { [weak self] reminders in
            reminders ? self?.calendar.openRemindersApp() : self?.calendar.openCalendarApp()
        }
    }

    // MARK: Catching

    func catchText(_ text: String, from source: CaptureSource) {
        work?.cancel()
        self.source = source
        rawText = text
        phase = .reading
        showIsland()
        work = Task { await extract(text) }
    }

    func catchCurrentClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            phase = .failed("There's no text on the clipboard. Copy a message, email, or flyer text first.")
            return
        }
        catchText(text, from: .clipboard)
    }

    /// The hotkey flow: drag over part of the screen, OCR it, then extract like copied text.
    func captureScreen() {
        guard ScreenCapturePermission.isGranted else {
            phase = .needsScreenAccess
            showIsland()
            return
        }
        work?.cancel()
        hideIsland()
        work = Task {
            guard let rect = await regionSelector.selectRegion() else { return }
            // Let the overlay leave the screen before it gets photographed.
            try? await Task.sleep(for: .milliseconds(120))
            source = .screen
            rawText = ""
            phase = .reading
            showIsland()
            do {
                let text = try await ScreenReader.readText(in: rect)
                guard !Task.isCancelled else { return }
                guard !text.isEmpty else {
                    phase = .failed("Catchy couldn't find any text there. Try selecting a larger area.")
                    return
                }
                rawText = text
                await extract(text)
            } catch {
                phase = .failed("Couldn't capture the screen: \(error.localizedDescription)")
            }
        }
    }

    func requestScreenAccess() {
        if !ScreenCapturePermission.request() {
            // After the first ask, macOS only changes this in System Settings.
            ScreenCapturePermission.openSettings()
        }
    }

    private func extract(_ text: String) async {
        let result = await extractor.extract(from: text)
        guard !Task.isCancelled else { return }
        usedOnDeviceModel = result.usedOnDeviceModel
        drafts = result.drafts
        selection = drafts.count == 1 ? 0 : nil
        phase = drafts.isEmpty ? .nothingFound : .review
    }

    // MARK: Card actions

    /// "Create anyway" when no date was found: a blank card with the text kept in the notes.
    func editManually() {
        drafts = [.blank(notes: String(rawText.prefix(500)))]
        selection = 0
        phase = .review
    }

    /// From the list: open one for editing, and come back to the list after.
    func open(_ draft: EventDraft) {
        selection = drafts.firstIndex { $0.id == draft.id }
    }

    func backToList() {
        selection = nil
    }

    /// Saves the card, or every ticked row when the list of several is showing.
    func save() {
        guard !isSaving else { return }
        let toSave = drafts.count > 1 ? includedDrafts : [draft]
        guard !toSave.isEmpty else { return }
        isSaving = true
        // macOS shows the Calendar/Reminders permission prompt for the active app; Catchy never
        // activates itself otherwise, so the first prompt could go unseen and Add looked stuck.
        if toSave.contains(where: { calendar.access(for: $0.kind) == .notDetermined }) {
            NSApp.activate()
        }
        Task {
            defer { isSaving = false }
            // On denial the card and list show a banner pointing at System Settings.
            guard await calendar.requestAccessIfNeeded(for: Set(toSave.map(\.kind))) else { return }
            do {
                let saved = try calendar.save(toSave)
                phase = .saved(saved)
                notifier.announce(saved)
            } catch {
                phase = .failed("Couldn't save: \(error.localizedDescription)")
            }
        }
    }

    func undo(_ saved: SavedCatch) {
        do {
            try calendar.undo(saved)
            // Back to what was caught, so a fix-and-resave is one click (if it's still around).
            phase = drafts.isEmpty ? .idle : .review
        } catch {
            phase = .failed("Couldn't undo: \(error.localizedDescription)")
        }
    }

    func reset() {
        work?.cancel()
        phase = .idle
    }

    func done() {
        hideIsland()
        reset()
    }
}
