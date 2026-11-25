extends Weapon
## Brocchiero. Funziona in entrambe le mani (modellato per la sinistra; nella destra è specchiato).
##   tasto della mano (tenuto) = parata frontale: il danno è ridotto
##   F / tasto laterale / RB   = parry: un colpo di brocchiero in avanti. Se un attacco arriva
##                               entro "parry_window" secondi, nessun danno e il nemico resta stordito
##                               (poi con la spada: riposte). Se lo sbagli, c'è un piccolo cooldown.
## Se l'altra mano fa un fendente, lo scudo si abbassa e smette di parare finché non torna su.

signal parried

## Secondi dopo la pressione di "parry" in cui un colpo viene parato con parry.
@export var parry_window := 0.25
## Tempo minimo tra due parry (così non si può premere a raffica).
@export var parry_cooldown := 0.5
## Dopo un parry riuscito il player è invincibile per questo tempo (secondi),
## così un altro nemico non lo colpisce durante il colpo di brocchiero o la riposte.
@export var parry_invulnerability := 0.6
## Angolo (dal centro della visuale) entro cui il brocchiero protegge.
@export var block_angle_deg := 75.0

## Durante la parata.
var is_blocking := false

var _wants_block := false
var _parry_until := 0
var _parry_ready_at := 0
var _invulnerable_until := 0


func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)


func use_pressed() -> void:
	_wants_block = true
	if not _is_parrying() and not is_lowered():
		_start_block()


func use_released() -> void:
	_wants_block = false
	if is_blocking:
		is_blocking = false
		if not _is_parrying():
			anim.play(&"unblock")


func can_parry() -> bool:
	return true


func parry_pressed() -> void:
	var now := Time.get_ticks_msec()
	if now < _parry_ready_at or is_lowered():
		return
	_parry_until = now + int(parry_window * 1000.0)
	_parry_ready_at = now + int(parry_cooldown * 1000.0)
	_play_from_start(&"parry")
	Sfx.play(self, &"parry_whiff", -8.0)


## Respinge i proiettili amici (sinergia "Specchio arcano"): col parry più forte che con la parata.
func reflect_strength(source_position: Vector3) -> float:
	if not _is_frontal(source_position) or is_lowered():
		return 0.0
	if Time.get_ticks_msec() <= _parry_until:
		_play_from_start(&"parry_hit")
		return 1.8
	if is_blocking:
		_play_from_start(&"block_hit")
		return 1.35
	return 0.0


func is_invulnerable() -> bool:
	return Time.get_ticks_msec() < _invulnerable_until


func reset_state() -> void:
	is_blocking = false
	_wants_block = false
	_parry_until = 0


func defend(source_position: Vector3) -> Combat.HitResult:
	if not _is_frontal(source_position):
		return Combat.HitResult.HIT
	if Time.get_ticks_msec() <= _parry_until:
		_parry_until = 0
		_parry_ready_at = 0  # parry riuscito: puoi subito pararne un altro
		_invulnerable_until = Time.get_ticks_msec() + int(parry_invulnerability * 1000.0)
		parried.emit()
		Sfx.play(self, &"parry", 0.0, 0.05)
		_play_from_start(&"parry_hit")
		return Combat.HitResult.PARRIED
	if is_blocking:
		_play_from_start(&"block_hit")
		Sfx.play(self, &"block", 0.0)
		return Combat.HitResult.BLOCKED
	return Combat.HitResult.HIT


## L'altra mano attacca: lo scudo scende e non para; quando torna su, se il tasto è ancora tenuto, para di nuovo.
func _on_lowered(lowered_now: bool) -> void:
	if lowered_now:
		if is_blocking:
			is_blocking = false
			anim.play(&"unblock")
	elif _wants_block and not _is_parrying():
		_start_block()


func _start_block() -> void:
	is_blocking = true
	anim.play(&"block")


func _is_parrying() -> bool:
	return anim.is_playing() and (anim.current_animation == &"parry" or anim.current_animation == &"parry_hit")


func _is_frontal(source_position: Vector3) -> bool:
	var to_source := source_position - player.global_position
	var forward := -player.global_basis.z
	to_source.y = 0.0
	forward.y = 0.0
	if to_source.length_squared() < 0.0001:
		return true
	return forward.normalized().dot(to_source.normalized()) >= cos(deg_to_rad(block_angle_deg))


func _on_animation_finished(anim_name: StringName) -> void:
	match anim_name:
		&"parry", &"parry_hit":
			# Dopo il colpo di brocchiero torna in parata se il tasto è ancora tenuto.
			if _wants_block and not is_lowered():
				_start_block()
			else:
				is_blocking = false
