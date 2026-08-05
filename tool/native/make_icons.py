#!/usr/bin/env python3
"""Generate every app icon and launch-screen asset BankSheet Pro needs.

Why a script and not a folder of PNGs someone exported once: an icon that only
exists as binary output cannot be adjusted without the original, and "who has
the Figma file" is a question no handover should ever have to answer. Run this
and every density is regenerated, consistently, from the brand tokens below.

    python3 tool/native/make_icons.py

Writes into tool/native/icons/, which IS tracked. tool/native/apply.py then
installs them into the generated android/ and ios/ trees.

DESIGN, AND WHY
---------------
The mark is a **PDF page**, not a spreadsheet. That is a deliberate change: the
app's first promise on the store listing and on the welcome screen is "open and
make PDFs", and a launcher icon that shows a data grid is describing the second
feature, not the first. A stranger scrolling their home screen has about a third
of a second and 48 logical pixels to decide what this app is.

So the silhouette carries the meaning and nothing else has to:

  * a white portrait page with a **folded top-right corner** — the universal
    document silhouette, readable at 48px where any wordmark is mud;
  * three ruled lines, so the page reads as a page and not as a blank card;
  * a **PDF chip** across the foot of the page in jade-bright, with the letters
    P, D and F knocked out of it. At xxxhdpi the letters are legible; at mdpi
    the chip degrades gracefully into a solid brand-coloured bar, which is
    exactly what every well-drawn small icon does.

The letters are drawn from primitives — stems, bars and knockouts — rather than
rendered from a font. That is not stubbornness: `make_icons.py` has to produce
the same output on the machine that regenerates it, and "which fonts are
installed" is the one thing that differs between a Linux CI box and the Windows
laptop this project is actually built on.

Background stays the forest-to-jade wash from `lib/core/theme/tokens.dart`, so
the icon, the native launch screen and the app's first frame are one colour.

Everything is drawn at 4x and downsampled, because PIL's polygon edges are
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
MINT        = (223, 245, 233)

SS = 4  # supersample factor


def _rr(d, box, r, fill):
    """A rounded rectangle that survives being drawn very small.

    Pillow's `rounded_rectangle` draws the straight middle of the shape as an
    inner rectangle inset by `radius + 1` on each side. When the box is only a
    few pixels tall — which happens on the 20px iOS icon, where the whole "PDF"
    chip is about five pixels — that inner rectangle comes out inverted and
    Pillow raises `ValueError: y1 must be greater than or equal to y0`.

    Clamping the radius to half the box is not enough, because the `+ 1` is
    still there. So the radius is clamped to (side - 2) / 2, and anything too
    small to round is drawn square: at that size a corner radius is sub-pixel
    and invisible anyway.

    Degenerate boxes are skipped rather than raising. Callers derive geometry
    from a glyph size that can legitimately round to nothing at 20px, and a
    missing three-pixel detail is not a reason to fail the whole icon set.
    """
    x0, y0, x1, y1 = box
    if x1 <= x0 or y1 <= y0:
        return

    w, h = x1 - x0, y1 - y0
    r = max(0.0, min(r, (w - 2) / 2, (h - 2) / 2))

    if r < 1 or w < 4 or h < 4:
        d.rectangle((x0, y0, x1, y1), fill=fill)
        return

    d.rounded_rectangle((x0, y0, x1, y1), radius=r, fill=fill)


def _rect(d, box, fill):
    """`rectangle` with the same degenerate-box guard as [_rr]."""
    x0, y0, x1, y1 = box
    if x1 <= x0 or y1 <= y0:
        return
    d.rectangle((x0, y0, x1, y1), fill=fill)


# --------------------------------------------------------------- lettering ---
#
# Each glyph is drawn inside a box of (w, h) at (x, y) with stroke thickness t.
# Counters (the holes in P and D) are knocked out with `bg` rather than left
# transparent, because these letters sit on a solid chip, and a transparent
# counter would show the white page through and read as a printing error.

def _letter_p(d, x, y, w, h, t, fg, bg):
    bowl_h = h * 0.58
    _rr(d, (x, y, x + w, y + bowl_h), min(w, bowl_h) * 0.44, fg)
    _rr(d, (x + t, y + t, x + w - t, y + bowl_h - t),
        min(w - 2 * t, bowl_h - 2 * t) * 0.40, bg)
    # The stem is drawn last so it closes the left side of the counter.
    _rect(d, (x, y, x + t, y + h), fg)


def _letter_d(d, x, y, w, h, t, fg, bg):
    _rr(d, (x, y, x + w, y + h), min(w, h) * 0.42, fg)
    _rr(d, (x + t, y + t, x + w - t, y + h - t),
        min(w - 2 * t, h - 2 * t) * 0.38, bg)
    _rect(d, (x, y, x + t, y + h), fg)


def _letter_f(d, x, y, w, h, t, fg, bg):
    _rect(d, (x, y, x + t, y + h), fg)                       # stem
    _rect(d, (x, y, x + w, y + t), fg)                       # top arm
    _rect(d, (x, y + h * 0.42, x + w * 0.80, y + h * 0.42 + t), fg)  # mid arm


# Below this letter height, in pixels of the supersampled canvas, the wordmark
# is drawn as nothing and the chip stays a solid bar. On the 20pt iOS icon the
# letters would be about one pixel tall — illegible at best, and mud once the
# whole thing is downsampled. Every well-drawn small icon degrades this way.
MIN_WORD_HEIGHT = 10


def _draw_pdf_word(d, x, y, w, h, fg, bg):
    """P D F laid out across a box of (w, h), optically spaced."""
    if h < MIN_WORD_HEIGHT or w < MIN_WORD_HEIGHT * 2:
        return

    gap = w * 0.085
    lw = (w - gap * 2) / 3
    t = max(1.0, h * 0.20)

    # Each letter needs room for two strokes plus a counter between them.
    if lw <= t * 2.2:
        return

    _letter_p(d, x, y, lw, h, t, fg, bg)
    _letter_d(d, x + lw + gap, y, lw, h, t, fg, bg)
    _letter_f(d, x + (lw + gap) * 2, y, lw, h, t, fg, bg)


# -------------------------------------------------------------- the glyph ---

def draw_glyph(img, size, inset):
    """The folded PDF page, centred, occupying `inset` fraction of `size`."""
    d = ImageDraw.Draw(img)
    g = size * inset
    ox = (size - g) / 2
    oy = (size - g) / 2

    # --- the page, with the top-right corner folded over -------------------
    pw, ph = g * 0.76, g * 0.94
    px, py = ox + (g - pw) / 2, oy + (g - ph) / 2
    fold = pw * 0.30                      # side length of the folded corner
    r = g * 0.06                          # page corner radius

    _rr(d, (px, py, px + pw, py + ph), r, PAPER_WHITE)

    # Knock the corner out with a transparent triangle, then lay the flap back
    # in a shade down. Drawn in that order so the diagonal is one clean edge
    # rather than two that nearly meet.
    d.polygon(
        [(px + pw - fold, py), (px + pw, py), (px + pw, py + fold)],
        fill=(0, 0, 0, 0),
    )
    d.polygon(
        [(px + pw - fold, py), (px + pw, py + fold), (px + pw - fold, py + fold)],
        fill=SAND,
    )

    pad = pw * 0.14
    lx0, lx1 = px + pad, px + pw - pad

    # --- ruled lines -------------------------------------------------------
    ly = py + ph * 0.30
    for frac in (1.0, 0.86, 0.62):
        lh = ph * 0.042
        _rr(d, (lx0, ly, lx0 + (lx1 - lx0) * frac, ly + lh), lh / 2, SAND)
        ly += ph * 0.098

    # --- PDF chip ----------------------------------------------------------
    ch = ph * 0.215
    cy = py + ph - ch - ph * 0.115
    _rr(d, (lx0, cy, lx1, cy + ch), ch * 0.30, JADE_BRIGHT)

    word_h = ch * 0.50
    word_w = (lx1 - lx0) * 0.60
    _draw_pdf_word(
        d,
        lx0 + ((lx1 - lx0) - word_w) / 2,
        cy + (ch - word_h) / 2,
        word_w,
        word_h,
        FOREST,
        JADE_BRIGHT,
    )


def background(size, radius_frac):
    """Forest-to-jade diagonal wash."""
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
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * radius_frac), fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def full_icon(size, radius_frac=0.22):
    big = size * SS
    img = background(big, radius_frac)
    draw_glyph(img, big, inset=0.64)
    return img.resize((size, size), Image.LANCZOS)


def adaptive_foreground(size=432):
    """Transparent; glyph inside the 66% safe zone Android masks to."""
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    draw_glyph(img, big, inset=0.44)
    return img.resize((size, size), Image.LANCZOS)


def splash_glyph(size):
    """Glyph only, on transparency — for the native launch screen.

    The launch window already paints the brand colour, so baking a background
    in here would put a slightly-different-green square on top of it, which is
    exactly the seam a launch screen exists to avoid.
    """
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    draw_glyph(img, big, inset=0.86)
    return img.resize((size, size), Image.LANCZOS)


def splash_icon_v31(size=768):
    """Android 12+ `windowSplashScreenAnimatedIcon`.

    The platform masks this to a circle and scales it down, and only the inner
    two thirds survive — so the glyph is drawn small on a large canvas rather
    than filling it, which is the single most common way this asset is got
    wrong.
    """
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    draw_glyph(img, big, inset=0.52)
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)

    android = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for name, px in android.items():
        full_icon(px).save(os.path.join(OUT, f'android_{name}_ic_launcher.png'))
        adaptive_foreground(px * 3).save(
            os.path.join(OUT, f'android_{name}_ic_launcher_foreground.png'))

    # Launch screen. 96dp on mdpi, scaled per density — large enough to be the
    # subject of the screen, small enough that it never crops on a short phone.
    for name, factor in (('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2),
                         ('xxhdpi', 3), ('xxxhdpi', 4)):
        splash_glyph(int(96 * factor)).save(
            os.path.join(OUT, f'android_{name}_splash_logo.png'))
    splash_icon_v31().save(os.path.join(OUT, 'android_splash_icon_v31.png'))

    # Play Store listing
    full_icon(512, radius_frac=0).save(os.path.join(OUT, 'play_store_512.png'))

    # iOS: no rounded corners and no alpha — the OS masks it, and an icon with
    # an alpha channel is rejected at upload.
    ios = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
    for px in ios:
        full_icon(px, radius_frac=0).convert('RGB').save(
            os.path.join(OUT, f'ios_{px}.png'))

    # The iOS launch image keeps its alpha — it is composited onto the brand
    # colour by the storyboard, not uploaded as an icon.
    for scale, px in ((1, 120), (2, 240), (3, 360)):
        splash_glyph(px).save(os.path.join(OUT, f'ios_launch_{scale}x.png'))

    print(f'wrote {len(os.listdir(OUT))} files to {OUT}')


if __name__ == '__main__':
    main()
