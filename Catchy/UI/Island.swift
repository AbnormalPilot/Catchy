import AppKit
import SwiftUI

/// The notch "island": a pitch-black panel that grows out of the notch like the Dynamic Island.
@Observable
final class IslandModel {
    enum Mode {
        /// Tucked into the notch (window ordered out once the spring settles).
        case hidden
        /// Notch-height pill: logo plus activity or a "waiting" badge. Click to expand.
        case compact
        /// The full card.
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
    /// The size the panel needs; the controller fits the window to it.
    let onSize: (CGSize) -> Void
    let onExpand: () -> Void

    @State private var contentSize: CGSize = .zero

    static let ear: CGFloat = 8
    /// One interruptible spring for everything, so a quick re-open retargets instead of restarting.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    private var showsCompact: Bool { island.mode == .compact || state.phase == .reading }
    private var closedSize: CGSize { CGSize(width: island.notch.width + 2 * Self.ear, height: island.notch.height) }
    private var shapeSize: CGSize { island.mode == .hidden || contentSize == .zero ? closedSize : contentSize }
    private var bottomRadius: CGFloat { island.mode == .hidden ? 10 : (showsCompact ? 14 : 22) }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: Self.ear, bottomRadius: bottomRadius)
                .fill(.black)
                .frame(width: shapeSize.width, height: shapeSize.height)

            content
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: \.size) { size in
                    contentSize = size
                    onSize(CGSize(width: max(size.width, closedSize.width), height: max(size.height, closedSize.height)))
                }
                .opacity(island.mode == .hidden ? 0 : 1)
                .scaleEffect(island.mode == .hidden ? 0.94 : 1, anchor: .top)
        }
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
        .clipShape(NotchShape(topRadius: Self.ear, bottomRadius: bottomRadius))
        .animation(Self.spring, value: island.mode)
        .animation(Self.spring, value: contentSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        // Look like system UI even while another app has focus; no flash to grey controls.
        .environment(\.controlActiveState, .key)
    }

    @ViewBuilder
    private var content: some View {
        if showsCompact {
            CompactIsland(state: state, notch: island.notch)
                .contentShape(.rect)
                .onTapGesture { if state.phase != .reading { onExpand() } }
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

/// Dynamic Island "compact" look: logo left of the notch, activity or a waiting badge right of it.
private struct CompactIsland: View {
    let state: AppState
    let notch: CGSize

    var body: some View {
        HStack(spacing: 0) {
            Image(.menuBarIcon)
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(.white)
            // Clear of the camera housing's rounded corners, so nothing looks cut.
            Spacer(minLength: notch.width + 28)
            trailing
        }
        .padding(.horizontal, 12 + IslandView.ear)
        // A little taller than the notch, so the pill's rounded bottom shows below it.
        .frame(height: notch.height + 8)
    }

    @ViewBuilder
    private var trailing: some View {
        if state.phase == .reading {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
        } else {
            // A card is waiting: what kind, and how many.
            let count = max(state.drafts.count, 1)
            HStack(spacing: 3) {
                Image(systemName: state.drafts.first?.kind == .task ? "checklist" : "calendar")
                Text("\(count)")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white, in: .capsule)
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
        animationBehavior = .none
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
    private var appSwitches: Any?
    private var pendingShrink: DispatchWorkItem?
    private var pendingOrderOut: DispatchWorkItem?

    // Hovering the notch opens the island; leaving closes it again unless you clicked inside.
    private var hoverTimer: Timer?
    private var hoverStarted: Date?
    private var leftAt: Date?
    private var openedByHover = false
    private var pinned = false
    private var insideClicks: Any?

    /// Open as the full card (compact counts as closed, so the menu bar icon expands it).
    var isShown: Bool { model.mode == .expanded }
    /// Called after the island has fully closed (for resetting finished catches).
    var onClose: () -> Void = {}

    init(state: AppState) {
        self.state = state
        let hosting = NSHostingView(rootView: IslandView(
            state: state,
            island: model,
            onSize: { [weak self] size in self?.fit(size) },
            onExpand: { [weak self] in self?.show() }
        ))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onEscape = { [weak self] in self?.hide() }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackHover() }
        }
        insideClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.panel { self.pinned = true }
            }
            return event
        }

        // Switching apps while a card is open tucks it into the notch instead of dropping it.
        appSwitches = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.collapse()
            }
        }
    }

    func show(byHover: Bool = false) {
        openedByHover = byHover
        pinned = false
        leftAt = nil
        pendingOrderOut?.cancel()
        if model.mode == .hidden {
            screen = Self.targetScreen()
            // Start from the notch-sized frame, so a hover-open grows out of the notch.
            model.notch = Self.notchSize(on: screen)
            panel.setFrame(frame(for: size), display: false)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        model.mode = .expanded
        watchOutsideClicks(true)
    }

    /// Back into the notch. A card that's still waiting stays as a compact pill.
    func collapse() {
        guard model.mode == .expanded else { return }
        openedByHover = false
        if state.phase == .review {
            model.mode = .compact
            watchOutsideClicks(false)
        } else {
            hide()
        }
    }

    func hide() {
        guard model.mode != .hidden else { return }
        model.mode = .hidden
        watchOutsideClicks(false)
        // Let it shrink back into the notch before the window goes.
        let orderOut = DispatchWorkItem { [weak self] in
            guard let self, self.model.mode == .hidden else { return }
            self.panel.orderOut(nil)
            self.onClose()
        }
        pendingOrderOut = orderOut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: orderOut)
    }

    func toggle() {
        model.mode == .expanded ? collapse() : show()
    }

    private func trackHover() {
        let mouse = NSEvent.mouseLocation
        switch model.mode {
        case .hidden, .compact:
            // Brief dwell, no buttons held (not while dragging), and never mid-read.
            guard NSEvent.pressedMouseButtons == 0, state.phase != .reading, hoverZone().contains(mouse) else {
                hoverStarted = nil
                return
            }
            if let started = hoverStarted {
                if Date.now.timeIntervalSince(started) > 0.15 {
                    hoverStarted = nil
                    state.calendar.refreshAccess()
                    show(byHover: true)
                }
            } else {
                hoverStarted = .now
            }
        case .expanded:
            guard openedByHover, !pinned else { return }
            if panel.frame.insetBy(dx: -12, dy: -12).contains(mouse) {
                leftAt = nil
            } else if let leftAt {
                if Date.now.timeIntervalSince(leftAt) > 0.3 { collapse() }
            } else {
                leftAt = .now
            }
        }
    }

    /// The notch itself (or the pill, when one is showing); a thin strip at the top centre without a notch.
    private func hoverZone() -> NSRect {
        if model.mode == .compact { return panel.frame }
        guard let screen = Self.targetScreen() else { return .zero }
        let notch = Self.notchSize(on: screen)
        let hasNotch = screen.safeAreaInsets.top > 0
        let height = hasNotch ? notch.height : 4
        return NSRect(x: Self.notchCenterX(on: screen) - notch.width / 2, y: screen.frame.maxY - height,
                      width: notch.width, height: height)
    }

    private func watchOutsideClicks(_ on: Bool) {
        if on, outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Reading shows the compact island; a stray click shouldn't cancel it.
                    guard let self, self.state.phase != .reading else { return }
                    self.collapse()
                }
            }
        } else if !on, let monitor = outsideClicks {
            NSEvent.removeMonitor(monitor)
            outsideClicks = nil
        }
    }

    /// Grow the window at once; shrink it after the spring settles so the animation isn't clipped.
    private func fit(_ newSize: CGSize) {
        pendingShrink?.cancel()
        let grown = CGSize(width: max(newSize.width, size.width), height: max(newSize.height, size.height))
        if grown != size {
            size = grown
            panel.setFrame(frame(for: grown), display: false)
        }
        guard grown != newSize else { return }
        let shrink = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.size = newSize
            self.panel.setFrame(self.frame(for: newSize), display: false)
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
