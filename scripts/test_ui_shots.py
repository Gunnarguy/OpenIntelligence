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
            rows = dict((name, kind) for name, kind, _ in shots.compare(before, after, out, "v1", "v2"))
            self.assertEqual(rows, {"chat-00.png": "same", "settings-01.png": "changed", "gone.png": "missing after",
                                    "added.png": "new", "resized.png": "changed"})
            self.assertTrue(os.path.exists(os.path.join(out, "changed", "settings-01.png")))
            self.assertTrue(os.path.exists(os.path.join(out, "sheet.png")))
            summary = open(os.path.join(out, "SUMMARY.txt")).read()
            self.assertIn("v1 against v2: 2 of 5 screens changed, 1 the same, 1 new, 1 missing after", summary)
            self.assertNotIn("chat-00", summary)  # unchanged screens are counted, not listed

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
