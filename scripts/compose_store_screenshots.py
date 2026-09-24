"""Composes captioned App Store screenshots from raw simulator captures.

usage: python3 compose_store_screenshots.py <raw_dir> <out_dir>
raw_dir holds iphone-<scene>.png (1320x2868) and ipad-<scene>.png (2064x2752).

Layout, second version (2026-09-23): the owner called the first set "a meme". It shrank the whole
screen into a flat white card under the headline, so the app read small and half of the chat shot
was empty. Now the screen sits in a drawn device (bezel, and the Dynamic Island on iPhone), sized
to bleed off the bottom edge, and each scene can lift one element out of the screen as an enlarged
callout so the point reads at thumbnail size. The blue panel and the headlines are unchanged.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
ICON = Path(__file__).resolve().parent.parent / "OpenIntelligence/Resources/Assets/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
BOLD = "/Library/Fonts/SF-Pro-Display-Bold.otf"
REG = "/Library/Fonts/SF-Pro-Display-Regular.otf"

# (scene, headline, subline, iPhone callout box, iPad callout box). Boxes are (x0, y0, x1, y1) in the
# raw capture's pixels; None shows the screen alone. Scenes without a raw capture are skipped.
SCENES = [
    ("answer", "Ask your own documents anything", "Every claim cites the page it came from",
     (70, 1080, 1180, 2000), (40, 600, 1920, 1200)),
    ("refusal", "It tells you when your files don't say it", "No guessing. No made-up answers.",
     (50, 1540, 1270, 2250), (40, 1110, 2020, 1520)),
    ("sources", "See where every answer came from", "The real passages, page by page",
     (50, 1235, 1270, 1760), (460, 1400, 1600, 1720)),
    # iPhone only: the iPad shows the whole page, whose Private Cloud Compute section reads "not
    # enabled in this build" in the simulator, which has no PCC entitlement. Devices show it enabled.
    ("howitworks", "No server. No account.", "Your documents are read, indexed and searched right on your device",
     (48, 396, 1272, 915), None),
    ("consent", "Built on Apple Intelligence", "On your device. Private Cloud Compute only when you approve it.",
     (70, 1545, 1260, 1975), (480, 1880, 1640, 2190)),
    # From the owner's iPhone (devicectl device capture screenshot) with the simulator's dark 9:41
    # status bar pasted over his: the simulator draws the axes and none of the points. The callout
    # sits low so it covers the library card, which reads "0 Docs" beside 41 chunks.
    ("atlas", "Your whole library, mapped in 3D", "Every passage placed by what it means",
     (38, 800, 1282, 2040), None, {"callout_bottom": 0.965}),
    # On iPad the whole tab shows, including "Performance Advantage" multipliers (100x, 10x) that no
    # benchmark backs, so the iPad callout sits over them. The iPhone crop ends above them.
    ("database", "Nothing hidden under the hood", "A real full-text search engine, running on your device",
     (40, 520, 1280, 1150), (30, 300, 2040, 710), {"tablet": {"callout_bottom": 0.83}}),
    ("settings", "It explains itself", "Every word it uses, defined in plain English",
     (40, 1000, 1280, 1640), (30, 770, 1990, 1180)),
    ("onboarding-1", "Bring any file you've got", "PDFs, Office files, scans, images, code and transcripts", None, None),
]

# The panel colour comes from the app icon so the listing reads as one product.
icon = Image.open(ICON).convert("RGB").resize((64, 64))
px = [icon.getpixel((x, y)) for x in range(8, 56) for y in range(8, 56)]
px = [p for p in px if sum(p) < 600]  # ignore white glyph pixels
base = tuple(sum(c[i] for c in px) // len(px) for i in range(3))
deep = tuple(max(0, int(v * 0.62)) for v in base)


def gradient(w, h):
    """Icon blue into deep blue, lit from above: a wide pale glow behind the headline, a violet
    glow low on one side, and a faint diagonal sheen, so the panel reads as a lit surface."""
    g = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(base[i] * (1 - t) + deep[i] * t) for i in range(3)))
    g = g.convert("RGBA")
    m = min(w, h)
    for (cx, cy, r, col, a) in ((0.5 * w, -0.12 * h, 0.95 * m, (150, 215, 255), 120),
                                 (0.05 * w, 0.92 * h, 0.75 * m, (92, 70, 220), 95),
                                 (0.98 * w, 0.55 * h, 0.55 * m, (40, 190, 255), 60)):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse((cx - r, cy - r, cx + r, cy + r), fill=col + (a,))
        g.alpha_composite(layer.filter(ImageFilter.GaussianBlur(int(r * 0.45))))
    sheen = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon([(0, 0.18 * h), (w, -0.1 * h), (w, 0.05 * h), (0, 0.33 * h)], fill=(255, 255, 255, 16))
    g.alpha_composite(sheen.filter(ImageFilter.GaussianBlur(int(0.04 * m))))
    return g.convert("RGB")


def headline(canvas, x, y, text, font, fill):
    """White text with a soft dark-blue shadow under it, for depth against the glow."""
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((x, y + font.size * 0.05), text, font=font, fill=(6, 30, 70, 110), anchor="ma")
    canvas.paste(sh.filter(ImageFilter.GaussianBlur(max(2, font.size // 14))), (0, 0), sh.filter(ImageFilter.GaussianBlur(max(2, font.size // 14))))
    ImageDraw.Draw(canvas).text((x, y), text, font=font, fill=fill, anchor="ma")


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
    if len(lines) != 2:
        return lines
    # Two lines: split where the longer line is shortest, so a headline never ends on a lone word
    # ("Bring any file you've / got" was the first render).
    best = min(range(1, len(words)), key=lambda i: max(draw.textlength(" ".join(words[:i]), font=font),
                                                       draw.textlength(" ".join(words[i:]), font=font)))
    return [" ".join(words[:best]), " ".join(words[best:])]


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=radius, fill=255)
    return mask


def shadow_under(canvas, box, radius, blur, alpha, dy):
    W, H = canvas.size
    s = Image.new("L", (W, H), 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(s).rounded_rectangle([x0, y0 + dy, x1, y1 + dy], radius=radius, fill=alpha)
    canvas.paste(Image.new("RGB", (W, H), (8, 18, 40)), (0, 0), s.filter(ImageFilter.GaussianBlur(blur)))


def compose(raw, size, title, sub, callout, phone, opts=None):
    opts = opts or {}
    W, H = size
    canvas = gradient(W, H)
    d = ImageDraw.Draw(canvas)
    title_px, sub_px = (112, 52) if phone else (108, 56)
    tf, sf = ImageFont.truetype(BOLD, title_px), ImageFont.truetype(REG, sub_px)
    y = 150 if phone else 140
    for line in wrap(d, title, tf, W * 0.88):
        headline(canvas, W / 2, y, line, tf, "white")
        y += int(title_px * 1.12)
    y += int(sub_px * 0.4)
    for line in wrap(d, sub, sf, W * 0.86):
        d.text((W / 2, y), line, font=sf, fill=(232, 240, 255), anchor="ma")
        y += int(sub_px * 1.24)
    top = y + int(title_px * 0.62)

    shot = Image.open(raw).convert("RGB")
    sw = int(W * (0.83 if phone else 0.84))
    sh = int(shot.height * sw / shot.width)
    scale = sw / shot.width
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bezel, band = (int(sw * 0.026), int(sw * 0.007)) if phone else (int(sw * 0.034), int(sw * 0.006))
    r_screen = int(sw * (0.125 if phone else 0.03))
    r_dev = r_screen + bezel + band
    dx = (W - sw) // 2
    dev = (dx - bezel - band, top, dx + sw + bezel + band, top + sh + 2 * (bezel + band))
    shadow_under(canvas, dev, r_dev, 56, 175, 34)
    d = ImageDraw.Draw(canvas)
    if phone:  # side buttons: action and volume on the left, side button on the right
        bw = max(6, int(sw * 0.006))
        for (bx, by, bh) in ((dev[0] - bw, 0.17, 0.035), (dev[0] - bw, 0.235, 0.06), (dev[0] - bw, 0.31, 0.06), (dev[2] - 2, 0.25, 0.09)):
            y0 = dev[1] + int((dev[3] - dev[1]) * by)
            d.rounded_rectangle((bx, y0, bx + bw + 2, y0 + int((dev[3] - dev[1]) * bh)), radius=bw // 2 + 1, fill=(74, 77, 84))
    d.rounded_rectangle(dev, radius=r_dev, fill=(118, 122, 130))  # lit edge of the band
    d.rounded_rectangle((dev[0] + 2, dev[1] + 2, dev[2] - 2, dev[3] - 2), radius=r_dev - 2, fill=(58, 60, 66))  # the band
    d.rounded_rectangle((dev[0] + band, dev[1] + band, dev[2] - band, dev[3] - band), radius=r_dev - band, fill=(10, 10, 12))
    sx, sy = dx, top + bezel + band
    canvas.paste(shot, (sx, sy), rounded(shot, r_screen))
    if phone:  # Dynamic Island, over the blank space the simulator leaves for it
        iw, ih, it = int(sw * 0.286), int(sw * 0.084), int(sw * 0.025)
        d.rounded_rectangle((sx + (sw - iw) // 2, sy + it, sx + (sw + iw) // 2, sy + it + ih), radius=ih // 2, fill=(0, 0, 0))

    if callout:
        _, y0, _, y1 = callout
        card = Image.open(raw).convert("RGB").crop(callout)
        cw = int(W * (0.9 if phone else 0.86))
        ch = int(card.height * cw / card.width)
        card = card.resize((cw, ch), Image.LANCZOS)
        cx = (W - cw) // 2
        cy = int(sy + (y0 + y1) / 2 * scale - ch / 2)  # centred on where it sits in the screen
        cy = max(top + int(sw * 0.1), min(cy, H - ch - int(H * 0.05)))
        if "callout_bottom" in opts:
            cy = int(H * opts["callout_bottom"]) - ch
        rc = int(cw * 0.04)
        shadow_under(canvas, (cx, cy, cx + cw, cy + ch), rc, 44, 190, 30)
        d = ImageDraw.Draw(canvas)
        d.rounded_rectangle((cx - 6, cy - 6, cx + cw + 6, cy + ch + 6), radius=rc + 6, fill=(255, 255, 255))
        canvas.paste(card, (cx, cy), rounded(card, rc))
    return canvas



# Mac (APP_DESKTOP, 2880x1800): raw_dir/mac-<scene>.png is a window capture from the debug build
# at 1440x900 points on a 2x display (screencapture -o -l <window>), rounded corners transparent.
# A macOS sheet is its own window, so a sheet scene is captured as mac-<scene>.w1.png (the app
# window), .w2.png (the sheet) and .windows.txt ("id x y w h" per window, points, largest first),
# and layered here. Boxes are in the capture's pixels; "mag" is the callout's size against the
# capture's own pixels, "bottom" seats it low (to cover what should not be featured).
MAC_SCENES = [
    ("answer", "Ask your own documents anything", "Every claim cites the page it came from",
     (40, 600, 2730, 1090), {}),
    ("refusal", "It tells you when your files don't say it", "No guessing. No made-up answers.",
     (45, 1050, 2865, 1530), {}),
    ("sources", "See where every answer came from", "The real passages, page by page", None, {}),
    ("consent", "Built on Apple Intelligence", "On your Mac. Private Cloud Compute only when you approve it.",
     (999, 759, 1881, 1011), {"mag": 1.7}),
    # The library card under the graph reads "0 Docs" beside 41 chunks, so the callout covers it.
    ("atlas", "Your whole library, mapped in 3D", "Every passage placed by what it means",
     (30, 300, 2850, 1131), {"bottom": 0.975}),
    # Seated low over the tab's "Performance Advantage" multipliers, which no benchmark backs.
    ("database", "Nothing hidden under the hood", "A real full-text search engine, running on your Mac",
     (40, 165, 2840, 480), {"bottom": 0.995}),
    ("settings", "It explains itself", "Every word it uses, defined in plain English",
     (30, 625, 1500, 1000), {"mag": 1.35}),
    ("whatsnew", "Answers that don't keep you waiting", "What's new in 5.4, in the app's own words", None, {}),
]


def layered(scene):
    """The app window with its sheet window(s) pasted at their on-screen offsets."""
    rows = [list(map(int, l.split())) for l in (RAW / f"mac-{scene}.windows.txt").read_text().split("\n") if l.strip()]
    base = Image.open(RAW / f"mac-{scene}.w1.png").convert("RGBA")
    k = base.width / rows[0][3]  # pixels per point
    for i, (_, x, y, _, _) in enumerate(rows[1:], 2):
        sheet = Image.open(RAW / f"mac-{scene}.w{i}.png").convert("RGBA")
        base.alpha_composite(sheet, (int((x - rows[0][1]) * k), int((y - rows[0][2]) * k)))
    return base


def compose_mac(raw, title, sub, callout, opts):
    W, H = 2880, 1800
    canvas = gradient(W, H)
    d = ImageDraw.Draw(canvas)
    tf, sf = ImageFont.truetype(BOLD, 124), ImageFont.truetype(REG, 60)
    y = 100
    for line in wrap(d, title, tf, W * 0.8):
        headline(canvas, W / 2, y, line, tf, "white")
        y += int(124 * 1.1)
    y += 18
    for line in wrap(d, sub, sf, W * 0.75):
        d.text((W / 2, y), line, font=sf, fill=(232, 240, 255), anchor="ma")
        y += int(60 * 1.22)
    top = y + 56
    src = raw if isinstance(raw, Image.Image) else Image.open(raw).convert("RGBA")
    ww = int(W * 0.9)  # bleeds off the bottom edge, like the iPhone shots
    wh = int(src.height * ww / src.width)
    scale = ww / src.width
    win = src.resize((ww, wh), Image.LANCZOS)
    x = (W - ww) // 2
    shadow_under(canvas, (x, top, x + ww, top + wh), 28, 60, 185, 34)
    canvas.paste(win, (x, top), win)
    if callout:
        _, y0, _, y1 = callout
        card = src.convert("RGB").crop(callout)
        cw = int(min(W * 0.9, card.width * opts.get("mag", 1.2)))
        ch = int(card.height * cw / card.width)
        card = card.resize((cw, ch), Image.LANCZOS)
        cx = (W - cw) // 2
        cy = int(top + (y0 + y1) / 2 * scale - ch / 2)
        cy = max(top + 80, min(cy, H - ch - 50))
        if "bottom" in opts:
            cy = int(H * opts["bottom"]) - ch
        rc = 34
        shadow_under(canvas, (cx, cy, cx + cw, cy + ch), rc, 36, 170, 22)
        d = ImageDraw.Draw(canvas)
        d.rounded_rectangle((cx - 6, cy - 6, cx + cw + 6, cy + ch + 6), radius=rc + 6, fill=(255, 255, 255))
        canvas.paste(card, (cx, cy), rounded(card, rc))
    return canvas.convert("RGB")

n = 0
for scene, title, sub, box_phone, box_tablet, *rest in SCENES:
    opts = rest[0] if rest else {}
    tablet_opts = opts.get("tablet", {})
    opts = {k: v for k, v in opts.items() if k != "tablet"}
    phone_raw, tablet_raw = RAW / f"iphone-{scene}.png", RAW / f"ipad-{scene}.png"
    if not phone_raw.exists() and not tablet_raw.exists():
        print("skipped", scene, "(no capture)")
        continue
    n += 1
    if phone_raw.exists():
        img = compose(phone_raw, (1320, 2868), title, sub, box_phone, True, opts)
        img.save(OUT / f"iphone67-{n}-{scene}.png")
        img.resize((1284, 2778), Image.LANCZOS).save(OUT / f"iphone65-{n}-{scene}.png")
        img.resize((1206, 2622), Image.LANCZOS).save(OUT / f"iphone61-{n}-{scene}.png")
    if tablet_raw.exists():
        compose(tablet_raw, (2048, 2732), title, sub, box_tablet, False, tablet_opts).save(OUT / f"ipad129-{n}-{scene}.png")
    print("composed", n, scene)
print("panel colour", base, "->", deep)

m = 0
for scene, title, sub, box, opts in MAC_SCENES:
    if (RAW / f"mac-{scene}.windows.txt").exists():
        src = layered(scene)
    elif (RAW / f"mac-{scene}.png").exists():
        src = Image.open(RAW / f"mac-{scene}.png").convert("RGBA")
    else:
        continue
    m += 1
    compose_mac(src, title, sub, box, opts).save(OUT / f"mac-{m}-{scene}.png")
    print("composed mac", m, scene)
