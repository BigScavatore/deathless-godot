#!/usr/bin/env python3
"""Genera gli effetti sonori del gioco (assets/sounds/*.wav), stile "gritty" e sporco.

Uso:
    python tools/generate_sounds.py            # scrive assets/sounds/<nome>_<n>.wav

Tutto è sintetizzato qui, in modo deterministico (stesso seed = stesso suono):
  - metallo: somme di parziali inarmoniche che decadono a velocità diverse (clang, armature);
  - fruscii (fendenti, dash): rumore filtrato con un passa-banda che si sposta nel tempo;
  - tonfi: sinusoidi con frequenza che scende + rumore grave;
  - "carne": rumore passa-basso a grani + risonanza che scende (squelch).
Poi ogni suono passa da dirty(): corpo sulle basse, saturazione morbida, pochi crepitii,
passa-basso ripido e un riverbero scuro da sotterraneo (suono pesante e cupo, non "arcade").
Ogni effetto ha più varianti (_1, _2, ...): il gioco ne sceglie una a caso con un pitch leggermente
diverso, così i suoni ripetuti non stancano. Per cambiarne uno modifica la sua funzione snd_*.

Dipendenze: numpy.
"""
import argparse
import math
import struct
import wave
from pathlib import Path

import numpy as np

SR = 22050  # bassa frequenza di campionamento = suono più "lo-fi"


# ---------------------------------------------------------------------------
# Mattoni di base
# ---------------------------------------------------------------------------

def times(duration):
    return np.arange(int(SR * duration)) / SR


def white(rng, n):
    return rng.uniform(-1.0, 1.0, n)


def env_exp(n, decay, attack=0.002):
    """Inviluppo: attacco lineare breve e decadimento esponenziale (decay = secondi per -60 dB circa / 7)."""
    t = np.arange(n) / SR
    env = np.exp(-t / max(decay, 1e-4))
    a = max(int(attack * SR), 1)
    env[:a] *= np.linspace(0.0, 1.0, a)
    return env


def svf(x, cutoff, q=0.7, mode="band"):
    """Filtro state-variable (Simper/TPT). cutoff può variare nel tempo (array)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    g = np.tan(np.pi * np.clip(cutoff, 20.0, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    out = np.empty_like(x)
    ic1 = ic2 = 0.0
    for i in range(len(x)):
        v3 = x[i] - ic2
        v1 = a1[i] * ic1 + a2[i] * v3
        v2 = ic2 + a2[i] * ic1 + a3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == "low":
            out[i] = v2
        elif mode == "high":
            out[i] = x[i] - k * v1 - v2
        else:
            out[i] = v1
    return out


def metal(rng, duration, base, decay, partials=6, spread=1.0, bright=0.6):
    """Clang metallico: parziali inarmoniche (rapporti tipo barra/piastra) leggermente stonate."""
    t = times(duration)
    ratios = [1.0, 2.32, 4.25, 6.63, 9.38, 12.1, 15.4, 19.2][:partials]
    out = np.zeros_like(t)
    for i, r in enumerate(ratios):
        f = base * (r + rng.uniform(-0.04, 0.04) * spread * r)
        amp = (bright ** i) * rng.uniform(0.6, 1.0)
        d = decay / (1.0 + 0.6 * i)
        phase = rng.uniform(0, 2 * np.pi)
        # coppia di parziali vicinissime: battimenti "storti" tipici del metallo rovinato
        out += amp * np.exp(-t / d) * (np.sin(2 * np.pi * f * t + phase)
                                       + 0.5 * np.sin(2 * np.pi * f * 1.007 * t + phase * 1.3))
    return out


def thud(rng, duration, f_start, f_end, decay):
    """Tonfo: sinusoide con frequenza che scende + un po' di rumore grave."""
    t = times(duration)
    f = f_end + (f_start - f_end) * np.exp(-t / 0.04)
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / decay)
    rumble = svf(white(rng, len(t)), 180.0, 0.8, "low") * np.exp(-t / (decay * 0.6))
    return body + 0.8 * rumble


def whoosh(rng, duration, f_from, f_peak, f_to, q=1.8, peak_at=0.45):
    """Fruscio d'aria: rumore con passa-banda che sale e scende, inviluppo a campana."""
    n = int(SR * duration)
    x = np.linspace(0.0, 1.0, n)
    rise = np.clip(x / peak_at, 0, 1)
    fall = np.clip((x - peak_at) / (1 - peak_at), 0, 1)
    cutoff = np.where(x < peak_at, f_from + (f_peak - f_from) * rise ** 1.5, f_peak + (f_to - f_peak) * fall)
    env = np.where(x < peak_at, rise ** 2, (1 - fall) ** 2.2)
    return svf(white(rng, n), cutoff, q, "band") * env


def grains(rng, duration, count, length=0.012, cutoff=900.0, decay=None):
    """Grani di rumore sparsi (detriti, carne, cotta di maglia)."""
    n = int(SR * duration)
    out = np.zeros(n)
    for _ in range(count):
        start = int(rng.beta(1.2, 3.0) * n) if decay is None else int(rng.exponential(decay) * SR)
        if start >= n:
            continue
        g = int(length * SR * rng.uniform(0.5, 1.5))
        g = min(g, n - start)
        if g <= 2:
            continue
        burst = white(rng, g) * np.hanning(g) * rng.uniform(0.3, 1.0)
        out[start:start + g] += burst
    return svf(out, cutoff, 0.9, "band")


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    m = min(len(src), len(dst) - i)
    if m > 0:
        dst[i:i + m] += src[:m] * gain
    return dst


def follow(x, smooth=0.01):
    """Inviluppo (ampiezza) del segnale, lisciato su "smooth" secondi."""
    n = max(int(smooth * SR), 1)
    return np.convolve(np.abs(x), np.ones(n) / n, mode="same")


def room(x, rng, wet=0.22, decay=0.7):
    """Riverbero scuro da ambiente in pietra: convoluzione con una coda di rumore filtrato
    che decade (-60 dB in "decay" secondi). Allunga il suono della coda."""
    n = int(decay * SR * 1.2)
    t = np.arange(n) / SR
    ir = white(rng, n) * np.exp(-t * 6.9 / decay)
    ir = svf(ir, 800.0, 0.6, "low")
    ir = np.concatenate([np.zeros(int(0.018 * SR)), ir])          # pre-delay: muri vicini
    size = len(x) + len(ir)
    wet_sig = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
    wet_sig *= np.max(np.abs(x)) / (np.max(np.abs(wet_sig)) + 1e-9)
    out = np.concatenate([x, np.zeros(len(ir))]) + wet * wet_sig
    # taglia il silenzio in fondo
    env = follow(out, 0.02)
    last = np.nonzero(env > np.max(env) * 0.001)[0]
    return out[: last[-1] + 1] if len(last) else out


def dirty(x, rng, drive=1.8, crackle=0.002, tone=1900.0, body=0.6, wet=0.22, room_decay=0.7):
    """Il carattere del suono: sporco ma scuro e "fisico", non da sala giochi.
      - corpo: rinforza le frequenze basse (peso, armature pesanti);
      - saturazione morbida (come un nastro/microfono spinto), niente bitcrush;
      - pochi crepitii gravi che seguono l'inviluppo (polvere, non rumore digitale);
      - tono: due passa-basso in serie (24 dB/ottava) che tagliano gli acuti;
      - stanza: riverbero corto e scuro da sotterraneo (wet=0 per i suoni in loop)."""
    x = x / (np.max(np.abs(x)) + 1e-9)
    env = np.clip(follow(x) * 4.0, 0.0, 1.0)
    x = x + body * svf(x, 220.0, 0.7, "low") * 2.0
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(drive * x) / np.tanh(drive)
    pops = (rng.random(len(x)) < crackle) * rng.uniform(-0.2, 0.2, len(x))
    x = x + svf(pops, 700.0, 0.7, "band") * env
    x = svf(svf(x, tone, 0.6, "low"), tone * 1.3, 0.6, "low")
    if wet > 0.0:
        # la parte asciutta sfuma dentro la coda (curva morbida: in dB scende in modo regolare)
        n = min(int(0.18 * SR), int(len(x) * 0.4))
        x[-n:] *= np.linspace(1.0, 0.0, n) ** 3
        x = room(x, rng, wet, room_decay)
    return x


def fade_out(x, duration=0.02):
    n = min(int(duration * SR), len(x))
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


def make_loop(x, fade=0.15):
    """Rende il suono ripetibile senza scatti: la coda sfuma nella testa."""
    f = int(fade * SR)
    body = x[:-f].copy()
    body[:f] = body[:f] * np.linspace(0, 1, f) + x[-f:] * np.linspace(1, 0, f)
    return body


# ---------------------------------------------------------------------------
# Effetti
# ---------------------------------------------------------------------------

def snd_swing(rng):
    """Fendente della claymore: fruscio pesante con un filo di metallo che vibra."""
    x = whoosh(rng, 0.42, 150, rng.uniform(600, 850), 200, q=1.6, peak_at=0.4)
    x += 0.08 * metal(rng, 0.42, rng.uniform(900, 1100), 0.12, partials=3) * np.linspace(0, 1, len(x)) ** 2
    return dirty(fade_out(x), rng, drive=2.0)


def snd_swing_heavy(rng):
    """Fendente del cavaliere: più grave e più lungo."""
    x = whoosh(rng, 0.5, 100, rng.uniform(400, 550), 150, q=1.4, peak_at=0.5)
    x += 0.5 * whoosh(rng, 0.5, 200, 900, 200, q=3.0, peak_at=0.55)
    return dirty(fade_out(x), rng, drive=2.2)


def snd_hit_armor(rng):
    """Lama contro armatura: clang sporco + scricchiolio + tonfo sordo."""
    d = 0.55
    x = 0.9 * metal(rng, d, rng.uniform(180, 280), 0.12, partials=7, bright=0.65)
    crunch = grains(rng, d, 40, length=0.006, cutoff=1400, decay=0.04)
    x += 1.4 * crunch
    x += 0.9 * thud(rng, d, 160, 55, 0.09)
    x[: int(0.004 * SR)] += white(rng, int(0.004 * SR)) * 1.5  # transiente
    return dirty(fade_out(x), rng, drive=4.0)


def snd_block(rng):
    """Colpo parato col brocchiero: legno che rimbomba + ferro smorzato."""
    d = 0.5
    x = 1.2 * thud(rng, d, 220, 80, 0.11)
    x += 0.5 * metal(rng, d, rng.uniform(500, 650), 0.06, partials=5, bright=0.5)
    x += 0.8 * svf(white(rng, int(d * SR)), 600.0, 1.2, "band") * env_exp(int(d * SR), 0.03)
    return dirty(fade_out(x), rng, drive=3.0)


def snd_parry(rng):
    """Parry: clang brillante che risuona a lungo, con una strusciata di lama."""
    d = 1.3
    x = metal(rng, d, rng.uniform(520, 650), 0.45, partials=7, bright=0.65)
    x += 0.4 * metal(rng, d, rng.uniform(1100, 1300), 0.25, partials=4, bright=0.5)
    n = int(d * SR)
    scrape = svf(white(rng, n), np.linspace(2500, 1300, n), 4.0, "band") * env_exp(n, 0.12)
    x += 0.7 * scrape
    x += 0.8 * thud(rng, d, 300, 120, 0.05)
    x[: int(0.003 * SR)] += white(rng, int(0.003 * SR)) * 2.0
    return dirty(fade_out(x, 0.1), rng, drive=3.0)


def snd_parry_whiff(rng):
    """Colpo di brocchiero a vuoto."""
    x = whoosh(rng, 0.25, 150, 600, 200, q=1.2, peak_at=0.35)
    return dirty(fade_out(x), rng, drive=1.8)


def snd_telegraph(rng):
    """Segnale prima del colpo nemico: lama che striscia e brilla (momento del parry)."""
    d = 0.35
    n = int(d * SR)
    scrape = svf(white(rng, n), np.linspace(1300, 3000, n), 6.0, "band")
    env = np.minimum(np.linspace(0, 1, n) * 4, 1) * env_exp(n, 0.12, attack=0.0)
    x = scrape * env + 0.35 * metal(rng, d, rng.uniform(1500, 1800), 0.15, partials=3)
    return dirty(fade_out(x), rng, drive=2.5)


def snd_stab(rng):
    """Riposte / backstab: l'armatura cede, la lama entra nella carne."""
    d = 0.75
    n = int(d * SR)
    x = 0.8 * metal(rng, d, rng.uniform(250, 330), 0.06, partials=6, bright=0.8)  # piastra che cede
    x += 1.2 * grains(rng, d, 60, length=0.008, cutoff=1200, decay=0.05)          # scricchiolio
    wet = svf(white(rng, n), 900 * np.exp(-np.arange(n) / SR / 0.15) + 150, 5.0, "band")
    x += 1.6 * wet * env_exp(n, 0.18, attack=0.01)                                  # squelch
    x += 1.2 * thud(rng, d, 120, 45, 0.15)
    return dirty(fade_out(x, 0.05), rng, drive=4.5)


def snd_stab_out(rng):
    """La lama viene estratta: risucchio umido + metallo che stride."""
    d = 0.6
    n = int(d * SR)
    wet = svf(white(rng, n), 200 + 700 * np.linspace(0, 1, n) ** 2, 6.0, "band") * env_exp(n, 0.2, attack=0.04)
    scrape = svf(white(rng, n), np.linspace(900, 2200, n), 5.0, "band") * np.linspace(0.2, 1.0, n) * env_exp(n, 0.3)
    x = 1.4 * wet + 0.6 * scrape + 0.8 * grains(rng, d, 30, length=0.01, cutoff=700, decay=0.15)
    return dirty(fade_out(x, 0.05), rng, drive=3.5)


def snd_step_armor(rng):
    """Passo del cavaliere: stivale pesante + cotta di maglia che tintinna."""
    d = 0.3
    x = 1.0 * thud(rng, d, 110, 50, 0.05)
    jingle = np.zeros(int(d * SR))
    for _ in range(6):
        place(jingle, metal(rng, 0.12, rng.uniform(1500, 2600), 0.02, partials=3), rng.uniform(0.0, 0.08), rng.uniform(0.1, 0.25))
    x += jingle
    return dirty(fade_out(x), rng, drive=2.5)


def snd_body_fall(rng):
    """Cavaliere che crolla a terra: tonfo enorme e pezzi d'armatura che sbattono."""
    d = 1.1
    x = 1.5 * thud(rng, d, 90, 35, 0.25)
    for _ in range(9):
        place(x, metal(rng, 0.3, rng.uniform(250, 700), 0.05, partials=5, bright=0.7), rng.exponential(0.12), rng.uniform(0.2, 0.6))
    x += 0.8 * grains(rng, d, 50, length=0.01, cutoff=1200, decay=0.2)
    return dirty(fade_out(x, 0.1), rng, drive=2.8, wet=0.28, room_decay=1.0)


def snd_player_hurt(rng):
    """Il player viene colpito: botta sorda e scricchiolio."""
    d = 0.45
    x = 1.4 * thud(rng, d, 140, 40, 0.1)
    x += 0.9 * grains(rng, d, 35, length=0.006, cutoff=1500, decay=0.04)
    x += 0.3 * metal(rng, d, rng.uniform(300, 400), 0.05, partials=4)
    return dirty(fade_out(x), rng, drive=5.0)


def snd_jump(rng):
    x = whoosh(rng, 0.18, 200, 700, 350, q=0.9, peak_at=0.3)
    return dirty(fade_out(x), rng, drive=1.5)


def snd_land(rng):
    d = 0.3
    x = thud(rng, d, 120, 50, 0.06) + 0.6 * grains(rng, d, 20, length=0.006, cutoff=1400, decay=0.03)
    return dirty(fade_out(x), rng, drive=2.5)


def snd_dash(rng):
    x = whoosh(rng, 0.3, 250, rng.uniform(1100, 1400), 450, q=1.0, peak_at=0.2)
    return dirty(fade_out(x), rng, drive=2.0)


def snd_slide_loop(rng):
    """Scivolata: grattata continua su pietra con sassolini (ripetibile)."""
    d = 1.35
    n = int(d * SR)
    base = svf(white(rng, n), 300.0, 0.6, "band") * 0.8
    grit = svf(white(rng, n) * (rng.random(n) < 0.08), 1400.0, 1.0, "band") * 3.0
    wobble = 0.75 + 0.25 * np.sin(2 * np.pi * 3.1 * np.arange(n) / SR)
    x = (base + grit) * wobble + 0.6 * grains(rng, d, 70, length=0.004, cutoff=1600)
    x = make_loop(x)
    return dirty(x, rng, drive=2.0, crackle=0.004, wet=0.0)


def snd_slam_dive(rng):
    x = whoosh(rng, 0.45, 120, 900, 800, q=1.2, peak_at=0.85)
    return dirty(fade_out(x), rng, drive=2.0)


def snd_slam_impact(rng):
    """Atterraggio dello slam: boato, pietra che si spacca, detriti."""
    d = 1.4
    x = 2.0 * thud(rng, d, 80, 28, 0.35)
    x += 1.2 * grains(rng, d, 160, length=0.012, cutoff=900, decay=0.25)
    x += 0.6 * grains(rng, d, 80, length=0.004, cutoff=2000, decay=0.3)
    n = int(d * SR)
    x += 0.8 * svf(white(rng, n), 300.0, 0.7, "low") * env_exp(n, 0.4)
    return dirty(fade_out(x, 0.15), rng, drive=3.0, wet=0.3, room_decay=1.2)


def snd_equip(rng):
    """Si estrae la claymore: lama che striscia nel fodero e un piccolo clang."""
    d = 0.5
    n = int(d * SR)
    scrape = svf(white(rng, n), np.linspace(1000, 2600, n), 5.0, "band") * np.linspace(0.3, 1, n) * env_exp(n, 0.25)
    x = scrape + place(np.zeros(n), metal(rng, 0.3, 800, 0.08, partials=4), 0.32, 0.5)
    return dirty(fade_out(x), rng, drive=2.5)


def snd_gore_burst(rng):
    """Nemico che esplode: schiocco umido, carne che si squarcia, schizzi che ricadono."""
    d = 1.0
    n = int(d * SR)
    t = np.arange(n) / SR
    x = 1.6 * thud(rng, d, 130, 38, 0.12)
    x += 1.2 * svf(white(rng, n), np.linspace(1800, 250, n), 1.2, "low") * env_exp(n, 0.07)
    x += 1.5 * svf(white(rng, n), 650 * np.exp(-t / 0.15) + 140, 8.0, "band") * env_exp(n, 0.25, attack=0.01)
    x += 1.0 * grains(rng, d, 110, length=0.008, cutoff=1000, decay=0.3)
    return dirty(fade_out(x, 0.08), rng, drive=4.0, wet=0.25)


def snd_gib_splat(rng):
    """Pezzo di carne che cade a terra."""
    d = 0.3
    n = int(d * SR)
    x = thud(rng, d, 170, 60, 0.04)
    x += 1.2 * svf(white(rng, n), np.linspace(900, 250, n), 4.0, "band") * env_exp(n, 0.06)
    x += 0.6 * grains(rng, d, 20, length=0.006, cutoff=900, decay=0.05)
    return dirty(fade_out(x), rng, drive=3.0)


SOUNDS = {  # nome: (funzione, varianti)
    "swing": (snd_swing, 3),
    "swing_heavy": (snd_swing_heavy, 2),
    "hit_armor": (snd_hit_armor, 4),
    "block": (snd_block, 3),
    "parry": (snd_parry, 2),
    "parry_whiff": (snd_parry_whiff, 2),
    "telegraph": (snd_telegraph, 2),
    "stab": (snd_stab, 2),
    "stab_out": (snd_stab_out, 2),
    "step_armor": (snd_step_armor, 4),
    "body_fall": (snd_body_fall, 2),
    "player_hurt": (snd_player_hurt, 3),
    "jump": (snd_jump, 2),
    "land": (snd_land, 2),
    "dash": (snd_dash, 2),
    "slide_loop": (snd_slide_loop, 1),
    "slam_dive": (snd_slam_dive, 1),
    "slam_impact": (snd_slam_impact, 2),
    "equip": (snd_equip, 1),
    "gore_burst": (snd_gore_burst, 3),   # in fondo: i seed degli altri suoni non cambiano
    "gib_splat": (snd_gib_splat, 3),
}


def write_wav(path, x, peak=0.35):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = np.clip(x * 32767, -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


def main():
    repo_root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(repo_root / "assets" / "sounds"))
    ap.add_argument("--only", help="genera solo questo effetto (es. parry)")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for index, (name, (fn, variants)) in enumerate(SOUNDS.items()):
        if args.only and name != args.only:
            continue
        for v in range(variants):
            rng = np.random.default_rng(1000 * index + v)
            write_wav(out / f"{name}_{v + 1}.wav", fn(rng))
        print(f"{name}: {variants} varianti")


if __name__ == "__main__":
    main()
