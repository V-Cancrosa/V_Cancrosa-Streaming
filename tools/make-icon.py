#!/usr/bin/env python3
"""Rysuje ikonę Vincent-Media (launcher/vincent-media.ico + logo.png): ciemny zaokrąglony kwadrat,
monogram V w gradiencie fiolet → cyjan i łuk radaru (GameRadar). Użycie: python3 tools/make-icon.py"""
import math, pathlib
from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / 'obs-game-overlay' / 'launcher'
S = 1024  # rysujemy duże, potem zmniejszamy (gładkie krawędzie)
A, B = (124, 92, 255), (0, 225, 255)

def grad(size):
    g = Image.new('RGB', (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            t = max(0.0, min(1.0, (x * 0.55 + (size - y) * 0.45) / size))
            px[x, y] = tuple(round(A[i] + (B[i] - A[i]) * t) for i in range(3))
    return g

def draw():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # tło: zaokrąglony kwadrat z lekkim gradientem
    bg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    m = Image.new('L', (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([40, 40, S - 40, S - 40], radius=220, fill=255)
    base = Image.new('RGBA', (S, S))
    bd = ImageDraw.Draw(base)
    for y in range(S):
        c = round(20 - 8 * y / S)
        bd.line([(0, y), (S, y)], fill=(c, c - 2 if c > 2 else 0, c + 10, 255))
    bg.paste(base, (0, 0), m)
    img = Image.alpha_composite(img, bg)
    # gradientowy obrys tła
    ring = Image.new('L', (S, S), 0)
    rd = ImageDraw.Draw(ring)
    rd.rounded_rectangle([40, 40, S - 40, S - 40], radius=220, outline=255, width=14)
    g = grad(S).convert('RGBA'); g.putalpha(ring.point(lambda v: v * 0.55))
    img = Image.alpha_composite(img, g)
    # łuki radaru za literą
    arcs = Image.new('L', (S, S), 0)
    ad = ImageDraw.Draw(arcs)
    cx, cy = S // 2, 760
    for r, w, a in [(250, 22, 150), (370, 18, 95), (490, 14, 55)]:
        ad.arc([cx - r, cy - r, cx + r, cy + r], start=205, end=335, fill=a, width=w)
    g2 = grad(S).convert('RGBA'); g2.putalpha(arcs)
    img = Image.alpha_composite(img, g2)
    # monogram V: dwie grube kreski ze ściętymi końcami
    vm = Image.new('L', (S, S), 0)
    vd = ImageDraw.Draw(vm)
    top, bot, half, w = 250, 790, 270, 120
    vd.polygon([(S/2 - half - w/2, top), (S/2 - half + w/2, top), (S/2 + w*0.42, bot - 70), (S/2, bot), (S/2 - w*0.42, bot - 70)], fill=255)
    vd.polygon([(S/2 + half - w/2, top), (S/2 + half + w/2, top), (S/2 + w*0.42, bot - 70), (S/2, bot), (S/2 - w*0.42, bot - 70)], fill=255)
    glow = vm.filter(ImageFilter.GaussianBlur(40)).point(lambda v: v * 0.6)
    gg = grad(S).convert('RGBA'); gg.putalpha(glow)
    img = Image.alpha_composite(img, gg)
    gv = grad(S).convert('RGBA'); gv.putalpha(vm)
    img = Image.alpha_composite(img, gv)
    # kropka „celu” radaru w ostrzu V
    dot = Image.new('L', (S, S), 0)
    ImageDraw.Draw(dot).ellipse([S/2 - 34, 640 - 34, S/2 + 34, 640 + 34], fill=255)
    img = Image.alpha_composite(img, Image.merge('RGBA', (Image.new('L', (S, S), 255),) * 3 + (dot.point(lambda v: v * 0.9),)))
    return img

if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    im = draw()
    im.resize((256, 256), Image.LANCZOS).save(OUT / 'vincent-media.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    im.resize((160, 160), Image.LANCZOS).save(OUT / 'logo.png')
    print('ok', OUT)
