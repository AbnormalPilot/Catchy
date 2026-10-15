import SwiftUI

/// Several events or tasks from one capture (a schedule, an agenda, a syllabus).
struct CatchListView: View {
    @Bindable var state: AppState

    private var calendar: CalendarService { state.calendar }
    private var included: [EventDraft] { state.includedDrafts }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found \(state.drafts.count)")
                .font(.title3.weight(.semibold))

            VStack(spacing: 2) {
                ForEach($state.drafts) { $draft in
                    Row(draft: $draft) { state.open(draft) }
                }
            }
            .padding(4)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))

            ForEach(deniedKinds, id: \.self) { kind in
                AccessDeniedBanner(kind: kind, calendar: calendar)
            }

            ModelNote(state: state)

            HStack {
                Button("Discard", action: state.done)
                    .buttonStyle(.island)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    state.save()
                } label: {
                    if state.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(saveTitle, systemImage: "plus")
                    }
                }
                .buttonStyle(.islandProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(included.isEmpty || !deniedKinds.isEmpty)
            }
        }
    }

    private var deniedKinds: [CatchKind] {
        [CatchKind.event, .task].filter { kind in
            included.contains { $0.kind == kind } && calendar.access(for: kind) == .denied
        }
    }

    /// "Add 3 Events", "Add 2 Reminders", "Add 4 Items".
    private var saveTitle: String {
        let kinds = Set(included.map(\.kind))
        let noun = kinds.count > 1 ? "Items" : (kinds.first == .task ? "Reminders" : "Events")
        return included.count == 1 ? "Add 1 \(String(noun.dropLast()))" : "Add \(included.count) \(noun)"
    }

    private struct Row: View {
        @Binding var draft: EventDraft
        let open: () -> Void

        var body: some View {
            HStack(spacing: 10) {
                Toggle("", isOn: $draft.isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Button(action: open) {
                    HStack(spacing: 8) {
                        Image(systemName: draft.kind == .event ? "calendar" : "checklist")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(draft.title.isEmpty ? "Untitled" : draft.title)
                                .lineLimit(1)
                            Text(when)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .opacity(draft.isIncluded ? 1 : 0.5)
        }

        private var when: String {
            draft.isAllDay
                ? draft.start.formatted(.dateTime.weekday(.abbreviated).month().day())
                : draft.start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
        }
    }
}
