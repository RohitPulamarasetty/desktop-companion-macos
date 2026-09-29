#!/usr/bin/env python3
"""Builds Sources/App/AppIcon.icns (Biscuit, from Characters/, on a warm rounded tile) and
Packaging/dmg-background.png (the drag-to-Applications backdrop).
Usage: python3 scripts/build_icon.py   (needs Pillow and macOS iconutil)"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SIZE = 1024


def tile():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle((60, 60, SIZE - 60, SIZE - 60), radius=210, fill=255)
    top, bottom = (255, 240, 214), (244, 192, 140)
    grad = Image.new("RGBA", (SIZE, SIZE))
    px = grad.load()
    for y in range(SIZE):
        t = y / SIZE
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(SIZE):
            px[x, y] = c
    img.paste(grad, (0, 0), mask)
    strip = Image.open(os.path.join(ROOT, "Characters/biscuit-proto/sprites/sit.png")).convert("RGBA")
    dog = strip.crop((0, 0, 64, 48))
    dog = dog.crop(dog.getbbox())
    scale = max(1, 620 // max(dog.width, dog.height))
    dog = dog.resize((dog.width * scale, dog.height * scale), Image.NEAREST)
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    x0, y0 = (SIZE - dog.width) // 2, (SIZE - dog.height) // 2 - 20
    ImageDraw.Draw(shadow).ellipse((x0 - 20, y0 + dog.height - 30, x0 + dog.width + 20, y0 + dog.height + 40), fill=(120, 70, 30, 70))
    img = Image.alpha_composite(img, shadow)
    img.alpha_composite(dog, (x0, y0))
    return img


def dmg_background():
    """600x400 logical window at 2x. Icons are placed at (150,190) and (450,190) by package_dmg.sh."""
    w, h = 1200, 800
    img = Image.new("RGBA", (w, h), (255, 246, 232, 255))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", 40)
        small = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", 28)
    except OSError:
        font = small = ImageFont.load_default()
    d.text((w // 2, 90), "Drag Desktop Companion to Applications", fill=(66, 48, 36, 255), font=font, anchor="mm")
    d.text((w // 2, 700), "Then open it from your Applications folder", fill=(134, 115, 100, 255), font=small, anchor="mm")
    # arrow between the two icons
    y = 380
    d.line((470, y, 700, y), fill=(217, 128, 66, 255), width=14)
    d.polygon([(700, y - 40), (770, y), (700, y + 40)], fill=(217, 128, 66, 255))
    img.convert("RGB").save(os.path.join(ROOT, "Packaging/dmg-background.png"))


def main():
    dmg_background()
    base = tile()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for size in (16, 32, 128, 256, 512):
            base.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
            base.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
        subprocess.check_call(["iconutil", "--convert", "icns", iconset, "--output", os.path.join(ROOT, "Sources/App/AppIcon.icns")])


if __name__ == "__main__":
    main()
