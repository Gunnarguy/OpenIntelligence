"""Composes captioned App Store screenshots from raw simulator captures.

usage: python3 compose.py <raw_dir> <out_dir>
raw_dir holds iphone-<scene>.png (1320x2868) and ipad-<scene>.png (2064x2752).
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
ICON = Path("/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Resources/Assets/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
BOLD = "/Library/Fonts/SF-Pro-Display-Bold.otf"
REG = "/Library/Fonts/SF-Pro-Display-Regular.otf"

SCENES = [
    ("answer", "Ask your own documents anything", "Every claim cites the page it came from"),
    ("refusal", "It tells you when your files don't say it", "No guessing. No made-up answers."),
    ("sources", "See where every answer came from", "The real passages, page by page"),
    ("consent", "Built on Apple Intelligence", "On your device. Private Cloud Compute only when you approve it."),
]

# The panel colour comes from the app icon so the listing reads as one product.
icon = Image.open(ICON).convert("RGB").resize((64, 64))
px = [icon.getpixel((x, y)) for x in range(8, 56) for y in range(8, 56)]
px = [p for p in px if sum(p) < 600]  # ignore white glyph pixels
base = tuple(sum(c[i] for c in px) // len(px) for i in range(3))
deep = tuple(max(0, int(v * 0.62)) for v in base)


def gradient(w, h):
    g = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(base[i] * (1 - t) + deep[i] * t) for i in range(3)))
    return g


def wrap(draw, text, font, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=font) <= width:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def compose(raw, size, title, sub, title_px, sub_px, top, shot_w, radius):
    W, H = size
    canvas = gradient(W, H)
    d = ImageDraw.Draw(canvas)
    tf, sf = ImageFont.truetype(BOLD, title_px), ImageFont.truetype(REG, sub_px)
    y = top
    for line in wrap(d, title, tf, W * 0.86):
        d.text((W / 2, y), line, font=tf, fill="white", anchor="ma")
        y += int(title_px * 1.14)
    y += int(sub_px * 0.45)
    for line in wrap(d, sub, sf, W * 0.84):
        d.text((W / 2, y), line, font=sf, fill=(255, 255, 255, 220), anchor="ma")
        y += int(sub_px * 1.25)
    y += int(title_px * 0.55)

    shot = Image.open(raw).convert("RGB")
    sh = int(shot.height * shot_w / shot.width)
    avail = H - y - int(H * 0.035)
    if sh > avail:  # keep the whole screen visible, tab bar included
        shot_w, sh = int(shot_w * avail / sh), avail
    shot = shot.resize((shot_w, sh), Image.LANCZOS)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot_w - 1, sh - 1], radius=radius, fill=255)
    x = (W - shot_w) // 2
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 18, x + shot_w, y + sh + 18], radius=radius, fill=120)
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.paste(Image.new("RGB", (W, H), deep), (0, 0), shadow)
    canvas.paste(shot, (x, y), mask)
    return canvas


for i, (scene, title, sub) in enumerate(SCENES, 1):
    phone = RAW / f"iphone-{scene}.png"
    if phone.exists():
        img = compose(phone, (1320, 2868), title, sub, 104, 50, 170, 1060, 72)
        img.save(OUT / f"iphone67-{i}-{scene}.png")
        img.resize((1284, 2778), Image.LANCZOS).save(OUT / f"iphone65-{i}-{scene}.png")
        img.resize((1206, 2622), Image.LANCZOS).save(OUT / f"iphone61-{i}-{scene}.png")
    tablet = RAW / f"ipad-{scene}.png"
    if tablet.exists():
        compose(tablet, (2048, 2732), title, sub, 100, 54, 150, 1560, 44).save(OUT / f"ipad129-{i}-{scene}.png")
    print("composed", scene)
print("panel colour", base, "->", deep)
