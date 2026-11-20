#!/usr/bin/env python3
"""Tests for the comparing half of scripts/ui_shots.py, on drawn images. No simulator.

Run: python3 scripts/test_ui_shots.py
"""
import os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui_shots as shots

try:
    from PIL import Image, ImageDraw
except ImportError:  # the comparing half needs Pillow
    Image = None


def screen(path, *boxes, size=(400, 800), clock=(40, 10, 120, 30)):
    image = Image.new("RGB", size, (255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle(clock, fill=(0, 0, 0))  # the status bar's clock
    for box, colour in boxes:
        draw.rectangle(box, fill=colour)
    image.save(path)


@unittest.skipIf(Image is None, "Pillow is not installed")
class UIShots(unittest.TestCase):
    def test_the_status_bar_and_faint_noise_are_not_a_change(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = os.path.join(d, "a.png"), os.path.join(d, "b.png")
            screen(a, ((50, 300, 350, 400), (0, 100, 200)))
            screen(b, ((50, 300, 350, 400), (10, 110, 210)), clock=(60, 10, 160, 30))  # clock moved, colour off by 10
            share, box = shots.difference(a, b)
            self.assertEqual((share, box), (0.0, None))

    def test_a_moved_control_is_a_change_with_its_area(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = os.path.join(d, "a.png"), os.path.join(d, "b.png")
            screen(a, ((50, 300, 350, 400), (0, 100, 200)))
            screen(b, ((50, 360, 350, 460), (0, 100, 200)))
            share, box = shots.difference(a, b)
            self.assertGreater(share, shots.CHANGED_SHARE)
            self.assertEqual((box[1], box[3]), (300, 461))

    def test_compare_sorts_screens_and_writes_the_pair_and_the_sheet(self):
        with tempfile.TemporaryDirectory() as d:
            before, after, out = (os.path.join(d, n) for n in ("before", "after", "out"))
            os.makedirs(before), os.makedirs(after)
            blue = ((50, 300, 350, 400), (0, 100, 200))
            screen(os.path.join(before, "chat-00.png"), blue)
            screen(os.path.join(after, "chat-00.png"), blue)
            screen(os.path.join(before, "settings-01.png"), blue)
            screen(os.path.join(after, "settings-01.png"), ((50, 500, 350, 700), (200, 0, 0)))
            screen(os.path.join(before, "gone.png"), blue)
            screen(os.path.join(after, "added.png"), blue)
            screen(os.path.join(before, "resized.png"), blue)
            screen(os.path.join(after, "resized.png"), blue, size=(400, 900))
            rows = dict((r[0], r[1]) for r in shots.compare(before, after, out, "v1", "v2"))
            self.assertEqual(rows, {"chat-00.png": "same", "settings-01.png": "changed", "gone.png": "missing after",
                                    "added.png": "new", "resized.png": "changed"})
            self.assertTrue(os.path.exists(os.path.join(out, "changed", "settings-01.png")))
            self.assertTrue(os.path.exists(os.path.join(out, "sheet.png")))
            summary = open(os.path.join(out, "SUMMARY.txt")).read()
            self.assertIn("v1 against v2: 2 of 5 screens changed, 1 the same (0 of them scrolled to a different place), "
                          "1 new, 1 missing after", summary)
            self.assertNotIn("chat-00", summary)  # unchanged screens are counted, not listed

    def test_the_same_content_scrolled_to_another_place_is_not_a_change(self):
        with tempfile.TemporaryDirectory() as d:
            before, after, out = (os.path.join(d, n) for n in ("before", "after", "out"))
            os.makedirs(before), os.makedirs(after)
            rows_of_text = [((40, y, 360, y + 14), (30, 30, 30)) for y in range(180, 640, 40)]
            screen(os.path.join(before, "settings-02.png"), *rows_of_text)
            moved = [((x0, y0 + 37, x1, y1 + 37), c) for (x0, y0, x1, y1), c in rows_of_text]  # 37 px further down
            screen(os.path.join(after, "settings-02.png"), *moved)
            self.assertGreater(shots.difference(os.path.join(before, "settings-02.png"), os.path.join(after, "settings-02.png"))[0],
                               shots.CHANGED_SHARE)
            fitted, slide = shots.aligned_difference(os.path.join(before, "settings-02.png"), os.path.join(after, "settings-02.png"))
            self.assertLess(fitted, shots.ALIGNED_SHARE)
            self.assertEqual(abs(slide), 37)
            rows = shots.compare(before, after, out)
            self.assertEqual([(r[1], r[3]) for r in rows], [("scrolled", "same content, 37 px apart")])
            self.assertFalse(os.path.exists(os.path.join(out, "sheet.png")))

    def test_a_renamed_label_is_a_change_however_small(self):
        tree = ("Attributes: Application, 0x1114d2080, pid: 88376, label: 'OpenIntelligence'\n"
                "    Window (Main), 0x1114d1680, {{0.0, 0.0}, {402.0, 874.0}}\n"
                "      StaticText, 0x1114d0140, {{163.0, 73.7}, {75.7, 20.7}}, label: '%s'\n"
                "      Button, 0x107873980, {{29.2, 147.3}, {11.3, 14.0}}, identifier: 'arrow.up', label: 'Send'\n"
                "      Switch, 0x107873981, {{29.2, 247.3}, {51.0, 31.0}}, label: 'Show details', value: 1\n")
        with tempfile.TemporaryDirectory() as d:
            before, after, out = (os.path.join(d, n) for n in ("before", "after", "out"))
            os.makedirs(before), os.makedirs(after)
            blue = ((50, 300, 350, 400), (0, 100, 200))
            for folder, title in ((before, "Conversations"), (after, "Evidence Threads")):
                screen(os.path.join(folder, "chat-00.png"), blue)
                with open(os.path.join(folder, "chat-00.tree.txt"), "w") as f:
                    f.write(tree % title)
            found = shots.labels(os.path.join(before, "chat-00.tree.txt"))
            self.assertEqual(found[("StaticText", "", "Conversations", "")], 1)
            self.assertEqual(found[("Switch", "", "Show details", "1")], 1)
            self.assertEqual(sum(found.values()), 3)  # the app line and the window carry no words
            rows = shots.compare(before, after, out)
            self.assertEqual(rows[0][1], "changed")
            self.assertEqual(rows[0][3], 'words: gone "Conversations"; new "Evidence Threads"')
            # A tip showing in one run, and how far a page is scrolled, are not changes either.
            with open(os.path.join(after, "chat-00.tree.txt"), "w") as f:
                f.write(tree % "Conversations"
                        + "      Other, 0x1, {{0.0, 0.0}, {402.0, 874.0}}, identifier: 'PopoverDismissRegion', label: 'dismiss popup'\n"
                        + "      StaticText, 0x2, {{40.0, 300.0}, {300.0, 20.0}}, label: 'One library or all'\n"
                        + "      Button, 0x3, {{340.0, 300.0}, {24.0, 24.0}}, identifier: 'xmark.circle.fill', label: 'Close'\n"
                        + "      Other, 0x4, {{396.0, 100.0}, {6.0, 600.0}}, label: 'Vertical scroll bar, 3 pages', value: 41%\n")
            said, tip, tipish = shots.words(os.path.join(after, "chat-00.tree.txt"), {"One library or all", "Send"})
            self.assertTrue(tip)
            self.assertEqual(said, {"Conversations", "Send", "Show details", "1", "One library or all", "Close"})
            self.assertEqual(tipish, {"One library or all", "Close", "Send"})
            # "Send" is a real label that also appears in the tips' text: with the tip up on one side only, it must
            # not read as gone or new.
            self.assertEqual(shots.compare(before, after, os.path.join(d, "out3"))[0][1], "same")
            self.assertEqual(shots.page_of("settings-02-Plain-English-3.png"), "settings-02-Plain-English")
            self.assertEqual(shots.normal("Stored at /Users/x/Library/Developer/CoreSimulator/Devices/ABC/data 3 seconds ago"),
                             "Stored at <path> <when>")
            self.assertTrue(os.path.exists(os.path.join(out, "sheet.png")))
            # The same words at other addresses and positions are not a change.
            with open(os.path.join(after, "chat-00.tree.txt"), "w") as f:
                f.write((tree % "Conversations").replace("0x1114d0140", "0x999").replace("{{163.0, 73.7}", "{{163.0, 99.0}"))
            self.assertEqual(shots.compare(before, after, os.path.join(d, "out2"))[0][1], "same")

    def test_nothing_changed_writes_no_sheet(self):
        with tempfile.TemporaryDirectory() as d:
            before, after, out = (os.path.join(d, n) for n in ("before", "after", "out"))
            os.makedirs(before), os.makedirs(after)
            for folder in (before, after):
                screen(os.path.join(folder, "chat-00.png"), ((50, 300, 350, 400), (0, 100, 200)))
            rows = shots.compare(before, after, out)
            self.assertEqual([r[1] for r in rows], ["same"])
            self.assertFalse(os.path.exists(os.path.join(out, "sheet.png")))


if __name__ == "__main__":
    unittest.main()
