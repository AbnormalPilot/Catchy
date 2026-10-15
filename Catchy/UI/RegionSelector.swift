import AppKit

/// Dims every screen and lets you drag out a rectangle, like ⇧⌘4. Esc or a plain click cancels.
final class RegionSelector {
    private var windows: [SelectionWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    /// Returns the chosen rect in AppKit screen coordinates, or nil if cancelled.
    func selectRegion() async -> CGRect? {
        finish(with: nil)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate()
            windows = NSScreen.screens.map { screen in
                let window = SelectionWindow(screen: screen) { [weak self] rect in self?.finish(with: rect) }
                window.orderFrontRegardless()
                return window
            }
            // Put the key window under the pointer so Esc works where you're looking.
            let mouse = NSEvent.mouseLocation
            (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
        }
    }

    private func finish(with rect: CGRect?) {
        guard let continuation else { return }
        self.continuation = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        continuation.resume(returning: rect)
    }
}

private final class SelectionWindow: NSWindow {
    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setFrame(screen.frame, display: false)
        acceptsMouseMovedEvents = true

        let view = SelectionView()
        view.onFinish = { [weak self] localRect in
            guard let self else { return }
            onFinish(localRect.map { self.convertToScreen($0) })
        }
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: (CGRect?) -> Void = { _ in }
    private var origin: NSPoint?
    private var current: NSPoint?

    private var selection: NSRect? {
        guard let origin, let current else { return nil }
        return NSRect(
            x: min(origin.x, current.x), y: min(origin.y, current.y),
            width: abs(origin.x - current.x), height: abs(origin.y - current.y)
        )
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            NSColor.white.withAlphaComponent(0.9).setStroke()
            border.stroke()
        } else {
            drawHint()
        }
    }

    private func drawHint() {
        let text = "Drag over the text to catch  ·  Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let pill = NSRect(
            x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - 120,
            width: size.width + 32, height: size.height + 14
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: NSPoint(x: pill.minX + 16, y: pill.minY + 7), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        origin = convert(event.locationInWindow, from: nil)
        current = origin
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        if let selection, selection.width > 8, selection.height > 8 {
            onFinish(selection)
        } else {
            onFinish(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } else { super.keyDown(with: event) }  // Esc
    }

    override func cancelOperation(_ sender: Any?) {
        onFinish(nil)
    }
}
