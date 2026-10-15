import SwiftUI

/// What the expanded island shows under the notch strip. Kept tight, like system UI.
struct IslandContent: View {
    @Bindable var state: AppState

    static let width: CGFloat = 300

    var body: some View {
        content
            .frame(width: Self.width, alignment: .leading)
            .transition(.opacity)
            .animation(IslandView.spring, value: state.phase)
            .font(.system(size: 12))
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            IdleView(state: state)
        case .reading:
            EmptyView()  // shown as the compact island
        case .review:
            if state.showsList {
                CatchListView(state: state)
            } else {
                EventCardView(state: state)
            }
        case .nothingFound:
            MessageView(
                symbol: "calendar.badge.exclamationmark",
                title: "No date found",
                message: "Catchy couldn't tell when this happens.",
                primary: ("Create Anyway", state.editManually),
                secondary: ("Cancel", state.done)
            )
        case .needsScreenAccess:
            ScreenAccessView(state: state)
        case .listening:
            ListeningView(state: state)
        case .saved(let saved):
            SavedView(saved: saved, state: state)
        case .failed(let message):
            MessageView(
                symbol: "exclamationmark.triangle",
                title: "Something went wrong",
                message: message,
                primary: ("OK", state.reset),
                secondary: nil
            )
        }
    }
}

// MARK: - States

private struct IdleView: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.hasSeenWelcome {
                Text(state.isPaused
                     ? "Paused. Turn catching back on from the ••• menu."
                     : "Copy anything with a date, here or on your iPhone.")
                    .foregroundStyle(.secondary)
            } else {
                WelcomeView()
            }

            HStack(spacing: 6) {
                Button {
                    state.captureScreen()
                } label: {
                    Label(state.shortcutIsActive ? "Capture  ⌥⌘" : "Capture", systemImage: "viewfinder")
                }
                .buttonStyle(.islandProminent)
                Button {
                    state.catchCurrentClipboard()
                } label: {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.island)
                Button {
                    state.startListening()
                } label: {
                    Image(systemName: "mic.fill")
                }
                .buttonStyle(.island)
                .help("Say it: \"lunch with Sam tomorrow at one\"")
                Spacer(minLength: 0)
            }

            if !state.shortcutIsActive {
                ShortcutSetupRow()
            }
        }
    }
}

private struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Welcome to Catchy")
                .font(.system(size: 14, weight: .semibold))
            step("doc.on.clipboard", "Copy anything with a date, here or on iPhone")
            step("command", "Tap ⌥⌘ and drag over a flyer")
            step("contextualmenu.and.cursorarrow", "Right-click › Services › Catch with Catchy")
            step("lock", "Read on this Mac by Apple's on-device model")
        }
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.white)
        }
    }
}

/// The ⌥⌘ tap needs Input Monitoring, which only the user can grant.
private struct ShortcutSetupRow: View {
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Turn on the ⌥⌘ shortcut")
                    .font(.system(size: 12, weight: .medium))
                Text("Needs Input Monitoring. Catchy never sees what you type.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Turn On", action: InputMonitoringPermission.request)
                .buttonStyle(.island)
        }
        .padding(8)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 10))
    }
}

/// Live dictation: a waveform that follows your voice, the words as they come, and Done/Cancel.
private struct ListeningView: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Waveform(level: state.voice.level)
                Text(state.voice.transcript.isEmpty ? "Listening… say when and what" : "Listening…")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            if !state.voice.transcript.isEmpty {
                Text(state.voice.transcript)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: state.voice.transcript)
            }
            HStack(spacing: 6) {
                Label("On this Mac", systemImage: "lock.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: state.cancelListening)
                    .buttonStyle(.island)
                    .keyboardShortcut(.cancelAction)
                Button("Done", action: state.finishListening)
                    .buttonStyle(.islandProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Five bars that rise and fall with the microphone level.
private struct Waveform: View {
    let level: Float
    private let weights: [CGFloat] = [0.45, 0.8, 1, 0.75, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.red)
                    .frame(width: 3, height: 4 + 16 * CGFloat(level) * weights[index])
            }
        }
        .frame(width: 24, height: 22)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: level)
    }
}

private struct ScreenAccessView: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow Screen Recording")
                .font(.system(size: 14, weight: .semibold))
            Text("Catchy reads only the area you select, on this Mac. Allow it, then reopen Catchy.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Spacer()
                Button("Reopen", action: ScreenCapturePermission.relaunch)
                    .buttonStyle(.island)
                Button("Allow", action: state.requestScreenAccess)
                    .buttonStyle(.islandProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The confirmation: a green check pops in and draws itself, the card shrinks to one line, and
/// the island tucks itself away a few seconds later (Undo stays until then).
private struct SavedView: View {
    let saved: SavedCatch
    let state: AppState

    private var onlyReminders: Bool { saved.eventIDs.isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            AnimatedCheck()
            VStack(alignment: .leading, spacing: 1) {
                Text(saved.count == 1 ? (saved.titles.first ?? "") : "Added \(saved.count) items")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .transition(.opacity.combined(with: .offset(x: -6)))
            Spacer(minLength: 6)
            Button("Undo") { state.undo(saved) }
                .buttonStyle(.island)
            Button {
                onlyReminders ? state.calendar.openRemindersApp() : state.calendar.openCalendarApp()
                state.done()
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.island)
            .help(onlyReminders ? "Open Reminders" : "Open Calendar")
        }
    }

    private var subtitle: String {
        let destination = saved.destinations.joined(separator: ", ")
        let sync = saved.syncsWithICloud ? " · syncing to iPhone" : ""
        guard saved.count == 1, let start = saved.firstStart else { return "Added to \(destination)\(sync)" }
        let when = saved.firstIsAllDay
            ? start.formatted(.dateTime.weekday(.abbreviated).month().day())
            : start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
        return "\(when) · \(destination)\(sync)"
    }
}

/// Green disc springs in, then the tick draws itself.
private struct AnimatedCheck: View {
    @State private var popped = false
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.green)
                .scaleEffect(popped ? 1 : 0.2)
                .opacity(popped ? 1 : 0)
            Circle()
                .stroke(.green.opacity(0.5), lineWidth: 2)
                .scaleEffect(popped ? 1.6 : 1)
                .opacity(popped ? 0 : 0.8)
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(.black, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 26, height: 26)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { popped = true }
            withAnimation(.easeOut(duration: 0.28).delay(0.15)) { drawn = true }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.36))
        return path
    }
}

/// The primary button's label: icon and title, or a dark spinner while saving (the button is
/// white, so a default spinner would be invisible), at a steady width.
struct AddLabel: View {
    let title: String
    let symbol: String
    let isSaving: Bool

    var body: some View {
        ZStack {
            Label(title, systemImage: symbol)
                .opacity(isSaving ? 0 : 1)
            if isSaving {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.black)
                    .colorScheme(.light)
            }
        }
    }
}

struct MessageView: View {
    let symbol: String
    let title: String
    let message: String
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Spacer()
                if let secondary {
                    Button(secondary.0, action: secondary.1)
                        .buttonStyle(.island)
                }
                Button(primary.0, action: primary.1)
                    .buttonStyle(.islandProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
