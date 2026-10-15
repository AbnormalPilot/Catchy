import SwiftUI

struct PopoverView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
                .transition(.blurReplace)
        }
        .padding(16)
        .frame(width: 340)
        .animation(.smooth(duration: 0.3), value: state.phase)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(.menuBarIcon)
                .foregroundStyle(.tint)
            Text("Catchy")
                .font(.headline)
            Spacer()
            if state.phase != .idle, state.phase != .needsScreenAccess {
                Label(state.source.rawValue, systemImage: state.source.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Toggle("Pause Catching", isOn: $state.isPaused)
                Toggle("Launch at Login", isOn: $state.launchesAtLogin)
                Divider()
                Button("Quit Catchy") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            IdleView(state: state)
        case .reading:
            ReadingView(text: state.rawText)
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
                message: "Catchy couldn't find when this happens.",
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
        VStack(alignment: .leading, spacing: 12) {
            if state.hasSeenWelcome {
                Text(state.isPaused
                     ? "Catching is paused. Use the buttons below, or turn it back on in the ••• menu."
                     : "Copy anything with a date in it, on this Mac or your iPhone, and Catchy turns it into an event.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                WelcomeView()
            }

            GlassEffectContainer {
                VStack(spacing: 8) {
                    Button {
                        state.captureScreen()
                    } label: {
                        HStack {
                            Label("Capture Screen", systemImage: "viewfinder")
                            Spacer()
                            Text("⌥⌘C").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        state.catchCurrentClipboard()
                    } label: {
                        Label("Catch from Clipboard", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
            }

            Label("Runs entirely on this Mac", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to Catchy")
                .font(.title3.weight(.semibold))
            Text("Turn dates you see into calendar events, without retyping.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                step("doc.on.clipboard", "Copy anything with a date", "on this Mac, or on your iPhone")
                step("viewfinder", "Press ⌥⌘C and drag", "over a flyer, poster or screenshot")
                step("contextualmenu.and.cursorarrow", "Or right-click selected text", "Services › Catch with Catchy")
                step("lock", "Everything stays on this Mac", "read by Apple's on-device model")
            }
            .padding(.vertical, 4)
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScreenAccessView: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Allow Screen Recording", systemImage: "rectangle.dashed.badge.record")
                .font(.headline)
            Text("To read text from part of your screen, Catchy needs Screen Recording access. It only looks at the area you select, and the image never leaves this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Click Allow Access, then switch on Catchy.")
                Text("2. Reopen Catchy so macOS applies the change.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Button("Reopen Catchy", action: ScreenCapturePermission.relaunch)
                    .buttonStyle(.glass)
                Spacer()
                Button("Allow Access", action: state.requestScreenAccess)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct ReadingView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text.isEmpty ? "Reading your screen…" : "Finding the event…")
                    .font(.callout.weight(.medium))
            }
            if !text.isEmpty {
                Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
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
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
            Text(saved.count == 1 ? (saved.titles.first ?? "") : "Added \(saved.count) items")
                .font(.headline)
                .multilineTextAlignment(.center)
            if saved.count == 1, let start = saved.firstStart {
                Text(saved.firstIsAllDay
                     ? start.formatted(.dateTime.weekday(.wide).month().day())
                     : start.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(saved.titles.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            let destination = saved.destinations.joined(separator: " and ")
            Label(
                saved.syncsWithICloud ? "Added to \(destination) · syncing to iPhone and Watch" : "Added to \(destination)",
                systemImage: saved.syncsWithICloud ? "icloud" : "calendar"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack {
                Button("Undo") { state.undo(saved) }
                    .buttonStyle(.glass)
                Button(onlyReminders ? "Open Reminders" : "Open Calendar") {
                    onlyReminders ? state.calendar.openRemindersApp() : state.calendar.openCalendarApp()
                    state.done()
                }
                .buttonStyle(.glass)
                Button("Done", action: state.done)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }
}

struct MessageView: View {
    let symbol: String
    let title: String
    let message: String
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if let secondary {
                    Button(secondary.0, action: secondary.1)
                        .buttonStyle(.glass)
                }
                Button(primary.0, action: primary.1)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
