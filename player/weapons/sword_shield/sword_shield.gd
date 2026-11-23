extends Weapon
## Spada e scudo: click sinistro = fendente, click destro (tenuto) = parata con lo scudo.
## Le pose sono nell'AnimationPlayer della scena: modificale dall'editor (pannello Animazione).

## Emesso nel momento in cui il fendente deve colpire (chiave "method" nell'animazione "slash").
## Qui andrà collegato il calcolo del danno (ShapeCast3D / query fisica davanti al player).
signal slash_hit

## Durante la parata: utile al futuro sistema di danno per ridurre i colpi frontali.
var is_blocking := false

var _wants_block := false
var _attack_queued := false


func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)


func primary_pressed() -> void:
	if is_blocking:
		return
	if _is_slashing():
		_attack_queued = true  # input buffer: il prossimo fendente parte appena finisce questo
	else:
		_slash()


func secondary_pressed() -> void:
	_wants_block = true
	if not _is_slashing():
		_start_block()


func secondary_released() -> void:
	_wants_block = false
	if is_blocking:
		is_blocking = false
		anim.play_backwards(&"block")


func can_switch() -> bool:
	return not _is_slashing()


func reset_state() -> void:
	is_blocking = false
	_wants_block = false
	_attack_queued = false


func _slash() -> void:
	anim.play(&"slash")
	anim.seek(0.0, true)


func _start_block() -> void:
	is_blocking = true
	anim.play(&"block")


func _is_slashing() -> bool:
	return anim.is_playing() and anim.current_animation == &"slash"


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != &"slash":
		return
	if _attack_queued and not _wants_block:
		_attack_queued = false
		_slash()
	elif _wants_block:
		_attack_queued = false
		_start_block()


# Chiamato dall'animazione "slash" (traccia metodo) nel frame dell'impatto.
func _on_slash_hit() -> void:
	slash_hit.emit()
