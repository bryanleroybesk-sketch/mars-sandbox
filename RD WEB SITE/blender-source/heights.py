import json, math, numpy as np
from PIL import Image, ImageDraw, ImageFilter

D = '/tmp/claude-0/-home-user-mars-sandbox/eda22a4b-fb0b-53b5-8c75-12a0626db0dd/scratchpad/'
N = 384            # grid resolution
SIZE = 4.0         # terrain plane size in blender units
FIT = 3.0          # country fits in this box
SS = 4             # raster supersample
geo = json.load(open(D + 'geo/countries.json'))
rng = np.random.default_rng(7)

def polys(g):
    return [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']

def fbm(n, octs, seed, base=4):
    r = np.random.default_rng(seed)
    out = np.zeros((n, n)); amp = 1.0; tot = 0
    for o in range(octs):
        k = base * 2 ** o
        a = (r.random((k + 1, k + 1)) * 255).astype(np.uint8)
        im = Image.fromarray(a).resize((n, n), Image.BICUBIC)
        out += amp * (np.asarray(im, dtype=np.float64) / 255.0)
        tot += amp; amp *= 0.5
    return out / tot

def ridged(n, octs, seed, base=3):
    f = fbm(n, octs, seed, base)
    f = (f - f.min()) / (f.max() - f.min())
    return 1.0 - np.abs(2 * f - 1)

def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)

def project(code):
    pts = [p for poly in polys(geo[code]) for ring in poly for p in ring]
    lon = np.array([p[0] for p in pts]); lat = np.array([p[1] for p in pts])
    lat0 = (lat.min() + lat.max()) / 2; c = math.cos(math.radians(lat0))
    x0, x1 = lon.min() * c, lon.max() * c; y0, y1 = lat.min(), lat.max()
    s = FIT / max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    def f(lo, la):  # to blender xy
        return ((lo * c - cx) * s, (la - cy) * s)
    return f, c

def raster(code, f):
    big = N * SS
    img = Image.new('L', (big, big), 0)
    dr = ImageDraw.Draw(img)
    def px(p):
        x, y = f(p[0], p[1])
        return ((x / SIZE + 0.5) * big, (0.5 - y / SIZE) * big)
    for poly in polys(geo[code]):
        for i, ring in enumerate(poly):
            dr.polygon([px(p) for p in ring], fill=255 if i == 0 else 0)
    img = img.resize((N, N), Image.LANCZOS)
    return np.asarray(img, dtype=np.float64) / 255.0

def edge_rough(mask, seed):
    sm = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4.5)), dtype=np.float64) / 255.0
    n = fbm(N, 5, seed, 12) - 0.5
    return smooth(sm + n * 0.14, 0.18, 0.86)

def world_to_grid(x, y):
    return (int((x / SIZE + 0.5) * N), int((0.5 - y / SIZE) * N))

def gauss(f, lon, lat, sig):
    cx, cy = f(lon, lat)
    gx = (np.arange(N) / N - 0.5) * SIZE
    gy = (0.5 - np.arange(N) / N) * SIZE
    X, Y = np.meshgrid(gx, gy)
    return np.exp(-(((X - cx) ** 2 + (Y - cy) ** 2) / (2 * sig ** 2)))

out = {}; cities = {}
# --- Switzerland: plateau + Jura + high Alps
f, _ = project('CHE'); m = raster('CHE', f); e = edge_rough(m, 11)
alp = ridged(N, 7, 21, 4)
w_alps = np.clip(gauss(f, 8.2, 46.45, 0.75) + 0.8 * gauss(f, 9.8, 46.6, 0.6) + 0.5 * gauss(f, 7.2, 46.2, 0.6), 0, 1)
w_jura = 0.35 * gauss(f, 6.6, 47.1, 0.5)
t = 0.10 * fbm(N, 6, 5, 6) + 1.25 * alp ** 2.1 * w_alps + 0.35 * alp ** 1.6 * w_jura
out['CHE'] = e * (0.05 + 0.95 * t) + 0.012 * (fbm(N, 6, 99, 24) - 0.5) * e
cities['CHE'] = f(8.54, 47.37)
# --- Thailand: northern mountains, central plain, southern ridge
f, _ = project('THA'); m = raster('THA', f); e = edge_rough(m, 12)
alp = ridged(N, 7, 22, 4)
w_n = np.clip(gauss(f, 99.0, 18.6, 1.0) + 0.7 * gauss(f, 98.6, 16.0, 0.8), 0, 1)
w_s = 0.55 * gauss(f, 99.2, 8.6, 0.9) + 0.35 * gauss(f, 98.9, 10.5, 0.7)
w_e = 0.4 * gauss(f, 102.5, 14.4, 0.6)
t = 0.06 * fbm(N, 6, 6, 6) + 1.0 * alp ** 1.9 * np.clip(w_n + w_s + w_e, 0, 1)
out['THA'] = e * (0.05 + 0.55 * t) + 0.01 * (fbm(N, 6, 98, 24) - 0.5) * e
cities['THA'] = f(100.88, 12.93)
# --- UAE: dunes, Hajar range in the east
f, _ = project('ARE'); m = raster('ARE', f); e = edge_rough(m, 13)
gx = (np.arange(N) / N - 0.5) * SIZE; gy = (0.5 - np.arange(N) / N) * SIZE
X, Y = np.meshgrid(gx, gy)
dunes = 0.5 + 0.5 * np.sin((X * 5.5 + Y * 3.2) + 2.2 * (fbm(N, 4, 8, 5) - 0.5) * 6)
alp = ridged(N, 7, 23, 4)
w_h = np.clip(gauss(f, 56.1, 25.4, 0.55) + 0.7 * gauss(f, 56.2, 24.3, 0.5), 0, 1)
t = 0.18 * dunes * (0.6 + fbm(N, 5, 9, 6)) + 1.1 * alp ** 1.9 * w_h
out['ARE'] = e * (0.05 + 0.45 * t) + 0.008 * (fbm(N, 6, 97, 24) - 0.5) * e
cities['ARE'] = f(55.27, 25.20)

np.savez_compressed(D + 'blender/heights.npz', N=N, SIZE=SIZE, **out)
json.dump({k: list(v) for k, v in cities.items()}, open(D + 'blender/cities.json', 'w'))
for k, v in out.items():
    print(k, round(v.min(), 3), round(v.max(), 3), cities[k])
# preview
prev = Image.new('L', (N * 3, N))
for i, k in enumerate(['CHE', 'THA', 'ARE']):
    a = out[k]; prev.paste(Image.fromarray((255 * a / a.max()).astype(np.uint8)), (i * N, 0))
prev.save(D + 'blender/heights_preview.png')
