#!/usr/bin/env python3
"""Builds the app icon and menu-bar glyph from the master logo, Branding/logo.png.

  Sources/App/AppIcon.icns          the Dock / Finder / About icon
  Branding/MenuBarIcon(@2x).png     a monochrome template glyph for the menu bar

The logo is never redrawn: it is only re-centred on the tile and scaled so the tile fills the
standard 824/1024 macOS icon grid. Usage: python3 scripts/build_icon.py (needs Pillow and iconutil)."""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOGO = os.path.join(ROOT, "Branding", "logo.png")
CANVAS = 1024
TILE = 824  # width of the solid tile inside the 1024 canvas (Apple's icon grid)


def master() -> Image.Image:
    logo = Image.open(LOGO).convert("RGBA")
    solid = logo.split()[3].point(lambda v: 255 if v > 200 else 0).getbbox()
    scale = TILE / (solid[2] - solid[0])
    resized = logo.resize((round(logo.width * scale), round(logo.height * scale)), Image.LANCZOS)
    cx, cy = (solid[0] + solid[2]) / 2 * scale, (solid[1] + solid[3]) / 2 * scale
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(resized, (round(CANVAS / 2 - cx), round(CANVAS / 2 - cy)))
    return canvas


def app_icon(base: Image.Image) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for size in (16, 32, 128, 256, 512):
            base.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
            base.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
        subprocess.check_call(["iconutil", "--convert", "icns", iconset, "--output", os.path.join(ROOT, "Sources/App/AppIcon.icns")])


def menu_bar_glyph() -> None:
    """A smiling pup head: the logo's character as a one-colour template image (macOS tints it)."""
    s = 4
    m = Image.new("L", (176 * s, 176 * s), 0)
    d = ImageDraw.Draw(m)
    pts = lambda p: [(x * s, y * s) for x, y in p]
    d.ellipse([26 * s, 60 * s, 150 * s, 150 * s], fill=255)
    d.polygon(pts([(30, 92), (38, 20), (92, 68)]), fill=255)
    d.polygon(pts([(146, 92), (138, 20), (84, 68)]), fill=255)
    d.arc([50 * s, 98 * s, 80 * s, 120 * s], 200, 340, fill=0, width=4 * s)
    d.arc([96 * s, 98 * s, 126 * s, 120 * s], 200, 340, fill=0, width=4 * s)
    d.ellipse([80 * s, 116 * s, 96 * s, 128 * s], fill=0)
    d.arc([70 * s, 124 * s, 106 * s, 142 * s], 20, 160, fill=0, width=3 * s)
    box = m.getbbox()
    side = max(box[2] - box[0], box[3] - box[1])
    square = Image.new("L", (side, side), 0)
    square.paste(m.crop(box), ((side - (box[2] - box[0])) // 2, (side - (box[3] - box[1])) // 2))
    for name, px in (("MenuBarIcon.png", 18), ("MenuBarIcon@2x.png", 36)):
        out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        out.putalpha(square.resize((px, px), Image.LANCZOS))
        out.save(os.path.join(ROOT, "Branding", name))


if __name__ == "__main__":
    app_icon(master())
    menu_bar_glyph()
