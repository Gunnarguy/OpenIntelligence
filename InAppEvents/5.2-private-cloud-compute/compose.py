#!/usr/bin/env python3
"""Event card (1920x1080) and details page (1080x1920) for the 5.2 event.

    python3 compose.py                      # hero = the 5.1 Chat screenshot
    python3 compose.py --hero consent.png   # hero = a real consent-sheet screenshot

Flat navy from the dark app icon, three phone frames, no added text or logo
(Apple overlays the badge, name and short description itself). Re-run with a
real Private Cloud Compute screenshot once 5.2 is on a device.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "5.1 Screenshots")
NAVY = (10, 18, 36, 255)
hero = sys.argv[sys.argv.index("--hero") + 1] if "--hero" in sys.argv else os.path.join(SRC, "IMG_3327.jpeg")
LEFT, RIGHT = os.path.join(SRC, "IMG_3334.jpeg"), os.path.join(SRC, "IMG_3340.jpeg")   # Settings (PCC row), Plain English

def device(path, width, rot=0):
    im = Image.open(path).convert("RGB")
    h = round(im.height * width / im.width); im = im.resize((width, h), Image.LANCZOS)
    r = round(width * 0.14); bez = round(width * 0.024); W, H = width + 2 * bez, h + 2 * bez
    m = Image.new("L", (width, h), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, width - 1, h - 1], r, fill=255)
    scr = Image.new("RGBA", (width, h), (0, 0, 0, 0)); scr.paste(im, (0, 0), m)
    body = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, W - 1, H - 1], r + bez, fill=(38, 40, 48, 255))
    body.alpha_composite(scr, (bez, bez))
    pad = round(width * 0.3); off = round(width * 0.07)
    canvas = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([pad, pad + off, pad + W - 1, pad + H - 1 + off], r + bez, fill=(0, 0, 0, 160))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(round(width * 0.08))))
    canvas.alpha_composite(body, (pad, pad))
    return canvas.rotate(rot, resample=Image.BICUBIC, expand=True) if rot else canvas

def put(bg, dev, cx, cy):
    bg.alpha_composite(dev, (round(cx - dev.width / 2), round(cy - dev.height / 2)))

card = Image.new("RGBA", (1920, 1080), NAVY)
put(card, device(LEFT, 470, -9), 700, 700); put(card, device(RIGHT, 470, 9), 1620, 700); put(card, device(hero, 540), 1160, 720)
card.convert("RGB").save(os.path.join(HERE, "event-card-1920x1080.png"), optimize=True)
det = Image.new("RGBA", (1080, 1920), NAVY)
put(det, device(LEFT, 560, -10), 300, 1120); put(det, device(RIGHT, 560, 10), 780, 1120); put(det, device(hero, 640), 540, 1150)
det.convert("RGB").save(os.path.join(HERE, "event-details-1080x1920.png"), optimize=True)
for f in ("event-card-1920x1080.png", "event-details-1080x1920.png"):
    p = os.path.join(HERE, f); print(f, Image.open(p).size, f"{os.path.getsize(p)/1e6:.1f} MB")
