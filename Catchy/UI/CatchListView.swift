import SwiftUI

/// Several events or tasks from one capture (a schedule, an agenda, a syllabus).
struct CatchListView: View {
    @Bindable var state: AppState

    private var calendar: CalendarService { state.calendar }
    private var included: [EventDraft] { state.includedDrafts }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Found \(state.drafts.count)")
                .font(.system(size: 15, weight: .semibold))

            VStack(spacing: 0) {
                ForEach($state.drafts) { $draft in
                    Row(draft: $draft) { state.open(draft) }
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 9))

            ForEach(deniedKinds, id: \.self) { kind in
                AccessDeniedBanner(kind: kind, calendar: calendar)
            }

            HStack(spacing: 6) {
                ModelNote(state: state)
                Spacer(minLength: 0)
                Button("Discard", action: state.done)
                    .buttonStyle(.island)
                    .keyboardShortcut(.cancelAction)
                Button {
                    state.save()
                } label: {
                    AddLabel(title: saveTitle, symbol: "plus", isSaving: state.isSaving)
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
            HStack(spacing: 8) {
                Toggle("", isOn: $draft.isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Button(action: open) {
                    HStack(spacing: 6) {
                        Image(systemName: draft.kind == .event ? "calendar" : "checklist")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 13)
                        Text(draft.title.isEmpty ? "Untitled" : draft.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(when)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .opacity(draft.isIncluded ? 1 : 0.5)
        }

        private var when: String {
            draft.isAllDay
                ? draft.start.formatted(.dateTime.weekday(.abbreviated).month().day())
                : draft.start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
        }
    }
}
