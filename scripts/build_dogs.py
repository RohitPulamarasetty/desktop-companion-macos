#!/usr/bin/env python3
"""Builds the dog characters under Characters/ from the licensed Pixel Dogs sheets
(Benvictus, https://benvictus.itch.io/pixel-dogs).

Usage: python3 scripts/build_dogs.py path/to/PixelDogsSprites.zip
The raw zip is not redistributed in this repository; download it from itch.io.

Source sheet layout (512x432, 64x48 cells, 8 columns, every frame faces
LEFT -- recorded as `nativeFacing: "left"` in the manifest so the engine
flips correctly when walking right):

  row 0  stand, tail wag (frames 6-7: bark while standing)
  row 1  sit             (frames 6-7: bark while sitting)
  row 2  lie down        (frames 6-7: head up / mouth open -> used as yawn)
  row 3  gallop / leap
  row 4  walk
  row 5  run (bounding)
  row 6  walk while barking
  row 7  beg / stand on hind legs (frames 6-7: bark while begging)
  row 8  curled-up sleep, 4 frames (breathing)

Every output strip is a re-sequencing of real frames from that sheet --
no pixels are drawn or edited. Requires Pillow (`pip install pillow`).
"""
import io
import os
import zipfile

from PIL import Image

import json
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
W, H = 64, 48

# name -> list of (row, column) frames, in playback order
CLIPS = {
    "stand":      [(0, c) for c in range(6)],
    "stand_bark": [(0, 0), (0, 6), (0, 7), (0, 6), (0, 7), (0, 0)],
    "sit":        [(1, c) for c in range(6)],
    "sit_bark":   [(1, 0), (1, 6), (1, 7), (1, 6), (1, 7), (1, 0)],
    "lie":        [(2, c) for c in range(6)],
    "yawn":       [(2, 0), (2, 5), (2, 6), (2, 7), (2, 7), (2, 6), (2, 5), (2, 0)],
    "sleep":      [(8, c) for c in range(4)],
    "walk":       [(4, c) for c in range(8)],
    "walk_bark":  [(6, c) for c in range(8)],
    "run":        [(5, c) for c in range(8)],
    "gallop":     [(3, c) for c in range(8)],
    "beg":        [(7, c) for c in range(6)],
    "beg_bark":   [(7, 0), (7, 6), (7, 7), (7, 6), (7, 7), (7, 0)],
    "dragged":    [(7, 0)],
    "fall":       [(3, 1)],
    "land":       [(2, 0)],
}

# id, display name, coat sheet, tagline, description, personality
DOGS = [
    ("biscuit-proto", "Biscuit", 0, "Charcoal, loyal and easygoing", "A steady charcoal pup who likes company.",
     dict(trait="friendly", restfulness=1.0, roaming=1.0, reactivity=1.1, chattiness=1.0, curiosity=1.0, affection=1.2, playfulness=1.0)),
    ("ginger", "Ginger", 2, "Tan, nosy and playful", "A tan pup who investigates everything.",
     dict(trait="curious", restfulness=0.9, roaming=1.15, reactivity=1.1, chattiness=1.1, curiosity=1.4, affection=1.0, playfulness=1.1)),
    ("smoky", "Smoky", 4, "Slate grey, calm and sleepy", "A slate-grey pup who would rather nap.",
     dict(trait="calm", restfulness=1.4, roaming=0.75, reactivity=0.9, chattiness=0.8, curiosity=0.9, affection=1.1, playfulness=0.7)),
    ("rusty", "Rusty", 8, "Red, energetic and loud", "A red pup with too much energy.",
     dict(trait="energetic", restfulness=0.7, roaming=1.4, reactivity=1.3, chattiness=1.3, curiosity=1.1, affection=0.9, playfulness=1.3)),
    ("snowy", "Snowy", 10, "Pale, gentle and clingy", "A pale pup who sticks close to you.",
     dict(trait="affectionate", restfulness=1.0, roaming=0.85, reactivity=1.2, chattiness=0.9, curiosity=0.9, affection=1.5, playfulness=1.0)),
    ("mango", "Mango", 22, "Orange, cheerful and bouncy", "A sunny orange pup who loves to play.",
     dict(trait="playful", restfulness=0.8, roaming=1.25, reactivity=1.2, chattiness=1.2, curiosity=1.2, affection=1.1, playfulness=1.5)),
]
FPS = {"stand": 5, "stand_bark": 8, "sit": 3, "sit_bark": 8, "lie": 2, "yawn": 5, "sleep": 1.2, "walk": 8,
       "walk_bark": 8, "run": 12, "gallop": 14, "beg": 4, "beg_bark": 8, "dragged": 1, "fall": 1, "land": 1}
LICENSE = {
    "type": "author-permission",
    "name": "Informal itch.io author permission (no SPDX license published)",
    "url": "https://benvictus.itch.io/pixel-dogs",
    "copyrightHolder": "Benvictus", "author": "Benvictus",
    "commercialUse": True, "redistribution": None, "modification": None,
    "attributionRequired": False,
    "sourceURL": "https://benvictus.itch.io/pixel-dogs",
    "provenanceNotes": "Author stated on the itch.io page: feel free to use this commercially, credit requested. See THIRD_PARTY.md.",
}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    z = zipfile.ZipFile(sys.argv[1])
    for cid, name, sheet_no, tagline, desc, personality in DOGS:
        sheet = Image.open(io.BytesIO(z.read(f"Pixel Dogs-Sprites/Dogs-Remastered-{sheet_no:02d}.png"))).convert("RGBA")
        out = os.path.join(ROOT, "Characters", cid)
        os.makedirs(os.path.join(out, "sprites"), exist_ok=True)
        for clip, frames in CLIPS.items():
            strip = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
            for i, (row, col) in enumerate(frames):
                strip.paste(sheet.crop((col * W, row * H, col * W + W, row * H + H)), (i * W, 0))
            strip.save(os.path.join(out, "sprites", clip + ".png"), optimize=True)
        states = [{"id": c, "animation": {"spriteSheet": f"sprites/{c}.png", "frameWidth": W, "frameHeight": H,
                                          "frameCount": len(f), "framesPerSecond": FPS[c], "loop": True}}
                  for c, f in CLIPS.items()]
        manifest = {
            "formatVersion": 2, "id": cid, "displayName": name, "description": desc, "tagline": tagline,
            "energy": "normal", "source": "Pixel Dogs by Benvictus", "attribution": "THIRD_PARTY.md",
            "nativeFacing": "left", "pointsPerPixel": 2.5, "gait": 1.0,
            "preview": {"spriteSheet": "sprites/sit.png", "frameWidth": W, "frameHeight": H,
                        "frameCount": 6, "framesPerSecond": 3, "loop": True},
            "initialState": "sit", "states": states, "transitions": [],
            "personality": personality, "license": LICENSE,
        }
        with open(os.path.join(out, "manifest.json"), "w") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")
        print("built", cid)


if __name__ == "__main__":
    main()
