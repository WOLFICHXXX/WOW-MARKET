"""Текстуры оформления «Тортуга»: доски, латунные уголки, канат, ели.
Всё рисуется процедурно (свои картинки, без чужих ассетов).
Запуск: python3 tools/make_wood.py  ->  addon/WolfichMarket/media/win/*.tga и превью в tools/wood_preview/*.png
"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), '..', 'addon', 'WolfichMarket', 'media', 'win')
PREV = os.path.join(os.path.dirname(__file__), 'wood_preview')
os.makedirs(PREV, exist_ok=True)
rnd = random.Random(7)

# палитра «Тортуга»: тёмное корабельное дерево, латунь, пергамент, морская волна, хвоя
WOOD_DARK = (34, 21, 13)
WOOD_MID = (62, 39, 23)
WOOD_LIGHT = (92, 60, 36)
BRASS = (201, 154, 62)
BRASS_LIGHT = (240, 200, 115)
BRASS_DARK = (110, 78, 30)
PINE_DARK = (18, 38, 27)
PINE = (31, 63, 44)
PINE_LIGHT = (52, 92, 62)


def save(img, name):
    img.save(os.path.join(OUT, name + '.tga'))
    img.save(os.path.join(PREV, name + '.png'))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def periodic_noise(w, h, seed, octaves):
    """гладкий шум, повторяющийся по ширине (сумма синусов со случайными фазами)"""
    r = random.Random(seed)
    waves = [(r.randint(1, 6) * (2 ** o), r.random() * 6.28, r.uniform(0.6, 1.0) / (o + 1), r.uniform(0.5, 3)) for o in range(octaves) for _ in range(3)]
    def f(x, y):
        v = 0
        for k, ph, amp, fy in waves:
            v += amp * math.sin(2 * math.pi * k * x / w + ph) * (1 + 0.15 * math.sin(fy * y * 0.08 + ph))
        return v
    return f


def planks(w=512, h=512, plank_h=64, base=WOOD_MID, dark=WOOD_DARK, light=WOOD_LIGHT, nails=True, seed=1):
    img = Image.new('RGB', (w, h))
    px = img.load()
    r = random.Random(seed)
    rows = h // plank_h
    for row in range(rows):
        tone = r.uniform(-0.12, 0.12)
        grain = periodic_noise(w, plank_h, seed * 100 + row, 4)
        knot_x, knot_y = r.randint(0, w - 1), r.randint(12, plank_h - 12)
        for y in range(plank_h):
            for x in range(w):
                g = grain(x, y)
                # продольные волокна: тонкие полосы, искривлённые шумом
                fib = math.sin((y + g * 2.2) * 0.9) * 0.5 + 0.5
                fine = math.sin((y + g * 1.2) * 3.1 + x * 0.004) * 0.5 + 0.5
                t = 0.42 + 0.10 * g + 0.20 * fib + 0.08 * fine + tone
                # сучок
                dx = min(abs(x - knot_x), w - abs(x - knot_x)); dy = y - knot_y
                d = math.hypot(dx * 0.6, dy * 1.6)
                if d < 16: t -= (16 - d) / 16 * 0.35 * (0.6 + 0.4 * math.sin(d * 1.8))
                t = max(0, min(1, t))
                c = lerp(dark, light, t) if t > 0.5 else lerp(dark, base, t * 2)
                # тень у стыков досок
                edge = min(y, plank_h - 1 - y)
                if edge < 3: c = lerp((14, 8, 4), c, edge / 3)
                px[x, row * plank_h + y] = c
        if nails:
            d = ImageDraw.Draw(img)
            for nx in (18, w // 2 + 18):
                for ny in (10, plank_h - 12):
                    cx, cy = nx, row * plank_h + ny
                    d.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), fill=(28, 22, 16))
                    d.ellipse((cx - 2, cy - 2, cx + 1, cy + 1), fill=(120, 104, 82))
    return img


def brass_corner(s=64):
    """латунная накладка на угол: уголок с заклёпками и гравировкой"""
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = [(0, 0), (s, 0), (s, 14), (24, 14), (14, 24), (14, s), (0, s)]
    d.polygon(pts, fill=BRASS + (255,), outline=BRASS_DARK + (255,))
    d.line([(3, 3), (s - 3, 3)], fill=BRASS_LIGHT + (255,), width=2)
    d.line([(3, 3), (3, s - 3)], fill=BRASS_LIGHT + (255,), width=2)
    d.line([(12, 12), (s - 4, 12)], fill=BRASS_DARK + (200,), width=1)
    d.line([(12, 12), (12, s - 4)], fill=BRASS_DARK + (200,), width=1)
    for (x, y) in [(7, 7), (s - 9, 7), (7, s - 9)]:
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=BRASS_DARK + (255,))
        d.ellipse((x - 2, y - 2, x + 1, y + 1), fill=BRASS_LIGHT + (255,))
    return img.filter(ImageFilter.SMOOTH)


def rope(w=64, h=8, vertical=False):
    """канат: витые пряди, повторяется по длине"""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    px = img.load()
    for x in range(w):
        for y in range(h):
            # витки по диагонали, 4 на длину текстуры
            ph = (x / w * 4 + y / h * 0.9) % 1.0
            t = 0.5 + 0.5 * math.cos(ph * 2 * math.pi)
            edge = 1 - abs((y + 0.5) / h * 2 - 1)
            a = int(255 * min(1, edge * 2.2))
            c = lerp((96, 70, 40), (196, 160, 108), t * (0.4 + 0.6 * edge))
            px[x, y] = c + (a,)
    if vertical: img = img.rotate(90, expand=True)
    return img


def pine(w=128, h=256, seed=3, col=PINE, dark=PINE_DARK, light=PINE_LIGHT):
    """ель: ярусы веток-треугольников, ствол, мягкая тень слева"""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = random.Random(seed)
    cx = w // 2
    d.rectangle((cx - 4, h - 34, cx + 4, h - 2), fill=(52, 34, 20, 255))
    tiers = 8
    top = 6
    for i in range(tiers):
        t = i / (tiers - 1)
        y0 = top + int(t * (h - 70))
        y1 = y0 + int(h * 0.24)
        half = int(12 + t * (w * 0.49 - 12))
        jag = []
        n = 7
        for k in range(n + 1):
            x = cx - half + k * (2 * half) / n
            jy = y1 + (r.randint(-4, 6) if 0 < k < n else 0)
            jag.append((x, jy if k % 2 == 0 else jy - r.randint(6, 12)))
        poly = [(cx, y0)] + jag[::-1][:0] + [(cx - half, y1)] + jag + [(cx + half, y1)]
        d.polygon([(cx, y0), (cx - half, y1)] + jag + [(cx + half, y1)], fill=lerp(dark, col, 0.4 + 0.6 * t) + (255,))
        # светлая сторона справа
        d.polygon([(cx, y0), (cx + 2, y1 - 6), (cx + half, y1)], fill=lerp(col, light, 0.5) + (255,))
    return img.filter(ImageFilter.SMOOTH)


def main():
    save(planks(seed=1), 'wood')                                     # фон окон: тёмные доски с гвоздями
    save(planks(256, 512, 64, base=(46, 29, 17), dark=(22, 13, 8), light=(70, 45, 27), seed=5), 'wood-dark')  # полоса разделов
    save(brass_corner(), 'brass-corner')
    save(rope(), 'rope-h')
    save(rope(vertical=True), 'rope-v')
    save(pine(seed=3), 'pine')
    save(pine(96, 200, seed=9, col=(26, 54, 38), dark=(14, 30, 21)), 'pine2')
    print('ok')


if __name__ == '__main__':
    main()
