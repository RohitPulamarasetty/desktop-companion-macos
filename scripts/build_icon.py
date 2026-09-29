#!/usr/bin/env python3
"""Builds Sources/App/AppIcon.icns (Biscuit, from Characters/, on a warm rounded tile).
Usage: python3 scripts/build_icon.py   (needs Pillow and macOS iconutil)"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

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


def main():
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
