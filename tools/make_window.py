# Текстуры нового главного окна (2.43): левая колонка разделов, шапка, рамка по частям, фон,
# колокольчик сигнала, конверт с печатью, свечение клетки, медальон уведомления.
# python3 tools/make_window.py  ->  addon/WolfichMarket/media/win/*.tga  + WinData.lua (размеры и доли текстур)
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'skin', 'win')
OUT = os.path.join(HERE, '..', 'addon', 'WolfichMarket', 'media', 'win')
LUA = os.path.join(HERE, '..', 'addon', 'WolfichMarket', 'WinData.lua')
os.makedirs(OUT, exist_ok=True)
TC = {}


def pot(n):
    p = 8
    while p < n:
        p *= 2
    return p


def fill_edges(img):
    """Цвет под прозрачными пикселями - от соседей: без тёмной каймы при фильтрации в игре."""
    a = np.array(img, dtype=np.float32)
    al = a[..., 3]
    pm = Image.fromarray(np.dstack([a[..., :3] * (al[..., None] / 255), al]).astype(np.uint8), 'RGBA')
    blur = np.array(pm.filter(ImageFilter.GaussianBlur(3)), dtype=np.float32)
    ba = np.maximum(blur[..., 3:4], 1)
    fill = np.clip(blur[..., :3] / ba * 255, 0, 255)
    m = al < 8
    a[..., :3][m] = fill[m]
    return Image.fromarray(a.astype(np.uint8), 'RGBA')


def save(img, name, size=None):
    if size:
        img = img.convert('RGBa').resize((max(1, round(size[0])), max(1, round(size[1]))), Image.LANCZOS).convert('RGBA')
    img = fill_edges(img)
    W, H = pot(img.width), pot(img.height)
    canvas = Image.new('RGBA', (W, H))
    canvas.paste(img, (0, 0))
    # поля до степени двойки - крайними пикселями (растяжение не цепляет пустоту)
    if W > img.width:
        canvas.paste(img.crop((img.width - 1, 0, img.width, img.height)).resize((W - img.width, img.height)), (img.width, 0))
    if H > img.height:
        canvas.paste(canvas.crop((0, img.height - 1, W, img.height)).resize((W, H - img.height)), (0, img.height))
    canvas.save(os.path.join(OUT, name + '.tga'), compression=None)
    TC[name] = (img.width / W, img.height / H)


# ---------- левая колонка: шашечный фон картинки убрать (заливка от краёв) ----------
side = np.array(Image.open(os.path.join(SRC, 'side-src.png')).convert('RGB')).astype(int)
mx, mn = side.max(2), side.min(2)
cand = (mn > 200) & ((mx - mn) < 14)
lab, _ = ndimage.label(cand)
edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(edge))
fringe = (mn > 170) & ((mx - mn) < 20)
for _ in range(3):
    bg = bg | (ndimage.binary_dilation(bg) & fringe)
A = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
S = Image.fromarray(side.astype(np.uint8)).convert('RGBA')
S.putalpha(A)
S = S.crop(S.getbbox())                      # 384 x 1517
SIDE_W, SIDE_H = S.size
save(S, 'side', size=(256, 256 * SIDE_H / SIDE_W))

# ---------- шапка: левый край (кристаллы) срезан и растушёван - он уходит под колонку; фон-дымка прозрачный ----------
# правый конец (синие кристаллы) срезан: там уже есть украшения рамки - иначе они накладываются
bar = Image.open(os.path.join(SRC, 'bar.png')).convert('RGBA').crop((150, 0, 985, 115))
a = np.array(bar).astype(int)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
mxb, mnb = a[..., :3].max(2), a[..., :3].min(2)
orn = (b > r + 25) | (((mxb - mnb) < 30) & (mxb > 60)) | (mxb > 215)
orn[88:, :] = ((b > r + 25) | (mxb > 215))[88:, :]  # под нижней кромкой - только кристаллы
outer = np.ones(r.shape, bool)
outer[26:90, :] = False
keep = ~outer | orn
M = Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
a[..., 3] = (a[..., 3] * np.array(M) / 255).astype(int)
w = a.shape[1]
for i in range(40):
    a[:, i, 3] = (a[:, i, 3] * (i / 40)).astype(int)
for i in range(60):
    a[:, w - 1 - i, 3] = (a[:, w - 1 - i, 3] * (i / 60) ** 1.4).astype(int)
BAR = Image.fromarray(a.astype(np.uint8))
save(BAR, 'bar')

# ---------- рамка: части в масштабе 1 (в игре - уменьшение); внутренняя ткань и внешняя дымка - прозрачные ----------
P = Image.open(os.path.join(SRC, 'panel.png')).convert('RGBA')     # 514 x 530
pw, ph = P.size
a = np.array(P).astype(int)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
mxp, mnp = a[..., :3].max(2), a[..., :3].min(2)
lum = a[..., :3].mean(2)
orn = (b > r + 25) | (mxp > 175) | ((r > 150) & (g > 90) & (r - b > 80))
interior = np.zeros((ph, pw), bool)
interior[58:ph - 34, 44:pw - 46] = True
plain = (lum < 95) & ((mxp - mnp) < 28)
outer = np.ones((ph, pw), bool)
outer[12:ph - 4, 20:pw - 20] = False
drop = (interior & plain) | (outer & ~orn)
M = Image.fromarray(np.where(drop, 0, 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.5))
a[..., 3] = (a[..., 3] * np.array(M) / 255).astype(int)
F = Image.fromarray(a.astype(np.uint8))
L, R, T, B = 200, 320, 200, 400
PARTS = {
    'f-tl': (0, 0, L, T), 'f-t': (L, 0, R, T), 'f-tr': (R, 0, pw, T),
    'f-l': (0, T, 60, B), 'f-r': (pw - 60, T, pw, B),
    'f-bl': (0, B, 98, ph), 'f-bf': (94, B, 97, ph), 'f-em': (98, B, 410, ph), 'f-br': (410, B, pw, ph),
}
FSIZE = {}
for k, bb in PARTS.items():
    im = F.crop(bb)
    FSIZE[k] = im.size
    save(im, k)
# фон внутри рамки: тёмный, с мягким светлым центром и едва заметным зерном (лапки - отдельной текстурой, в игре)
N = 256
yy, xx = np.mgrid[0:N, 0:N].astype(float)
rr = np.sqrt(((xx - N / 2) / (N / 2)) ** 2 + ((yy - N / 2) / (N / 2)) ** 2)
base = 23 - 9 * np.clip(rr, 0, 1.4) ** 1.6
rng = np.random.default_rng(5)
grain = np.array(Image.fromarray(((rng.normal(0, 1, (N, N)) * 40) + 128).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(float) - 128
v = base + grain * 0.05
bgc = np.dstack([v * 0.97, v * 0.95, v * 1.06, np.full((N, N), 255.0)]).clip(0, 255).astype(np.uint8)
save(Image.fromarray(bgc, 'RGBA').filter(ImageFilter.GaussianBlur(0.8)), 'f-c')
# лапка для украшения фона: светлый силуэт, чуть размытый (цвет и прозрачность - в игре)
def paw(d, k):
    s = k
    d.ellipse((34 * s, 54 * s, 94 * s, 106 * s), fill=(255, 255, 255, 255))
    for (x, y, rx, ry) in ((22, 40, 11, 15), (44, 20, 12, 16), (74, 20, 12, 16), (98, 40, 11, 15)):
        d.ellipse(((x - rx) * s, (y - ry) * s, (x + rx) * s, (y + ry) * s), fill=(255, 255, 255, 255))
pw_img = Image.new('RGBA', (128 * 4, 128 * 4)); paw(ImageDraw.Draw(pw_img), 4)
pw_img = pw_img.resize((128, 128), Image.LANCZOS).filter(ImageFilter.GaussianBlur(2.2))
save(pw_img, 'paw-bg')
# ---------- значки ----------
def supersample(draw_fn, W, H, k=4):
    im = Image.new('RGBA', (W * k, H * k))
    draw_fn(ImageDraw.Draw(im), k)
    return im.resize((W, H), Image.LANCZOS)


def bell(d, k, fill, line):
    s = k
    body = [(16 * s, 4 * s), (22 * s, 7 * s), (24 * s, 14 * s), (24 * s, 20 * s), (28 * s, 25 * s), (4 * s, 25 * s), (8 * s, 20 * s), (8 * s, 14 * s), (10 * s, 7 * s)]
    d.polygon(body, fill=fill)
    d.line(body + [body[0]], fill=line, width=2 * s, joint='curve')
    d.ellipse((13 * s, 25 * s, 19 * s, 30 * s), fill=line)
    d.ellipse((14 * s, 1 * s, 18 * s, 5 * s), fill=line)


save(supersample(lambda d, k: bell(d, k, (242, 199, 97, 255), (120, 80, 20, 255)), 32, 32), 'bell-on')
save(supersample(lambda d, k: bell(d, k, (60, 50, 36, 200), (190, 160, 100, 255)), 32, 32), 'bell-off')


def envelope(d, k):
    s = k
    d.rounded_rectangle((2 * s, 8 * s, 62 * s, 46 * s), radius=3 * s, fill=(232, 214, 170, 255), outline=(122, 90, 42, 255), width=2 * s)
    d.line([(3 * s, 9 * s), (32 * s, 30 * s), (61 * s, 9 * s)], fill=(122, 90, 42, 255), width=2 * s)
    d.ellipse((21 * s, 19 * s, 43 * s, 41 * s), fill=(179, 32, 28, 255), outline=(110, 15, 12, 255), width=2 * s)
    d.ellipse((28 * s, 27 * s, 36 * s, 35 * s), fill=(232, 180, 168, 255))
    for x, y in ((26, 23), (32, 21), (38, 23)):
        d.ellipse(((x - 2) * s, (y - 2) * s, (x + 2) * s, (y + 2) * s), fill=(232, 180, 168, 255))


save(supersample(envelope, 64, 48), 'envelope')
save(supersample(lambda d, k: d.polygon([(4 * k, 2 * k), (13 * k, 8 * k), (4 * k, 14 * k)], fill=(242, 199, 97, 255), outline=(90, 60, 15, 255)), 16, 16), 'tri')

# свечение клетки колонки: светлая кромка внутрь (цвет задаётся в игре)
G = np.zeros((128, 128), float)
yy, xx = np.mgrid[0:128, 0:128]
dist = np.minimum.reduce([xx, yy, 127 - xx, 127 - yy]).astype(float)
G = np.clip(1 - dist / 26, 0, 1) ** 1.6
G[dist < 3] = 1
glow = np.dstack([np.full_like(G, 255), np.full_like(G, 255), np.full_like(G, 255), G * 255]).astype(np.uint8)
save(Image.fromarray(glow, 'RGBA'), 'slot-glow')

# медальон уведомления (воющий волк) - круг
hw = Image.open(os.path.join(SRC, 'howl.png')).convert('RGBA')
c = min(hw.size)
hw = hw.crop(((hw.width - c) // 2, 0, (hw.width - c) // 2 + c, c))
mask = Image.new('L', (c * 4, c * 4))
ImageDraw.Draw(mask).ellipse((6, 6, c * 4 - 6, c * 4 - 6), fill=255)
hw.putalpha(ImageChops.multiply(hw.split()[3], mask.resize((c, c), Image.LANCZOS)))
save(hw, 'howl', size=(64, 64))

# ---------- данные для игры ----------
with open(LUA, 'w', encoding='utf-8') as f:
    f.write('-- Сгенерировано tools/make_window.py: размеры частей нового окна и доли текстур\n')
    f.write('local _, ns = ...\n')
    f.write('ns.WIN = {\n')
    f.write('  side = { %d, %d },\n' % (SIDE_W, SIDE_H))
    f.write('  bar = { %d, %d },\n' % BAR.size)
    for k, (w2, h2) in FSIZE.items():
        f.write('  ["%s"] = { %d, %d },\n' % (k, w2, h2))
    f.write('}\n')
    f.write('ns.WIN_TC = {\n')
    for k in sorted(TC):
        f.write('  ["%s"] = { %.5f, %.5f },\n' % (k, TC[k][0], TC[k][1]))
    f.write('}\n')
print('ok', len(TC), 'textures')

# ---------- кнопки (3 части), галочка, тень под окном ----------
def cut_bg(img, tol=46):
    """Фон картинки вокруг рамки (заливка от краёв по цвету угла) - прозрачный."""
    a = np.array(img.convert('RGBA')).astype(int)
    h, w = a.shape[:2]
    ref = a[[0, 0, h - 1, h - 1], [0, w - 1, 0, w - 1], :3].mean(0)
    d = np.abs(a[..., :3] - ref).sum(2)
    lab, _ = ndimage.label(d < tol)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bgm = np.isin(lab, list(edge))
    m = Image.fromarray(np.where(bgm, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    a[..., 3] = (a[..., 3] * np.array(m) / 255).astype(int)
    return Image.fromarray(a.astype(np.uint8))


BTN_CAP = 22
for kind in ('gold', 'dark', 'blue'):
    im = cut_bg(Image.open(os.path.join(SRC, 'wm-btn_%s.png' % kind)))
    w, h = im.size
    save(im.crop((0, 0, BTN_CAP, h)), 'btn-%s-l' % kind)
    save(im.crop((BTN_CAP + 6, 0, w - BTN_CAP - 6, h)).resize((64, h)), 'btn-%s-m' % kind)
    save(im.crop((w - BTN_CAP, 0, w, h)), 'btn-%s-r' % kind)
chk = cut_bg(Image.open(os.path.join(SRC, 'wm-chk.png')))
save(chk, 'chk-on', size=(32, 28))
off = np.array(chk).astype(int)
# пустая галочка: внутренность рамки - ровная тёмная (галка стёрта целиком)
ins = off[11:32, 11:35]
r, g, b = ins[..., 0], ins[..., 1], ins[..., 2]
goldish = (r > 60) & (r - b > 18)
dark = np.median(ins[~goldish][:, :3], axis=0) if (~goldish).any() else np.array([30, 30, 32])
ins[:, :, :3] = dark
off[11:32, 11:35] = ins
save(Image.fromarray(off.astype(np.uint8)), 'chk-off', size=(32, 28))
# мягкая чёрная подложка под окном (заполняет просветы между колонкой, шапкой и рамкой)
S2 = 128
yy, xx = np.mgrid[0:S2, 0:S2].astype(float)
dd = np.minimum.reduce([xx, yy, S2 - 1 - xx, S2 - 1 - yy])
al = np.clip(dd / 16, 0, 1) ** 1.3 * 232
save(Image.fromarray(np.dstack([np.full((S2, S2), 6), np.full((S2, S2), 6), np.full((S2, S2), 9), al]).astype(np.uint8), 'RGBA'), 'shade')
# доли текстур - ещё раз (новые записи)
with open(LUA, 'a', encoding='utf-8') as f:
    f.write('ns.WIN_BTN_CAP = %d / 55\n' % BTN_CAP)
    for k in sorted(TC):
        f.write('ns.WIN_TC["%s"] = { %.5f, %.5f }\n' % (k, TC[k][0], TC[k][1]))
print('ok buttons')
