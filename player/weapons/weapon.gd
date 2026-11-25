class_name Weapon
extends Node3D
## Classe base per tutto ciò che il player può tenere in una mano (spada, scudo, bastone...).
##
## Come in Dark Souls ogni mano ha la sua arma e qualsiasi arma va in qualsiasi mano:
## il Viewmodel (player/viewmodel.gd) istanzia le armi di ogni mano, inoltra l'input e,
## se un'arma sta nella mano opposta a quella per cui è modellata ("native_hand"), la specchia
## (scala X = -1): modello e animazioni restano gli stessi, solo riflessi.
##
## Ogni arma è una scena a sé: la radice ha uno script che estende Weapon, dentro ci sono il
## modello e un AnimationPlayer (chiamato "AnimationPlayer") con le sue animazioni.
## L'arma non legge mai Input direttamente: riceve le chiamate qui sotto dal Viewmodel.
##
## Animazioni riconosciute dalla base (tutte opzionali):
##   "RESET"    posa di riposo (serve all'editor)
##   "equip"    estrazione; se manca "unequip", viene riprodotta al contrario per riporre l'arma
##   "unequip"  riposizione

enum Hand { RIGHT, LEFT }

## Nome mostrato nell'interfaccia.
@export var display_name := "Arma"
## Effetto sonoro quando si estrae l'arma (vedi audio/sfx.gd); vuoto = nessuno.
@export var equip_sound := &""
## Mano per cui è modellata e animata. Nell'altra mano viene specchiata.
@export var native_hand := Hand.RIGHT
## Tipo d'arma (es. &"sword", &"shield", &"staff"): serve a riconoscere le sinergie tra le mani
## (vedi player/weapons/synergies.gd).
@export var kind := &""

## Il player che impugna l'arma (lo imposta il Viewmodel).
var player: CharacterBody3D
## In che mano è adesso (lo imposta il Viewmodel).
var hand := Hand.RIGHT
## Le sinergie tra le due mani (le imposta il Viewmodel; null se l'arma è usata da sola).
var synergies: Synergies

var _lowered := false
var _lower_tween: Tween

@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")


# --- Da sovrascrivere nelle armi -------------------------------------------

## Il tasto della mano in cui si trova l'arma è stato premuto / rilasciato
## (mano destra = click sinistro / RT, mano sinistra = click destro / LT).
func use_pressed() -> void:
	pass


func use_released() -> void:
	pass


## true se l'arma sa fare parry (F / tasto laterale / RB va a lei).
func can_parry() -> bool:
	return false


func parry_pressed() -> void:
	pass


## Modalità successiva (R / X sul pad): es. cambia incantesimo sul bastone.
func next_mode_pressed() -> void:
	pass


## true mentre l'arma fa un'azione ampia (fendente, colpo critico): l'altra mano si abbassa
## per lasciarle spazio (e uno scudo smette di parare).
func wants_other_hand_lowered() -> bool:
	return false


## true durante un'azione che blocca tutto il resto (es. riposte): l'altra mano non riceve input.
func is_exclusive() -> bool:
	return false


## Informazioni extra per la HUD (vedi player/hud.gd). Chiavi riconosciute:
##   "spell": Spell selezionato, "spells": Array[Spell] disponibili, "ready": 0..1 (ricarica)
func hud_info() -> Dictionary:
	return {}


## false mentre l'arma non vuole essere interrotta (es. a metà di un fendente).
func can_switch() -> bool:
	return true


## Riporta lo stato interno a riposo (chiamato prima di riporre l'arma).
func reset_state() -> void:
	pass


## true quando il player non può essere colpito (es. durante un colpo critico o subito dopo un parry).
func is_invulnerable() -> bool:
	return false


## Il player sta per essere colpito da un attacco che arriva da `source_position`:
## l'arma può pararlo (scudo, parry...). Restituisce un Combat.HitResult.
func defend(_source_position: Vector3) -> Combat.HitResult:
	return Combat.HitResult.HIT


## L'altra mano chiede spazio: l'arma si abbassa (o torna su). Le armi possono reagire
## sovrascrivendo _on_lowered() (es. lo scudo smette di parare).
func set_lowered(lowered: bool) -> void:
	if lowered == _lowered:
		return
	_lowered = lowered
	if _lower_tween:
		_lower_tween.kill()
	_lower_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_lower_tween.tween_property(self, "position", Vector3(0, -0.22, 0.06) if lowered else Vector3.ZERO, 0.12)
	_lower_tween.tween_property(self, "rotation", Vector3(0.35, 0, 0) if lowered else Vector3.ZERO, 0.12)
	_on_lowered(lowered)


func is_lowered() -> bool:
	return _lowered


func _on_lowered(_lowered_now: bool) -> void:
	pass


## +1 nella mano destra, -1 nella sinistra: utile per effetti che partono "dal lato dell'arma".
func side() -> float:
	return 1.0 if hand == Hand.RIGHT else -1.0


# --- Equip / unequip (coroutine: usale con await) --------------------------

func equip() -> void:
	visible = true
	if equip_sound != &"":
		Sfx.play(self, equip_sound, -6.0)
	if anim and anim.has_animation(&"equip"):
		anim.play(&"equip")
		await anim.animation_finished


func unequip() -> void:
	reset_state()
	set_lowered(false)
	if anim and anim.has_animation(&"unequip"):
		anim.play(&"unequip")
		await anim.animation_finished
	elif anim and anim.has_animation(&"equip"):
		anim.play_backwards(&"equip")
		await anim.animation_finished
	visible = false


func _play_from_start(anim_name: StringName) -> void:
	anim.play(anim_name)
	anim.seek(0.0, true)
