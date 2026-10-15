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

private struct SavedView: View {
    let saved: SavedCatch
    let state: AppState
    @State private var appeared = false

    private var onlyReminders: Bool { saved.eventIDs.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: appeared)
                VStack(alignment: .leading, spacing: 1) {
                    Text(saved.count == 1 ? (saved.titles.first ?? "") : "Added \(saved.count) items")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                Button("Undo") { state.undo(saved) }
                    .buttonStyle(.island)
                Button(onlyReminders ? "Reminders" : "Calendar") {
                    onlyReminders ? state.calendar.openRemindersApp() : state.calendar.openCalendarApp()
                    state.done()
                }
                .buttonStyle(.island)
                Spacer()
                Button("Done", action: state.done)
                    .buttonStyle(.islandProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { appeared = true }
    }

    private var subtitle: String {
        let destination = saved.destinations.joined(separator: ", ")
        let sync = saved.syncsWithICloud ? " · syncing to iPhone" : ""
        guard saved.count == 1, let start = saved.firstStart else { return destination + sync }
        let when = saved.firstIsAllDay
            ? start.formatted(.dateTime.weekday(.abbreviated).month().day())
            : start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
        return "\(when) · \(destination)\(sync)"
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
