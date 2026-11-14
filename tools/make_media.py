# Рисует собственные текстуры аддона WolfichMarket (тёмное дерево, бронза, золото, волчья лапа).
# python3 tools/make_media.py  →  addon/WolfichMarket/media/*.tga
import math, random, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = os.path.join(os.path.dirname(__file__), '..', 'addon', 'WolfichMarket', 'media')
os.makedirs(OUT, exist_ok=True)
S = 4  # суперсэмплинг

def save(img, name, size=None):
    if size: img = img.resize(size, Image.LANCZOS)
    img.save(os.path.join(OUT, name + '.tga'), compression=None)

GOLD = [(0, (255, 236, 170)), (0.45, (233, 196, 106)), (1, (150, 104, 38))]
BRONZE = [(0, (214, 160, 92)), (0.5, (150, 98, 48)), (1, (82, 50, 22))]

def grad(w, h, stops, vertical=True):
    img = Image.new('RGBA', (w, h))
    px = img.load()
    n = h if vertical else w
    for i in range(n):
        t = i / max(1, n - 1)
        for k in range(len(stops) - 1):
            a, ca = stops[k]; b, cb = stops[k + 1]
            if a <= t <= b:
                u = (t - a) / (b - a or 1)
                c = tuple(int(ca[j] + (cb[j] - ca[j]) * u) for j in range(3))
                break
        for j in range(w if vertical else h):
            if vertical: px[j, i] = c + (255,)
            else: px[i, j] = c + (255,)
    return img

def masked(fill, mask):
    out = Image.new('RGBA', mask.size, (0, 0, 0, 0))
    out.paste(fill.resize(mask.size), (0, 0), mask)
    return out

# 1) фон: тёмное дерево (тайлится)
random.seed(7)
W = 256
bg = Image.new('RGB', (W, W))
px = bg.load()
for y in range(W):
    for x in range(W):
        v = 0.5 + 0.5 * math.sin((x / W) * 2 * math.pi * 3 + math.sin(y / W * 2 * math.pi * 2) * 1.8 + math.sin(y / W * 2 * math.pi * 7) * 0.25)
        n = random.random() * 0.12
        k = 0.55 + 0.35 * v + n
        px[x, y] = (int(34 * k + 6), int(25 * k + 5), int(17 * k + 5))
bg = bg.filter(ImageFilter.GaussianBlur(0.6)).convert('RGBA')
save(bg, 'bg')

# 2) угол рамки: бронзовая накладка с заклёпкой (верх-лево; остальные — поворотом текстурных координат)
c = 64 * S
m = Image.new('L', (c, c), 0)
d = ImageDraw.Draw(m)
d.polygon([(0, 0), (c, 0), (c, c * 0.28), (c * 0.28, c * 0.28), (c * 0.28, c), (0, c)], fill=255)
d.ellipse([c * 0.06, c * 0.06, c * 0.5, c * 0.5], fill=255)
corner = masked(grad(c, c, BRONZE), m)
d2 = ImageDraw.Draw(corner)
d2.ellipse([c * 0.17, c * 0.17, c * 0.39, c * 0.39], fill=(70, 42, 18, 255))
d2.ellipse([c * 0.2, c * 0.2, c * 0.36, c * 0.36], fill=(240, 205, 120, 255))
d2.ellipse([c * 0.23, c * 0.22, c * 0.29, c * 0.28], fill=(255, 245, 210, 255))
edge = ImageChops.subtract(m, m.filter(ImageFilter.MinFilter(9)))
corner.paste((255, 225, 150, 255), (0, 0), edge)
save(corner, 'corner', (64, 64))

# 3) кромки рамки: горизонтальная и вертикальная бронзовая планка
hb = grad(8, 16 * S, [(0, (60, 36, 14)), (0.25, (205, 152, 82)), (0.5, (150, 98, 48)), (0.8, (96, 60, 26)), (1, (40, 24, 10))])
save(hb.resize((64, 16 * S)), 'edge-h', (64, 16))
save(hb.resize((64, 16 * S)).rotate(90, expand=True), 'edge-v', (16, 64))

# 4) плашка заголовка
hw, hh = 512, 64
hd = Image.new('RGBA', (hw, hh), (0, 0, 0, 0))
base = grad(hw, hh, [(0, (70, 44, 18)), (0.5, (40, 24, 10)), (1, (22, 13, 6))])
mk = Image.new('L', (hw, hh), 0); ImageDraw.Draw(mk).rounded_rectangle([0, 0, hw - 1, hh - 1], radius=10, fill=255)
hd.paste(base, (0, 0), mk)
ImageDraw.Draw(hd).rounded_rectangle([1, 1, hw - 2, hh - 2], radius=10, outline=(214, 160, 92, 255), width=2)
ImageDraw.Draw(hd).line([(16, hh - 6), (hw - 16, hh - 6)], fill=(233, 196, 106, 120), width=1)
save(hd, 'header')

# 5) кнопки: обычная, наведение, нажата, неактивна
def button(stops, name, glow=False):
    w, h = 128 * S, 32 * S
    mk = Image.new('L', (w, h), 0); ImageDraw.Draw(mk).rounded_rectangle([0, 0, w - 1, h - 1], radius=7 * S, fill=255)
    im = masked(grad(w, h, stops), mk)
    dd = ImageDraw.Draw(im)
    dd.rounded_rectangle([S, S, w - S - 1, h - S - 1], radius=7 * S, outline=(255, 230, 160, 200 if glow else 140), width=S)
    dd.line([(10 * S, 3 * S), (w - 10 * S, 3 * S)], fill=(255, 250, 220, 90), width=S)
    save(im, name, (128, 32))
button([(0, (96, 62, 26)), (0.5, (70, 44, 18)), (1, (44, 27, 11))], 'btn')
button([(0, (138, 92, 40)), (0.5, (104, 66, 28)), (1, (60, 37, 15))], 'btn-hover', True)
button([(0, (44, 27, 11)), (0.5, (70, 44, 18)), (1, (96, 62, 26))], 'btn-down', True)
button([(0, (55, 50, 45)), (1, (35, 32, 29))], 'btn-off')
button([(0, (255, 226, 140)), (0.5, (220, 170, 70)), (1, (150, 100, 30))], 'btn-gold', True)

# 6) иконки 32×32
def icon(draw_fn, name, size=32):
    big = Image.new('RGBA', (size * S * 2, size * S * 2), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(big), size * S * 2)
    save(big, name, (size, size))

def star(d, n, fill, outline):
    cx = cy = n / 2; R = n * 0.46; r = R * 0.45
    pts = [(cx + (R if i % 2 == 0 else r) * math.sin(i * math.pi / 5), cy - (R if i % 2 == 0 else r) * math.cos(i * math.pi / 5)) for i in range(10)]
    d.polygon(pts, fill=fill, outline=outline)
    if outline: d.line(pts + [pts[0]], fill=outline, width=int(n * 0.05))
icon(lambda d, n: star(d, n, (240, 200, 90, 255), (120, 80, 20, 255)), 'star-on')
icon(lambda d, n: star(d, n, (0, 0, 0, 0), (170, 150, 120, 220)), 'star-off')

def search(d, n):
    w = int(n * 0.1)
    d.ellipse([n * 0.12, n * 0.12, n * 0.64, n * 0.64], outline=(240, 220, 170, 255), width=w)
    d.line([(n * 0.58, n * 0.58), (n * 0.88, n * 0.88)], fill=(240, 220, 170, 255), width=int(w * 1.4))
icon(search, 'search')

def paw(d, n):
    g = (233, 196, 106, 255)
    d.ellipse([n * .28, n * .48, n * .72, n * .86], fill=g)
    for (x, y, rx, ry) in [(.2, .38, .08, .11), (.38, .22, .085, .12), (.62, .22, .085, .12), (.8, .38, .08, .11)]:
        d.ellipse([n * (x - rx), n * (y - ry), n * (x + rx), n * (y + ry)], fill=g)
icon(paw, 'paw', 64)

def chart(d, n):
    w = int(n * 0.08)
    d.line([(n * .1, n * .9), (n * .9, n * .9)], fill=(170, 150, 120, 255), width=w // 2)
    d.line([(n * .12, n * .72), (n * .38, n * .45), (n * .58, n * .6), (n * .88, n * .18)], fill=(233, 196, 106, 255), width=w, joint='curve')
icon(chart, 'chart')

def arrow(d, n, up):
    col = (120, 217, 138, 255) if up else (255, 122, 102, 255)
    pts = [(n * .5, n * .18), (n * .85, n * .7), (n * .15, n * .7)] if up else [(n * .5, n * .82), (n * .85, n * .3), (n * .15, n * .3)]
    d.polygon(pts, fill=col)
icon(lambda d, n: arrow(d, n, True), 'up')
icon(lambda d, n: arrow(d, n, False), 'down')

def coin(d, n):
    d.ellipse([n * .14, n * .14, n * .86, n * .86], fill=(233, 196, 106, 255), outline=(150, 104, 38, 255), width=int(n * .06))
    d.ellipse([n * .32, n * .32, n * .68, n * .68], outline=(255, 240, 190, 255), width=int(n * .05))
icon(coin, 'coin')

def bag(d, n):
    d.rounded_rectangle([n * .18, n * .34, n * .82, n * .88], radius=n * .12, fill=(170, 120, 60, 255), outline=(90, 60, 25, 255), width=int(n * .05))
    d.arc([n * .34, n * .1, n * .66, n * .5], 180, 360, fill=(220, 180, 110, 255), width=int(n * .07))
icon(bag, 'bag')

def scan(d, n):
    w = int(n * .08); c = (233, 196, 106, 255)
    for a in [(n*.1, n*.1, n*.32, n*.1, n*.1, n*.32), (n*.9, n*.1, n*.68, n*.1, n*.9, n*.32), (n*.1, n*.9, n*.32, n*.9, n*.1, n*.68), (n*.9, n*.9, n*.68, n*.9, n*.9, n*.68)]:
        d.line([(a[2], a[3]), (a[0], a[1]), (a[4], a[5])], fill=c, width=w)
    d.line([(n * .2, n * .5), (n * .8, n * .5)], fill=(255, 240, 190, 255), width=w)
icon(scan, 'scan')

# 7) свечение (для уведомлений и подсветки строк)
gw = 256 * S
gl = Image.new('L', (gw, 64 * S), 0)
ImageDraw.Draw(gl).rounded_rectangle([8 * S, 8 * S, gw - 8 * S, 56 * S], radius=24 * S, fill=255)
gl = gl.filter(ImageFilter.GaussianBlur(9 * S))
glow = Image.new('RGBA', gl.size, (255, 210, 120, 0)); glow.putalpha(gl)
save(glow, 'glow', (256, 64))

# 8) светлая полоса для строк списка
row = Image.new('RGBA', (256, 32), (0, 0, 0, 0))
rp = row.load()
for x in range(256):
    a = int(70 * math.sin(math.pi * x / 255))
    for y in range(32): rp[x, y] = (255, 214, 140, a)
save(row, 'row-hl')
print('media:', sorted(os.listdir(OUT)))
