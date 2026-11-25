class_name Spell
extends Resource
## Un incantesimo lanciabile dal bastone (player/weapons/staff/staff.gd).
##
## Per crearne uno nuovo: uno script che estende Spell e sovrascrive cast(), poi lo si aggiunge
## alla lista "spells" del bastone. Gli incantesimi si sbloccano nel gioco con Staff.unlock_spell(id)
## (es. da un oggetto raccolto); quelli in "unlocked" del bastone sono già disponibili all'inizio.
##
## L'icona per la HUD è pixel art scritta a mano: righe di caratteri, uno per pixel
##   "." trasparente, "a" contorno scuro, "b" colore base, "c" chiaro, "d" riflesso (quasi bianco)
## Le tonalità vengono da "color".

## Identificativo usato per sbloccarlo (es. &"magic_shard").
@export var id := &""
@export var display_name := "Incantesimo"
@export_multiline var description := ""
@export var mana_cost := 10.0
## Secondi tra due lanci (tenendo premuto si lancia di continuo a questo ritmo).
@export var cooldown := 0.3
## Colore della magia: cristallo del bastone, HUD, proiettili.
@export var color := Color(0.6, 0.45, 1.0)
## Suono del lancio (vedi audio/sfx.gd); vuoto = nessuno.
@export var cast_sound := &""
## Scossone della camera al lancio (0..1).
@export var cast_shake := 0.18
@export var icon := PackedStringArray()


## Lancia l'incantesimo. `aim`: origine = punto da cui parte, -Z = direzione (verso il mirino).
## `caster`: chi lancia (non viene colpito dai suoi incantesimi).
func cast(_caster: Node3D, _aim: Transform3D) -> void:
	pass


## Colori dell'icona per i caratteri a/b/c/d.
func icon_palette() -> Dictionary:
	return {
		"a": color.darkened(0.75),
		"b": color,
		"c": color.lightened(0.45),
		"d": color.lightened(0.85),
	}
