"""The DMG window's background, at 1x and 2x (640 × 360 pt).

Finder draws the icon labels in black in light mode and in white in dark
mode, over this picture: the band they sit on has a relative luminance near
0.18, where both read at about 4.5:1. Keep it there.

Run with Pillow: python3 make_background.py (writes background.png and
background@2x.png next to this file).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
FONT = HERE.parents[2] / 'website/assets/fonts/trueno-semibold.otf'
WIDTH, HEIGHT = 640, 360
APP, APPLICATIONS, ICON_Y = 160, 480, 180   # icon centres, in points
TOP, BOTTOM = (95, 166, 157), (60, 114, 110)


def render(scale):
    w, h = WIDTH * scale, HEIGHT * scale
    image = Image.new('RGB', (w, h))
    pixels = image.load()
    for y in range(h):
        t = y / (h - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        for x in range(w):
            pixels[x, y] = row

    # A soft mint halo behind the app, a fainter one behind Applications.
    glow = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(glow)
    for cx, strength in ((APP, 70), (APPLICATIONS, 30)):
        r = 120 * scale
        draw.ellipse((cx * scale - r, ICON_Y * scale - r, cx * scale + r, ICON_Y * scale + r), fill=strength)
    glow = glow.filter(ImageFilter.GaussianBlur(48 * scale))
    image = Image.composite(Image.new('RGB', (w, h), (214, 250, 235)), image, glow)

    # The arrow from the app to Applications.
    draw = ImageDraw.Draw(image)
    ink = (240, 252, 247)
    x0, x1, y = 252 * scale, 388 * scale, ICON_Y * scale
    draw.line((x0, y, x1, y), fill=ink, width=2 * scale)
    head = 9 * scale
    draw.line((x1 - head, y - head, x1, y), fill=ink, width=2 * scale)
    draw.line((x1 - head, y + head, x1, y), fill=ink, width=2 * scale)

    font = ImageFont.truetype(str(FONT), 17 * scale)
    text = 'Drag skil.li to Applications'
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((w - (right - left)) / 2, 50 * scale), text, font=font, fill=ink)
    return image


if __name__ == '__main__':
    render(1).save(HERE / 'background.png', optimize=True)
    render(2).save(HERE / 'background@2x.png', optimize=True)
