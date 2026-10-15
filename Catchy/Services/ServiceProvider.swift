import AppKit

/// "Catch with Catchy" in every app's right-click › Services menu (declared under
/// `NSServices` in Info.plist). Select text, pick it, and the card opens.
final class ServiceProvider: NSObject {
    var onText: (String) -> Void = { _ in }

    @objc func catchText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            error.pointee = "No text was selected." as NSString
            return
        }
        onText(text)
    }
}
