"""Frames the raw app screens (screenshots/raw, made by
screenshots/capture_test.dart) into store images under store/.

Usage: python3 tool/make_store_images.py   (requires Pillow and Inter or Roboto)
"""
import glob
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'screenshots', 'raw')
OUT = os.path.join(ROOT, 'store')

TOP, BOTTOM = (57, 73, 171), (26, 35, 126)  # brand indigo gradient

# (raw screen, headline, subline), in store order.
SLIDES = [
    ('2_remote', 'Your TV remote,\nalways in your pocket', 'D-pad, volume, power and what’s playing'),
    ('3_keyboard', 'Type with your\nphone keyboard', 'Search in seconds instead of arrow-key typing'),
    ('1_tvs', 'Every TV in\nyour home', 'Found automatically on your Wi-Fi'),
    ('4_apps', 'Open apps\nwith one tap', 'Your TV’s apps, right on your phone'),
    ('6_watchlist', 'Save shows for\nmovie night', 'Share a link, then open it on the TV'),
    ('7_theme', 'Make it\nyour own', 'Themes, dark mode and custom remotes'),
    ('5_touchpad', 'A touchpad for\nthe TV browser', 'Point, click and scroll like a laptop'),
]

SIZES = {
    'app_store/iphone_6.9': (1320, 2868),
    'app_store/iphone_6.5': (1284, 2778),
    'play/phone': (1080, 1920),
}


def font(weight, size):
    for path in (
        f'/usr/share/fonts/opentype/inter/Inter-{weight}.otf',
        os.path.expanduser(f'~/Library/Fonts/Inter-{weight}.otf'),
        f'/opt/sdk/flutter/bin/cache/artifacts/material_fonts/Roboto-{"Bold" if weight != "Regular" else "Regular"}.ttf',
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def gradient(w, h):
    img = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    # soft light in the top corner
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse([-w * 0.4, -h * 0.25, w * 0.9, h * 0.35], fill=60)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.15))
    return Image.composite(Image.new('RGB', (w, h), (120, 140, 255)), img, glow)


def phone(screen, width):
    """The screen in a rounded dark bezel, with a drop shadow (RGBA)."""
    bezel = int(width * 0.035)
    inner_w = width - 2 * bezel
    inner_h = round(screen.height * inner_w / screen.width)
    h = inner_h + 2 * bezel
    radius = int(width * 0.13)
    pad = int(width * 0.08)
    out = Image.new('RGBA', (width + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new('RGBA', out.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad + width * 0.03, pad + width, pad + h + width * 0.03], radius, fill=(5, 8, 40, 150))
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(width * 0.035)))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([pad, pad, pad + width, pad + h], radius, fill=(18, 18, 24, 255))
    scr = screen.convert('RGBA').resize((inner_w, inner_h), Image.LANCZOS)
    mask = Image.new('L', scr.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner_w, inner_h], radius - bezel, fill=255)
    out.paste(scr, (pad + bezel, pad + bezel), mask)
    return out, pad


def slide(raw, headline, subline, w, h):
    img = gradient(w, h).convert('RGBA')
    d = ImageDraw.Draw(img)
    unit = w / 1320
    head = font('ExtraBold', int(104 * unit * (h / w) / 2.17))
    sub = font('Medium', int(50 * unit * (h / w) / 2.17))
    y = int(h * 0.055)
    for line in headline.split('\n'):
        tw = d.textlength(line, font=head)
        d.text(((w - tw) / 2, y), line, font=head, fill='white')
        y += int(head.size * 1.18)
    y += int(head.size * 0.25)
    tw = d.textlength(subline, font=sub)
    if tw > w * 0.9:  # shrink long sublines to fit
        sub = font('Medium', int(sub.size * w * 0.9 / tw))
        tw = d.textlength(subline, font=sub)
    d.text(((w - tw) / 2, y), subline, font=sub, fill=(214, 220, 255))
    top = y + int(sub.size * 2.0)
    # The phone bleeds off the bottom edge.
    pw = int(w * 0.80)
    framed, pad = phone(raw, pw)
    img.alpha_composite(framed, ((w - framed.width) // 2, top - pad))
    return img.convert('RGB')


def feature_graphic():
    w, h = 1024, 500
    img = gradient(w, h).convert('RGBA')
    d = ImageDraw.Draw(img)
    icon = Image.open(os.path.join(ROOT, 'assets/icon/ios_1024.png')).convert('RGBA').resize((150, 150), Image.LANCZOS)
    mask = Image.new('L', icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 150, 150], 34, fill=255)
    img.paste(icon, (60, 90), mask)
    d.text((60, 270), 'OpenRemote', font=font('ExtraBold', 64), fill='white')
    d.text((62, 345), 'Free · No ads · No accounts', font=font('Medium', 28), fill=(214, 220, 255))
    raw = Image.open(os.path.join(RAW, '2_remote.png'))
    framed, pad = phone(raw, 300)
    img.alpha_composite(framed, (w - framed.width - 20, 40 - pad))
    return img.convert('RGB')


def main():
    for folder, (w, h) in SIZES.items():
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
        for old in glob.glob(os.path.join(OUT, folder, '*.png')):
            os.remove(old)
        for i, (name, headline, subline) in enumerate(SLIDES, 1):
            raw = Image.open(os.path.join(RAW, f'{name}.png'))
            slide(raw, headline, subline, w, h).save(
                os.path.join(OUT, folder, f'{i:02d}_{name.split("_", 1)[1]}.png'), optimize=True)
    os.makedirs(os.path.join(OUT, 'play'), exist_ok=True)
    feature_graphic().save(os.path.join(OUT, 'play', 'feature_graphic.png'), optimize=True)
    Image.open(os.path.join(ROOT, 'assets/icon/ios_1024.png')).convert('RGB').resize(
        (512, 512), Image.LANCZOS).save(os.path.join(OUT, 'play', 'icon_512.png'), optimize=True)


if __name__ == '__main__':
    main()
