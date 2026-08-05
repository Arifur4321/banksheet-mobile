#!/usr/bin/env python3
"""Vertical height budget for the welcome screen.

    python3 tool/welcome_budget.py

WHY THIS EXISTS
---------------
`lib/features/auth/presentation/welcome_screen.dart` carries a hard
requirement: everything is reachable without scrolling, on every phone, at the
default text size. That requirement is enforced properly by
`test/welcome_layout_test.dart`, which pumps the real widget — but a widget test
needs the Flutter toolchain, and this repository is regularly worked on where
that is not available.

So this script computes the same column height from the same constants, and
answers the one question that matters before you change a number in that
`LayoutBuilder`: does it still fit on a 320x548 screen.

It is a *model*, not a renderer. Line counts are estimated from a conservative
character-advance figure for Outfit and rounded up, so it errs towards saying
something is too tall. Treat a negative slack as a definite problem and a slack
under ~10pt as a warning. `flutter test test/welcome_layout_test.dart` remains
the authority.

If you change the layout, change the mirrored constants at the top of `budget()`
in the same commit — a model that has drifted from the code is worse than no
model, because it is believed.
"""

import math
import sys

# --- mirrors lib/core/theme/tokens.dart ------------------------------------
PAGE = 20
SM, MD, LG, XXL = 8, 12, 16, 24

# --- mirrors lib/core/i18n/strings.dart ------------------------------------
TITLE = 'Turn any bank statement into clean data'
BODY = ('Upload a PDF, get reconciled transactions you can review and export. '
        'Plus PDF tools, barcodes and e-signature.')
FREE = 'Reading is always free · 3 of 3 free scans left'

# Outfit's average advance as a fraction of the em, measured across the strings
# above. Deliberately on the wide side.
EM_ADVANCE = 0.52

# Post-safe-area sizes. That is what the LayoutBuilder receives, and using the
# raw screen size is the single easiest way to get this wrong by 90 points.
DEVICES = [
    ('iPhone SE 1st gen', 320, 548),
    ('low-end Android', 360, 616),
    ('iPhone 12 mini', 360, 650),
    ('Galaxy A / mid Android', 384, 720),
    ('iPhone 15', 393, 759),
    ('Pixel 7', 412, 800),
    ('iPhone 15 Pro Max', 430, 830),
    ('Fold, outer screen', 344, 760),
    ('small tablet', 600, 900),
]


def lines(text, font_px, width_px):
    return max(1, math.ceil(len(text) * font_px * EM_ADVANCE / width_px))


def budget(h, w):
    """Total intrinsic height of the welcome screen's column, in logical px."""
    # --- mirrors the bands in welcome_screen.dart --------------------------
    tiny = h < 600
    short = h < 720
    roomy = h >= 780

    gap_sm = 6 if tiny else SM
    gap_md = 8 if tiny else MD
    gap_lg = 12 if tiny else LG
    gap_xl = 16 if tiny else (20 if short else XXL)

    scene = min(max(h * (0.15 if tiny else (0.17 if short else 0.20)), 84), 232)
    title_px = 25 if tiny else (28 if short else 31)
    body_px = 13.5 if tiny else 15
    body_max = 2 if tiny else 3

    content_w = w - 2 * PAGE
    total = gap_md + gap_lg                       # column padding
    total += 34                                   # BrandMark
    total += gap_sm + scene + gap_lg
    total += lines(TITLE, title_px, content_w) * title_px * 1.13
    total += gap_sm
    total += min(lines(BODY, body_px, content_w), body_max) * body_px * 1.5
    total += gap_xl

    # PrimaryActionTile: padding*2 + icon + gap + label + 2 + caption
    pad, icon, gap = (LG, 26, MD) if roomy else (MD, 22, SM)
    total += pad * 2 + icon + gap + 15 * 1.5 + 2 + 12 * 1.4

    total += gap_sm + min(lines(FREE, 12, content_w), 2) * 12 * 1.4

    if roomy:                                     # two _ValueRow entries
        total += gap_lg + 30 + gap_sm + 30

    total += gap_lg + 52 + gap_sm + 52            # Spacer collapses; 2 buttons
    return total


def main():
    worst = None
    print(f'{"device":24} {"size":>10} {"content":>9} {"slack":>8}')
    print('-' * 56)
    for name, w, h in DEVICES:
        used = budget(h, w)
        slack = h - used
        worst = slack if worst is None else min(worst, slack)
        flag = 'OK' if slack >= 10 else ('TIGHT' if slack >= 0 else 'OVERFLOW')
        print(f'{name:24} {f"{w}x{h}":>10} {used:9.1f} {slack:+8.1f}  {flag}')

    print('-' * 56)
    print(f'worst slack: {worst:+.1f}pt')
    if worst < 0:
        print('\nThe welcome screen does not fit. Shrink the scene fractions, '
              'drop a band, or compact the action tiles.')
        return 1
    if worst < 10:
        print('\nUnder 10pt of slack. The model rounds line counts up, but this '
              'is close enough to verify on a device.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
