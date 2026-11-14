# Нарезка макетов оформления (tools/skin/*.png) на текстуры аддона: 9-частные рамки, кнопки, иконки.
# python3 tools/make_skin.py  ->  addon/WolfichMarket/media/skin/*.tga  (+ превью в tools/skin/preview_*.png)
import os
from PIL import Image, ImageFilter
from scipy import ndimage
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'skin')
OUT = os.path.join(HERE, '..', 'addon', 'WolfichMarket', 'media', 'skin')
os.makedirs(OUT, exist_ok=True)

def pot(n):
    p = 8
    while p < n: p *= 2
    return p

Q = 1.5        # запас разрешения: текстура в 1.5 раза крупнее, чем рисуется в игре
TC = {}        # доли текстуры, занятые картинкой (остальное - поля до степени двойки)

def clean(img):
    """Чистка краёв: убрать полупрозрачную пыль, залить цвет прозрачных пикселей соседним,
    чтобы при фильтрации в игре не было тёмной каймы."""
    a = np.array(img, dtype=np.float32)
    al = a[..., 3]
    al[al < 28] = 0
    al[al > 236] = 255
    a[..., 3] = al
    # цвет под прозрачными пикселями - размытый цвет непрозрачных соседей
    pm = Image.fromarray(np.dstack([a[..., :3] * (al[..., None] / 255), al]).astype(np.uint8), 'RGBA')
    blur = np.array(pm.filter(ImageFilter.GaussianBlur(3)), dtype=np.float32)
    ba = np.maximum(blur[..., 3:4], 1)
    fill = np.clip(blur[..., :3] / ba * 255, 0, 255)
    m = al == 0
    a[..., :3][m] = fill[m]
    return Image.fromarray(a.astype(np.uint8), 'RGBA')

def resize(img, w, h):
    # уменьшение в предумноженной альфе - без светлых/тёмных ореолов по краю
    w, h = max(1, int(round(w))), max(1, int(round(h)))
    return img.convert('RGBa').resize((w, h), Image.LANCZOS).convert('RGBA')

def save(img, name, scale=1.0, size=None):
    w, h = size or (img.width * scale * Q, img.height * scale * Q)
    # растягиваемые части (фон, кромки) в игре всё равно тянутся - хватает меньшего размера
    if name.endswith('-c'):
        k = min(1, 500 / max(w, h)); w, h = w * k, h * k
    elif name.endswith(('-t', '-b', '-m')) and w > 250: w = 250
    elif name.endswith(('-l', '-r')) and not name.startswith(('mbtn', 'abtn')) and h > 250: h = 250
    p = clean(resize(clean(img), w, h))
    W, H = pot(p.width), pot(p.height)
    canvas = Image.new('RGBA', (W, H))
    canvas.paste(p, (0, 0))
    # поля заполняем крайними пикселями, чтобы растяжение в игре не цепляло пустоту
    if W > p.width: canvas.paste(p.crop((p.width - 1, 0, p.width, p.height)).resize((W - p.width, p.height)), (p.width, 0))
    if H > p.height: canvas.paste(canvas.crop((0, p.height - 1, W, p.height)).resize((W, H - p.height)), (0, p.height))
    canvas.save(os.path.join(OUT, name + '.tga'), compression=None)
    TC[name] = (p.width / W, p.height / H)

def tight(img, box, pad=6):
    """Рамка вокруг элемента по непрозрачным пикселям (с небольшим запасом поиска)."""
    x1, y1, x2, y2 = box
    c = img.crop((x1 - pad, y1 - pad, x2 + pad, y2 + pad))
    al = np.array(c)[..., 3]
    ys, xs = np.where(al > 28)
    return (x1 - pad + xs.min(), y1 - pad + ys.min(), x1 - pad + xs.max() + 1, y1 - pad + ys.max() + 1)

def solo(img, strict=False):
    """Оставить только сам элемент: убрать куски соседних элементов макета, попавшие в вырезку."""
    a = np.array(img)
    m = a[..., 3] > 28
    lab, n = ndimage.label(m)
    if n <= 1: return img
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    big = int(np.argmax(sizes)) + 1
    ys, xs = np.where(lab == big)
    x1, x2, y1, y2 = xs.min() - 2, xs.max() + 2, ys.min() - 2, ys.max() + 2
    keep = np.zeros(n + 1, bool); keep[big] = True
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        if not strict and sl and sl[0].start >= y1 and sl[0].stop - 1 <= y2 and sl[1].start >= x1 and sl[1].stop - 1 <= x2: keep[i] = True
    a[..., 3] = np.where(keep[lab], a[..., 3], 0)
    return Image.fromarray(a, 'RGBA')

def border(img, side):
    """Толщина золотой кромки (до тёмного фона) по середине стороны."""
    a = np.array(img.convert('RGBA')).astype(np.float32)
    H, W = a.shape[:2]
    if side == 'l': line = a[H // 2, :, :]
    elif side == 'r': line = a[H // 2, ::-1, :]
    else: line = a[::-1, W // 2, :]
    luma = line[:, :3] @ np.array([0.3, 0.59, 0.11])
    i = int(np.argmax(line[:, 3] > 128))
    seen = False
    while i < len(line) - 3:
        if luma[i] > 70: seen = True
        if seen and (luma[i:i + 3] < 45).all(): return i + 2
        i += 1
    return 20

INSET = {}
FEATHER = 14

# рамка: box = (x1,y1,x2,y2); l,t,r,b — толщина краёв в пикселях макета; center — прямоугольник фона;
# top_inset — где кончается заголовок (рамка внутри него не прозрачная)
def nine(img, prefix, box, l, t, r, b, center=None, top_edge_x=None, bottom_edge_x=None, side_y=None, scale=1.0, top_inset=20, r_edge=None):
    x1, y1, x2, y2 = box
    F = solo(img.crop(box), strict=True)
    W, H = F.size
    ins = (border(F, 'l'), top_inset, border(F, 'r'), border(F, 'b'))
    INSET[prefix] = ins
    # внутри кромки рамка плавно уходит в прозрачность - фон рисуется отдельной текстурой под ней, без швов
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.minimum.reduce([xx - ins[0], yy - ins[1], (W - 1 - xx) - ins[2], (H - 1 - yy) - ins[3]])
    k = np.clip(1 - d / FEATHER, 0, 1)
    A = np.array(F).astype(np.float32); A[..., 3] *= k
    F = Image.fromarray(A.astype(np.uint8), 'RGBA')
    def rel(bb): return (bb[0] - x1, bb[1] - y1, bb[2] - x1, bb[3] - y1)
    parts = {
        'tl': (x1, y1, x1 + l, y1 + t), 'tr': (x2 - r, y1, x2, y1 + t),
        'bl': (x1, y2 - b, x1 + l, y2), 'br': (x2 - r, y2 - b, x2, y2),
    }
    tx = top_edge_x or (x1 + l + 40, x2 - r - 40)
    bx = bottom_edge_x or tx
    sy = side_y or (y1 + t + 20, y2 - b - 20)
    parts['t'] = (tx[0], y1, tx[1], y1 + t)
    parts['b'] = (bx[0], y2 - b, bx[1], y2)
    parts['l'] = (x1, sy[0], x1 + l, sy[1])
    parts['r'] = (x2 - (r_edge or r), sy[0], x2, sy[1])
    for k2, bb in parts.items():
        save(F.crop(rel(bb)), f'{prefix}-{k2}', scale)
    # фон: середина макета без рамки
    save(img.crop(center or (x1 + l, y1 + t, x2 - r, y2 - b)), f'{prefix}-c', scale)

def three(img, prefix, box, cap, H=44):
    x1, y1, x2, y2 = tight(img, box, 4)
    img = solo(img.crop((x1, y1, x2, y2))); x2, y2, x1, y1 = x2 - x1, y2 - y1, 0, 0
    k = H / (y2 - y1)
    cap = round(cap * (y2 - y1) / 82)
    save(img.crop((x1, y1, x1 + cap, y2)), prefix + '-l', size=(cap * k, H))
    save(img.crop((x1 + cap + 10, y1, x2 - cap - 10, y2)), prefix + '-m', size=(64, H))
    save(img.crop((x2 - cap, y1, x2, y2)), prefix + '-r', size=(cap * k, H))

def icon(img, name, box, S=48):
    bb = tight(img, box, 3)
    save(solo(img.crop(bb)), name, size=(S, S * (bb[3] - bb[1]) / (bb[2] - bb[0])))

M = Image.open(os.path.join(SRC, 'main.png')).convert('RGBA')
A = Image.open(os.path.join(SRC, 'ah.png')).convert('RGBA')

# главное окно (второй макет)
nine(M, 'main', (15, 12, 941, 628), l=100, t=92, r=96, b=60, center=(70, 120, 880, 560), side_y=(140, 540), scale=0.85, top_inset=70)
nine(M, 'mcard', (816, 603, 1426, 889), l=175, t=60, r=58, b=50, center=(870, 670, 1370, 830), top_edge_x=(1000, 1300), side_y=(680, 820), scale=0.5, top_inset=44)
three(M, 'mbtn-gold', (954, 47, 1220, 129), 36)
three(M, 'mbtn-dark', (1230, 47, 1516, 129), 36)
icon(M, 'mchk-on', (36, 648, 93, 703)); icon(M, 'mchk-off', (118, 652, 167, 701))
icon(M, 'mi-star', (34, 910, 114, 987)); icon(M, 'mi-search', (140, 909, 220, 987)); icon(M, 'mi-gear', (240, 902, 330, 990))
icon(M, 'mi-left', (394, 921, 455, 980)); icon(M, 'mi-right', (483, 921, 543, 980)); icon(M, 'mi-close', (880, 16, 940, 80))

# панель аукциона (первый макет)
nine(A, 'ah', (44, 20, 901, 822), l=176, t=108, r=120, b=64, center=(90, 140, 800, 760), top_edge_x=(300, 700), side_y=(160, 740), scale=0.5, top_inset=92, r_edge=39)
# у правого края макета внутри — полоса прокрутки; правую кромку берём снаружи от неё
nine(A, 'acard', (927, 570, 1509, 975), l=72, t=70, r=70, b=70, center=(962, 640, 1476, 905), top_edge_x=(1100, 1300), side_y=(660, 890), scale=0.3, top_inset=20)
three(A, 'abtn-gold', (937, 76, 1215, 161), 36)
three(A, 'abtn-dark', (1227, 76, 1500, 161), 36)
for n, bb in [('ai-paw', (943, 472, 1014, 543)), ('ai-x', (1042, 472, 1113, 543)), ('ai-down', (1136, 472, 1207, 543)), ('ai-gear', (1232, 472, 1302, 543)), ('ai-q', (1327, 472, 1397, 543)), ('ai-ex', (1423, 471, 1494, 542))]:
    icon(A, n, bb)

# превью: как соберётся рамка заданного размера
def part(name):
    im = Image.open(os.path.join(OUT, name + '.tga')).convert('RGBA'); u, v = TC[name]
    return im.crop((0, 0, round(im.width * u), round(im.height * v)))
def preview(prefix, W, H, s, name):
    z = sizes_src[prefix]
    P = {k: part(f'{prefix}-{k}') for k in ['tl', 't', 'tr', 'l', 'c', 'r', 'bl', 'b', 'br']}
    im = Image.new('RGBA', (W, H), (40, 90, 40, 255))
    def put(k, x, y, w, h): im.alpha_composite(P[k].resize((max(1, round(w)), max(1, round(h))), Image.LANCZOS), (round(x), round(y)))
    l, r, t, b = z['l'] * s, z['r'] * s, z['t'] * s, z['b'] * s
    i = INSET[prefix]; put('c', i[0] * s, i[1] * s, W - (i[0] + i[2]) * s, H - (i[1] + i[3]) * s)
    put('t', z['tl'][0] * s, 0, W - (z['tl'][0] + z['tr'][0]) * s, t); put('b', z['bl'][0] * s, H - b, W - (z['bl'][0] + z['br'][0]) * s, b)
    put('l', 0, z['tl'][1] * s, l, H - (z['tl'][1] + z['bl'][1]) * s); put('r', W - r, z['tr'][1] * s, r, H - (z['tr'][1] + z['br'][1]) * s)
    for k, (x, y) in {'tl': (0, 0), 'tr': (1, 0), 'bl': (0, 1), 'br': (1, 1)}.items():
        w, h = z[k][0] * s, z[k][1] * s
        put(k, x * (W - w), y * (H - h), w, h)
    im.save(os.path.join(HERE, 'skin', name))
def btn(prefix, w, h):
    cap = round(h * 36 / 82); im = Image.new('RGBA', (w, h), (40, 30, 20, 255))
    im.alpha_composite(part(prefix + '-m').resize((w - 2 * cap, h), Image.LANCZOS), (cap, 0))
    im.alpha_composite(part(prefix + '-l').resize((cap, h), Image.LANCZOS), (0, 0))
    im.alpha_composite(part(prefix + '-r').resize((cap, h), Image.LANCZOS), (w - cap, 0))
    return im
row = Image.new('RGBA', (560, 40), (40, 30, 20, 255))
for i, p in enumerate(['mbtn-gold', 'mbtn-dark', 'abtn-gold', 'abtn-dark']):
    row.alpha_composite(btn(p, 130, 24), (i * 138 + 4, 8))
row.save(os.path.join(HERE, 'skin', 'preview_btn.png'))
# размеры частей в пикселях макета — для раскладки в игре
sizes = {}
def add(prefix, keys):
    for k in keys:
        f = os.path.join(OUT, f'{prefix}-{k}.tga')
sizes_src = {
  'main': {'tl': (100, 92), 'tr': (96, 92), 'bl': (100, 60), 'br': (96, 60), 'l': 100, 'r': 96, 't': 92, 'b': 60},
  'ah': {'tl': (176, 108), 'tr': (120, 108), 'bl': (176, 64), 'br': (120, 64), 'l': 176, 'r': 39, 't': 108, 'b': 64},
  'mcard': {'tl': (175, 60), 'tr': (58, 60), 'bl': (175, 50), 'br': (58, 50), 'l': 175, 'r': 58, 't': 60, 'b': 50},
  'acard': {'tl': (72, 70), 'tr': (70, 70), 'bl': (72, 70), 'br': (70, 70), 'l': 72, 'r': 70, 't': 70, 'b': 70},
}
preview('main', 860, 600, 0.85, 'preview_main.png')
preview('ah', 440, 620, 0.5, 'preview_ah.png')
preview('mcard', 400, 420, 0.5, 'preview_mcard.png')
preview('acard', 400, 180, 0.3, 'preview_acard.png')
lines = ['-- Сгенерировано tools/make_skin.py: размеры частей рамок в пикселях макета', 'local _, ns = ...', 'ns.SKIN = {']
for name, d in sizes_src.items():
    parts = []
    for k, v in d.items():
        parts.append(f'{k} = {{ {v[0]}, {v[1]} }}' if isinstance(v, tuple) else f'{k} = {v}')
    i = INSET[name]; parts.append(f'inset = {{ {i[0]}, {i[1]}, {i[2]}, {i[3]} }}')
    lines.append(f'  {name} = {{ ' + ', '.join(parts) + ' },')
lines.append('}')
lines.append('-- доли текстур, занятые картинкой (поля до степени двойки не рисуем)')
lines.append('ns.SKIN_TC = {')
for k in sorted(TC):
    lines.append(f'  ["{k}"] = {{ {TC[k][0]:.5f}, {TC[k][1]:.5f} }},')
lines.append('}')
open(os.path.join(HERE, '..', 'addon', 'WolfichMarket', 'SkinData.lua'), 'w').write('\n'.join(lines) + '\n')
print('ok', len(os.listdir(OUT)))
