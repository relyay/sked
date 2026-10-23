"""Generate the iOS and Android app icons from icon.png.

Usage (needs Pillow): python3 tools/make_icons.py icon.png .

The source is a 1254x1254 white "S" on #2573FC with no alpha. iOS gets it as
is (1024x1024, no alpha). Android gets an adaptive icon: the background color
plus the "S" on a transparent foreground layer, so launchers can mask it and
Android 13+ can theme it.
"""
import sys
from pathlib import Path

from PIL import Image

src, root = Path(sys.argv[1]), Path(sys.argv[2])
im = Image.open(src).convert("RGB")
# Sampled background; keep android/.../values/colors.xml ic_launcher_background in sync.
BG = (37, 115, 252)

(root / "ios/AppResources").mkdir(parents=True, exist_ok=True)
im.resize((1024, 1024), Image.LANCZOS).save(root / "ios/AppResources/AppIcon.png", optimize=True)

# Every glyph pixel is white blended over BG: p = a*255 + (1-a)*bg, so the
# alpha can be recovered exactly. Blue is ~252 in the background and carries
# no signal, so only R and G are used; tiny values are background noise.
w, h = im.size
fg = Image.new("RGBA", (w, h), (255, 255, 255, 0))
px, out = im.load(), fg.load()
for y in range(h):
    for x in range(w):
        p = px[x, y]
        a = max((p[i] - BG[i]) / (255 - BG[i]) for i in range(2))
        a = 0.0 if a < 0.04 else min(1.0, a)
        out[x, y] = (255, 255, 255, round(a * 255))

# At full size the glyph's corner touches a circular launcher mask; 85% keeps
# it inside the adaptive icon safe zone.
scale = 0.85
glyph = fg.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
canvas = Image.new("RGBA", (w, h), (255, 255, 255, 0))
canvas.paste(glyph, ((w - glyph.width) // 2, (h - glyph.height) // 2), glyph)

# 108dp adaptive-icon layer at each density.
for density, size in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
    out_dir = root / f"android/app/src/main/res/mipmap-{density}"
    out_dir.mkdir(parents=True, exist_ok=True)
    canvas.resize((size, size), Image.LANCZOS).save(out_dir / "ic_launcher_foreground.png", optimize=True)
