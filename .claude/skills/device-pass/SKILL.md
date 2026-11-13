---
name: device-pass
description: Close OpenIntelligence roadmap rows that wait on a device check, with the owner doing one short pass on his iPhone and one on his Mac, and everything else done by the agent. Use when rows sit In Progress waiting on "a check on his phone or Mac", when he asks what he has to test, says "done" after testing, asks "what's been closed", or complains the list is too long. Also use before telling him anything needs testing.
---

# Device pass

The owner wants rows closed only on real proof, and he wants the asking to be tiny. Both hold at once
(his words, 2026-11-04: "I appreciate you standing so strong with the testing... but it needs to be made
very clear"). So:

- **Never hand him a list of rows.** Hand him the pass below: at most five phone steps and seven Mac steps.
  One step proves many rows, because the development build logs every event (`VerificationJournal`) and
  `scripts/phone_evidence.py` matches those events to rows.
- **Everything the agent can prove, the agent proves.** iOS 27 Simulator with the demo copy (Apple's model
  answers there), unit tests, headless runs. Allowed for any row not about the phone itself (owner,
  2026-10-18).
- **Unbuilt work is not on the release.** A row whose fix or feature is not built goes to Future Backlog,
  unless it loses data, breaks an advertised capability or blocks shipping (`CLAUDE.md`).
- **When he asks what closed, answer with the count from Notion**, `date:Completed:start` since the date he
  means, before anything else.

## The pass (5.8, rewritten 2026-11-13 from a triage of all 133 open v5.8 rows)

The triage: 1 closed on recorded evidence, 44 for the agent (unit and UI tests, the iOS 27 Simulator demo copy, code
checks), 21 moved to Future Backlog (unbuilt, or proof needs an event he cannot cause), the rest covered below.

Before the phone pass: a development build of the final commit installed over Wi-Fi; Settings, Developer logging on;
the X-Ray on. The first launch of that build is part of step 1 (the reranker's first load).

Phone:

1. **Import, then leave.** In a library that already holds a document, share from Files a PDF over 10 MB with hundreds
   of pages (MoreMacintoshToolbox.pdf, 913 pages, if none is) and leave the app at once. Then share a voice memo
   renamed like "Plumber visit_friday". When both finish, swipe the app away, reopen, ask one question about the voice
   memo and tap its citation, and see that Chat shows suggested questions.
2. **Deep Think.** Dictate a Deep Think question about that PDF with the mic; tap Just Once at the Private Cloud
   Compute sheet; while it answers open the Atlas; lock the phone a minute; unlock, back to Chat. Ask a second Deep
   Think question: the sheet must appear again; tap Deny.
3. **Siri.** With the app closed and Library 8 open last: "Hey Siri, ask OpenIntelligence how much DHA is
   recommended"; on the card tap a document, Ask a Follow-Up ("compare the DHA and EPA amounts"), Think Deeper. Then
   "Open <document> in OpenIntelligence", and "Search OpenIntelligence for <a phrase>".
4. **Share.** Share an answer to Messages, then as Image; Copy Link on a document, paste in Notes, tap it.
5. **Lock Screen and Control Center.** Add the "Ask OpenIntelligence" and "Your Library" widgets, the Ask and Scan
   controls on the Lock Screen, and Add and Scan in Control Center; tap each; scan one page into a library; start a
   Deep Think question from Ask, lock, tap Stop on its Live Activity.

Mac:

1. Quit the app; he copies the Debug build (agents are refused this copy) from
   `/private/tmp/oi58-mac-dd/Build/Products/Debug/OpenIntelligence.app` into Applications, opens it, and reads 8,192
   on the Context Window card.
2. File > New Window, both kept open. Rebuild a small library in one; while it runs, drag a folder with a subfolder
   onto that library. Then make a library "Test", delete it, quit, reopen.
3. Make that folder the library's watched folder; add one file to it and edit another. With the HUD on, drag a PDF
   holding a scanned table onto the Dock icon, Add to Library.
4. Ask a Deep Think question; Copy, paste in TextEdit; tap a PDF citation; Export Conversation as PDF; paste a link
   and a paragraph with the library's Paste chip; open the Atlas and turn it to three or four angles.
5. TextEdit: Services > Ask OpenIntelligence, then Add to OpenIntelligence; Finder: right-click > Quick Actions > Add
   to OpenIntelligence.
6. Ask from the menu bar item; Shift-Command-N, Command-O, Command-F, Command-], Command-[.
7. Start a conversation on the iPhone and see it on the Mac; delete it on the Mac and see it gone on the iPhone; open a
   document on the iPhone and click the Handoff icon in the Mac's Dock.

Waits on the TestFlight build, not this pass: "PCC works on device; prove the entitlement survives Archive and
TestFlight signing" (step 2 on the TestFlight build of 5.8 closes it).

Update this list when a release's rows change, keeping the limit of five and seven. Merge steps; never add a step for a
single row.

## When he says "done"

```bash
python3 scripts/phone_evidence.py --since <the time of the install, local>
```

```bash
python3 scripts/phone_evidence.py --mac --since <the time he copied the build, local>
```

Add `--json` to get each rule's `status`, `proof` lines and `needs`. For every `PASS` whose `needs` does not
say PARTIAL, set the row `Completed` with today's `date:Completed:start` and `Shipped On` empty (the build is
not released), and append the proof lines with their timestamps. A `FAIL` is a finding: read its `problems`,
write them on the row, keep it open. `NOT SEEN` after the pass means the step did not reach that code: say
which step, once.

A row whose proof needs a condition he cannot just make happen (a real crash, Low Power, heat, days of Siri
learning) goes to Future Backlog with a note naming the event that will close it; the journal keeps
recording, so a later pull can still close it.

## Traps

- The journal ignores test hosts, and lines from UI-test launches (`--uitest-stand-in-model`,
  `--screenshot`) carry `"host":"uitest"` and are dropped. A UI test run on the Simulator demo copy without
  those flags counts.
- Never run the whole macOS hosted unit suite: it runs in his real Mac library (auto memory
  `mac-unit-tests-run-in-his-real-library.md`).
- The pull goes over Wi-Fi with `devicectl`; whether it works with the phone locked is untested.
