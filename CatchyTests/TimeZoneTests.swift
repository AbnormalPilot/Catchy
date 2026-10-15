import Foundation
import Testing

/// Times are checked as absolute instants (UTC), so these pass whatever zone the Mac is in.
private func utc(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: string)!
}

/// A wall-clock time in this Mac's zone, like the model writes after converting.
private func localParts(_ date: Date) -> (day: String, time: String) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    let day = formatter.string(from: date)
    formatter.dateFormat = "HH:mm"
    return (day, formatter.string(from: date))
}

private func item(_ day: String, _ time: String, end: String = "", zone: String = "") -> GeneratedItem {
    GeneratedItem(kind: .event, title: "T", startDate: day, startTime: time, endDate: "", endTime: end,
                  timeZone: zone, location: "", notes: "")
}

private func draft(_ text: String, _ generated: GeneratedItem) -> EventDraft? {
    EventExtractor.draft(from: generated, text: text, hints: DateHints(text: text), now: utc("2026-10-15T10:00:00Z"))
}

@Suite("Basic detector")
struct DetectorTimeZones {
    @Test func easternTime() {
        let text = "Will It Ship, Thursday, Oct 22, 2026 at 3:00 pm ET"
        let event = DateHints(text: text).fallbackDrafts(from: text).first
        #expect(event?.start == utc("2026-10-22T19:00:00Z"))
        #expect(event?.sourceTimeZone?.identifier == "America/New_York" || TimeZone.current.identifier == "America/New_York")
    }

    @Test func splitDateAndZonedRange() {
        let text = "Sat, Oct 24, 2026 • 4pm - 9pm PT\nRooftop meetup"
        let event = DateHints(text: text).fallbackDrafts(from: text).first
        #expect(event?.start == utc("2026-10-24T23:00:00Z"))
        #expect(event?.end == utc("2026-10-25T04:00:00Z"))
    }

    @Test func afterDaylightSavingEnds() {
        let text = "Office hours Nov 3, 2026 9am ET"
        #expect(DateHints(text: text).fallbackDrafts(from: text).first?.start == utc("2026-11-03T14:00:00Z"))
    }
}

@Suite("Model output")
struct ModelTimeZones {
    @Test func timeAsWrittenWithZone() {
        #expect(draft("Oct 22, 2026 at 3:00 pm ET", item("2026-10-22", "15:00", zone: "ET"))?.start == utc("2026-10-22T19:00:00Z"))
    }

    @Test func alreadyConvertedIsNotConvertedTwice() {
        let local = localParts(utc("2026-10-22T19:00:00Z"))
        let event = draft("Oct 22, 2026 at 3:00 pm ET", item(local.day, local.time))
        #expect(event?.start == utc("2026-10-22T19:00:00Z"))
    }

    @Test func zoneOnlyFromTheMatchingPhrase() {
        // The ET belongs to the call, not the dinner.
        let text = "Dinner Oct 24, 2026 8pm. Call with NY team Oct 25, 2026 9am ET"
        let event = draft(text, item("2026-10-24", "20:00"))
        var calendar = Calendar.current
        calendar.timeZone = .current
        #expect(event?.start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20)))
        #expect(event?.sourceTimeZone == nil)
    }

    @Test func zoneBorrowedWhenTheModelLeavesItOut() {
        #expect(draft("Oct 22, 2026 at 3:00 pm ET", item("2026-10-22", "15:00"))?.start == utc("2026-10-22T19:00:00Z"))
    }

    @Test func twelveHourTime() {
        let event = draft("Oct 22, 2026 at 3:00 pm ET", item("2026-10-22", "3:00 PM", zone: "ET"))
        #expect(event?.isAllDay == false)
        #expect(event?.start == utc("2026-10-22T19:00:00Z"))
    }

    @Test func overnightEndsNextDay() {
        let event = draft("Party Oct 24, 2026 10pm-1am ET", item("2026-10-24", "22:00", end: "01:00", zone: "ET"))
        #expect(event?.start == utc("2026-10-25T02:00:00Z"))
        #expect(event?.end == utc("2026-10-25T05:00:00Z"))
    }

    @Test(arguments: [("Eastern Time", "2026-11-03T14:00:00Z"), ("UTC", "2026-11-03T09:00:00Z"),
                      ("America/New_York", "2026-11-03T14:00:00Z"), ("GMT+1", "2026-11-03T08:00:00Z")])
    func writtenZones(zone: String, expected: String) {
        #expect(draft("Nov 3, 2026 9am", item("2026-11-03", "09:00", zone: zone))?.start == utc(expected))
    }
}

@Suite("Parsing")
struct Parsing {
    @Test(arguments: [("15:00", 15, 0), ("3:00 PM", 15, 0), ("3pm", 15, 0), ("12am", 0, 0), ("12:30 pm", 12, 30),
                      ("9.30", 9, 30), ("15:00:00", 15, 0)])
    func times(text: String, hour: Int, minute: Int) {
        let parsed = EventExtractor.parseTime(text)
        #expect(parsed?.hour == hour && parsed?.minute == minute)
    }

    @Test(arguments: ["", "3", "25:00", "13pm", "noonish"])
    func notTimes(text: String) {
        #expect(EventExtractor.parseTime(text) == nil)
    }

    @Test(arguments: [("ET", "America/New_York"), ("pst", "America/Los_Angeles"), ("London time", "Europe/London"),
                      ("IST", "Asia/Kolkata"), ("Asia/Tokyo", "Asia/Tokyo")])
    func zoneNames(text: String, identifier: String) {
        #expect(TimeZones.resolve(text)?.identifier == identifier)
    }

    @Test func lengthIsDuration() {
        let relative = DateHints.relativeTimes(in: "meet with sujan 20 mins", now: .now)
        #expect(relative.start == nil)
        #expect(relative.duration?.seconds == 1200)
    }
}

@Suite("Alerts")
struct Alerts {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func chosenAlertWhenThereIsTime() {
        #expect(EventAlert.fifteenMinutes.effective(start: now.addingTimeInterval(3600), allDay: false, now: now) == .fifteenMinutes)
    }

    @Test func startsTooSoonFallsBackToStart() {
        // Starts in 10 minutes: "15 minutes before" was 5 minutes ago and would never fire.
        #expect(EventAlert.fifteenMinutes.effective(start: now.addingTimeInterval(600), allDay: false, now: now) == .atStart)
    }

    @Test func alreadyStartedHasNoAlert() {
        #expect(EventAlert.fifteenMinutes.effective(start: now.addingTimeInterval(-60), allDay: false, now: now) == .none)
    }

    @Test func noneStaysNone() {
        #expect(EventAlert.none.effective(start: now.addingTimeInterval(3600), allDay: false, now: now) == .none)
    }
}
