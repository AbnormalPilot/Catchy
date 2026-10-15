import AppKit
import Observation

/// Drives the popover: what was caught, what the card shows, and saving it.
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case reading
        case review
        case nothingFound
        case needsScreenAccess
        case saved(SavedEvent)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var source: CaptureSource = .clipboard
    private(set) var rawText = ""
    private(set) var usedOnDeviceModel = true
    private(set) var isSaving = false
    var draft = EventDraft.blank(notes: "")

    let calendar = CalendarService()
    let extractor = EventExtractor()
    private let regionSelector = RegionSelector()

    /// Wired up by the status item controller.
    var presentPopover: () -> Void = {}
    var closePopover: () -> Void = {}

    private var work: Task<Void, Never>?

    func prepare() {
        extractor.prewarm()
    }

    // MARK: Catching

    func catchText(_ text: String, from source: CaptureSource) {
        work?.cancel()
        self.source = source
        rawText = text
        phase = .reading
        presentPopover()
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
            presentPopover()
            return
        }
        work?.cancel()
        closePopover()
        work = Task {
            guard let rect = await regionSelector.selectRegion() else { return }
            // Let the overlay leave the screen before it gets photographed.
            try? await Task.sleep(for: .milliseconds(120))
            source = .screen
            rawText = ""
            phase = .reading
            presentPopover()
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
        if let draft = result.draft {
            self.draft = draft
            phase = .review
        } else {
            phase = .nothingFound
        }
    }

    // MARK: Card actions

    /// "Create anyway" when no date was found: a blank card with the text kept in the notes.
    func editManually() {
        draft = .blank(notes: String(rawText.prefix(500)))
        phase = .review
    }

    func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            guard await calendar.requestAccessIfNeeded() else { return }  // the card shows the denied banner
            do {
                phase = .saved(try calendar.save(draft))
            } catch {
                phase = .failed("Couldn't save the event: \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        work?.cancel()
        phase = .idle
    }

    func done() {
        closePopover()
        reset()
    }
}
