import Foundation
import Testing

@Suite("Editing a card by voice")
struct VoiceEditing {
    /// Fri 16 Oct 2026, 09:00–10:00 local, like the "Classes" card.
    private var card: EventDraft {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9))!
        return EventDraft(title: "Classes", start: start, end: start.addingTimeInterval(3600),
                          isAllDay: false, location: "", notes: "", url: nil)
    }

    private func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    @Test func newTimeKeepsTheDayAndLength() {
        let edit = VoiceEdit.apply("make it 6 pm", to: card)
        #expect(clock(edit.draft.start) == "18:00")
        #expect(clock(edit.draft.end) == "19:00")
        #expect(Calendar.current.isDate(edit.draft.start, inSameDayAs: card.start))
        #expect(edit.changed == ["time"])
    }

    @Test func spokenTimeWithDot() {
        #expect(clock(VoiceEdit.apply("change it to 5.30", to: card).draft.start) == "05:30"
                || clock(VoiceEdit.apply("change it to 5.30", to: card).draft.start) == "17:30")
    }

    @Test func newDayKeepsTheTime() {
        let edit = VoiceEdit.apply("move it to Monday", to: card)
        #expect(Calendar.current.component(.weekday, from: edit.draft.start) == 2)
        #expect(clock(edit.draft.start) == "09:00")
    }

    @Test func length() {
        let edit = VoiceEdit.apply("for 2 hours", to: card)
        #expect(clock(edit.draft.end) == "11:00")
        #expect(edit.changed == ["length"])
    }

    @Test func place() {
        let edit = VoiceEdit.apply("at the Starbucks in Bandra", to: card)
        #expect(edit.draft.location == "Starbucks in Bandra")
        #expect(clock(edit.draft.start) == "09:00")
    }

    @Test func rename() {
        #expect(VoiceEdit.apply("call it Physics class", to: card).draft.title == "Physics class")
    }

    @Test func bareShortPhraseIsATitle() {
        #expect(VoiceEdit.apply("physics lecture", to: card).draft.title == "Physics lecture")
    }

    @Test func reminderAndAllDay() {
        #expect(VoiceEdit.apply("make it a reminder", to: card).draft.kind == .task)
        #expect(VoiceEdit.apply("make it all day", to: card).draft.isAllDay)
    }

    @Test func severalAtOnce() {
        let edit = VoiceEdit.apply("call it Physics lab, move it to 2 pm", to: card)
        #expect(edit.draft.title == "Physics lab")
        #expect(clock(edit.draft.start) == "14:00")
        #expect(VoiceEdit.summary(edit.changed) == "Changed title and time")
    }
}

@Suite("Voice edits read the hour in context")
struct VoiceEditHours {
    private func card(at hour: Int, title: String = "Classes") -> EventDraft {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: hour))!
        return EventDraft(title: title, start: start, end: start.addingTimeInterval(3600),
                          isAllDay: false, location: "", notes: "", url: nil)
    }

    private func hour(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) }

    @Test func bareHourNearTheEveningCardIsEvening() {
        // The bug: "make it at 10" on a 21:00 card became the title.
        let edit = VoiceEdit.apply("make it at 10", to: card(at: 21))
        #expect(edit.draft.title == "Classes")
        #expect(hour(edit.draft.start) == 22)
        #expect(hour(edit.draft.end) == 23)
    }

    @Test func bareHourNearTheMorningCardIsMorning() {
        #expect(hour(VoiceEdit.apply("make it at 10", to: card(at: 9)).draft.start) == 10)
    }

    @Test(arguments: ["make it 10", "change it to 10", "move it to 10", "at 10"])
    func phrasings(said: String) {
        let edit = VoiceEdit.apply(said, to: card(at: 21))
        #expect(hour(edit.draft.start) == 22)
        #expect(edit.draft.title == "Classes")
    }

    @Test func explicitMeridiemWins() {
        #expect(hour(VoiceEdit.apply("make it 10 am", to: card(at: 21)).draft.start) == 10)
    }

    @Test func eveningGuessForSeven() {
        #expect(hour(VoiceEdit.apply("change it to 7", to: card(at: 18)).draft.start) == 19)
    }

    @Test func commandsNeverBecomeTitles() {
        let edit = VoiceEdit.apply("make it better somehow", to: card(at: 21))
        #expect(edit.draft.title == "Classes")
        #expect(edit.changed.isEmpty)
    }
}
