#!/usr/bin/env python3
"""Genera la mappa del tutorial (maps/tutorial.map) in formato Valve 220 per TrenchBroom.

Uso:
    python tools/generate_tutorial_map.py                      # scrive maps/tutorial.map
    python tools/generate_tutorial_map.py --preview pianta.png # + pianta e profilo della mappa

È un punto di partenza: la mappa si apre e si modifica in TrenchBroom come qualsiasi altra
(rigenerarla qui sovrascrive le modifiche fatte a mano, quindi dopo averla ritoccata in
TrenchBroom non rilanciare questo script, o salvala con un altro nome).

Castello in rovina, un percorso dritto lungo +X con una prova per ogni meccanica e le
spiegazioni scritte sui muri e sul pavimento (entità info_text):
    cortile d'ingresso -> salto -> fossato (salto + scatto) -> crollo (scivolata) ->
    pozzo (salto dal muro) -> mura (schianto e salto potenziato) -> arena (fendente) ->
    sala del parry (parata, parry, riposte, pugnalata) -> armeria (mani, bastone, sinergie) ->
    cortile finale (tre cavalieri).

Coordinate: si progetta in metri (X avanti, Y a sinistra, Z in alto, come Quake) e si scrive in
unità di Quake (32 unità = 1 m). Texture: textures/castle/*.png (tools/generate_textures.py).
"""
import argparse
from pathlib import Path

U = 32  # unità per metro

WALL = "castle/stone_wall"
MOSS = "castle/stone_wall_moss"
FLOOR = "castle/stone_floor"
COBBLE = "castle/cobble"
DIRT = "castle/dirt"
GRASS = "castle/grass"
TRIM = "castle/trim"
WOOD = "castle/wood_planks"
BEAM = "castle/wood_beam"
IRON = "castle/iron"
BARS = "castle/iron_bars"
PLASTER = "castle/plaster"
BANNER = "castle/banner"
CLIP = "clip"

brushes = []   # (mins, maxs, {faccia: texture})
entities = []  # dizionari di proprietà


def box(x0, y0, z0, x1, y1, z1, tex=WALL, top=None, bottom=None):
    """Brush a forma di scatola, in metri. `top`/`bottom`: texture diverse per la faccia sopra/sotto."""
    lo = (min(x0, x1), min(y0, y1), min(z0, z1))
    hi = (max(x0, x1), max(y0, y1), max(z0, z1))
    faces = {k: tex for k in ("-x", "+x", "-y", "+y", "-z", "+z")}
    if top:
        faces["+z"] = top
    if bottom:
        faces["-z"] = bottom
    brushes.append((lo, hi, faces))


def ent(classname, x, y, z, **props):
    e = {"classname": classname, "origin": f"{round(x * U)} {round(y * U)} {round(z * U)}"}
    for k, v in props.items():
        e[k] = str(v)
    entities.append(e)


def text(x, y, z, message, angle, size=64, pitch=0, color=None):
    """Scritta. `angle`: direzione verso chi legge (0 = +X, 90 = +Y, 180 = -X, 270 = -Y)."""
    props = {"message": message, "angle": angle, "size": size, "pitch": pitch}
    if color:
        props["color"] = color
    ent("info_text", x, y, z, **props)


def torch(x, y, z, **props):
    ent("light_torch", x, y, z, **props)


def knight(x, y, angle=180, respawn=0):
    """Cavaliere. `angle`: dove guarda (180 = verso l'inizio della mappa)."""
    ent("monster_knight", x, y, 0.05, angle=angle, respawn=respawn)


def seal(x0, x1, y_abs0, y_abs1, z0=-6.0, z1=12.0):
    """Chiude su entrambi i lati i buchi tra sezioni di larghezza diversa."""
    box(x0, y_abs0, z0, x1, y_abs1, z1, top=TRIM)
    box(x0, -y_abs1, z0, x1, -y_abs0, z1, top=TRIM)


def side_walls(x0, x1, half_w, floor_z=0.0, heights=(8.0, 10.5), seg=4.0, tex=WALL, thick=1.0, seed=0):
    """Muri laterali in rovina: segmenti di altezza diversa (sembrano crollati in alto)."""
    import random
    r = random.Random(seed)
    x = x0
    while x < x1 - 0.01:
        nx = min(x + seg, x1)
        for side in (-1, 1):
            h = r.uniform(*heights)
            y_in = side * half_w
            y_out = side * (half_w + thick)
            box(x, y_in, floor_z, nx, y_out, floor_z + h, tex if r.random() > 0.3 else MOSS, top=TRIM)
        x = nx


def gate_wall(x, half_w, door_w=4.0, door_h=5.0, height=10.0, thick=1.0, floor_z=0.0, bars=False):
    """Muro trasversale con un passaggio al centro (largo door_w, alto door_h)."""
    hw = door_w / 2
    box(x, -half_w - 1, floor_z, x + thick, -hw, floor_z + height, top=TRIM)
    box(x, hw, floor_z, x + thick, half_w + 1, floor_z + height, top=TRIM)
    box(x, -hw, floor_z + door_h, x + thick, hw, floor_z + height, tex=WALL, bottom=TRIM)
    # architrave di legno
    box(x - 0.2, -hw - 0.3, floor_z + door_h - 0.4, x + thick + 0.2, hw + 0.3, floor_z + door_h, tex=BEAM)
    if bars:  # grata sollevata sopra il passaggio
        box(x + 0.4, -hw, floor_z + door_h, x + 0.6, hw, floor_z + door_h + 1.5, tex=BARS)


def banner(x, y, z, side, length=2.8, width=1.2):
    """Stendardo appeso a un muro laterale (side = +1 muro a sinistra, -1 a destra)."""
    y0 = side * 0.02
    box(x - width / 2, y + y0, z - length, x + width / 2, y + y0 - side * 0.08, z, tex=BANNER)


def build():
    # ------------------------------------------------------------------
    # Terreno sotto tutto (erba/terra) e limiti invisibili (clip) attorno alla mappa
    # ------------------------------------------------------------------
    X0, X1, Y0, Y1 = -10.0, 262.0, -26.0, 26.0
    box(X0, Y0, -8, X1, Y1, -6, tex=DIRT, top=GRASS)               # fondo (sotto il fossato)
    for (a, b, c, d) in [(X0 - 1, Y0, X0, Y1), (X1, Y0, X1 + 1, Y1), (X0, Y0 - 1, X1, Y0), (X0, Y1, X1, Y1 + 1)]:
        box(a, b, -8, c, d, 18, tex=CLIP)
    box(X0, Y0, 18, X1, Y1, 19, tex=CLIP)                          # soffitto invisibile

    # ------------------------------------------------------------------
    # 0. Cortile d'ingresso (x 0..16)
    # ------------------------------------------------------------------
    hw = 7.0
    box(-2, -hw - 1, -1, 16, hw + 1, 0, tex=COBBLE, top=COBBLE)
    box(-3, -hw - 1, 0, -2, hw + 1, 10, top=TRIM)                  # muro alle spalle
    side_walls(-2, 16, hw, seed=1)
    ent("info_player_start", 1.5, 0, 0.1, angle=0)
    text(6, hw - 0.05, 3.2, "DEATHLESS", 270, size=150, color="220 170 90")
    text(6, hw - 0.05, 2.2, "WASD per muoverti  ·  mouse per guardare", 270, size=56)
    text(10, -hw + 0.05, 2.6, "ESC: pausa e impostazioni", 90, size=48)
    torch(3, hw - 0.4, 3.2)
    torch(3, -hw + 0.4, 3.2)
    torch(13, hw - 0.4, 3.2)
    torch(13, -hw + 0.4, 3.2)
    banner(9.5, hw, 7.5, 1)
    banner(9.5, -hw, 7.5, -1)
    gate_wall(16, hw, bars=True)

    # ------------------------------------------------------------------
    # 1. Salto: muretti crollati (x 17..34)
    # ------------------------------------------------------------------
    hw = 5.0
    box(17, -hw - 1, -1, 34, hw + 1, 0, tex=FLOOR, top=FLOOR)
    side_walls(17, 34, hw, seed=2)
    for x, h in ((21, 1.1), (26, 1.4), (30.5, 1.7)):
        box(x, -hw, 0, x + 1.0, hw, h, tex=WALL, top=TRIM)
    text(19.5, 0, 0.03, "SPAZIO: salta", 180, size=72, pitch=-90)
    torch(24, hw - 0.4, 3.0)
    torch(24, -hw + 0.4, 3.0)
    torch(32.5, hw - 0.4, 3.0)

    # ------------------------------------------------------------------
    # 2. Fossato: troppo largo per un salto, serve lo scatto a mezz'aria (x 34..58)
    # ------------------------------------------------------------------
    box(34, -hw - 1, -1, 36, hw + 1, 0, tex=FLOOR, top=TRIM)       # bordo di partenza
    box(52, -hw - 1, -1, 58, hw + 1, 0, tex=FLOOR, top=FLOOR)      # bordo d'arrivo
    box(36, -hw - 1, -6, 52, hw + 1, -5, tex=DIRT, top=DIRT)       # fondo del fossato (-5 m)
    box(36, -hw - 1, -5, 52, -hw, 0, tex=MOSS)                     # pareti del fossato
    box(36, hw, -5, 52, hw + 1, 0, tex=MOSS)
    box(36, -hw, -5, 36.01, hw, -1, tex=MOSS)
    box(51.99, -hw, -5, 52, hw, -1, tex=MOSS)
    for i in range(5):                                             # scala per risalire e riprovare
        z = -5 + (i + 1) * 0.9
        box(36 + i * 1.2, hw - 1.6, -5, 37.2 + i * 1.2, hw, z, tex=WALL, top=FLOOR)
    box(36, hw - 1.6, -0.5, 36 + 6.0, hw, 0, tex=WALL, top=FLOOR)
    side_walls(34, 58, hw, seed=3)
    text(34.6, 0, 0.03, "SALTA, poi SHIFT a mezz'aria: SCATTO", 180, size=64, pitch=-90)
    text(41, -hw + 0.05, 3.0, "Lo scatto ha 3 cariche|si ricaricano da sole", 90, size=52)
    text(44, hw - 0.05, -2.5, "Caduto? La scala riporta su.", 270, size=44)
    torch(35, hw - 0.4, 3.2)
    torch(35, -hw + 0.4, 3.2)
    torch(55, hw - 0.4, 3.2)
    torch(55, -hw + 0.4, 3.2)
    torch(44, 0, -4.4, range=7.0, energy=1.0, color="140 170 255", flame=0)
    gate_wall(58, hw)

    # ------------------------------------------------------------------
    # 3. Crollo: passaggio basso, si passa solo scivolando (x 59..76)
    # ------------------------------------------------------------------
    hw = 3.0
    box(59, -hw - 1, -1, 76, hw + 1, 0, tex=FLOOR, top=FLOOR)
    side_walls(59, 76, hw, seed=4)
    box(63, -hw, 1.2, 71, hw, 7.5, tex=WALL, bottom=BEAM)          # muro crollato sopra il passaggio
    for x in (63.2, 66.5, 69.8):                                   # travi spezzate
        box(x, -hw, 1.0, x + 0.6, hw, 1.2, tex=BEAM)
    text(61.5, 0, 0.03, "CTRL a terra: SCIVOLA|(tienilo premuto)", 180, size=60, pitch=-90)
    torch(61, hw - 0.4, 3.0)
    torch(61, -hw + 0.4, 3.0)
    torch(73, hw - 0.4, 3.0)
    gate_wall(76, hw, door_w=3.0)

    # ------------------------------------------------------------------
    # 4. Pozzo: si sale saltando da un muro all'altro (x 77..85, sporgenza a 6 m)
    # ------------------------------------------------------------------
    hw = 1.8
    box(77, -hw - 1, -1, 85, hw + 1, 0, tex=FLOOR, top=FLOOR)
    box(77, -hw - 1, 0, 85, -hw, 13, tex=MOSS, top=TRIM)           # pareti alte del pozzo
    box(77, hw, 0, 85, hw + 1, 13, tex=MOSS, top=TRIM)
    box(85, -hw - 1, 0, 101, hw + 1, 6, tex=WALL, top=FLOOR)       # la sporgenza in cima (6 m)
    seal(84, 85, hw + 1, 7)                                        # niente buchi ai lati del pozzo
    text(80, hw - 0.05, 2.4, "SPAZIO contro un muro:|SALTO DAL MURO", 270, size=56)
    text(80, -hw + 0.05, 2.4, "rimbalza da un muro|all'altro (3 volte)", 90, size=48)
    torch(78, hw - 0.3, 4.0)
    torch(84, -hw + 0.3, 9.0)

    # ------------------------------------------------------------------
    # 5. Mura: dall'alto si salta giù col CTRL (schianto), poi si risale col salto potenziato
    # ------------------------------------------------------------------
    hw = 6.0
    side_walls(85, 101, hw, floor_z=6.0, heights=(3.0, 5.0), seed=5)
    box(85, -hw, 0, 101, -1.8 - 1, 6, tex=WALL)                    # riempie sotto il camminamento
    box(85, 1.8 + 1, 0, 101, hw, 6, tex=WALL)
    box(85, -hw, 5.99, 101, hw, 6, tex=FLOOR)
    seal(100, 101, 6, 11)
    text(97, 0, 6.03, "In aria CTRL: SCHIANTO|(colpisce chi è vicino)", 180, size=64, pitch=-90)
    torch(92, hw - 0.4, 8.5)
    torch(92, -hw + 0.4, 8.5)
    # cortile basso
    box(101, -10, -1, 121, 10, 0, tex=COBBLE, top=COBBLE)
    side_walls(101, 121, 10, seed=6)
    box(110, -10, 0, 121, 10, 5.5, tex=WALL, top=FLOOR)           # bastione da raggiungere (5,5 m)
    text(107.5, 0, 0.03, "Subito dopo lo schianto: SPAZIO|SALTO POTENZIATO", 180, size=64, pitch=-90)
    text(109.95, 4, 3.0, "Troppo alto? Salta, CTRL in aria,|poi subito SPAZIO", 180, size=46)
    torch(104, 9.6, 3.5)
    torch(104, -9.6, 3.5)
    torch(118, 9.6, 8.0)
    torch(118, -9.6, 8.0)
    banner(104, 10, 8.0, 1)
    banner(104, -10, 8.0, -1)
    # camminamento e scale verso l'arena
    box(121, -4, 0, 127, 4, 5.5, tex=WALL, top=FLOOR)
    for i in range(6):
        z = 5.5 - (i + 1) * 0.9
        box(127 + i * 1.0, -4, 0, 128 + i * 1.0, 4, max(z, 0.01), tex=WALL, top=FLOOR)
    side_walls(121, 133, 4, seed=7)
    seal(121, 122, 5, 11)
    seal(132, 133, 5, 11)

    # ------------------------------------------------------------------
    # 6. Arena: il primo cavaliere (x 133..157)
    # ------------------------------------------------------------------
    hw = 10.0
    box(133, -hw - 1, -1, 157, hw + 1, 0, tex=FLOOR, top=FLOOR)
    side_walls(133, 157, hw, seed=8)
    for x, y in ((140, 6), (150, -6)):                             # colonne spezzate
        box(x, y - 0.8, 0, x + 1.6, y + 0.8, 4.5, tex=WALL, top=TRIM)
    text(137, hw - 0.05, 2.6, "CLICK SINISTRO: FENDENTE|colpi di fila: dritto e rovescio", 270, size=56)
    knight(150, 0)
    torch(136, hw - 0.4, 3.5)
    torch(136, -hw + 0.4, 3.5)
    torch(154, hw - 0.4, 3.5)
    torch(154, -hw + 0.4, 3.5)
    banner(145, hw, 8.0, 1)
    banner(145, -hw, 8.0, -1)
    gate_wall(157, hw)

    # ------------------------------------------------------------------
    # 7. Sala del parry (x 158..184)
    # ------------------------------------------------------------------
    box(158, -hw - 1, -1, 184, hw + 1, 0, tex=FLOOR, top=FLOOR)
    side_walls(158, 184, hw, tex=PLASTER, seed=9)
    text(162, hw - 0.05, 3.0, "CLICK DESTRO tenuto: PARATA", 270, size=56)
    text(162, -hw + 0.05, 3.0, "F quando il cavaliere lampeggia di giallo: PARRY", 90, size=52)
    text(170, 0, 0.03, "Dopo un parry, attacca: RIPOSTE|Alle sue spalle: PUGNALATA", 180, size=64, pitch=-90)
    knight(178, 0)
    torch(160, hw - 0.4, 3.5)
    torch(160, -hw + 0.4, 3.5)
    torch(181, hw - 0.4, 3.5)
    torch(181, -hw + 0.4, 3.5)
    gate_wall(184, hw)

    # ------------------------------------------------------------------
    # 8. Armeria: due mani, bastone e sinergie (x 185..211), cavaliere che ricompare
    # ------------------------------------------------------------------
    box(185, -hw - 1, -1, 211, hw + 1, 0, tex=WOOD, top=WOOD)
    side_walls(185, 211, hw, seed=10)
    for x in (190, 198, 206):                                     # rastrelliere (travi)
        box(x, hw - 1.2, 0, x + 2.5, hw - 0.6, 2.2, tex=BEAM)
    text(189, hw - 0.05, 3.4, "E / Q: cambia l'arma della mano DESTRA / SINISTRA", 270, size=52)
    text(189, hw - 0.05, 2.6, "ogni arma va in qualsiasi mano", 270, size=44)
    text(189, -hw + 0.05, 3.4, "BASTONE: il click della sua mano lancia|R: cambia incantesimo", 90, size=52)
    text(199, 0, 0.03, "Due armi insieme hanno una SINERGIA:|provale tutte", 180, size=60, pitch=-90)
    knight(206, 0, respawn=1)
    torch(188, hw - 0.4, 3.5)
    torch(188, -hw + 0.4, 3.5)
    torch(208, hw - 0.4, 3.5)
    torch(208, -hw + 0.4, 3.5)
    banner(198, hw, 8.0, 1)
    banner(198, -hw, 8.0, -1)
    gate_wall(211, hw, bars=True)
    seal(211, 212, 11, 15)

    # ------------------------------------------------------------------
    # 9. Cortile finale: tre cavalieri (x 212..250), poi l'uscita
    # ------------------------------------------------------------------
    hw = 14.0
    box(212, -hw - 1, -1, 250, hw + 1, 0, tex=COBBLE, top=COBBLE)
    side_walls(212, 250, hw, heights=(9.0, 12.0), seed=11)
    for x, y in ((222, 7), (222, -7), (238, 0)):                  # rovine
        box(x, y - 1.2, 0, x + 2.4, y + 1.2, 3.0, tex=WALL, top=TRIM)
    text(214.5, 0, 0.03, "SOPRAVVIVI", 180, size=110, pitch=-90, color="210 60 40")
    knight(232, 6)
    knight(236, -7)
    knight(244, 0)
    for x in (216, 230, 246):
        torch(x, hw - 0.4, 4.0)
        torch(x, -hw + 0.4, 4.0)
    banner(231, hw, 9.0, 1)
    banner(231, -hw, 9.0, -1)
    gate_wall(250, hw)
    box(251, -4, -1, 260, 4, 0, tex=FLOOR, top=FLOOR)
    side_walls(251, 260, 4, seed=12)
    box(260, -5, 0, 261, 5, 10, top=TRIM)
    text(259.9, 0, 2.6, "Fine del tutorial|ESC: impostazioni", 180, size=60, color="220 170 90")
    torch(255, 3.6, 3.2)
    torch(255, -3.6, 3.2)


# ---------------------------------------------------------------------------
# Scrittura del file .map (Valve 220)
# ---------------------------------------------------------------------------

def face_lines(lo, hi, faces):
    x0, y0, z0 = (round(v * U) for v in lo)
    x1, y1, z1 = (round(v * U) for v in hi)
    out = []

    def f(p1, p2, p3, tex, u, v):
        pts = " ".join(f"( {a} {b} {c} )" for a, b, c in (p1, p2, p3))
        out.append(f"{pts} {tex} [ {u} 0 ] [ {v} 0 ] 0 1 1")

    f((x0, y0, z0), (x0, y0 + 1, z0), (x0, y0, z0 + 1), faces["-x"], "0 -1 0", "0 0 -1")
    f((x0, y0, z0), (x0, y0, z0 + 1), (x0 + 1, y0, z0), faces["-y"], "1 0 0", "0 0 -1")
    f((x0, y0, z0), (x0 + 1, y0, z0), (x0, y0 + 1, z0), faces["-z"], "-1 0 0", "0 -1 0")
    f((x1, y1, z1), (x1, y1 + 1, z1), (x1 + 1, y1, z1), faces["+z"], "1 0 0", "0 -1 0")
    f((x1, y1, z1), (x1 + 1, y1, z1), (x1, y1, z1 + 1), faces["+y"], "-1 0 0", "0 0 -1")
    f((x1, y1, z1), (x1, y1, z1 + 1), (x1, y1 + 1, z1), faces["+x"], "0 1 0", "0 0 -1")
    return out


def write_map(path):
    lines = ["// Game: Deathless", "// Format: Valve", "// generato da tools/generate_tutorial_map.py", "// entity 0",
             "{", '"classname" "worldspawn"', '"mapversion" "220"', '"message" "Tutorial - castello in rovina"']
    for i, (lo, hi, faces) in enumerate(brushes):
        if any(round(a * U) >= round(b * U) for a, b in zip(lo, hi)):
            continue  # brush vuoto (spessore zero dopo l'arrotondamento)
        lines += [f"// brush {i}", "{"] + face_lines(lo, hi, faces) + ["}"]
    lines.append("}")
    n = 1
    for e in entities:
        if e.get("classname") == "info_text" and not e.get("message"):
            continue
        lines += [f"// entity {n}", "{"] + [f'"{k}" "{v}"' for k, v in e.items()] + ["}"]
        n += 1
    Path(path).write_text("\n".join(lines) + "\n")


def preview(path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Rectangle
    fig, (top, side) = plt.subplots(2, 1, figsize=(22, 9), gridspec_kw={"height_ratios": [2.2, 1]}, facecolor="#141311")
    colors = {WALL: "#6a6660", MOSS: "#5a6a48", FLOOR: "#4a4744", COBBLE: "#55504a", DIRT: "#4a3a2a",
              GRASS: "#2e3a1e", TRIM: "#7a766e", WOOD: "#6a4a2a", BEAM: "#4a3220", BARS: "#222",
              PLASTER: "#8a7a60", BANNER: "#8a1a14", CLIP: "none", IRON: "#333"}
    for lo, hi, faces in sorted(brushes, key=lambda b: b[1][2]):
        if faces["-x"] == CLIP:
            continue
        top.add_patch(Rectangle((lo[0], lo[1]), hi[0] - lo[0], hi[1] - lo[1], fc=colors.get(faces["+z"], "#888"),
                                ec="#000", lw=0.3, alpha=0.9))
        if abs(lo[1]) < 2.5 or (lo[1] < 0 < hi[1]):
            side.add_patch(Rectangle((lo[0], lo[2]), hi[0] - lo[0], hi[2] - lo[2], fc=colors.get(faces["-x"], "#888"),
                                     ec="#000", lw=0.3, alpha=0.85))
    for e in entities:
        x, y, z = (float(v) / U for v in e["origin"].split())
        c = {"info_player_start": "lime", "monster_knight": "red", "light_torch": "orange", "info_text": "white"}[e["classname"]]
        top.plot(x, y, "o", color=c, ms=4 if c != "white" else 2)
        if e["classname"] in ("info_player_start", "monster_knight"):
            side.plot(x, z + 0.9, "o", color=c, ms=5)
    for ax, (ylo, yhi) in ((top, (-27, 27)), (side, (-7, 15))):
        ax.set_xlim(-12, 264)
        ax.set_ylim(ylo, yhi)
        ax.set_aspect("equal")
        ax.set_facecolor("#1d1b18")
        ax.tick_params(colors="#888")
    top.set_title("Pianta (Y in alto = sinistra del player)  ·  verde = inizio, rosso = cavalieri, arancio = torce, bianco = scritte", color="#ccc")
    side.set_title("Profilo lungo il percorso (altezze in metri)", color="#ccc")
    fig.tight_layout()
    fig.savefig(path, dpi=80, facecolor="#141311")


def main():
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(root / "maps" / "tutorial.map"))
    ap.add_argument("--preview")
    args = ap.parse_args()
    build()
    write_map(args.out)
    print(f"Scritto {args.out}: {len(brushes)} brush, {len(entities)} entità")
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
