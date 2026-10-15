---
doc: prd
status: approved
---

# Catchy — Product Requirements

A Mac menu bar app for people who keep retyping dates from flyers, messages and emails. It turns what they copy or capture into a ready-to-save calendar event or reminder, on-device.
Source: `scope.md > The Unique Kernel`, `scope.md > Who It's For`.

> Sources: the learner's opening brief, their later decisions in session (⌥⌘ tap, minimal logo, black notch island), and agent recommendations they accepted with "do the needful autonomously" (marked *rec.*).

## The Core Journey
1. **First launch:** a "C" logo appears in the menu bar and a welcome card opens under it. It explains the ways to catch (copy, or tap ⌥⌘) and that everything stays on the Mac. *(rec.)*
2. **Catch:**
   - copy text that contains a date, on the Mac or on the iPhone; or
   - copy an image or photo (including from the iPhone); or
   - tap ⌥⌘ and drag over part of the screen; or
   - select text in any app and choose **Catch with Catchy** from the right-click Services menu. *(rec.)*
3. A compact black island appears in the notch while Catchy reads (logo and spinner), then grows into a pre-filled card: title, date, start and end, all-day, location, notes, and the calendar to save into.
4. The user fixes anything wrong and clicks **Add to Calendar** (or **Add to Reminders** for a task). The first save shows the system permission prompt.
5. A confirmation shows the title, the time, and "syncing to iPhone and Watch" when the calendar is in iCloud, with **Undo**. *(rec.)*
6. The event appears on the user's iPhone. Success.

## Screens and Layout
One surface: a compact pitch-black island, about 300 pt wide, with its header beside the notch, that grows out of the notch like the Dynamic Island (learner). On a Mac without a notch it grows from the top centre of the screen. Clicking outside or switching apps hides it completely, with nothing left on screen while idle (learner); a waiting card is kept and comes back when you hover the notch. Esc closes it; the menu bar icon toggles it. Hovering the notch opens it, so Capture and Clipboard are one hover and one click away (learner); moving away closes it unless you clicked inside. Its states:
- **Welcome / idle:** what Catchy does, plus **Capture Screen** and **Catch from Clipboard** buttons, and a **Turn on the ⌥⌘ shortcut** row until Input Monitoring is allowed.
- **Reading:** a spinner and a snippet of the text being read.
- **Card:** one event or task. Or a **list** of several, each with a checkbox. *(rec.)*
- **Saved:** a checkmark, a summary, Undo, and Open Calendar.
- **Permission explainer:** Screen Recording or Calendar access is missing, with a button straight to the right System Settings pane.
- **Nothing found / error:** a plain message, plus "Create anyway" where it makes sense.
- **Region overlay:** a dimmed screen with a crosshair, a drag to select, and Esc to cancel. The hint reads "Drag over the text to catch · Esc to cancel".
- **••• menu:** Pause Catching, Launch at Login, Quit. These are not a settings screen (settings screens are cut). *(rec.)*

## Look and Feel
- Pitch black, like system UI in the notch (learner: "pitch black and it should be felt like macos internal system"). White capsule primary buttons, translucent capsule secondary buttons, system font, SF Symbols. Nothing should look like a web app. Replaces the original Liquid Glass popover.
- Logo: a minimal white "C" arc catching a coral dot on a dark rounded square. The menu bar shows the same mark in monochrome (learner: "minimistic logo").
- The tone of the copy is short, friendly and plain, e.g. "Reading your screen…", "No date found".

## Features and Behavior

### Clipboard catching
- Copying text that the system recognises as containing an event opens the card automatically. Text copied on an iPhone arrives through Universal Clipboard and behaves the same.
- Password-manager copies (concealed/transient types) are ignored. The same text copied twice opens only once.
- **Pause Catching** in the ••• menu stops automatic catching until it's turned back on. Manual catching still works. *(rec.)*
  - [ ] Copying "SPRING FLING this saturday 7-10pm Riverside Park" opens a card with Sat 19:00–22:00.
  - [ ] Copying "hello world" does nothing.

### Image catching *(rec.)*
- Copying an image (a screenshot copied to the clipboard, or a photo copied on the iPhone) is read with on-device text recognition. If it contains a date, the card opens.
  - [ ] Copying a photo of a flyer opens a card with its date.

### Screen capture
- Tapping ⌥⌘ (pressed together and released, with nothing else in between) dims every screen. Dragging selects an area, and Esc or a plain click cancels. The selected area is read, and the card opens.
- If Input Monitoring is missing, the island offers **Turn On** for the shortcut; the Capture Screen button works without it.
- If Screen Recording access is missing, the island explains why it's needed, offers **Allow Access**, and then **Reopen Catchy** (macOS only applies the grant after a relaunch).
  - [ ] Dragging over a flyer on screen produces a card with its date and title.

### Services menu *(rec.)*
- In any app, select text, right-click, then Services → **Catch with Catchy** to open the card from that text.
  - [ ] In Notes, selecting "Lunch with Sam tomorrow 1pm" and using the service opens a card for tomorrow at 13:00.

### Understanding the text
- The on-device model picks out:
  - the main event: title, date, start and end, location, notes
  - whether it's an **event** or a **task with a deadline**
  - **every** event when the text lists several *(rec.)*
- **Time zones** in the text (ET, PST, GMT+1, "London time") are converted to the Mac's local time. The card shows the original, e.g. "3:00 PM ET → 12:30 AM". *(rec.)*
- Titles are short and human, never in all caps.
- When Apple Intelligence is off, a basic date detector still fills the card, and a small note says so.
  - [ ] "Thursday, Oct 22 at 3:00 pm ET" becomes Fri 23 Oct 00:30 in India (IST) and shows the ET note.
  - [ ] "Submit the report by Friday" becomes a reminder due Friday.

### The card
- Every field can be edited. Moving the start moves the end with it. The all-day toggle switches the pickers to dates only.
- The calendar picker defaults to the last one used, otherwise to an iCloud calendar (so it reaches the iPhone).
- **Clash warning:** if something is already in the calendar at that time, a line says "Clashes with Dentist 7:00 PM". *(rec.)*
- **Original text** expands to show what was read.
- A task card has a title, a due date, notes and a reminders list, and the button reads **Add to Reminders**.

### Several at once *(rec.)*
- When more than one event is found, the island lists them (title and time), all checked by default. The button reads **Add 3 Events**. Clicking a row opens it for editing.
  - [ ] A pasted 3-line schedule produces a list of 3 that saves 3 events.

### Saving and Undo
- One click saves. The first save triggers the system Calendar (or Reminders) prompt. If access was denied, the card shows a banner with **Open Privacy Settings** and disables the button.
- Each event gets a Calendar alert, 15 minutes before by default; a bell chip on the card changes it (all-day: 9 AM on the day or the day before). The last choice is remembered (learner: "along with calendar notification").
- A Mac notification confirms every save, with Undo and Open (learner: "have in mac notification as well").
- After saving: the summary, "syncing to iPhone and Watch" when the calendar is in iCloud, **Undo** (removes what was just added), and **Open Calendar**. *(rec.)*
  - [ ] The event appears in Calendar.app and on the iPhone.
  - [ ] Undo removes it from Calendar.

### Welcome and login *(rec.)*
- On first launch, the island opens by itself with the welcome card.
- **Launch at Login** in the ••• menu.

## States and Boundaries
- **First use:** the welcome card. No permissions are asked until they're needed.
- **Permission missing:** Calendar, Reminders and Screen Recording each have an explainer and a button to the right System Settings pane. Nothing fails silently.
- **Nothing found:** "No date found", with **Create Anyway** (a blank card with the text in its notes).
- **Model unavailable:** basic detection, with a note on the card.
- **Persists:** the last calendar and reminders list chosen, Pause, Launch at Login, and whether the welcome was seen. Nothing else; there is no history (cut).
- **Privacy:** nothing leaves the Mac. Clipboard contents are only read after the system says they contain an event.

## Product Decisions
- Menu bar only, with no window or Dock icon (learner's brief).
- Hotkey: a bare ⌥⌘ tap (learner; changed from ⌥⌘C). Needs Input Monitoring.
- The card lives in a black notch island instead of a popover (learner).
- On-device only (learner's brief).
- Breadth over depth for the hackathon: the *rec.* items above (learner: "increase the horizontal of the features"; accepted with "do the needful autonomously").

## What We're Building
Everything under **Features and Behavior**.

## Deferred From the POC
- **Shortcuts/Siri action:** hard to show in a 3-minute video. Next after this.
- **Repeating events:** the card would need recurrence controls.
- **Contacts, maps, flights as outputs:** each is a new card type.

## Possible Later Enhancements
An iPhone share sheet (would need an iOS app, which is cut), smarter default alerts, and travel time.

## Non-Goals
iOS app, accounts, server, settings screens, history (learner's brief). No cloud AI.

## Open Questions
- Which iCloud calendar to demo with. Can wait until the demo.
