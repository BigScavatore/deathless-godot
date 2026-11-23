#!/usr/bin/env python3
"""Genera spada e scudo in prima persona (assets/models/viewmodel.glb), stile low-poly "gritty".

Uso:
    python tools/generate_viewmodel.py                       # scrive assets/models/viewmodel.glb
    python tools/generate_viewmodel.py --preview anteprima.png   # + anteprima dal punto di vista del player

Stile (ispirato a DUSK): pochi poligoni, texture piccole e pixelate (atlas 3x3 da 128 px,
palette posterizzata, ruggine, graffi, vernice scrostata), campionate senza filtro (nearest).
Le texture sono generate qui, in modo deterministico: modifica le funzioni tile_* per cambiarle.

Convenzioni:
  - il modello è nello spazio della camera: la camera sta nell'origine e guarda verso -Z
    (+X = destra, +Y = su), quindi va messo come figlio di Camera3D;
  - nodi: Viewmodel > SwordArm (> Sword) e ShieldArm (> Shield). I pivot SwordArm/ShieldArm
    sono vicino alla spalla, così si possono animare (fendente, parata) ruotandoli.

Dipendenze: numpy (matplotlib solo per --preview).
"""
import argparse
import json
import math
import struct
import zlib
from pathlib import Path

import numpy as np

from generate_knight import box, cyl, flat_normals, mat_to_quat, node, place, rot_matrix, taper

# ---------------------------------------------------------------------------
# Atlas delle texture
# ---------------------------------------------------------------------------
TILE = 128          # pixel per tile
COLS, ROWS = 3, 3
ATLAS_W, ATLAS_H = COLS * TILE, ROWS * TILE
DENSITY = 150.0     # texel per metro (1 tile = ~0.85 m): pixel grossi e uniformi su tutto il modello
LEVELS = 14         # livelli per canale: palette posterizzata

TILE_NAMES = ["iron", "steel", "leather", "brass", "wood_paint", "rust", "wood"]


def _blocks(rng, cell):
    n = TILE // cell
    return np.kron(rng.random((n, n)), np.ones((cell, cell)))


def _fbm(rng):
    """Rumore a blocchi su 3 scale, valori in [0, 1]."""
    return 0.5 * _blocks(rng, 32) + 0.3 * _blocks(rng, 8) + 0.2 * _blocks(rng, 2)


def _base(rng, color, amount):
    n = _fbm(rng)
    img = np.empty((TILE, TILE, 3))
    img[:] = color
    img *= (1.0 - amount / 2 + amount * n)[..., None]
    return img


def _scratches(img, rng, count, length, delta, angles=(0.0, math.pi)):
    for _ in range(count):
        x, y = rng.random() * TILE, rng.random() * TILE
        a = rng.uniform(*angles)
        for t in range(int(rng.integers(length[0], length[1]))):
            img[int(y + math.sin(a) * t) % TILE, int(x + math.cos(a) * t) % TILE] += delta


def _specks(img, rng, count, delta):
    ys, xs = rng.integers(0, TILE, count), rng.integers(0, TILE, count)
    img[ys, xs] += delta


def _mix(img, mask, color, amount):
    img[mask] = img[mask] * (1.0 - amount) + np.array(color) * amount


def tile_iron(rng):
    img = _base(rng, (0.20, 0.21, 0.24), 0.5)
    img += (rng.random(TILE) * 0.05)[:, None, None]                  # striature orizzontali
    _scratches(img, rng, 45, (8, 30), 0.10)
    _scratches(img, rng, 25, (8, 30), -0.08)
    _mix(img, _fbm(rng) > 0.66, (0.31, 0.16, 0.08), 0.65)             # ruggine
    _specks(img, rng, 80, -0.10)
    return img


def tile_steel(rng):
    img = _base(rng, (0.40, 0.42, 0.45), 0.35)
    img += (rng.random(TILE) * 0.08)[None, :, None]                   # striature lungo la lama
    _scratches(img, rng, 40, (20, 70), 0.10, angles=(1.35, 1.80))
    _scratches(img, rng, 40, (20, 70), -0.12, angles=(1.35, 1.80))
    _mix(img, _fbm(rng) > 0.72, (0.30, 0.13, 0.10), 0.7)              # macchie scure / sangue secco
    _specks(img, rng, 90, -0.12)
    return img


def tile_leather(rng):
    img = _base(rng, (0.21, 0.14, 0.10), 0.5)
    _scratches(img, rng, 70, (6, 18), -0.07)                          # crepe
    for y in (10, 118):                                               # cuciture
        for x in range(0, TILE, 8):
            img[y:y + 2, x:x + 4] = (0.45, 0.38, 0.28)
    _specks(img, rng, 60, 0.08)
    return img


def tile_brass(rng):
    img = _base(rng, (0.45, 0.36, 0.17), 0.4)
    _mix(img, _fbm(rng) > 0.70, (0.22, 0.36, 0.28), 0.6)              # verderame
    _scratches(img, rng, 30, (6, 20), 0.10)
    _specks(img, rng, 60, -0.12)
    return img


def tile_wood_paint(rng):
    img = _base(rng, (0.30, 0.09, 0.08), 0.4)                         # vernice rossa sporca
    n = _fbm(rng)
    grain = 0.5 + 0.5 * np.sin(np.arange(TILE)[None, :] * 0.8 + n * 8.0)
    img *= (0.8 + 0.25 * grain)[..., None]
    for x in range(0, TILE, 32):                                      # giunture tra le assi
        img[:, x:x + 2] = (0.08, 0.05, 0.04)
    chips = _fbm(rng) > 0.64                                          # vernice scrostata: legno a vista
    img[chips] = np.array((0.40, 0.28, 0.17)) * (0.7 + 0.5 * grain[chips])[:, None]
    _scratches(img, rng, 30, (8, 30), 0.08)
    _specks(img, rng, 60, -0.10)
    return img


def tile_wood(rng):
    img = _base(rng, (0.24, 0.17, 0.11), 0.45)
    n = _fbm(rng)
    grain = 0.5 + 0.5 * np.sin(np.arange(TILE)[None, :] * 0.9 + n * 8.0)
    img *= (0.75 + 0.30 * grain)[..., None]
    for x in range(0, TILE, 32):
        img[:, x:x + 2] = (0.06, 0.04, 0.03)
    _scratches(img, rng, 35, (8, 30), 0.07)
    _specks(img, rng, 80, -0.09)
    return img


def tile_rust(rng):
    img = _base(rng, (0.30, 0.16, 0.09), 0.6)
    _mix(img, _fbm(rng) > 0.70, (0.20, 0.18, 0.18), 0.8)              # ferro sotto la ruggine
    _specks(img, rng, 90, 0.10)
    _scratches(img, rng, 15, (6, 20), -0.08)
    return img


TILE_FUNCS = [tile_iron, tile_steel, tile_leather, tile_brass, tile_wood_paint, tile_rust, tile_wood]


def build_atlas():
    rng = np.random.default_rng(1234)
    atlas = np.zeros((ATLAS_H, ATLAS_W, 3), dtype=np.uint8)
    for i, fn in enumerate(TILE_FUNCS):
        img = np.clip(np.round(np.clip(fn(rng), 0, 1) * LEVELS) / LEVELS, 0, 1)
        r, c = divmod(i, COLS)
        atlas[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE] = (img * 255).astype(np.uint8)
    return atlas


def png_bytes(rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def make_uvs(tris, tile_index):
    """UV per triangolo: proiezione piana sull'asse dominante, con densità fissa (DENSITY)."""
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    axis = np.argmax(np.abs(n), axis=1)
    uv = np.zeros((len(tris), 3, 2))
    for ax, (iu, iv) in {0: (2, 1), 1: (0, 2), 2: (0, 1)}.items():
        sel = axis == ax
        if not sel.any():
            continue
        u, v = tris[sel][:, :, iu], tris[sel][:, :, iv]
        uv[sel, :, 0] = (u - u.min()) * DENSITY
        uv[sel, :, 1] = (v - v.min()) * DENSITY
    uv = np.clip(uv, 0.5, TILE - 0.5)
    col, row = tile_index % COLS, tile_index // COLS
    out = np.empty_like(uv)
    out[..., 0] = (col * TILE + uv[..., 0]) / ATLAS_W
    out[..., 1] = (row * TILE + (TILE - uv[..., 1])) / ATLAS_H    # in alto = coordinata mondo più alta
    return out


def jitter(tris, amount, seed):
    """Sposta in modo casuale (ma coerente tra triangoli che condividono un vertice) i vertici: forme "malmesse"."""
    rng = np.random.default_rng(seed)
    cache = {}
    out = tris.copy()
    for i in range(len(tris)):
        for j in range(3):
            key = tuple(np.round(tris[i, j], 4))
            if key not in cache:
                cache[key] = rng.normal(0.0, amount, 3)
            out[i, j] = tris[i, j] + cache[key]
    return out


# ---------------------------------------------------------------------------
# Modello
# ---------------------------------------------------------------------------

# Pivot (vicino alla spalla) e posizione del polso, in spazio camera (+X destra, +Y su, camera guarda -Z)
SWORD_PIVOT = (0.32, -0.36, -0.04)
SWORD_WRIST = (-0.02, 0.08, -0.24)         # relativo al pivot (vicino al corpo: claymore tenuta "in guardia")
SWORD_FOREARM_ROT = (104, 0, 24)
SWORD_ROT = (-44, 0, 4)                    # inclinazione della spada (lama in avanti e verso il centro)

SHIELD_PIVOT = (-0.36, -0.40, -0.04)
SHIELD_POS = (-0.06, 0.22, -0.32)          # centro dello scudo, relativo al pivot
SHIELD_ROT = (6, 40, 14)                   # il retro dello scudo guarda il player, girato verso il centro


def forearm(wrist, rot, seed):
    """Avambraccio corazzato che parte dal polso e va verso la camera (fuori dall'inquadratura)."""
    def part(tris):
        return place(tris, pos=wrist, rot=rot)

    return [
        (part(jitter(cyl(0.050, 0.066, 0.42, seg=6, base=(0, 0.02, 0)), 0.002, seed)), "iron"),
        (part(jitter(cyl(0.060, 0.060, 0.030, seg=6, base=(0, 0.04, 0)), 0.002, seed + 1)), "iron"),  # anello al polso
        (part(cyl(0.066, 0.066, 0.025, seg=6, base=(0, 0.20, 0))), "leather"),  # cinghie
        (part(cyl(0.068, 0.068, 0.025, seg=6, base=(0, 0.31, 0))), "leather"),
    ]


def build_sword():
    # Claymore. Asse dell'impugnatura = +Y, mano all'origine, la lama punta verso +Y.
    # Impugnatura lunga (a due mani), guardia con bracci inclinati verso la lama e terminali a quadrifoglio.
    parts = [
        (jitter(cyl(0.040, 0.034, 0.06, seg=6, base=(0, -0.33, 0)), 0.002, 1), "rust"),    # pomolo
        (cyl(0.022, 0.020, 0.30, seg=6, base=(0, -0.27, 0)), "leather"),                    # impugnatura lunga
        (cyl(0.025, 0.025, 0.02, seg=6, base=(0, -0.16, 0)), "iron"),                       # anello sull'impugnatura
        (box((0.09, 0.034, 0.05), (0, 0.075, 0)), "iron"),                                  # centro guardia
        (box((0.05, 0.05, 0.016), (0, 0.11, 0)), "iron"),                                   # langet
        # pugno
        (box((0.09, 0.085, 0.095), (0, -0.005, 0)), "leather"),
        (box((0.095, 0.022, 0.030), (0, 0.05, -0.045)), "iron"),                            # nocche
        (box((0.026, 0.05, 0.03), (-0.01, 0.048, 0.05)), "leather"),                        # pollice
    ]
    for side, mat in [(1, "rust"), (-1, "iron")]:
        arm_rot = (0, 0, 24 * side)                                                         # bracci verso la lama
        parts.append((place(box((0.15, 0.028, 0.040)), pos=(0.105 * side, 0.105, 0), rot=arm_rot), mat))
        for dx, dy in [(0, 0), (0.022, 0), (0, 0.022), (0.011, 0.011)]:                     # quadrifoglio
            parts.append((box((0.026, 0.026, 0.036), (side * (0.175 + dx), 0.135 + dy, 0)), "iron"))
    # Lama larga e lunga a segmenti con tacche e scheggiature (ogni segmento è convesso)
    segments = [  # (lunghezza, largh. base, largh. cima, spess. base, spess. cima)
        (0.12, 0.080, 0.078, 0.018, 0.017),
        (0.12, 0.074, 0.073, 0.017, 0.016),   # tacca
        (0.12, 0.077, 0.072, 0.016, 0.016),   # sporgenza
        (0.12, 0.068, 0.069, 0.015, 0.015),   # scheggiatura
        (0.12, 0.070, 0.066, 0.015, 0.014),
        (0.12, 0.064, 0.062, 0.014, 0.013),
        (0.12, 0.060, 0.056, 0.013, 0.012),   # tacca
        (0.11, 0.058, 0.050, 0.012, 0.011),
    ]
    y = 0.13
    for i, (length, wb, wt, tb, tt) in enumerate(segments):
        seg = taper((wb, tb), (wt, tt), length, base=(0, y, 0))
        parts.append((jitter(seg, 0.0012, 10 + i), "steel"))
        y += length
    tip = place(taper((0.050, 0.011), (0.0, 0.0), 0.12), pos=(0, y, 0), rot=(0, 0, 4))  # punta storta
    parts.append((tip, "steel"))
    return node("Sword", pos=SWORD_WRIST, rot=SWORD_ROT, parts=parts)


def build_shield():
    # Centro dello scudo all'origine. La faccia (con umbone e fasce) guarda -Z, cioe' lontano dal player:
    # dalla camera si vede il RETRO (+Z): assi di legno, traverse, maniglia di ferro e il pugno che la stringe.
    s = 0.0235  # sporgenza degli elementi sulla faccia
    parts = [
        # corpo (vernice rossa scrostata sul davanti)
        (box((0.40, 0.26, 0.035), (0, 0, 0)), "wood_paint"),
        (taper((0.06, 0.035), (0.40, 0.035), 0.30, base=(0, -0.43, 0)), "wood_paint"),
        # bordo in ferro
        (box((0.43, 0.032, 0.05), (0, 0.131, 0)), "iron"),
        (box((0.03, 0.26, 0.05), (0.205, 0, 0)), "iron"),
        (box((0.03, 0.26, 0.05), (-0.205, 0, 0)), "rust"),
        (place(box((0.03, 0.345, 0.05)), pos=(0.1175, -0.28, 0), rot=(0, 0, -29.5)), "iron"),
        (place(box((0.03, 0.345, 0.05)), pos=(-0.1175, -0.28, 0), rot=(0, 0, 29.5)), "rust"),
        # davanti: fasce e umbone
        (box((0.40, 0.045, 0.012), (0, 0.0, -s)), "iron"),
        (box((0.045, 0.56, 0.012), (0, -0.15, -s)), "iron"),
        (place(cyl(0.075, 0.030, 0.07, seg=8), pos=(0, 0.0, -0.03), rot=(-90, 0, 0)), "rust"),
        (place(cyl(0.090, 0.090, 0.012, seg=8), pos=(0, 0.0, -0.025), rot=(-90, 0, 0)), "iron"),
        # retro: assi di legno grezzo, traverse, maniglia
        (box((0.39, 0.25, 0.006), (0, 0, 0.0185)), "wood"),
        (taper((0.058, 0.006), (0.39, 0.006), 0.30, base=(0, -0.43, 0.0185)), "wood"),
        (box((0.36, 0.05, 0.022), (0, 0.07, 0.034)), "wood"),
        (box((0.05, 0.40, 0.022), (0, -0.10, 0.034)), "wood"),
        (box((0.15, 0.026, 0.026), (0, -0.02, 0.066)), "iron"),
        (box((0.03, 0.07, 0.012), (0.08, -0.02, 0.050)), "iron"),
        (box((0.03, 0.07, 0.012), (-0.08, -0.02, 0.050)), "iron"),
    ]
    for rx, ry in [(0.17, 0.0), (-0.17, 0.0), (0.0, 0.10), (0.0, -0.25)]:      # borchie davanti
        parts.append((box((0.022, 0.022, 0.014), (rx, ry, -0.032)), "brass"))
    parts = [(jitter(t, 0.003, 100 + i), m) for i, (t, m) in enumerate(parts)]
    # pugno che stringe la maniglia + avambraccio (si muovono insieme allo scudo)
    parts += [
        (box((0.105, 0.078, 0.05), (0, -0.02, 0.098)), "leather"),              # dita
        (box((0.105, 0.02, 0.022), (0, 0.02, 0.118)), "iron"),                  # nocche
        (box((0.085, 0.07, 0.06), (0, -0.05, 0.14)), "leather"),                # palmo
    ]
    parts += forearm((0, -0.05, 0.15), (104, 0, 0), 60)
    return node("Shield", pos=SHIELD_POS, rot=SHIELD_ROT, parts=parts)


def build_viewmodel():
    sword_arm = node(
        "SwordArm", pos=SWORD_PIVOT,
        parts=forearm(SWORD_WRIST, SWORD_FOREARM_ROT, 50),
        children=[build_sword()],
    )
    shield_arm = node("ShieldArm", pos=SHIELD_PIVOT, children=[build_shield()])
    return node("Viewmodel", children=[sword_arm, shield_arm])


# ---------------------------------------------------------------------------
# Esportazione GLB (un solo materiale con l'atlas, campionamento NEAREST)
# ---------------------------------------------------------------------------

def write_glb(root, path, atlas):
    gltf = {
        "asset": {"version": "2.0", "generator": "deathless tools/generate_viewmodel.py"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [], "meshes": [], "accessors": [], "bufferViews": [], "buffers": [],
        "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
        "images": [], "textures": [{"sampler": 0, "source": 0}],
        "materials": [{
            "name": "viewmodel_atlas",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                "metallicFactor": 0.0, "roughnessFactor": 1.0,
            },
        }],
    }
    blob = bytearray()

    def pad():
        while len(blob) % 4:
            blob.append(0)

    def add_view(data, target=None):
        pad()
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        blob.extend(data)
        gltf["bufferViews"].append(view)
        return len(gltf["bufferViews"]) - 1

    def add_attr(data, kind, bounds=False):
        data = np.ascontiguousarray(data, dtype="<f4")
        acc = {"bufferView": add_view(data.tobytes(), 34962), "componentType": 5126,
               "count": int(len(data)), "type": kind}
        if bounds:
            acc["min"] = [float(v) for v in data.min(axis=0)]
            acc["max"] = [float(v) for v in data.max(axis=0)]
        gltf["accessors"].append(acc)
        return len(gltf["accessors"]) - 1

    gltf["images"].append({"bufferView": add_view(png_bytes(atlas)), "mimeType": "image/png"})

    def add_node(n):
        idx = len(gltf["nodes"])
        g = {"name": n["name"]}
        gltf["nodes"].append(g)
        if any(abs(v) > 1e-9 for v in n["pos"]):
            g["translation"] = [float(v) for v in n["pos"]]
        if any(abs(v) > 1e-9 for v in n["rot"]):
            g["rotation"] = [float(v) for v in mat_to_quat(rot_matrix(*n["rot"]))]
        if n["parts"]:
            tris = np.concatenate([t for t, _ in n["parts"]])
            uvs = np.concatenate([make_uvs(t, TILE_NAMES.index(m)) for t, m in n["parts"]])
            gltf["meshes"].append({"name": n["name"], "primitives": [{
                "attributes": {
                    "POSITION": add_attr(tris.reshape(-1, 3), "VEC3", bounds=True),
                    "NORMAL": add_attr(flat_normals(tris), "VEC3"),
                    "TEXCOORD_0": add_attr(uvs.reshape(-1, 2), "VEC2"),
                },
                "material": 0, "mode": 4,
            }]})
            g["mesh"] = len(gltf["meshes"]) - 1
        kids = [add_node(c) for c in n["children"]]
        if kids:
            g["children"] = kids
        return idx

    add_node(root)
    pad()
    gltf["buffers"].append({"byteLength": len(blob)})

    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * (-len(js) % 4)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    return gltf


# ---------------------------------------------------------------------------
# Anteprima: rasterizzatore minimale con z-buffer e texture, dal punto di vista della camera
# ---------------------------------------------------------------------------

def world_geometry(n, parent_r=None, parent_t=None, out=None):
    if out is None:
        out = []
    parent_r = np.eye(3) if parent_r is None else parent_r
    parent_t = np.zeros(3) if parent_t is None else parent_t
    r = parent_r @ rot_matrix(*n["rot"])
    t = parent_r @ np.array(n["pos"], dtype=float) + parent_t
    for tris, mat in n["parts"]:
        out.append((tris @ r.T + t, make_uvs(tris, TILE_NAMES.index(mat))))
    for c in n["children"]:
        world_geometry(c, r, t, out)
    return out


def rasterize(geo, atlas, width=960, height=540, fov_deg=90.0):
    f = 1.0 / math.tan(math.radians(fov_deg) / 2)
    aspect = width / height
    gy = np.linspace(0.16, 0.05, height)[:, None, None]
    img = np.broadcast_to(np.array([1.0, 0.9, 0.85]) * gy, (height, width, 3)).copy()  # sfondo scuro
    zbuf = np.full((height, width), np.inf)
    light = np.array([-0.3, 0.6, 0.75])
    light /= np.linalg.norm(light)

    for tris, uvs in geo:
        for v, uv in zip(tris, uvs):
            if (v[:, 2] > -0.05).any():
                continue
            nrm = np.cross(v[1] - v[0], v[2] - v[0])
            ln = np.linalg.norm(nrm)
            if ln < 1e-12:
                continue
            nrm /= ln
            if np.dot(nrm, -v[0]) <= 0:      # faccia rivolta via dalla camera
                continue
            d = -v[:, 2]
            px = (v[:, 0] * f / (aspect * d) * 0.5 + 0.5) * width
            py = (0.5 - v[:, 1] * f / d * 0.5) * height
            x0, x1 = max(int(px.min()), 0), min(int(px.max()) + 1, width - 1)
            y0, y1 = max(int(py.min()), 0), min(int(py.max()) + 1, height - 1)
            if x0 > x1 or y0 > y1:
                continue
            den = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
            if abs(den) < 1e-9:
                continue
            X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            w0 = ((py[1] - py[2]) * (X - px[2]) + (px[2] - px[1]) * (Y - py[2])) / den
            w1 = ((py[2] - py[0]) * (X - px[2]) + (px[0] - px[2]) * (Y - py[2])) / den
            w2 = 1.0 - w0 - w1
            inv = w0 / d[0] + w1 / d[1] + w2 / d[2]
            depth = 1.0 / inv
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            mask = (w0 >= 0) & (w1 >= 0) & (w2 >= 0) & (depth < sub)
            if not mask.any():
                continue
            u = (w0 * uv[0, 0] / d[0] + w1 * uv[1, 0] / d[1] + w2 * uv[2, 0] / d[2]) * depth
            vv = (w0 * uv[0, 1] / d[0] + w1 * uv[1, 1] / d[1] + w2 * uv[2, 1] / d[2]) * depth
            ix = np.clip((u * ATLAS_W).astype(int), 0, ATLAS_W - 1)
            iy = np.clip((vv * ATLAS_H).astype(int), 0, ATLAS_H - 1)
            shade = 0.30 + 0.70 * max(float(np.dot(nrm, light)), 0.0)
            colors = atlas[iy, ix] / 255.0 * shade
            sub[mask] = depth[mask]
            region = img[y0:y1 + 1, x0:x1 + 1]
            region[mask] = colors[mask]
    return img


def render_preview(root, atlas, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    view = rasterize(world_geometry(root), atlas)
    fig, axes = plt.subplots(1, 2, figsize=(14, 4.6), gridspec_kw={"width_ratios": [3, 1.35]},
                             facecolor="#15161a")
    axes[0].imshow(np.clip(view, 0, 1), interpolation="nearest")
    axes[0].set_title("Vista del player (FOV 90, 16:9)", color="#ccd")
    axes[0].plot([480], [270], "+", color="#ffffff", alpha=0.5, ms=10)
    axes[1].imshow(atlas, interpolation="nearest")
    axes[1].set_title("Atlas texture (128 px per tile)", color="#ccd")
    for ax in axes:
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=110, facecolor=fig.get_facecolor())
    plt.close(fig)


def main():
    repo_root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(repo_root / "assets" / "models" / "viewmodel.glb"))
    ap.add_argument("--preview", help="percorso PNG per l'anteprima dal punto di vista del player")
    args = ap.parse_args()

    root = build_viewmodel()
    atlas = build_atlas()
    gltf = write_glb(root, args.out, atlas)
    n_tris = sum(len(t) for t, _ in world_geometry(root))
    print(f"Scritto {args.out}")
    print(f"  triangoli: {n_tris} | nodi: {len(gltf['nodes'])} | atlas: {ATLAS_W}x{ATLAS_H}")
    if args.preview:
        render_preview(root, atlas, args.preview)
        print(f"Anteprima: {args.preview}")


if __name__ == "__main__":
    main()
