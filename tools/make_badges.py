# Значки на предметах в сумках: молоток аукциониста (выгоднее на аукцион) и мешочек с монетой (выгоднее торговцу).
# Рисуются крупно (512) и сжимаются до 64 - ровные края без лесенок; чёрная обводка, чтобы значок читался на любом фоне.
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math, sys
S = 512
def poly_rot(cx, cy, w, h, ang, r=0):
    pts = [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + x*c - y*s, cy + x*s + y*c) for x, y in pts]
def shade(img, mask, top, bottom):
    # вертикальный градиент внутри маски
    g = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(g)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    img.paste(g, (0, 0), mask)
def layer(draw_fn):
    m = Image.new("L", (S, S), 0); draw_fn(ImageDraw.Draw(m)); return m
def finish(img, out, outline=34):
    a = img.split()[3]
    big = a.filter(ImageFilter.MaxFilter(outline * 2 + 1 if outline * 2 + 1 <= 99 else 99))
    big = big.filter(ImageFilter.GaussianBlur(4))
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0)); base.putalpha(big)
    res = Image.alpha_composite(base, img)
    res = res.resize((64, 64), Image.LANCZOS)
    # убрать почти прозрачный мусор по краям
    px = res.load()
    for y in range(64):
        for x in range(64):
            r, g, b, al = px[x, y]
            if al < 10: px[x, y] = (0, 0, 0, 0)
    res.save(out)

def rect(cx, cy, vx, vy, length, width):
    # прямоугольник: центр, ось длины (vx, vy), длина вдоль оси, ширина поперёк
    n = math.hypot(vx, vy); vx, vy = vx / n, vy / n; px, py = -vy, vx
    l, w = length / 2, width / 2
    return [(cx + vx*l + px*w, cy + vy*l + py*w), (cx + vx*l - px*w, cy + vy*l - py*w),
            (cx - vx*l - px*w, cy - vy*l - py*w), (cx - vx*l + px*w, cy - vy*l + py*w)]

def gavel(out):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # рукоять вниз-вправо, головка поперёк неё вверху слева
    hm = layer(lambda d: d.polygon(rect(320, 320, 1, 1, 300, 50), fill=255))
    shade(img, hm, (196, 132, 70), (110, 64, 30))
    hc = (196, 196)
    head = layer(lambda d: d.polygon(rect(hc[0], hc[1], 1, -1, 270, 140), fill=255))
    shade(img, head, (176, 110, 56), (96, 54, 22))
    k = 0.7071
    for sgn in (-1, 1):
        cx, cy = hc[0] + sgn * 96 * k, hc[1] - sgn * 96 * k
        ring = layer(lambda d, cx=cx, cy=cy: d.polygon(rect(cx, cy, 1, -1, 30, 156), fill=255))
        shade(img, ring, (255, 226, 110), (196, 136, 26))
    # торцы головки чуть светлее
    hl = layer(lambda d: d.polygon(rect(hc[0] - 34 * k, hc[1] - 34 * k, 1, -1, 150, 24), fill=140))
    img.paste((255, 228, 176, 255), (0, 0), hl.filter(ImageFilter.GaussianBlur(6)))
    finish(img, out)

def sack(out):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body = layer(lambda d: (d.ellipse((96, 190, 400, 470), fill=255), d.polygon([(190, 200), (306, 200), (350, 260), (146, 260)], fill=255)))
    shade(img, body, (214, 172, 112), (140, 96, 52))
    neck = layer(lambda d: d.polygon([(200, 120), (296, 120), (276, 190), (220, 190)], fill=255))
    shade(img, neck, (214, 172, 112), (170, 128, 74))
    top = layer(lambda d: (d.ellipse((150, 70, 250, 140), fill=255), d.ellipse((246, 70, 346, 140), fill=255)))
    shade(img, top, (226, 186, 124), (176, 132, 76))
    tie = layer(lambda d: d.rounded_rectangle((186, 176, 310, 210), 14, fill=255))
    shade(img, tie, (150, 40, 30), (96, 20, 16))
    # монета спереди справа
    coin = layer(lambda d: d.ellipse((268, 286, 456, 474), fill=255))
    shade(img, coin, (255, 230, 120), (204, 140, 20))
    rim = layer(lambda d: d.ellipse((296, 314, 428, 446), outline=255, width=12))
    img.paste((170, 110, 10, 255), (0, 0), rim)
    hl = layer(lambda d: d.ellipse((300, 304, 352, 340), fill=170))
    img.paste((255, 250, 210, 255), (0, 0), hl.filter(ImageFilter.GaussianBlur(8)))
    finish(img, out)

d = sys.argv[1]
gavel(d + "/badge-ah.tga"); sack(d + "/badge-vendor.tga")
