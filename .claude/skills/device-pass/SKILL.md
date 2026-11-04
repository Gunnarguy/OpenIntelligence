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

## The pass (5.8, 2026-11-04)

Phone, in his biggest library, any order, on a development build of the current commit:

1. **Deep Think.** Ask a Deep Think question, tap Just Once at the Private Cloud Compute sheet; while it
   answers, open Documents, then lock the phone a minute; unlock, back to Chat; ask a second Deep Think question.
2. **Siri.** "Hey Siri, ask OpenIntelligence ...", tap a document, Ask a Follow-Up and Think Deeper on the
   card; then "Open <document> in OpenIntelligence".
3. **Import.** Share a PDF over 10 MB from Files and leave the app at once; then a voice memo.
4. **Share.** Share an answer to Messages, then as Image; Copy Link on a document, paste in Notes, tap it.
5. **Lock Screen.** Add the widget and the Ask control; tap each.

Mac:

1. Quit the app; he copies the Debug build (agents are refused this copy) from
   `/private/tmp/oi58-mac-dd/Build/Products/Debug/OpenIntelligence.app` into Applications, opens it.
2. File > New Window; Rebuild a small library in one window; make a library "Test", delete it, quit, reopen.
3. Drag a folder with a subfolder onto a library; drag a PDF onto the Dock icon, Add to Library.
4. Ask a Deep Think question; Copy, paste in TextEdit; tap a PDF citation.
5. TextEdit: Services > Ask OpenIntelligence, then Add to OpenIntelligence; Finder: right-click > Quick
   Actions > Add to OpenIntelligence.
6. Ask from the menu bar item; Shift-Command-N, Command-O, Command-F, Command-], Command-[.
7. Start a conversation on the iPhone and see it on the Mac.

Update this list when a release's rows change, keeping the limit of five and seven. Merge steps; never add a
step for a single row.

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
