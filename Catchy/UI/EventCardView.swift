import EventKit
import SwiftUI

/// The pre-filled card for one event or task, in a few dense rows:
/// title + kind · date and times · place · (notes) · calendar and actions.
struct EventCardView: View {
    @Bindable var state: AppState

    private var calendar: CalendarService { state.calendar }
    private var kind: CatchKind { state.draft.kind }
    private var fromList: Bool { state.drafts.count > 1 }
    private var spansDays: Bool {
        !Calendar.current.isDate(state.draft.start, inSameDayAs: state.draft.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fromList {
                Button {
                    state.backToList()
                } label: {
                    Label("All \(state.drafts.count)", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(kind == .event ? "Event" : "Reminder", text: $state.draft.title, axis: .vertical)
                    .font(.system(size: 15, weight: .semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                Button {
                    state.startListening(for: .edit)
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 20)
                        .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Change it by voice (or tap ⌃⌘): “make it 6 pm”, “move it to Friday”, “at Starbucks”")
                kindPicker
            }

            if let summary = state.editSummary {
                Label(summary, systemImage: "waveform")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            whenRow

            if let zone = state.draft.sourceTimeZone, !state.draft.isAllDay {
                Label("\(TimeZones.label(state.draft.start, in: zone)) in your time", systemImage: "globe")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            if let clash = calendar.clash(for: state.draft) {
                Label("Clashes with \(clash.title ?? "an event") at \(clash.startDate.formatted(date: .omitted, time: .shortened))",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            if kind == .event {
                field("mappin", "Add location", text: $state.draft.location)
            }
            if !state.draft.notes.isEmpty {
                field("text.alignleft", "Notes", text: $state.draft.notes)
            }

            if calendar.access(for: kind) == .denied {
                AccessDeniedBanner(kind: kind, calendar: calendar)
            }

            HStack(spacing: 6) {
                if calendar.access(for: kind) == .granted {
                    destinationPicker
                }
                if kind == .event {
                    AlertPicker(calendar: calendar, allDay: state.draft.isAllDay, start: state.draft.start)
                }
                ModelNote(state: state)
                Spacer(minLength: 0)
                if fromList {
                    Button("Done", action: state.backToList)
                        .buttonStyle(.islandProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Discard", action: state.done)
                        .buttonStyle(.island)
                        .keyboardShortcut(.cancelAction)
                    Button {
                        state.save()
                    } label: {
                        AddLabel(title: "Add", symbol: kind == .event ? "calendar.badge.plus" : "plus.circle", isSaving: state.isSaving)
                    }
                    .buttonStyle(.islandProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(calendar.access(for: kind) == .denied)
                }
            }
            .padding(.top, 2)
        }
    }

    /// One line: date, then start–end (or "All day"), with a tiny all-day switch.
    private var whenRow: some View {
        HStack(spacing: 4) {
            DatePicker("", selection: startBinding, displayedComponents: .date)
            if !state.draft.isAllDay {
                DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                if kind == .event {
                    Text("–").foregroundStyle(.secondary)
                    DatePicker("", selection: $state.draft.end, in: state.draft.start...,
                               displayedComponents: spansDays ? [.date, .hourAndMinute] : .hourAndMinute)
                }
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(IslandView.spring) { state.draft.isAllDay.toggle() }
            } label: {
                Text(kind == .event ? "All day" : "Any time")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(state.draft.isAllDay ? Color.black : Color.secondary)
                    .background(state.draft.isAllDay ? Color.white : Color.white.opacity(0.1), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .labelsHidden()
        // Plain fields (no stepper arrows): type or use ↑↓ to change.
        .datePickerStyle(.field)
        .controlSize(.small)
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $state.draft.kind) {
            Image(systemName: "calendar").tag(CatchKind.event)
            Image(systemName: "checklist").tag(CatchKind.task)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
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

    private func field(_ symbol: String, _ prompt: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            TextField(prompt, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 7))
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

/// A small menu showing the calendar or list's colour dot and name.
struct CalendarPicker: View {
    let calendars: [EKCalendar]
    @Binding var selection: String

    var body: some View {
        if let current = calendars.first(where: { $0.calendarIdentifier == selection }) ?? calendars.first {
            Menu {
                ForEach(calendars, id: \.calendarIdentifier) { item in
                    Button {
                        selection = item.calendarIdentifier
                    } label: {
                        Label {
                            Text("\(item.title) · \(item.source.title)")
                        } icon: {
                            Image(nsImage: Self.swatch(item.color))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(Color(nsColor: current.color)).frame(width: 7, height: 7)
                    Text(current.title).lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// Menu items render SwiftUI shapes poorly, so draw the colour dot as an image.
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
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            Text("\(kind == .event ? "Calendar" : "Reminders") access is off")
                .font(.system(size: 11.5, weight: .medium))
            Spacer(minLength: 0)
            Button("Settings") { calendar.openPrivacySettings(for: kind) }
                .buttonStyle(.island)
        }
        .padding(7)
        .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 9))
    }
}

/// A small mark when the on-device model wasn't used; the reason is in its tooltip.
struct ModelNote: View {
    let state: AppState

    var body: some View {
        if !state.usedOnDeviceModel, let reason = state.extractor.unavailableReason {
            Image(systemName: "sparkles")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .overlay(Rectangle().frame(width: 14, height: 1.2).rotationEffect(.degrees(-45)).foregroundStyle(.tertiary))
                .help(reason)
        }
    }
}

/// The event's alert (Calendar's notification before it starts), as a small bell menu.
struct AlertPicker: View {
    @Bindable var calendar: CalendarService
    let allDay: Bool
    let start: Date

    var body: some View {
        Menu {
            ForEach(EventAlert.options(allDay: allDay)) { option in
                Button {
                    calendar.alert = option
                } label: {
                    if option == shown {
                        Label(option.title(allDay: allDay), systemImage: "checkmark")
                    } else {
                        Text(option.title(allDay: allDay))
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: effective == .none ? "bell.slash" : "bell")
                Text(effective.shortTitle(allDay: allDay))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }

    /// What will really be set, given how soon it starts.
    private var effective: EventAlert { shown.effective(start: start, allDay: allDay) }

    private var help: String {
        effective == shown
            ? "Calendar alert: \(shown.title(allDay: allDay))"
            : "\(shown.title(allDay: allDay)) has already passed, so the alert will be \(effective.title(allDay: allDay).lowercased())"
    }

    /// Minute offsets don't apply to all-day events; show what will actually be used.
    private var shown: EventAlert {
        EventAlert.options(allDay: allDay).contains(calendar.alert) ? calendar.alert : (allDay ? .atStart : calendar.alert)
    }
}
