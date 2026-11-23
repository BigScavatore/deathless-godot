class_name Weapon
extends Node3D
## Classe base per tutto ciò che il player può impugnare (spada e scudo, armi da fuoco, magie...).
##
## Ogni arma è una scena a sé: la radice ha uno script che estende Weapon, dentro ci sono il
## modello e un AnimationPlayer (chiamato "AnimationPlayer") con le sue animazioni.
## Il Viewmodel (player/viewmodel.gd) istanzia le armi, le cambia e inoltra l'input:
## l'arma non legge mai Input direttamente, così la stessa arma funziona anche per altri usi.
##
## Animazioni riconosciute dalla base (tutte opzionali):
##   "RESET"    posa di riposo (serve all'editor)
##   "equip"    estrazione; se manca "unequip", viene riprodotta al contrario per riporre l'arma
##   "unequip"  riposizione

## Nome mostrato nell'interfaccia (futuro HUD / ruota armi).
@export var display_name := "Arma"

## Il player che impugna l'arma (lo imposta il Viewmodel).
var player: CharacterBody3D

@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")


# --- Da sovrascrivere nelle armi -------------------------------------------

## Attacco principale (click sinistro / grilletto destro).
func primary_pressed() -> void:
	pass


func primary_released() -> void:
	pass


## Azione secondaria (click destro / grilletto sinistro): parata, mira, colpo caricato...
func secondary_pressed() -> void:
	pass


func secondary_released() -> void:
	pass


## false mentre l'arma non vuole essere interrotta (es. a metà di un fendente).
func can_switch() -> bool:
	return true


## Riporta lo stato interno a riposo (chiamato prima di riporre l'arma).
func reset_state() -> void:
	pass


## Il player sta per essere colpito da un attacco che arriva da `source_position`:
## l'arma può pararlo (scudo, parry...). Restituisce un Combat.HitResult.
func defend(_source_position: Vector3) -> Combat.HitResult:
	return Combat.HitResult.HIT


# --- Equip / unequip (coroutine: usale con await) --------------------------

func equip() -> void:
	visible = true
	if anim and anim.has_animation(&"equip"):
		anim.play(&"equip")
		await anim.animation_finished


func unequip() -> void:
	reset_state()
	if anim and anim.has_animation(&"unequip"):
		anim.play(&"unequip")
		await anim.animation_finished
	elif anim and anim.has_animation(&"equip"):
		anim.play_backwards(&"equip")
		await anim.animation_finished
	visible = false
