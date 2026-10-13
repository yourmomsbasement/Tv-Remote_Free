# Regenerates the app icon artwork in assets/icon/ (requires Pillow).
# Usage: python3 tool/make_icon.py ios|android|foreground
from PIL import Image, ImageDraw, ImageFilter
import sys
S = 1024

def gradient(size, top, bottom):
    img = Image.new('RGB', (size, size), top)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c)
    return img

def remote(size, scale=1.0):
    """White remote silhouette with D-pad, centred, on transparent."""
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = int(size * 0.36 * scale), int(size * 0.70 * scale)
    x0, y0 = (size - w) // 2, (size - h) // 2
    r = int(w * 0.38)
    # shadow
    sh = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([x0, y0 + size * 0.02, x0 + w, y0 + h + size * 0.02], r, fill=(0, 0, 40, 90))
    layer = Image.alpha_composite(layer, sh.filter(ImageFilter.GaussianBlur(size * 0.02)))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], r, fill=(255, 255, 255, 255))
    cx = size // 2
    indigo = (61, 90, 254, 255)
    # power dot
    pr = int(w * 0.09)
    d.ellipse([cx - pr, y0 + int(h * 0.09) - pr, cx + pr, y0 + int(h * 0.09) + pr], fill=(255, 82, 82, 255))
    # D-pad ring
    dr = int(w * 0.36)
    dcy = y0 + int(h * 0.36)
    d.ellipse([cx - dr, dcy - dr, cx + dr, dcy + dr], fill=indigo)
    ir = int(dr * 0.42)
    d.ellipse([cx - ir, dcy - ir, cx + ir, dcy + ir], fill=(255, 255, 255, 255))
    # arrow notches
    n = int(dr * 0.16)
    for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
        px, py = cx + dx * int(dr * 0.72), dcy + dy * int(dr * 0.72)
        d.ellipse([px - n, py - n, px + n, py + n], fill=(255, 255, 255, 255))
    # button grid
    br = int(w * 0.085)
    for row in range(2):
        for col in (-1, 1):
            bx = cx + col * int(w * 0.22)
            by = y0 + int(h * (0.70 + row * 0.13))
            d.ellipse([bx - br, by - br, bx + br, by + br], fill=(200, 208, 255, 255))
    return layer

top, bottom = (83, 109, 254), (40, 53, 147)
mode = sys.argv[1]
if mode == 'ios':          # full-bleed square, no alpha (iOS applies its own mask)
    bg = gradient(S, top, bottom).convert('RGBA')
    Image.alpha_composite(bg, remote(S)).convert('RGB').save('ios_1024.png')
elif mode == 'android':    # legacy launcher icon: rounded square with transparency
    bg = gradient(S, top, bottom).convert('RGBA')
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], int(S * 0.22), fill=255)
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(Image.alpha_composite(bg, remote(S, 0.9)), (0, 0), mask)
    out.save('android_legacy.png')
elif mode == 'foreground': # adaptive icon foreground: art inside the 66% safe zone
    remote(S, 0.62).save('android_foreground.png')
