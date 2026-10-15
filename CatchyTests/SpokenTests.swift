import Foundation
import Testing

@Suite("Spoken and casual text")
struct Spoken {
    @Test(arguments: [
        ("meet Ravi around 5.30", "meet Ravi around 5:30"),
        ("lunch at one", "lunch at 1:00"),
        ("call around five thirty", "call around 5:30"),
        ("dinner at half past seven", "dinner at 7:30"),
        ("standup at quarter to ten", "standup at 9:45"),
        ("version 2.30 release", "version 2.30 release"),
    ])
    func normalizesTimes(input: String, expected: String) {
        #expect(TextCleanup.normalized(input) == expected)
    }

    @Test func dictatedSentenceBecomesACleanCard() {
        let said = TextCleanup.normalized("So tomorrow, I have to meet Ravi around 5.30, probably at the Starbucks in Bandra.")
        let card = DateHints(text: said).fallbackDrafts(from: said).first
        #expect(card?.title == "Meet Ravi")
        #expect(card?.location == "Starbucks in Bandra")
        #expect(card?.isAllDay == false)
        #expect(card.map { Calendar.current.component(.minute, from: $0.start) } == 30)
    }

    @Test func spelledOutHour() {
        let said = TextCleanup.normalized("uh lunch with Sam tomorrow at one")
        let card = DateHints(text: said).fallbackDrafts(from: said).first
        #expect(card?.isAllDay == false)
        #expect(card?.title == "Lunch with Sam")
    }
}
