---
doc: checklist
status: draft
---

# Build Checklist

Build mode: fast. The learner asked the agent to proceed autonomously ("do the needful autonomously").

## Slices

- [x] **1. Copy text with a date and get a calendar event**
  Becomes usable: The menu bar app; copying event-like text opens a pre-filled card; Add to Calendar saves via EventKit.
  Why now: It is the kernel. Everything else feeds this card.
  PRD ref: `prd.md > Clipboard catching`, `prd.md > The card`, `prd.md > Saving and Undo`
  Spec ref: `spec.md > ClipboardWatcher`, `spec.md > EventExtractor + DateHints`, `spec.md > CalendarService`
  Build: XcodeGen project, status item + popover, clipboard watcher with system event detection, Foundation Models extraction with NSDataDetector fallback, editable card, EventKit save.
  Verify (mechanical): `xcodebuild … build` succeeds; `printf 'SPRING FLING\nthis saturday 7-10pm\nRiverside Park' | pbcopy` opens a card with Sat 19:00–22:00 (screenshot).
  Learner check: Copy a flyer's text and click Add to Calendar; check the iPhone.
  Commit: `Catch events from the clipboard into Calendar`

- [x] **2. ⌥⌘C to capture part of the screen**
  Becomes usable: The hotkey dims the screens; dragging selects an area; Vision reads it; the same card opens. Screen Recording explainer when access is missing. Minimal logo.
  Why now: The second way in from the learner's brief (Layer 2). It reuses the card.
  PRD ref: `prd.md > Screen capture`
  Spec ref: `spec.md > GlobalHotKey + RegionSelector + ScreenReader`
  Build: Carbon hotkey, overlay windows, SCScreenshotManager capture, RecognizeTextRequest OCR, permission view, icon generator.
  Verify (mechanical): Build succeeds; hotkey shows the permission explainer (screenshot); a rendered flyer image OCRs to the exact text and the date and time are merged.
  Learner check: Grant Screen Recording, reopen, press ⌥⌘C and drag over a flyer.
  Commit: `Capture a screen region with a hotkey and read it with Vision`

- [x] **3. Times in other time zones land at the right local time**
  Becomes usable: "Thursday, Oct 22 at 3:00 pm ET" becomes a card at the right local time, with a "3:00 PM ET" note.
  Why now: Cheapest high-impact accuracy fix, and it shapes the extractor that slices 4–5 extend.
  PRD ref: `prd.md > Understanding the text`
  Spec ref: `spec.md > EventExtractor + DateHints`, `spec.md > Data Model`
  Build: `TimeZones.swift` table; `timeZone` in the generated item; NSDataDetector time zones in DateHints; build dates in the source zone; note on the card.
  Verify (mechanical): Standalone harness over DateHints + time-zone code: the ET example resolves to 00:30 IST the next day.
  Learner check: Copy a line from the Devpost schedule written in ET and check the card's time.
  Commit: `Convert times written in other time zones`

- [ ] **4. Several events from one capture**
  Becomes usable: A schedule with several dates shows a checklist, and "Add 3 Events" saves them all.
  Why now: Changes the extractor's output to a list, which slice 5 also needs.
  PRD ref: `prd.md > Several at once`
  Spec ref: `spec.md > EventExtractor + DateHints`, `spec.md > AppState`, `spec.md > Views`
  Build: `GeneratedCatch.items`; drafts array in AppState; CatchListView; fallback produces one draft per detected date when several dates exist on separate lines.
  Verify (mechanical): Build; harness: a 3-line schedule produces 3 drafts in the fallback; screenshot of the list.
  Learner check: Copy a 3-line schedule; uncheck one; add the rest.
  Commit: `Catch several events at once`

- [ ] **5. Tasks go to Reminders**
  Becomes usable: "Submit the report by Friday" becomes a reminder card; Add to Reminders saves it.
  Why now: Layer 3 from the learner's brief; reuses the kind field from slice 4.
  PRD ref: `prd.md > The card`, `prd.md > Saving and Undo`
  Spec ref: `spec.md > CalendarService`
  Build: `kind` on drafts; reminder access + save; card variant; list rows show the kind icon.
  Verify (mechanical): Build; fallback marks "by Friday"/"due" text as a task; screenshot.
  Learner check: Copy a deadline and add it; check Reminders on the iPhone.
  Commit: `Send tasks to Reminders`

- [ ] **6. Copy an image or iPhone photo**
  Becomes usable: Copying a picture of a flyer (on the Mac or the iPhone) opens the card.
  Why now: The strongest demo moment; reuses the OCR from slice 2.
  PRD ref: `prd.md > Image catching`
  Spec ref: `spec.md > ClipboardWatcher`
  Build: Watch for image types without text; OCR; continue only if DateHints finds a date.
  Verify (mechanical): Put the rendered flyer PNG on the clipboard with a script; the card opens (screenshot).
  Learner check: On the iPhone, copy a photo of a poster; watch the Mac.
  Commit: `Catch dates from copied images`

- [ ] **7. Catch with Catchy in the right-click menu**
  Becomes usable: Select text anywhere → Services → Catch with Catchy.
  Why now: Small, native, and needs no hotkey to learn.
  PRD ref: `prd.md > Services menu`
  Spec ref: `spec.md > ServiceProvider`
  Build: NSServices in Info.plist; provider object; `NSUpdateDynamicServices`.
  Verify (mechanical): Build; `/System/Library/CoreServices/pbs -dump_pboard`-style check that the service is registered (or `pbs -update` + listing).
  Learner check: In Notes, select a sentence with a date and use the service.
  Commit: `Add Catch with Catchy to the Services menu`

- [ ] **8. Clash warning and Undo**
  Becomes usable: The card warns about overlapping events; the saved view offers Undo.
  Why now: Trust: the user sees conflicts before saving and can take it back after.
  PRD ref: `prd.md > The card`, `prd.md > Saving and Undo`
  Spec ref: `spec.md > CalendarService`
  Build: Overlap lookup with full access; keep saved identifiers; remove on Undo.
  Verify (mechanical): Build; code path reviewed; live check needs Calendar access (learner check).
  Learner check: Add an event, catch another at the same time and see the clash line; Undo removes the second.
  Commit: `Warn about clashes and allow undo`

- [ ] **9. Welcome, Pause and Launch at Login**
  Becomes usable: The first launch opens a welcome card; the ••• menu has Pause Catching and Launch at Login.
  Why now: Turns the proof of concept into a coherent product experience (judging: Design).
  PRD ref: `prd.md > Welcome and login`, `prd.md > Clipboard catching`
  Spec ref: `spec.md > StatusItemController`, `spec.md > Data Model`
  Build: hasSeenWelcome; welcome copy in the idle view; pause flag honoured by the watcher; SMAppService toggle.
  Verify (mechanical): Reset defaults, launch, and the welcome shows (screenshot); with Pause on, a copy opens nothing.
  Learner check: Toggle Pause and copy something.
  Commit: `Add welcome, pause and launch at login`

- [ ] **10. Ready to ship**
  Becomes usable: README with install and demo steps, MIT LICENSE, demo script.
  Why now: Required for submission.
  PRD ref: `prd.md > What We're Building`
  Spec ref: `spec.md > Where It Runs and How Someone Tries It`
  Build: README, LICENSE, `devpost/demo-script.md`.
  Verify (mechanical): Clean build from a fresh clone path; links in README resolve to files.
  Learner check: Read the README as a stranger would.
  Commit: `Add README, license and demo script`

## Hands-on Checkpoints

- [ ] Early feedback after slice 4: the learner grants Calendar access, turns on Apple Intelligence, and tries a real flyer end to end.
- [ ] Final review: the learner runs the full demo script once before recording.

## Final Review

- [ ] The learner has tried the full core journey and every requested revision is done.

## Code Tour and App Map

- [ ] Learning wrap-up and `devpost/app-map.html`.

## Revisions

- Slices 1–2 were built before the Skill Pack was installed (2026-10-15). The planning docs were written afterwards from the learner's brief, so these two are recorded as done.
- Slices 3–10 are built ahead of the learner's approval of the docs, at their request ("do the needful autonomously"). The docs stay `draft` until they review them.
