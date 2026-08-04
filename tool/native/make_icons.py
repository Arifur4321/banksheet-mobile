#!/usr/bin/env python3
"""Generate every app icon BankSheet Pro needs, from one vector-ish source.

Why a script and not a folder of PNGs someone exported once: an icon that only
exists as binary output cannot be adjusted without the original, and "who has
the Figma file" is a question no handover should ever have to answer. Run this
and every density is regenerated, consistently, from the brand tokens below.

    python3 tool/native/make_icons.py

Writes into tool/native/icons/, which IS tracked. tool/native/apply.py then
installs them into the generated android/ and ios/ trees.

Design, and why:
  * Deep forest-to-jade background, straight off lib/core/theme/tokens.dart, so
    the icon is the same green as the app's first screen.
  * A white page whose top is ruled lines (the statement you feed in) and whose
    bottom is a grid of cells (the clean data you get back). That is the entire
    product in one silhouette.
  * A jade-bright bolt badge, the same mark the "Reconciled" pill carries.
  * Everything is drawn at 4x and downsampled, because PIL's polygon edges are
    hard-aliased and a 48px launcher icon shows every jagged pixel.
"""

import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'icons')

# --- brand tokens (must match lib/core/theme/tokens.dart) -------------------
FOREST      = (16, 40, 32)
FOREST_SOFT = (31, 64, 54)
JADE        = (31, 122, 90)
JADE_BRIGHT = (67, 198, 139)
PAPER_WHITE = (255, 254, 250)
SAND        = (239, 233, 220)

SS = 4  # supersample factor


def _round_rect(d, box, r, fill):
    d.rounded_rectangle(box, radius=r, fill=fill)


def draw_glyph(img, size, inset):
    """The page-and-grid mark, centred, occupying `inset` fraction of `size`."""
    d = ImageDraw.Draw(img)
    g = size * inset                      # glyph box side
    ox = (size - g) / 2
    oy = (size - g) / 2

    # --- the page ---------------------------------------------------------
    pw, ph = g * 0.74, g * 0.92
    px, py = ox + (g - pw) / 2, oy + (g - ph) / 2
    _round_rect(d, (px, py, px + pw, py + ph), g * 0.075, PAPER_WHITE)

    pad = pw * 0.14
    lx0, lx1 = px + pad, px + pw - pad

    # ruled lines: the raw statement
    ly = py + ph * 0.14
    for i, frac in enumerate((1.0, 0.78, 0.90)):
        h = ph * 0.035
        _round_rect(d, (lx0, ly, lx0 + (lx1 - lx0) * frac, ly + h), h / 2, SAND)
        ly += ph * 0.085

    # grid of cells: the clean data
    gy = py + ph * 0.47
    gh = ph * 0.38
    cols, rows = 3, 3
    gap = (lx1 - lx0) * 0.06
    cw = ((lx1 - lx0) - gap * (cols - 1)) / cols
    ch = (gh - gap * (rows - 1)) / rows
    for r in range(rows):
        for c in range(cols):
            x = lx0 + c * (cw + gap)
            y = gy + r * (ch + gap)
            # the right-hand column is the reconciled total, so it is solid
            fill = JADE if c == cols - 1 else FOREST_SOFT + (0,)
            if c == cols - 1:
                _round_rect(d, (x, y, x + cw, y + ch), ch * 0.28, JADE)
            else:
                _round_rect(d, (x, y, x + cw, y + ch), ch * 0.28,
                            (JADE[0], JADE[1], JADE[2], 90))
    # --- bolt badge -------------------------------------------------------
    br = g * 0.155
    bx = px + pw - br * 0.55
    by = py + ph - br * 0.75
    d.ellipse((bx - br, by - br, bx + br, by + br), fill=JADE_BRIGHT)
    s = br * 0.92
    d.polygon(
        [
            (bx + s * 0.10, by - s * 0.62),
            (bx - s * 0.42, by + s * 0.10),
            (bx - s * 0.04, by + s * 0.10),
            (bx - s * 0.12, by + s * 0.64),
            (bx + s * 0.42, by - s * 0.12),
            (bx + s * 0.02, by - s * 0.12),
        ],
        fill=FOREST,
    )


def background(size, radius_frac):
    """Forest-to-jade diagonal wash with a soft top-left highlight."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    grad = Image.new('RGBA', (size, size))
    px = grad.load()
    for y in range(size):
        for x in range(size):
            t = (x / size * 0.45 + y / size * 0.55)
            px[x, y] = (
                int(FOREST[0] + (JADE[0] - FOREST[0]) * t),
                int(FOREST[1] + (JADE[1] - FOREST[1]) * t),
                int(FOREST[2] + (JADE[2] - FOREST[2]) * t),
                255,
            )
    if radius_frac <= 0:
        return grad
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * radius_frac), fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def full_icon(size, radius_frac=0.22):
    big = size * SS
    img = background(big, radius_frac)
    draw_glyph(img, big, inset=0.66)
    return img.resize((size, size), Image.LANCZOS)


def adaptive_foreground(size=432):
    """Transparent; glyph inside the 66% safe zone Android masks to."""
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    draw_glyph(img, big, inset=0.46)
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)

    android = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for name, px in android.items():
        full_icon(px).save(os.path.join(OUT, f'android_{name}_ic_launcher.png'))
        adaptive_foreground(px * 3).save(
            os.path.join(OUT, f'android_{name}_ic_launcher_foreground.png'))

    # Play Store listing
    full_icon(512, radius_frac=0).save(os.path.join(OUT, 'play_store_512.png'))

    # iOS: no rounded corners and no alpha — the OS masks it, and an icon with
    # an alpha channel is rejected at upload.
    ios = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
    for px in ios:
        full_icon(px, radius_frac=0).convert('RGB').save(
            os.path.join(OUT, f'ios_{px}.png'))

    print(f'wrote {len(os.listdir(OUT))} files to {OUT}')


if __name__ == '__main__':
    main()
