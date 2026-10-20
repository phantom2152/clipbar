#!/usr/bin/env python3
"""Renders the ClipBar app icon (1024px PNG + .icns) and a preview sheet.
Usage: python3 Tools/make_icon.py        (needs: pip install pillow numpy)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Resources")
K = 2                       # supersampling factor
S = 1024 * K

TEAL_LIGHT = (45, 212, 191)
TEAL_DARK = (8, 70, 90)
INK = (14, 116, 128)        # text lines on the sheet
CLIP = (10, 78, 94)         # metal clip


def px(v): return int(round(v * K))


def rrect(draw, x0, y0, x1, y1, r, fill):
    draw.rounded_rectangle([px(x0), px(y0), px(x1), px(y1)], radius=px(r), fill=fill)


def gradient(size, c0, c1):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    t = ((xx + yy) / (2 * (size - 1)))[..., None]
    a = np.array(c0, np.float32); b = np.array(c1, np.float32)
    rgb = a + (b - a) * t
    img = np.dstack([rgb, np.full((size, size, 1), 255, np.float32)])
    return Image.fromarray(img.astype(np.uint8), "RGBA")


def app_icon():
    # --- background squircle (macOS grid: 824px artwork inside the 1024 canvas)
    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = gradient(S, TEAL_LIGHT, TEAL_DARK)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([px(100), px(100), px(924), px(924)], radius=px(188), fill=255)
    art.paste(bg, (0, 0), mask)

    # soft top highlight
    ys = np.linspace(0, 1, S, dtype=np.float32)[:, None]
    hd = np.zeros((S, S, 4), np.uint8)
    hd[..., :3] = 255
    hd[..., 3] = (np.clip(1 - ys / 0.55, 0, 1) * 34).astype(np.uint8).repeat(S, axis=1)
    hl = Image.fromarray(hd, "RGBA")
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0)); clipped.paste(hl, (0, 0), mask)
    art = Image.alpha_composite(art, clipped)

    # --- glyph: a clipboard with a second sheet behind it (= history)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    white = (255, 255, 255, 255)

    bx0, by0, bx1, by1 = 270, 252, 710, 802          # front board
    rrect(d, bx0 + 38, by0 - 30, bx1 + 38, by1 - 30, 56, (255, 255, 255, 105))   # sheet behind
    rrect(d, bx0, by0, bx1, by1, 56, white)                                        # board

    # text lines
    x0 = bx0 + 62
    for i, w in enumerate((316, 316, 226, 316, 168)):
        y = by0 + 128 + i * 82
        rrect(d, x0, y, x0 + w, y + 30, 15, INK + (255,))

    # clip on top
    cx = (bx0 + bx1) / 2
    rrect(d, cx - 100, by0 - 44, cx + 100, by0 + 50, 34, CLIP + (255,))
    rrect(d, cx - 46, by0 - 18, cx + 46, by0 + 6, 12, (255, 255, 255, 230))

    # drop shadow under the glyph
    shadow = layer.filter(ImageFilter.GaussianBlur(px(14)))
    sh = np.array(shadow); sh[..., :3] = 6; sh[..., 3] = (sh[..., 3] * 0.35).astype(np.uint8)
    shadow = Image.fromarray(sh, "RGBA")
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0)); shifted.paste(shadow, (0, px(10)))
    art = Image.alpha_composite(art, shifted)
    art = Image.alpha_composite(art, layer)

    # --- outer drop shadow of the whole tile
    sm = mask.filter(ImageFilter.GaussianBlur(px(18)))
    blk = Image.new("RGBA", (S, S), (0, 0, 0, 90)); sb = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sb.paste(blk, (0, px(14)), sm)
    base = Image.alpha_composite(Image.new("RGBA", (S, S), (0, 0, 0, 0)), sb)
    base = Image.alpha_composite(base, art)
    return base.resize((1024, 1024), Image.LANCZOS)


def preview(icon):
    sheet = Image.new("RGBA", (1100, 640), (24, 26, 30, 255))
    sheet.alpha_composite(icon.resize((512, 512), Image.LANCZOS), (50, 64))
    d = ImageDraw.Draw(sheet)
    # small sizes on a dark and a light card
    for i, color in enumerate(((44, 46, 54, 255), (238, 240, 244, 255))):
        y = 64 + i * 270
        d.rounded_rectangle([620, y, 1050, y + 240], radius=18, fill=color)
        for j, size in enumerate((128, 64, 32, 16)):
            sheet.alpha_composite(icon.resize((size, size), Image.LANCZOS),
                                  (650 + [0, 150, 240, 300][j], y + 56))
    d.text((50, 590), "ClipBar", fill=(255, 255, 255, 255))
    return sheet


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icon = app_icon()
    icon.save(os.path.join(OUT, "AppIcon-1024.png"))
    icon.save(os.path.join(OUT, "AppIcon.icns"), format="ICNS",
              sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    preview(icon).convert("RGB").save(os.path.join(OUT, "icon-preview.png"))
    print("ok")
