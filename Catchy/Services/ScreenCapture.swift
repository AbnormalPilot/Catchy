import AppKit
import ScreenCaptureKit
import Vision

enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time only; later calls just return the current state.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// macOS only applies a new Screen Recording grant to a fresh process.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

enum ScreenReader {
    /// Captures a rect given in AppKit screen coordinates and returns the text Vision finds in it.
    static func readText(in appKitRect: CGRect) async throws -> String {
        // ScreenCaptureKit wants global display space: origin at the primary screen's top-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let displayRect = CGRect(
            x: appKitRect.minX,
            y: primaryHeight - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
        let image = try await SCScreenshotManager.captureImage(in: displayRect)

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: image)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
