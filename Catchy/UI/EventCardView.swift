import EventKit
import SwiftUI

/// The pre-filled, editable event card.
struct EventCardView: View {
    @Bindable var state: AppState
    @State private var showsSource = false

    private var calendar: CalendarService { state.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Event title", text: $state.draft.title, axis: .vertical)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.plain)
                .lineLimit(1...2)

            VStack(spacing: 8) {
                Toggle("All-day", isOn: $state.draft.isAllDay.animation())
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                datePicker("Starts", selection: startBinding)
                datePicker("Ends", selection: $state.draft.end, in: state.draft.start...)
                if let zone = state.draft.sourceTimeZone, !state.draft.isAllDay {
                    Label("\(TimeZones.label(state.draft.start, in: zone)) · shown in your time", systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            field("mappin.and.ellipse", "Location", text: $state.draft.location)
            field("text.alignleft", "Notes", text: $state.draft.notes)

            if calendar.access == .granted, !calendar.calendars.isEmpty {
                calendarPicker
            }

            if calendar.access == .denied {
                CalendarDeniedBanner(calendar: calendar)
            }

            if !state.usedOnDeviceModel, let reason = state.extractor.unavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(calendar.access == .denied)
            }
        }
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

    private var calendarPicker: some View {
        Picker(selection: Binding(
            get: { calendar.targetCalendar?.calendarIdentifier ?? "" },
            set: { calendar.selectedCalendarID = $0 }
        )) {
            ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                HStack {
                    Image(nsImage: Self.swatch(item.color))
                    Text(item.title)
                    Text(item.source.title).foregroundStyle(.secondary)
                }
                .tag(item.calendarIdentifier)
            }
        } label: {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
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

private struct CalendarDeniedBanner: View {
    let calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Calendar access is off", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.callout.weight(.semibold))
            Text("Turn on Catchy in System Settings › Privacy & Security › Calendars, then come back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy Settings", action: calendar.openPrivacySettings)
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}
