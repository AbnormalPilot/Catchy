import AppKit
import SwiftUI

/// The notch "island": a pitch-black panel that grows out of the notch like the Dynamic Island.
/// Compact (notch-height, logo + spinner) while reading; expanded into the card otherwise.
@Observable
final class IslandModel {
    var isOpen = false
    /// The physical notch on the screen it's shown on, or a menu-bar-height stand-in without one.
    var notch = CGSize(width: 185, height: 32)
}

/// Black shape with the notch's outward-curving top "ears" and rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, rect.height / 2, (rect.width - 2 * top) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandView: View {
    @Bindable var state: AppState
    let island: IslandModel
    /// The size the panel needs; the controller fits the window to it.
    let onSize: (CGSize) -> Void

    @State private var contentSize: CGSize = .zero

    private static let ear: CGFloat = 8
    private var isCompact: Bool { state.phase == .reading }
    private var closedSize: CGSize { CGSize(width: island.notch.width + 2 * Self.ear, height: island.notch.height) }
    private var shapeSize: CGSize { island.isOpen && contentSize != .zero ? contentSize : closedSize }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: Self.ear, bottomRadius: island.isOpen ? (isCompact ? 14 : 26) : 10)
                .fill(.black)
                .frame(width: shapeSize.width, height: shapeSize.height)

            content
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: \.size) { size in
                    contentSize = size
                    onSize(CGSize(width: max(size.width, closedSize.width), height: max(size.height, closedSize.height)))
                }
                .opacity(island.isOpen ? 1 : 0)
                .blur(radius: island.isOpen ? 0 : 8)
                .scaleEffect(island.isOpen ? 1 : 0.92, anchor: .top)
        }
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
        .clipShape(NotchShape(topRadius: Self.ear, bottomRadius: island.isOpen ? (isCompact ? 14 : 26) : 10))
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: island.isOpen)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: contentSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if isCompact {
            // Dynamic Island "compact" look: logo left of the notch, activity right of it.
            HStack(spacing: 0) {
                Image(.menuBarIcon)
                    .foregroundStyle(.white)
                Spacer(minLength: island.notch.width)
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            .padding(.horizontal, 14 + Self.ear)
            .frame(width: island.notch.width + 2 * Self.ear + 96, height: island.notch.height)
        } else {
            IslandContent(state: state)
                .padding(.top, island.notch.height + 8)
                .padding(.horizontal, 18 + Self.ear)
                .padding(.bottom, 18)
        }
    }
}

/// Borderless and non-activating, so it can take typing without pulling focus from your app,
/// the way system UI does.
final class IslandPanel: NSPanel {
    var onEscape: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Above the menu bar, so it can sit in the notch.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }
}

final class IslandController {
    private let state: AppState
    private let model = IslandModel()
    private let panel = IslandPanel()
    private var screen: NSScreen?
    private var size = CGSize(width: 201, height: 32)
    private var outsideClicks: Any?
    private var pendingShrink: DispatchWorkItem?

    var isShown: Bool { model.isOpen }
    /// Called after the island closes (for resetting finished catches).
    var onClose: () -> Void = {}

    init(state: AppState) {
        self.state = state
        let hosting = NSHostingView(rootView: IslandView(state: state, island: model) { [weak self] size in
            self?.fit(size)
        })
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onEscape = { [weak self] in self?.hide() }
    }

    func show() {
        pendingShrink?.cancel()
        let screen = Self.targetScreen()
        self.screen = screen
        model.notch = Self.notchSize(on: screen)
        panel.setFrame(frame(for: size), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        model.isOpen = true

        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Reading shows the compact island; a stray click shouldn't cancel it.
                    guard let self, self.state.phase != .reading else { return }
                    self.hide()
                }
            }
        }
    }

    func hide() {
        guard model.isOpen else { return }
        model.isOpen = false
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        // Let it shrink back into the notch before it goes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.model.isOpen else { return }
            self.panel.orderOut(nil)
            self.onClose()
        }
    }

    func toggle() {
        model.isOpen ? hide() : show()
    }

    /// Grow the window at once; shrink it after the spring settles so the animation isn't clipped.
    private func fit(_ newSize: CGSize) {
        pendingShrink?.cancel()
        let grown = CGSize(width: max(newSize.width, size.width), height: max(newSize.height, size.height))
        size = grown
        panel.setFrame(frame(for: grown), display: true)
        guard grown != newSize else { return }
        let shrink = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.size = newSize
            self.panel.setFrame(self.frame(for: newSize), display: true)
        }
        pendingShrink = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: shrink)
    }

    private func frame(for size: CGSize) -> NSRect {
        guard let screen = screen ?? NSScreen.main else { return .zero }
        let centerX = Self.notchCenterX(on: screen)
        return NSRect(x: (centerX - size.width / 2).rounded(), y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// The screen you're working on: the one under the pointer.
    private static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private static func notchSize(on screen: NSScreen?) -> CGSize {
        guard let screen else { return CGSize(width: 185, height: 32) }
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
        }
        // No notch: grow out of the top edge from a notch-sized slit hidden in the menu bar.
        return CGSize(width: 185, height: NSStatusBar.system.thickness)
    }

    private static func notchCenterX(on screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            return screen.frame.minX + (left.maxX + right.minX) / 2
        }
        return screen.frame.midX
    }
}

// MARK: - Buttons

/// White capsule (primary) or translucent capsule (secondary), like system UI on black.
struct IslandButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, prominent: prominent)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .background(prominent ? Color.white : Color.white.opacity(0.12), in: .capsule)
                .contentShape(.capsule)
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == IslandButtonStyle {
    static var island: IslandButtonStyle { IslandButtonStyle() }
    static var islandProminent: IslandButtonStyle { IslandButtonStyle(prominent: true) }
}
