"""Generate the iOS, Android and desktop app icons from icon.png.

Usage (needs Pillow): python3 tools/make_icons.py icon.png . [preview.png]

The source is a square white glyph (any shading) on a flat background, with
no alpha. iOS gets it as is (1024x1024, no alpha), the desktop app at
512x512. Android gets an adaptive icon: the background color (sampled from the corners and written to
values/colors.xml) plus the glyph on a transparent foreground layer, so
launchers can mask it and Android 13+ can theme it. The optional third
argument writes a preview under a circular launcher mask.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

src, root = Path(sys.argv[1]), Path(sys.argv[2])
preview = Path(sys.argv[3]) if len(sys.argv) > 3 else None
im = Image.open(src).convert("RGB")
w, h = im.size

# Background: per-channel median of pixels near the four corners.
samples = [im.getpixel((x, y)) for x in (4, 8, w - 9, w - 5) for y in (4, 8, h - 9, h - 5)]
BG = tuple(sorted(s[i] for s in samples)[len(samples) // 2] for i in range(3))
hex_bg = "%02X%02X%02X" % BG

(root / "ios/AppResources").mkdir(parents=True, exist_ok=True)
im.resize((1024, 1024), Image.LANCZOS).save(root / "ios/AppResources/AppIcon.png", optimize=True)

# Desktop (hicolor 512x512, installed by `just desktop-install`).
(root / "desktop/data").mkdir(parents=True, exist_ok=True)
im.resize((512, 512), Image.LANCZOS).save(root / "desktop/data/ru.sked.app.png", optimize=True)

# Every glyph pixel is white blended over BG: p = a*255 + (1-a)*bg, so the
# alpha can be recovered exactly. Channels where the background is already
# near 255 carry no signal (and amplify noise), so only use channels with
# room to spare; tiny values are background noise.
channels = [i for i in range(3) if 255 - BG[i] > 40]
fg = Image.new("RGBA", (w, h), (255, 255, 255, 0))
px, out = im.load(), fg.load()
for y in range(h):
    for x in range(w):
        p = px[x, y]
        a = max((p[i] - BG[i]) / (255 - BG[i]) for i in channels)
        a = 0.0 if a < 0.04 else min(1.0, a)
        out[x, y] = (255, 255, 255, round(a * 255))

# At full size a large glyph touches a circular launcher mask; 85% keeps it
# inside the adaptive icon safe zone.
scale = 0.85
glyph = fg.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
canvas = Image.new("RGBA", (w, h), (255, 255, 255, 0))
canvas.paste(glyph, ((w - glyph.width) // 2, (h - glyph.height) // 2), glyph)

# 108dp adaptive-icon layer at each density.
for density, size in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
    out_dir = root / f"android/app/src/main/res/mipmap-{density}"
    out_dir.mkdir(parents=True, exist_ok=True)
    canvas.resize((size, size), Image.LANCZOS).save(out_dir / "ic_launcher_foreground.png", optimize=True)

colors = root / "android/app/src/main/res/values/colors.xml"
text = colors.read_text()
text = re.sub(r'(<color name="ic_launcher_background">)#[0-9A-Fa-f]{6,8}(</color>)', rf"\g<1>#FF{hex_bg}\g<2>", text)
colors.write_text(text)

if preview:
    size = 432
    icon = Image.new("RGBA", (size, size), BG + (255,))
    icon.alpha_composite(canvas.resize((size, size), Image.LANCZOS))
    mask = Image.new("L", (size, size), 0)
    # Launchers show the inner 72dp of the 108dp layer; a circle mask fills it.
    inset = size * 18 / 108
    ImageDraw.Draw(mask).ellipse((inset, inset, size - inset, size - inset), fill=255)
    out_img = Image.new("RGBA", (size, size), (240, 240, 240, 255))
    out_img.paste(icon, (0, 0), mask)
    out_img.save(preview)

print(f"background #{hex_bg}")
