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
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Catchy")
                .font(.headline)
            Spacer()
            if state.phase != .idle {
                Label(state.source.rawValue, systemImage: state.source.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Menu {
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
            EventCardView(state: state)
        case .nothingFound:
            MessageView(
                symbol: "calendar.badge.exclamationmark",
                title: "No date found",
                message: "Catchy couldn't find when this happens.",
                primary: ("Create Anyway", state.editManually),
                secondary: ("Cancel", state.done)
            )
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
            Text("Copy any text with a date in it, on this Mac or your iPhone, and Catchy turns it into an event.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                state.catchCurrentClipboard()
            } label: {
                Label("Catch from Clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Label("Runs entirely on this Mac", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ReadingView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading…")
                    .font(.callout.weight(.medium))
            }
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

private struct SavedView: View {
    let saved: SavedEvent
    let state: AppState
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
            Text(saved.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(saved.isAllDay
                 ? saved.start.formatted(.dateTime.weekday(.wide).month().day())
                 : saved.start.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                .font(.callout)
                .foregroundStyle(.secondary)
            Label(
                saved.syncsWithICloud ? "Added to \(saved.calendarTitle) · syncing to iPhone and Watch" : "Added to \(saved.calendarTitle)",
                systemImage: saved.syncsWithICloud ? "icloud" : "calendar"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack {
                Button("Open Calendar") {
                    state.calendar.openCalendarApp()
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
