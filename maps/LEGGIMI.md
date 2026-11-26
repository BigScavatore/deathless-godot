# Mappe con TrenchBroom

I livelli si disegnano in [TrenchBroom](https://trenchbroom.github.io/) e in Godot vengono caricati
dal plugin **func_godot** (in `addons/func_godot`, già attivo nel progetto).

| File | Cosa è |
|---|---|
| `maps/tutorial.map` | la mappa del tutorial (si apre in TrenchBroom) |
| `levels/tutorial.tscn` | la scena del livello: nodo `Map` (FuncGodotMap) + ambiente + navigazione |
| `maps/deathless_fgd.tres` | le entità del gioco che compaiono in TrenchBroom |
| `maps/deathless_map_settings.tres` | come func_godot costruisce la mappa (scala, texture, materiale) |
| `maps/deathless_trenchbroom.tres` | la configurazione di gioco da esportare per TrenchBroom |
| `textures/castle/*.png` | le texture (generate da `tools/generate_textures.py`) |

## Prima volta: collegare TrenchBroom

1. Installa TrenchBroom e aprilo una volta (crea la sua cartella delle impostazioni).
2. In Godot apri `addons/func_godot/func_godot_local_config.tres` e nell'ispettore imposta:
   - **Trenchbroom Game Config Folder**: la cartella dei giochi di TrenchBroom più `Deathless`, per esempio
     su Windows `C:/Users/<tuo nome>/AppData/Roaming/TrenchBroom/games/Deathless`
   - **Map Editor Game Path**: la cartella di questo progetto (quella con `project.godot`)

   poi premi **Export func_godot settings**.
3. Apri `maps/deathless_trenchbroom.tres` e premi **Export GameConfig**.
4. In TrenchBroom: *File → Preferences → Deathless* e come **Game Path** scegli la cartella del progetto.
5. *File → Open* → `maps/tutorial.map`.

## Lavorare su una mappa

- Salva in TrenchBroom, poi in Godot premi Play: se il nodo `Map` della scena è vuoto, la mappa
  viene costruita all'avvio del gioco.
- Per vederla nell'editor di Godot: apri `levels/tutorial.tscn`, seleziona `Map` e premi
  **Build Map** nell'ispettore (salva la scena per tenerla costruita; premi **Clear Map** per tornare
  alla costruzione all'avvio).
- Scala: 32 unità di TrenchBroom = 1 metro. Il player è alto 1,8 m (circa 58 unità), salta circa 2 m.

## Entità del gioco

| Entità | Cosa fa | Proprietà |
|---|---|---|
| `info_player_start` | dove parte il player (la freccia indica dove guarda) | `angle` |
| `monster_knight` | un cavaliere nemico | `angle`, `respawn` (0/1), `respawn_delay` |
| `info_text` | scritta nel mondo; la freccia punta verso chi legge | `message` (`\|` = a capo), `size`, `color` (r g b), `pitch` (0 = sul muro, -90 = sul pavimento) |
| `light_torch` | luce calda che tremola, con fiamma | `color`, `energy`, `range`, `flicker`, `flame`, `shadows` |

Più le entità di base di func_godot: `func_detail` (geometria che non blocca la visibilità),
`func_illusionary` (senza collisioni), ecc. Le texture `clip` (collisione invisibile) e `skip`
(faccia non disegnata) stanno in `textures/`.

Per aggiungere un'entità nuova: una voce in `maps/deathless_fgd.tres` (una scena da istanziare o una
classe + script con `_func_godot_apply_properties(properties)`), poi di nuovo **Export GameConfig**.

## Rigenerare

- Texture: `python tools/generate_textures.py`
- Tutorial: `python tools/generate_tutorial_map.py` (**sovrascrive** `maps/tutorial.map`: dopo averla
  modificata in TrenchBroom non rilanciarlo, o scrivi su un altro file con `--out`).
