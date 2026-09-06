#!/usr/bin/env python3
"""
Generates the Vehicle Finder toggle-bar icons.

The sprite is hand-plotted pixel art (no font/clipart), drawn in the muted
Project Zomboid UI palette: dark outline, desaturated body colour, cold glass,
flat black tyres. Run this script to regenerate the textures:

    python3 tools/generate_icons.py
"""

import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "Contents", "mods", "VehicleFinder", "42",
                   "media", "textures")

# ---------------------------------------------------------------- palette ---
P = {
    ".": (0, 0, 0, 0),          # transparent
    "K": (23, 22, 26, 255),     # outline
    "B": (140, 66, 54, 255),    # body
    "H": (176, 92, 74, 255),    # body highlight
    "S": (92, 42, 35, 255),     # body shadow
    "G": (122, 148, 160, 255),  # glass
    "g": (88, 112, 124, 255),   # glass shadow
    "T": (22, 21, 25, 255),     # tyre
    "R": (84, 84, 92, 255),     # rim
    "L": (222, 178, 82, 255),   # head light
    "r": (168, 62, 52, 255),    # tail light
    "W": (198, 190, 172, 255),  # bumper / trim
    "z": (0, 0, 0, 70),         # ground shadow
}

# 32x32 side view. Rows are written top to bottom, one character per pixel.
CAR = [
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "..........KKKKKKKKKK............",
    ".........KHHHHHHHHHHK...........",
    "........KKGGGGGKGGGGKK..........",
    ".......KKGGGGGGKGGGGGGKK........",
    "......KKgGGGGGGKGGGGGGggKKK.....",
    "....KKKHHHHHHHHHHHHHHHHHHHKKK...",
    "...KHHBBBBBBBBBBBBBBBBBBBBBBBHK.",
    "..KrBBBBBBBBBBBBBBBBBBBBBBBBBBLK",
    "..KrBBBBBBBBBBBBBBBBBBBBBBBBBBLK",
    "..KSSKTTTTTKSSSSSSSKTTTTTKSSSSSK",
    "..KWSTTRRRTTSSSSSSSTTRRRTTSSSSWK",
    "..KKKTTRRRTTKKKKKKKTTRRRTTKKKKKK",
    ".....TTRRRTT.......TTRRRTT......",
    "......TTTTT.........TTTTT.......",
    "...zzzzzzzzzzzzzzzzzzzzzzzzzz...",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
]


def build(rows):
    for i, r in enumerate(rows):
        assert len(r) == 32, "row %d has %d px" % (i, len(r))
    assert len(rows) == 32, "%d rows" % len(rows)
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px[x, y] = P[ch]
    return img


def save(img, name):
    os.makedirs(TEX, exist_ok=True)
    path = os.path.join(TEX, name)
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def poster(car, size=256):
    """Mod poster / workshop preview: the same sprite on a PZ-ish dark board."""
    img = Image.new("RGBA", (size, size), (38, 37, 42, 255))
    d = ImageDraw.Draw(img)
    # subtle scan bands, keeps the flat background from looking dead
    for y in range(0, size, 4):
        d.line([(0, y), (size, y)], fill=(44, 43, 49, 255))
    d.rectangle([0, 0, size - 1, size - 1], outline=(23, 22, 26, 255), width=4)
    d.rectangle([6, 6, size - 7, size - 7], outline=(88, 84, 78, 255), width=1)
    scale = 6
    big = car.resize((32 * scale, 32 * scale), Image.NEAREST)
    img.alpha_composite(big, ((size - big.width) // 2, (size - big.height) // 2))
    return img


def main():
    car = build(CAR)
    save(car, "VehicleFinder_Car.png")

    art = poster(car)
    mod_dir = os.path.join(ROOT, "Contents", "mods", "VehicleFinder")
    os.makedirs(mod_dir, exist_ok=True)
    art.convert("RGB").save(os.path.join(mod_dir, "poster.png"))
    art.convert("RGB").save(os.path.join(ROOT, "preview.png"))
    print("wrote Contents/mods/VehicleFinder/poster.png")
    print("wrote preview.png")

    # 8x zoom, for eyeballing the pixels while iterating.
    car.resize((256, 256), Image.NEAREST).save("/tmp/claude-0/vf_preview.png")


if __name__ == "__main__":
    main()
