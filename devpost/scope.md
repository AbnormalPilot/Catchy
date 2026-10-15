---
doc: scope
status: draft
---

# Catchy

A Mac menu bar app that turns anything you copy or capture into the right action (a calendar event first), using on-device AI.

> Written from the learner's opening brief (quoted below) and the decisions they made later in the same session. Their brief already answered the scope questions, and they asked the agent to proceed autonomously. Items marked *(agent recommendation, accepted)* were proposed by the agent after reviewing the hackathon rules and accepted with "do the needful autonomously".

## The Unique Kernel
**Copy it, and it's already a calendar event.** Catchy notices when something with a date lands on your clipboard (from the Mac, or from your iPhone via Universal Clipboard), or when you drag over part of the screen, and the on-device model turns the mess into a pre-filled card. One click saves it, and it reaches your iPhone and Watch through iCloud. Nothing leaves the Mac.

What's distinctive versus the Calendar app's own date detection or a chatbot: there is no app to open and nothing to paste. The trigger is the copy itself. The AI runs entirely on-device.

## Who It's For
"Mac and iPhone users who constantly see dates, plans and tasks in flyers, messages and emails and have to retype them." Today they retype it into Calendar by hand, or screenshot it and forget.

## The Core Loop
1. See a date somewhere: a flyer, a WhatsApp message, an email, a webinar page, a photo of a poster on your iPhone.
2. Copy it, or press ⌥⌘C and drag over it.
3. A small popover under the menu bar icon shows the card, already filled in.
4. Check it, click **Add to Calendar**, and move on.

They come back because it costs one copy and one click, every time.

## Inspiration & Identity
- Native and calm. It should feel like part of macOS: a Liquid Glass popover and a menu bar icon (learner's brief).
- A minimal logo (learner: "have a minimistic logo"): a "C" arc catching a coral dot.
- Hotkey ⌥⌘C (learner's choice). The popover appears under the menu bar icon (learner's correction).

## Why This Matters to the Learner
They see dates, plans and tasks everywhere and keep retyping them. It's also their hackathon entry, and they want it broad and usable.

## What "Working" Looks Like
The learner's words: "A 1–3 minute demo where I copy or capture a messy flyer and watch it become a correct calendar event that shows up on my iPhone."

The "oh, that's cool" beat: copy a webinar time written in ET and see it land at the right local time. Or take a photo of a paper flyer on the iPhone, copy it, and see the card pop up on the Mac *(agent recommendation, accepted)*.

## The POC Boundary
- **Copy → card → Calendar**, including text copied on the iPhone (Universal Clipboard). *(Layer 1, learner)*
- **⌥⌘C → drag a region → Vision reads it → same card.** *(Layer 2, learner)*
- **Tasks go to Reminders** instead of Calendar. *(Layer 3, learner: "only if time allows")*
- Breadth, all *(agent recommendations, accepted)*:
  - copied **images**, including iPhone photos, are read too
  - **time zones** in the text are converted to local time
  - **several events from one capture** (agenda, syllabus)
  - **Catch with Catchy** in the right-click Services menu
  - a **clash warning** for events already in the calendar
  - **undo** after saving
  - a **first-run welcome**, plus **Launch at Login** and **Pause** in the ••• menu
- Clear permission handling for Calendar, Reminders and Screen Recording. *(learner)*

## Later
- App Intents action for Shortcuts/Siri *(Layer 3, learner: "only if time allows")*. Deferred behind the items above because the demo can't show Siri well in under 3 minutes.
- Repeating events ("every Tuesday"), contact cards to Contacts, flight numbers.

## Explicitly Cut
From the learner's brief: "an iOS app, accounts, a server, settings screens, history." Reasons:
- The iPhone gets the events through iCloud anyway.
- On-device only means no accounts or server.
- Settings and history are scope creep for a proof of concept.
