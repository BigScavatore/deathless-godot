#!/usr/bin/env python3
"""Genera le texture del mondo (textures/castle/*.png) per le mappe di TrenchBroom: castello in rovina.

Uso:
    python tools/generate_textures.py                     # scrive textures/castle/*.png
    python tools/generate_textures.py --preview tav.png   # + tavola con tutte le texture

Stile: come le armi (tools/generate_viewmodel.py) ma più grezzo, alla DUSK: 128x128 px, palette
posterizzata, pixel netti (il materiale delle mappe le campiona senza filtro). Tutte le texture si
ripetono senza cuciture (rumore periodico, file e celle che "girano" sui bordi).
In TrenchBroom a scala 1 una texture copre 128 unità = 4 metri (32 unità = 1 m).

Dipendenze: numpy (matplotlib solo per --preview).
"""
import argparse
import struct
import zlib
from pathlib import Path

import numpy as np

N = 128
LEVELS = 12


# ---------------------------------------------------------------------------
# Rumore periodico e utility
# ---------------------------------------------------------------------------

def value_noise(rng, cells):
    """Rumore liscio e periodico: griglia casuale cells x cells interpolata (si ripete sui bordi)."""
    g = rng.random((cells, cells))
    x = np.arange(N) * cells / N
    i0 = np.floor(x).astype(int) % cells
    i1 = (i0 + 1) % cells
    t = x - np.floor(x)
    t = t * t * (3 - 2 * t)
    a = g[i0][:, i0] * (1 - t)[None, :] + g[i0][:, i1] * t[None, :]
    b = g[i1][:, i0] * (1 - t)[None, :] + g[i1][:, i1] * t[None, :]
    return a * (1 - t)[:, None] + b * t[:, None]


def fbm(rng, octaves=((4, 0.5), (8, 0.25), (16, 0.15), (32, 0.1))):
    return sum(value_noise(rng, c) * w for c, w in octaves)


def fill(color):
    img = np.empty((N, N, 3))
    img[:] = color
    return img


def shade(img, amount, noise):
    return img * (1.0 - amount / 2 + amount * noise)[..., None]


def specks(img, rng, count, delta, size=1):
    for _ in range(count):
        y, x = rng.integers(0, N, 2)
        img[y:y + size, x:x + size] += delta
    return img


def cracks(img, rng, count, length, delta):
    for _ in range(count):
        x, y = rng.random(2) * N
        ang = rng.uniform(0, np.pi * 2)
        for _ in range(int(rng.integers(*length))):
            img[int(y) % N, int(x) % N] += delta
            ang += rng.normal(0, 0.5)
            x += np.cos(ang)
            y += np.sin(ang)
    return img


def voronoi(rng, count):
    """Celle di Voronoi periodiche: (indice cella, distanza dal bordo approssimata)."""
    pts = rng.random((count, 2)) * N
    yy, xx = np.mgrid[0:N, 0:N]
    d = np.full((N, N, 2), np.inf)
    idx = np.zeros((N, N), int)
    for k, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, N - dx)
        dy = np.minimum(dy, N - dy)
        dist = np.sqrt(dx * dx + dy * dy)
        closer = dist < d[..., 0]
        d[..., 1] = np.where(closer, d[..., 0], np.minimum(d[..., 1], dist))
        d[..., 0] = np.where(closer, dist, d[..., 0])
        idx = np.where(closer, k, idx)
    return idx, d[..., 1] - d[..., 0]


def blocks_rows(rng, row_h, w_range, offset_rows=True):
    """File di blocchi (mattoni/pietre): restituisce (id blocco, maschera malta)."""
    ids = np.zeros((N, N), int)
    mortar = np.zeros((N, N), bool)
    bid = 0
    for r, y0 in enumerate(range(0, N, row_h)):
        widths = []
        while sum(widths) < N:
            widths.append(int(rng.integers(*w_range)))
        widths[-1] -= sum(widths) - N  # la fila chiude esattamente a N (si ripete)
        x = int(rng.integers(0, N)) if offset_rows else 0
        for w in widths:
            cols = (np.arange(x, x + w)) % N
            ids[y0:y0 + row_h, cols] = bid
            mortar[y0:y0 + row_h, cols[0]] = True
            bid += 1
            x += w
        mortar[y0, :] = True
    return ids, mortar


# ---------------------------------------------------------------------------
# Texture
# ---------------------------------------------------------------------------

def stone_wall(rng, moss=False):
    ids, mortar = blocks_rows(rng, 16, (18, 42))
    tint = rng.random(ids.max() + 1)
    base = np.array((0.36, 0.35, 0.33))
    img = fill(base) * (0.72 + 0.4 * tint[ids])[..., None]
    img = shade(img, 0.5, fbm(rng))
    # bordo dei blocchi più chiaro in alto e più scuro in basso (rilievo)
    top = np.roll(mortar, 1, axis=0) & ~mortar
    bottom = np.roll(mortar, -1, axis=0) & ~mortar
    img[top] *= 1.18
    img[bottom] *= 0.75
    img[mortar] = (0.12, 0.11, 0.1)
    img = cracks(img, rng, 14, (6, 22), -0.12)
    img = specks(img, rng, 120, -0.08)
    if moss:
        m = fbm(rng) + np.linspace(-0.15, 0.25, N)[:, None]   # più muschio in basso
        mask = m > 0.62
        img[mask] = img[mask] * 0.45 + np.array((0.16, 0.24, 0.09)) * 0.75
        img = specks(img, rng, 60, np.array((-0.02, 0.05, -0.02)))
    return img


def stone_floor(rng):
    idx, edge = voronoi(rng, 14)
    tint = rng.random(idx.max() + 1)
    img = fill((0.32, 0.31, 0.29)) * (0.75 + 0.35 * tint[idx])[..., None]
    img = shade(img, 0.45, fbm(rng))
    img[edge < 1.6] = (0.1, 0.095, 0.09)
    img[(edge >= 1.6) & (edge < 2.6)] *= 0.8
    img = cracks(img, rng, 18, (5, 18), -0.1)
    img = specks(img, rng, 150, -0.07)
    return img


def cobble(rng):
    idx, edge = voronoi(rng, 70)
    tint = rng.random(idx.max() + 1)
    img = fill((0.34, 0.32, 0.3)) * (0.7 + 0.45 * tint[idx])[..., None]
    img = shade(img, 0.35, fbm(rng))
    img[edge < 1.5] = (0.13, 0.11, 0.09)
    img[(edge >= 1.5) & (edge < 2.5)] *= 0.78
    hl = (edge > 3.5) & (fbm(rng) > 0.55)
    img[hl] *= 1.1
    return img


def wood_planks(rng):
    img = fill((0.3, 0.2, 0.12))
    plank = np.arange(N) // 16
    tint = rng.random(N // 16)
    img *= (0.75 + 0.4 * tint[plank])[None, :, None]
    grain = value_noise(rng, 64)
    stretch = np.roll(grain, 0, axis=0)
    g = 0.5 + 0.5 * np.sin(np.arange(N)[None, :] * 1.3 + fbm(rng) * 10.0)
    img *= (0.8 + 0.25 * g)[..., None]
    for x in range(0, N, 16):
        img[:, x] = (0.08, 0.05, 0.03)
    # giunture orizzontali sfalsate e chiodi
    for p in range(N // 16):
        y = int(rng.integers(0, N))
        img[y, p * 16:(p + 1) * 16] = (0.1, 0.06, 0.04)
        for yy in ((y + 3) % N, (y - 4) % N):
            img[yy, p * 16 + 3] = (0.5, 0.48, 0.45)
            img[yy, p * 16 + 12] = (0.5, 0.48, 0.45)
    img = cracks(img, rng, 10, (6, 18), -0.06)
    return img


def wood_beam(rng):
    img = fill((0.2, 0.13, 0.08))
    g = 0.5 + 0.5 * np.sin(np.arange(N)[:, None] * 0.9 + fbm(rng) * 12.0)
    img *= (0.75 + 0.35 * g)[..., None]
    img = shade(img, 0.3, fbm(rng))
    img = cracks(img, rng, 12, (10, 40), -0.05)
    return img


def dirt(rng):
    img = fill((0.24, 0.18, 0.12))
    img = shade(img, 0.6, fbm(rng))
    img = specks(img, rng, 220, 0.08)
    img = specks(img, rng, 120, -0.08, 2)
    g = fbm(rng) > 0.6
    img[g] = img[g] * 0.5 + np.array((0.14, 0.19, 0.08)) * 0.6
    return img


def grass(rng):
    img = fill((0.14, 0.18, 0.08))
    img = shade(img, 0.55, fbm(rng))
    for _ in range(500):  # fili d'erba
        x, y = rng.integers(0, N, 2)
        h = int(rng.integers(2, 6))
        c = np.array((0.22, 0.28, 0.12)) * rng.uniform(0.7, 1.3)
        for k in range(h):
            img[(y - k) % N, x] = c
    d = fbm(rng) > 0.68
    img[d] = img[d] * 0.4 + np.array((0.22, 0.17, 0.11)) * 0.6
    return img


def iron(rng):
    img = fill((0.17, 0.17, 0.18))
    img = shade(img, 0.4, fbm(rng))
    r = fbm(rng) > 0.6
    img[r] = img[r] * 0.4 + np.array((0.3, 0.14, 0.07)) * 0.6
    for y in (0, 63, 64, 127):
        img[y, :] = (0.08, 0.08, 0.08)
    for y in (6, 57, 70, 121):  # rivetti
        for x in range(8, N, 24):
            img[y - 1:y + 2, x - 1:x + 2] = (0.28, 0.27, 0.26)
            img[y + 1, x - 1:x + 2] = (0.07, 0.07, 0.07)
    img = cracks(img, rng, 20, (4, 14), 0.06)
    return img


def iron_bars(rng):
    """Grata: sbarre verticali e traverse su fondo nero (per cancelli e finestre)."""
    img = fill((0.02, 0.02, 0.02))
    metal = shade(fill((0.2, 0.19, 0.19)), 0.5, fbm(rng))
    for x in range(8, N, 32):
        img[:, x:x + 6] = metal[:, x:x + 6]
        img[:, x] *= 1.4
    for y in (20, 100):
        img[y:y + 8, :] = metal[y:y + 8, :]
        img[y + 7, :] *= 0.6
    return img


def trim(rng):
    """Fascia di pietra scolpita (cornici, gradini, bordi delle mura)."""
    img = stone_wall(rng) * 0.4 + fill((0.4, 0.38, 0.35)) * 0.6
    img = shade(img, 0.3, fbm(rng))
    for y in (0, 1, 30, 31, 32, 33, 94, 95, 96, 97, 126, 127):
        img[y, :] *= 0.55
    for y in (2, 34, 98):
        img[y, :] *= 1.25
    for x in range(0, N, 16):  # dentelli
        img[40:56, x:x + 8] *= 0.75
        img[40, x:x + 8] *= 1.3
    img = cracks(img, rng, 8, (6, 20), -0.1)
    return img


def plaster(rng):
    """Intonaco scrostato con mattoni a vista."""
    ids, mortar = blocks_rows(rng, 8, (14, 22))
    tint = rng.random(ids.max() + 1)
    brick = fill((0.42, 0.2, 0.14)) * (0.75 + 0.35 * tint[ids])[..., None]
    brick[mortar] = (0.2, 0.17, 0.14)
    img = shade(fill((0.52, 0.48, 0.4)), 0.35, fbm(rng))
    hole = fbm(rng) > 0.58
    img[hole] = brick[hole]
    edge = hole ^ np.roll(hole, 1, axis=0)
    img[edge] *= 0.6
    img = cracks(img, rng, 14, (8, 30), -0.1)
    img = specks(img, rng, 100, -0.06)
    return img


def banner(rng):
    """Stendardo rosso consumato con un emblema dorato (decorazione)."""
    img = shade(fill((0.42, 0.06, 0.05)), 0.5, fbm(rng))
    yy, xx = np.mgrid[0:N, 0:N]
    for x in range(0, N, 4):  # trama del tessuto
        img[:, x] *= 0.92
    ring = np.abs(np.hypot(xx - 64, yy - 58) - 26) < 3
    img[ring] = (0.62, 0.48, 0.18)
    cross = ((np.abs(xx - 64) < 3) & (np.abs(yy - 58) < 20)) | ((np.abs(yy - 58) < 3) & (np.abs(xx - 64) < 20))
    img[cross] = (0.62, 0.48, 0.18)
    img[:6, :] = (0.5, 0.38, 0.15)
    img[-6:, :] = (0.5, 0.38, 0.15)
    torn = fbm(rng) > 0.7
    img[torn & (yy > 100)] = (0.05, 0.02, 0.02)
    return img


TEXTURES = {
    "stone_wall": stone_wall,
    "stone_wall_moss": lambda rng: stone_wall(rng, moss=True),
    "stone_floor": stone_floor,
    "cobble": cobble,
    "wood_planks": wood_planks,
    "wood_beam": wood_beam,
    "dirt": dirt,
    "grass": grass,
    "iron": iron,
    "iron_bars": iron_bars,
    "trim": trim,
    "plaster": plaster,
    "banner": banner,
}


# ---------------------------------------------------------------------------

def png_bytes(rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


## Quanto togliere saturazione (0..1): le tinte casuali delle pietre, posterizzate, virano al rosa/verde.
DESATURATE = {"stone_wall": 0.55, "stone_wall_moss": 0.3, "stone_floor": 0.6, "cobble": 0.6, "trim": 0.55,
              "iron": 0.3, "iron_bars": 0.3}


def finish(img, desaturate=0.0):
    gray = img.mean(axis=2, keepdims=True)
    img = img * (1 - desaturate) + gray * desaturate
    img = np.clip(img, 0, 1)
    img = np.round(img * LEVELS) / LEVELS
    return (img * 255).astype(np.uint8)


def main():
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(root / "textures" / "castle"))
    ap.add_argument("--preview")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    images = {}
    for i, (name, fn) in enumerate(TEXTURES.items()):
        img = finish(fn(np.random.default_rng(500 + i)), DESATURATE.get(name, 0.0))
        images[name] = img
        (out / f"{name}.png").write_bytes(png_bytes(img))
        print(f"{name}.png")
    if args.preview:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        cols = 5
        rows = (len(images) + cols - 1) // cols
        fig, axes = plt.subplots(rows, cols, figsize=(cols * 3, rows * 3.2), facecolor="#151412")
        for ax in axes.ravel():
            ax.axis("off")
        for ax, (name, img) in zip(axes.ravel(), images.items()):
            ax.imshow(np.tile(img, (2, 2, 1)), interpolation="nearest")
            ax.set_title(name, color="#ccc", fontsize=9)
        fig.tight_layout()
        fig.savefig(args.preview, dpi=90, facecolor="#151412")


if __name__ == "__main__":
    main()
