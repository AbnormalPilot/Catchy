import EventKit
import SwiftUI

/// The pre-filled, editable card for one event or task.
struct EventCardView: View {
    @Bindable var state: AppState
    @State private var showsSource = false

    private var calendar: CalendarService { state.calendar }
    private var kind: CatchKind { state.draft.kind }
    private var fromList: Bool { state.drafts.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if fromList {
                Button {
                    state.backToList()
                } label: {
                    Label("All \(state.drafts.count) catches", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                TextField(kind == .event ? "Event title" : "Reminder", text: $state.draft.title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                kindPicker
            }

            VStack(spacing: 8) {
                Toggle(kind == .event ? "All-day" : "Any time", isOn: $state.draft.isAllDay.animation())
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                datePicker(kind == .event ? "Starts" : "Due", selection: startBinding)
                if kind == .event {
                    datePicker("Ends", selection: $state.draft.end, in: state.draft.start...)
                }
                if let zone = state.draft.sourceTimeZone, !state.draft.isAllDay {
                    Label("\(TimeZones.label(state.draft.start, in: zone)) · shown in your time", systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if let clash = calendar.clash(for: state.draft) {
                Label("Clashes with \(clash.title ?? "an event") at \(clash.startDate.formatted(date: .omitted, time: .shortened))",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if kind == .event {
                field("mappin.and.ellipse", "Location", text: $state.draft.location)
            }
            field("text.alignleft", "Notes", text: $state.draft.notes)

            if calendar.access(for: kind) == .granted {
                destinationPicker
            }

            if calendar.access(for: kind) == .denied {
                AccessDeniedBanner(kind: kind, calendar: calendar)
            }

            ModelNote(state: state)

            DisclosureGroup("Original text", isExpanded: $showsSource) {
                ScrollView {
                    Text(state.rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                if fromList {
                    Button("Done Editing", action: state.backToList)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Discard", action: state.done)
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button {
                        state.save()
                    } label: {
                        if state.isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(kind == .event ? "Add to Calendar" : "Add to Reminders",
                                  systemImage: kind == .event ? "calendar.badge.plus" : "checklist")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(calendar.access(for: kind) == .denied)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $state.draft.kind) {
            Image(systemName: "calendar").tag(CatchKind.event)
            Image(systemName: "checklist").tag(CatchKind.task)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Event in Calendar, or task in Reminders")
    }

    /// Moving the start drags the end along, like Calendar does. A binding rather than
    /// `onChange`, which also fired when a new catch replaced the draft and broke its end time.
    private var startBinding: Binding<Date> {
        Binding(
            get: { state.draft.start },
            set: { newStart in
                let shift = newStart.timeIntervalSince(state.draft.start)
                state.draft.start = newStart
                state.draft.end = state.draft.end.addingTimeInterval(shift)
            }
        )
    }

    private func datePicker(_ title: String, selection: Binding<Date>, in range: PartialRangeFrom<Date>? = nil) -> some View {
        let components: DatePickerComponents = state.draft.isAllDay ? .date : [.date, .hourAndMinute]
        return Group {
            if let range {
                DatePicker(title, selection: selection, in: range, displayedComponents: components)
            } else {
                DatePicker(title, selection: selection, displayedComponents: components)
            }
        }
        .datePickerStyle(.compact)
    }

    private func field(_ symbol: String, _ prompt: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            TextField(prompt, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var destinationPicker: some View {
        if kind == .event {
            CalendarPicker(
                calendars: calendar.calendars,
                selection: Binding(
                    get: { calendar.targetCalendar?.calendarIdentifier ?? "" },
                    set: { calendar.selectedCalendarID = $0 }
                )
            )
        } else {
            CalendarPicker(
                calendars: calendar.reminderLists,
                selection: Binding(
                    get: { calendar.targetReminderList?.calendarIdentifier ?? "" },
                    set: { calendar.selectedReminderListID = $0 }
                )
            )
        }
    }
}

/// Picks a calendar or reminders list, with its colour and account.
struct CalendarPicker: View {
    let calendars: [EKCalendar]
    @Binding var selection: String

    var body: some View {
        if !calendars.isEmpty {
            Picker(selection: $selection) {
                ForEach(calendars, id: \.calendarIdentifier) { item in
                    HStack {
                        Image(nsImage: Self.swatch(item.color))
                        Text(item.title)
                        Text(item.source.title).foregroundStyle(.secondary)
                    }
                    .tag(item.calendarIdentifier)
                }
            } label: {
                Image(systemName: "tray.full")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Menu items render SwiftUI shapes poorly, so draw the color dot as an image.
    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}

struct AccessDeniedBanner: View {
    let kind: CatchKind
    let calendar: CalendarService

    var body: some View {
        let app = kind == .event ? "Calendars" : "Reminders"
        VStack(alignment: .leading, spacing: 6) {
            Label("\(kind == .event ? "Calendar" : "Reminders") access is off", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.callout.weight(.semibold))
            Text("Turn on Catchy in System Settings › Privacy & Security › \(app), then come back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy Settings") { calendar.openPrivacySettings(for: kind) }
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

/// Says so when the on-device model wasn't used.
struct ModelNote: View {
    let state: AppState

    var body: some View {
        if !state.usedOnDeviceModel, let reason = state.extractor.unavailableReason {
            Label(reason, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
