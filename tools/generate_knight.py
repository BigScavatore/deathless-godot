#!/usr/bin/env python3
"""Genera il cavaliere low-poly (assets/models/knight.glb).

Uso:
    python tools/generate_knight.py                      # scrive assets/models/knight.glb
    python tools/generate_knight.py --preview anteprima.png   # + anteprima (serve matplotlib)

Convenzioni:
  - scala: 1 unità = 1 metro, altezza ~1.9 m, piedi a y = 0
  - il cavaliere guarda verso -Z (come il "forward" di Godot)
  - flat shading (ogni triangolo ha le sue normali), colori come materiali PBR
  - il modello è una gerarchia di nodi con i pivot sulle articolazioni
    (Hips > Torso > Head / Arm_R > Elbow_R > Hand_R > Sword, Leg_R > Knee_R, ...),
    quindi si anima ruotando i nodi (AnimationPlayer) senza bisogno di uno skeleton.
    "R" = lato destro del personaggio (+X), "L" = sinistro (-X).

Dipendenze: numpy (matplotlib solo per --preview).
"""
import argparse
import json
import math
import struct
from pathlib import Path

import numpy as np

# ---------------------------------------------------------------------------
# Materiali: nome -> (colore sRGB, metallic, roughness)
# ---------------------------------------------------------------------------
MATERIALS = {
    "steel":      ((0.66, 0.69, 0.75), 0.35, 0.55),
    "steel_dark": ((0.36, 0.39, 0.45), 0.35, 0.60),
    "gold":       ((0.85, 0.68, 0.25), 0.50, 0.45),
    "cloth_red":  ((0.64, 0.10, 0.11), 0.00, 0.90),
    "leather":    ((0.34, 0.22, 0.13), 0.00, 0.85),
    "visor_dark": ((0.04, 0.04, 0.06), 0.00, 0.80),
    "blade":      ((0.84, 0.87, 0.92), 0.45, 0.35),
}

# ---------------------------------------------------------------------------
# Primitive (array di triangoli, shape (N, 3, 3)), tutte con normali verso l'esterno
# ---------------------------------------------------------------------------

def _orient(tris, center=None):
    """Scarta i triangoli degenerati e orienta le normali verso l'esterno (solidi convessi)."""
    tris = np.asarray(tris, dtype=float)
    if center is None:
        center = tris.reshape(-1, 3).mean(axis=0)
    out = []
    for t in tris:
        n = np.cross(t[1] - t[0], t[2] - t[0])
        if np.linalg.norm(n) < 1e-9:
            continue
        if np.dot(n, t.mean(axis=0) - center) < 0:
            t = t[[0, 2, 1]]
        out.append(t)
    return np.array(out)


def taper(bottom, top, h, base=(0.0, 0.0, 0.0)):
    """Tronco di piramide a base rettangolare. bottom/top = (larghezza X, profondità Z)."""
    bx, bz = bottom[0] / 2, bottom[1] / 2
    tx, tz = top[0] / 2, top[1] / 2
    v = np.array(
        [(-bx, 0, -bz), (bx, 0, -bz), (bx, 0, bz), (-bx, 0, bz),
         (-tx, h, -tz), (tx, h, -tz), (tx, h, tz), (-tx, h, tz)],
        dtype=float,
    ) + np.array(base, dtype=float)
    quads = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    tris = []
    for a, b, c, d in quads:
        tris.append([v[a], v[b], v[c]])
        tris.append([v[a], v[c], v[d]])
    return _orient(tris, v.mean(axis=0))


def box(size, center=(0.0, 0.0, 0.0)):
    sx, sy, sz = size
    cx, cy, cz = center
    return taper((sx, sz), (sx, sz), sy, base=(cx, cy - sy / 2, cz))


def cyl(r_bottom, r_top, h, seg=8, base=(0.0, 0.0, 0.0), phase=22.5):
    """Cilindro/cono lungo +Y con `seg` lati. Con phase=22.5 una faccia piatta guarda -Z."""
    ang = [math.radians(phase + i * 360.0 / seg) for i in range(seg)]
    bot = [np.array((r_bottom * math.cos(a), 0.0, r_bottom * math.sin(a))) for a in ang]
    top = [np.array((r_top * math.cos(a), h, r_top * math.sin(a))) for a in ang]
    cb, ct = np.array((0.0, 0.0, 0.0)), np.array((0.0, h, 0.0))
    tris = []
    for i in range(seg):
        j = (i + 1) % seg
        tris.append([bot[i], bot[j], top[j]])
        tris.append([bot[i], top[j], top[i]])
        tris.append([cb, bot[j], bot[i]])
        tris.append([ct, top[i], top[j]])
    arr = np.array(tris) + np.array(base, dtype=float)
    return _orient(arr)


def rot_matrix(rx=0.0, ry=0.0, rz=0.0):
    """Rotazione da angoli di Eulero in gradi, ordine R = Rz * Ry * Rx."""
    a, b, c = map(math.radians, (rx, ry, rz))
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    rx_m = np.array([[1, 0, 0], [0, ca, -sa], [0, sa, ca]])
    ry_m = np.array([[cb, 0, sb], [0, 1, 0], [-sb, 0, cb]])
    rz_m = np.array([[cc, -sc, 0], [sc, cc, 0], [0, 0, 1]])
    return rz_m @ ry_m @ rx_m


def place(tris, pos=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0)):
    """Ruota attorno all'origine della primitiva, poi la sposta in `pos`."""
    return tris @ rot_matrix(*rot).T + np.array(pos, dtype=float)


def mat_to_quat(r):
    """Matrice di rotazione 3x3 -> quaternione glTF [x, y, z, w]."""
    t = r[0, 0] + r[1, 1] + r[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        w, x, y, z = 0.25 * s, (r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = math.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
        w, x, y, z = (r[2, 1] - r[1, 2]) / s, 0.25 * s, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s
    elif r[1, 1] > r[2, 2]:
        s = math.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
        w, x, y, z = (r[0, 2] - r[2, 0]) / s, (r[0, 1] + r[1, 0]) / s, 0.25 * s, (r[1, 2] + r[2, 1]) / s
    else:
        s = math.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
        w, x, y, z = (r[1, 0] - r[0, 1]) / s, (r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, 0.25 * s
    return [x, y, z, w]


# ---------------------------------------------------------------------------
# Modello
# ---------------------------------------------------------------------------

def node(name, pos=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0), parts=None, children=None):
    """Nodo della gerarchia. parts = lista di (triangoli, nome_materiale)."""
    return {"name": name, "pos": pos, "rot": rot, "parts": parts or [], "children": children or []}


HIP_Y = 0.88  # altezza dell'anca da terra


def build_leg(side):
    """side = +1 gamba destra (+X), -1 sinistra (-X)."""
    s = "R" if side > 0 else "L"
    knee = node(
        f"Knee_{s}", pos=(0, -0.41, 0),
        parts=[
            (box((0.11, 0.09, 0.08), (0, 0.0, -0.07)), "steel"),                 # ginocchiera
            (cyl(0.055, 0.07, 0.36, seg=8, base=(0, -0.38, 0)), "steel"),        # schiniere
            (box((0.11, 0.12, 0.27), (0, -0.41, -0.05)), "leather"),             # stivale
            (box((0.10, 0.07, 0.07), (0, -0.44, -0.20)), "steel_dark"),          # punta
        ],
    )
    return node(
        f"Leg_{s}", pos=(0.11 * side, 0, 0),
        parts=[(cyl(0.075, 0.09, 0.40, seg=8, base=(0, -0.40, 0)), "steel_dark")],  # coscia
        children=[knee],
    )


def build_arm(side):
    s = "R" if side > 0 else "L"
    hand_children = []
    if side > 0:
        hand_children.append(build_sword())

    hand = node(
        f"Hand_{s}", pos=(0, -0.27, 0),
        parts=[(box((0.085, 0.11, 0.095), (0, -0.05, 0)), "steel_dark")],      # guanto
        children=hand_children,
    )
    elbow_children = [hand]
    if side < 0:
        elbow_children.append(build_shield())

    elbow = node(
        f"Elbow_{s}", pos=(0, -0.27, 0), rot=(14, 0, 0),
        parts=[
            (box((0.09, 0.09, 0.09), (0, 0, 0)), "steel_dark"),                  # gomitiera
            (cyl(0.048, 0.058, 0.25, seg=8, base=(0, -0.25, 0)), "steel"),       # avambraccio
        ],
        children=elbow_children,
    )
    return node(
        f"Arm_{s}", pos=(0.31 * side, 0.40, 0), rot=(0, 0, 8 * side),
        parts=[
            (taper((0.24, 0.24), (0.12, 0.14), 0.11, base=(0.03 * side, -0.03, 0)), "steel"),  # spallaccio
            (cyl(0.055, 0.065, 0.26, seg=8, base=(0, -0.26, 0)), "steel_dark"),                # braccio
        ],
        children=[elbow],
    )


def build_sword():
    """Spada tenuta nella mano destra: pomolo in alto, lama verso -Y (poi inclinata in avanti)."""
    tip = place(taper((0.05, 0.012), (0.0, 0.0), 0.10), pos=(0, -0.62, 0), rot=(180, 0, 0))
    return node(
        "Sword", pos=(0, -0.05, 0), rot=(25, 0, 0),
        parts=[
            (cyl(0.028, 0.028, 0.04, seg=6, base=(0, 0.05, 0)), "gold"),         # pomolo
            (cyl(0.02, 0.02, 0.14, seg=6, base=(0, -0.09, 0)), "leather"),       # impugnatura
            (box((0.22, 0.03, 0.05), (0, -0.105, 0)), "gold"),                   # guardia
            (box((0.05, 0.50, 0.012), (0, -0.37, 0)), "blade"),                  # lama
            (tip, "blade"),                                                       # punta
        ],
    )


def build_shield():
    """Scudo a goccia legato all'avambraccio sinistro, faccia verso -Z."""
    boss = place(cyl(0.045, 0.045, 0.03, seg=6), pos=(0, 0.03, -0.027), rot=(-90, 0, 0))
    return node(
        "Shield", pos=(-0.08, -0.12, -0.085),
        parts=[
            (box((0.32, 0.20, 0.03), (0, 0.05, 0)), "steel_dark"),
            (taper((0.04, 0.03), (0.32, 0.03), 0.26, base=(0, -0.31, 0)), "steel_dark"),
            (box((0.26, 0.16, 0.012), (0, 0.05, -0.021)), "cloth_red"),
            (taper((0.02, 0.012), (0.26, 0.012), 0.22, base=(0, -0.27, -0.021)), "cloth_red"),
            (boss, "gold"),
        ],
    )


def build_head():
    slit_z = -0.138
    # coda del cimiero: parte dal retro della cupola e ricade all'indietro
    plume_tail = place(taper((0.035, 0.07), (0.015, 0.03), 0.20), pos=(0, 0.33, 0.10), rot=(115, 0, 0))
    return node(
        "Head", pos=(0, 0.48, 0),
        parts=[
            (cyl(0.15, 0.14, 0.26, seg=8, base=(0, 0.0, 0)), "steel"),           # elmo
            (cyl(0.14, 0.0, 0.09, seg=8, base=(0, 0.26, 0)), "steel"),           # cupola
            (box((0.10, 0.022, 0.012), (0, 0.17, slit_z)), "visor_dark"),        # fessura orizzontale
            (box((0.022, 0.16, 0.012), (0, 0.16, slit_z)), "visor_dark"),        # fessura verticale
            (taper((0.04, 0.30), (0.02, 0.22), 0.10, base=(0, 0.30, 0)), "cloth_red"),  # cimiero
            (plume_tail, "cloth_red"),                                            # coda del cimiero
        ],
    )


def build_torso():
    return node(
        "Torso", pos=(0, 0.12, 0),
        parts=[
            (taper((0.30, 0.20), (0.34, 0.22), 0.14), "steel_dark"),                          # addome
            (taper((0.36, 0.24), (0.52, 0.30), 0.32, base=(0, 0.12, 0)), "steel"),            # pettorale
            (box((0.20, 0.30, 0.02), (0, 0.26, -0.145)), "cloth_red"),                        # sopravveste
            (place(box((0.09, 0.09, 0.02)), pos=(0, 0.32, -0.158), rot=(0, 0, 45)), "gold"),  # emblema
            (cyl(0.11, 0.10, 0.07, seg=8, base=(0, 0.44, 0)), "steel_dark"),                  # gorgiera
            (taper((0.46, 0.025), (0.34, 0.025), 0.80, base=(0, -0.30, 0.16)), "cloth_red"),  # mantello
        ],
        children=[build_head(), build_arm(+1), build_arm(-1)],
    )


def build_knight():
    hips = node(
        "Hips", pos=(0, HIP_Y, 0),
        parts=[
            (box((0.34, 0.18, 0.22)), "steel_dark"),                                          # bacino
            (box((0.37, 0.06, 0.25), (0, 0.10, 0)), "leather"),                               # cintura
            (box((0.06, 0.05, 0.02), (0, 0.10, -0.135)), "gold"),                             # fibbia
            (taper((0.44, 0.30), (0.34, 0.22), 0.36, base=(0, -0.42, 0)), "cloth_red"),       # gonnellino
        ],
        children=[build_torso(), build_leg(+1), build_leg(-1)],
    )
    return node("Knight", children=[hips])


# ---------------------------------------------------------------------------
# Esportazione GLB (glTF 2.0 binario, scritto a mano: nessuna dipendenza)
# ---------------------------------------------------------------------------

def _srgb_to_linear(c):
    return [float(x) ** 2.2 for x in c]


def flat_normals(tris):
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True)
    return np.repeat(n, 3, axis=0)


def write_glb(root, path):
    gltf = {
        "asset": {"version": "2.0", "generator": "deathless tools/generate_knight.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [], "meshes": [], "materials": [],
        "accessors": [], "bufferViews": [], "buffers": [],
    }
    mat_index = {}
    for name, (color, metallic, rough) in MATERIALS.items():
        mat_index[name] = len(gltf["materials"])
        gltf["materials"].append({
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": _srgb_to_linear(color) + [1.0],
                "metallicFactor": metallic,
                "roughnessFactor": rough,
            },
        })

    blob = bytearray()

    def add_vec3(data, with_bounds=False):
        data = np.ascontiguousarray(data, dtype="<f4")
        while len(blob) % 4:
            blob.append(0)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": data.nbytes, "target": 34962}
        blob.extend(data.tobytes())
        gltf["bufferViews"].append(view)
        acc = {"bufferView": len(gltf["bufferViews"]) - 1, "componentType": 5126,
               "count": int(len(data)), "type": "VEC3"}
        if with_bounds:
            acc["min"] = [float(v) for v in data.min(axis=0)]
            acc["max"] = [float(v) for v in data.max(axis=0)]
        gltf["accessors"].append(acc)
        return len(gltf["accessors"]) - 1

    def add_node(n):
        idx = len(gltf["nodes"])
        g = {"name": n["name"]}
        gltf["nodes"].append(g)
        if any(abs(v) > 1e-9 for v in n["pos"]):
            g["translation"] = [float(v) for v in n["pos"]]
        if any(abs(v) > 1e-9 for v in n["rot"]):
            g["rotation"] = [float(v) for v in mat_to_quat(rot_matrix(*n["rot"]))]

        if n["parts"]:
            by_mat = {}
            for tris, mat in n["parts"]:
                by_mat.setdefault(mat, []).append(tris)
            prims = []
            for mat, lst in by_mat.items():
                tris = np.concatenate(lst, axis=0)
                prims.append({
                    "attributes": {
                        "POSITION": add_vec3(tris.reshape(-1, 3), with_bounds=True),
                        "NORMAL": add_vec3(flat_normals(tris)),
                    },
                    "material": mat_index[mat],
                    "mode": 4,
                })
            gltf["meshes"].append({"name": n["name"], "primitives": prims})
            g["mesh"] = len(gltf["meshes"]) - 1

        kids = [add_node(c) for c in n["children"]]
        if kids:
            g["children"] = kids
        return idx

    add_node(root)
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"].append({"byteLength": len(blob)})

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(blob)

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(bytes(blob))
    return gltf


# ---------------------------------------------------------------------------
# Anteprima (opzionale)
# ---------------------------------------------------------------------------

def world_triangles(n, parent_r=None, parent_t=None, out=None):
    if out is None:
        out = []
    parent_r = np.eye(3) if parent_r is None else parent_r
    parent_t = np.zeros(3) if parent_t is None else parent_t
    r = parent_r @ rot_matrix(*n["rot"])
    t = parent_r @ np.array(n["pos"], dtype=float) + parent_t
    for tris, mat in n["parts"]:
        out.append((tris @ r.T + t, mat))
    for c in n["children"]:
        world_triangles(c, r, t, out)
    return out


def render_preview(root, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection

    parts = world_triangles(root)
    light = np.array([-0.3, 0.6, -0.75])
    light /= np.linalg.norm(light)
    views = [("Fronte", 0), ("3/4", 40), ("Lato", 90), ("Retro", 180)]

    fig, axes = plt.subplots(1, len(views), figsize=(4 * len(views), 6.4), facecolor="#dfe6ee")
    for ax, (title, yaw) in zip(axes, views):
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        ry = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        polys, colors, depths = [], [], []
        for tris, mat in parts:
            tv = tris @ ry.T
            n = np.cross(tv[:, 1] - tv[:, 0], tv[:, 2] - tv[:, 0])
            n /= np.linalg.norm(n, axis=1, keepdims=True)
            base = np.array(MATERIALS[mat][0])
            for tri, nn in zip(tv, n):
                if nn[2] >= 0:  # faccia rivolta via dalla camera (camera su -Z)
                    continue
                shade = 0.30 + 0.70 * max(float(np.dot(nn, light)), 0.0)
                polys.append([(-p[0], p[1]) for p in tri])
                colors.append(tuple(np.clip(base * shade, 0, 1)))
                depths.append(tri[:, 2].mean())
        order = np.argsort(depths)[::-1]  # dal più lontano al più vicino
        pc = PolyCollection([polys[i] for i in order], facecolors=[colors[i] for i in order],
                            edgecolors=[colors[i] for i in order], linewidths=0.4)
        ax.add_collection(pc)
        ax.set_xlim(-0.9, 0.9)
        ax.set_ylim(-0.05, 2.05)
        ax.set_aspect("equal")
        ax.axhline(0, color="#7b8794", lw=1)
        ax.set_title(title)
        ax.axis("off")
        ax.set_title(title, color="#33404d")
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def main():
    repo_root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(repo_root / "assets" / "models" / "knight.glb"))
    ap.add_argument("--preview", help="percorso PNG per un'anteprima a 4 viste (richiede matplotlib)")
    args = ap.parse_args()

    root = build_knight()
    gltf = write_glb(root, args.out)
    tris = np.concatenate([t.reshape(-1, 3) for t, _ in world_triangles(root)])
    n_tris = sum(len(t) for t, _ in world_triangles(root))
    lo, hi = tris.min(axis=0), tris.max(axis=0)
    print(f"Scritto {args.out}")
    print(f"  triangoli: {n_tris} | nodi: {len(gltf['nodes'])} | materiali: {len(gltf['materials'])}")
    print(f"  altezza: {hi[1] - lo[1]:.2f} m (y {lo[1]:.2f} .. {hi[1]:.2f}) | larghezza: {hi[0] - lo[0]:.2f} m")
    if args.preview:
        render_preview(root, args.preview)
        print(f"Anteprima: {args.preview}")


if __name__ == "__main__":
    main()
