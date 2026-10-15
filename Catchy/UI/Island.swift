import AppKit
import SwiftUI

/// The notch "island": a pitch-black panel that grows out of the notch like the Dynamic Island.
@Observable
final class IslandModel {
    enum Mode {
        /// Tucked into the notch (window ordered out once the spring settles). A waiting card is
        /// kept; hovering the notch brings it back. Nothing stays on screen while idle.
        case hidden
        /// Open. Shown compact (notch-height spinner) while reading, otherwise the full card.
        case expanded
    }

    var mode: Mode = .hidden
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
    /// The black shape's current target size, for hit-testing (clicks elsewhere pass through).
    let onShapeSize: (CGSize) -> Void

    @State private var contentSize: CGSize = .zero

    static let ear: CGFloat = 8
    /// One interruptible spring for the shape, so a quick re-open retargets instead of restarting.
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.8)

    private var isOpen: Bool { island.mode == .expanded }
    private var showsCompact: Bool { state.phase == .reading }
    private var closedSize: CGSize { CGSize(width: island.notch.width + 2 * Self.ear, height: island.notch.height) }
    private var shapeSize: CGSize { !isOpen || contentSize == .zero ? closedSize : contentSize }
    private var bottomRadius: CGFloat { isOpen ? (showsCompact ? 14 : 22) : 10 }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: Self.ear, bottomRadius: bottomRadius)
                .fill(.black)
                // The window never leaves the screen; once tucked into the notch the shape vanishes.
                .opacity(isOpen ? 1 : 0)
                .animation(isOpen ? nil : .easeOut(duration: 0.12).delay(0.3), value: isOpen)

            content
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: \.size) { size in
                    contentSize = size
                }
                // Content arrives just after the shape starts to grow, and leaves first.
                .opacity(isOpen ? 1 : 0)
                .scaleEffect(isOpen ? 1 : 0.96, anchor: .top)
                .animation(isOpen ? .easeOut(duration: 0.18).delay(0.03) : .easeIn(duration: 0.08), value: isOpen)
        }
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
        .clipShape(NotchShape(topRadius: Self.ear, bottomRadius: bottomRadius))
        .animation(Self.spring, value: shapeSize)
        .animation(Self.spring, value: bottomRadius)
        .onChange(of: shapeSize, initial: true) { _, size in onShapeSize(size) }
        // A fixed canvas: the window never resizes mid-animation, which is what made it stutter.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        // Look like system UI even while another app has focus; no flash to grey controls.
        .environment(\.controlActiveState, .key)
    }

    @ViewBuilder
    private var content: some View {
        if showsCompact {
            CompactIsland(notch: island.notch)
        } else {
            VStack(spacing: 0) {
                IslandHeader(state: state, notch: island.notch)
                IslandContent(state: state)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
            }
            .padding(.horizontal, 14 + Self.ear)
        }
    }
}

/// The strip beside the notch: logo on the left, source and menu on the right.
private struct IslandHeader: View {
    @Bindable var state: AppState
    let notch: CGSize
    @State private var showsSource = false

    var body: some View {
        HStack(spacing: 8) {
            Image(.menuBarIcon)
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(.white)
            Spacer(minLength: notch.width + 12)
            if state.phase == .review || state.phase == .nothingFound {
                Button {
                    showsSource.toggle()
                } label: {
                    Image(systemName: state.source.symbol)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show what Catchy read (\(state.source.rawValue))")
                .popover(isPresented: $showsSource, arrowEdge: .bottom) {
                    ScrollView {
                        Text(state.rawText)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(width: 260, height: 140)
                }
            }
            Menu {
                Toggle("Pause Catching", isOn: $state.isPaused)
                Toggle("Launch at Login", isOn: $state.launchesAtLogin)
                Divider()
                Button("Quit Catchy") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .font(.system(size: 12, weight: .medium))
        .frame(height: notch.height)
    }
}

/// Dynamic Island "compact" look while reading: logo left of the notch, spinner right of it.
private struct CompactIsland: View {
    let notch: CGSize

    var body: some View {
        HStack(spacing: 0) {
            Image(.menuBarIcon)
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(.white)
            // Clear of the camera housing's rounded corners, so nothing looks cut.
            Spacer(minLength: notch.width + 28)
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
        }
        .padding(.horizontal, 12 + IslandView.ear)
        // A little taller than the notch, so the rounded bottom shows below it.
        .frame(height: notch.height + 8)
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
        animationBehavior = .none
        acceptsMouseMovedEvents = true
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
    /// Big enough for the largest card. The window keeps this size; only the black shape animates.
    private static let canvas = CGSize(width: 400, height: 520)

    private let state: AppState
    private let model = IslandModel()
    private let panel = IslandPanel()
    private var screen: NSScreen?
    private var shapeSize: CGSize = .zero
    private var outsideClicks: Any?
    private var appSwitches: Any?
    private var insideClicks: Any?
    private var pendingClose: DispatchWorkItem?
    private var spaceChanges: Any?

    // Hovering the notch opens the island; leaving closes it again unless you clicked inside.
    // Driven by mouse-moved events (instant), with a slow timer as a safety net.
    private var mouseMoves: [Any] = []
    private var tracker: Timer?
    private var pendingHoverOpen: DispatchWorkItem?
    private var pendingLeave: DispatchWorkItem?
    private var openedByHover = false
    private var pinned = false

    var isShown: Bool { model.mode == .expanded }
    /// Called after the island has fully closed (for resetting finished catches).
    var onClose: () -> Void = {}

    init(state: AppState) {
        self.state = state
        let hosting = NSHostingView(rootView: IslandView(state: state, island: model) { [weak self] size in
            self?.shapeSize = size
        })
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onEscape = { [weak self] in self?.hide(reason: "escape") }

        // Mouse-moved events need no permission. Global covers other apps (full-screen ones
        // included); local covers the pointer over our own panel.
        mouseMoves.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        } as Any)
        mouseMoves.append(NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated { self?.track() }
            return event
        } as Any)
        tracker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        insideClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.panel { self.pinned = true }
            }
            return event
        }
        // The window stays up for good (transparent and click-through while closed). Taking it off
        // screen and back is what lost it on other apps' full-screen spaces (VS Code, Chrome).
        screen = Self.targetScreen()
        model.notch = Self.notchSize(on: screen)
        panel.setFrame(canvasFrame(), display: false)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        spaceChanges = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.orderFrontRegardless() }
        }

        // Switching apps tucks the island away; a waiting card comes back on hover.
        appSwitches = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      self?.state.phase != .reading else { return }
                self?.hide(reason: "app switch to \(app?.localizedName ?? "?")")
            }
        }
    }

    func show(byHover: Bool = false) {
        openedByHover = byHover
        pinned = false
        pendingLeave?.cancel()
        pendingHoverOpen?.cancel()
        pendingClose?.cancel()
        // Follow the pointer to another display.
        if model.mode == .hidden, let target = Self.targetScreen(), target != screen {
            screen = target
            model.notch = Self.notchSize(on: target)
            panel.setFrame(canvasFrame(), display: false)
        }
        panel.orderFrontRegardless()
        // A hover only peeks; focus moves to the island once you click in it.
        if !byHover { panel.makeKey() }
        model.mode = .expanded
        watchOutsideClicks(true)
    }

    func hide(reason: String = "other") {
        guard model.mode != .hidden else { return }
        model.mode = .hidden
        openedByHover = false
        watchOutsideClicks(false)
        panel.ignoresMouseEvents = true
        // The window stays up, so hand keyboard focus back to the app you were using.
        if panel.isKeyWindow, let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate()
        }
        let close = DispatchWorkItem { [weak self] in
            guard let self, self.model.mode == .hidden else { return }
            self.onClose()
        }
        pendingClose = close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: close)
    }

    func toggle() {
        model.mode == .expanded ? hide() : show()
    }

    /// On every mouse move: hover-to-open, leave-to-close, and click-through outside the black shape.
    private func track() {
        let mouse = NSEvent.mouseLocation
        // Only the black shape takes clicks; the rest of the canvas (and all of it while closed) passes them through.
        panel.ignoresMouseEvents = !(model.mode == .expanded && shapeRect().contains(mouse))

        switch model.mode {
        case .hidden:
            // A short dwell so passing through doesn't open it; never while dragging.
            guard NSEvent.pressedMouseButtons == 0, notchRect().contains(mouse) else {
                pendingHoverOpen?.cancel()
                pendingHoverOpen = nil
                return
            }
            guard pendingHoverOpen == nil else { return }
            let open = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingHoverOpen = nil
                guard self.model.mode == .hidden, self.notchRect().contains(NSEvent.mouseLocation) else { return }
                self.state.calendar.refreshAccess()
                self.show(byHover: true)
            }
            pendingHoverOpen = open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: open)
        case .expanded:
            guard openedByHover, !pinned, state.phase != .reading else { return }
            if shapeRect().insetBy(dx: -14, dy: -14).contains(mouse) {
                pendingLeave?.cancel()
                pendingLeave = nil
            } else if pendingLeave == nil {
                let leave = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingLeave = nil
                    guard self.openedByHover, !self.pinned,
                          !self.shapeRect().insetBy(dx: -14, dy: -14).contains(NSEvent.mouseLocation) else { return }
                    self.hide(reason: "pointer left")
                }
                pendingLeave = leave
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: leave)
            }
        }
    }

    private func watchOutsideClicks(_ on: Bool) {
        if on, outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Reading shows the compact island; a stray click shouldn't cancel it.
                    guard let self, self.state.phase != .reading else { return }
                    self.hide(reason: "outside click")
                }
            }
        } else if !on, let monitor = outsideClicks {
            NSEvent.removeMonitor(monitor)
            outsideClicks = nil
        }
    }

    private func canvasFrame() -> NSRect {
        guard let screen = screen ?? NSScreen.main else { return .zero }
        let size = Self.canvas
        return NSRect(x: (Self.notchCenterX(on: screen) - size.width / 2).rounded(), y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// Where the black shape is on screen right now.
    private func shapeRect() -> NSRect {
        let frame = panel.frame
        return NSRect(x: frame.midX - shapeSize.width / 2, y: frame.maxY - shapeSize.height,
                      width: shapeSize.width, height: shapeSize.height)
    }

    /// The notch itself; a thin strip at the top centre on a screen without one.
    private func notchRect() -> NSRect {
        guard let screen = Self.targetScreen() else { return .zero }
        let notch = Self.notchSize(on: screen)
        let height = screen.safeAreaInsets.top > 0 ? notch.height : 4
        return NSRect(x: Self.notchCenterX(on: screen) - notch.width / 2, y: screen.frame.maxY - height,
                      width: notch.width, height: height)
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
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .background(prominent ? Color.white : Color.white.opacity(0.13), in: .capsule)
                .contentShape(.capsule)
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == IslandButtonStyle {
    static var island: IslandButtonStyle { IslandButtonStyle() }
    static var islandProminent: IslandButtonStyle { IslandButtonStyle(prominent: true) }
}
