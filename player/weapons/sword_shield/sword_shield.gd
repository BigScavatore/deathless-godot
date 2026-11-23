extends Weapon
## Claymore e scudo.
##   click sinistro          = fendente (colpisce tutto ciò che è nel box davanti alla camera)
##   click destro (tenuto)   = parata frontale: il danno è ridotto
##   click destro AL MOMENTO GIUSTO (entro "parry_window" dal colpo) = parry:
##                             nessun danno e il nemico resta stordito (riposte = danno doppio)
## Le pose sono nell'AnimationPlayer della scena: modificale dall'editor (pannello Animazione).

## Emesso nel frame d'impatto del fendente (chiave "method" nell'animazione "slash").
signal slash_hit
signal parried

@export_group("Slash")
@export var slash_damage := 35.0
## Portata del fendente davanti alla camera (metri).
@export var slash_reach := 2.8
## Larghezza e altezza del box del fendente.
@export var slash_size := Vector2(2.4, 1.6)

@export_group("Block / parry")
## Secondi dopo la pressione di "parata" in cui un colpo viene parato con parry.
@export var parry_window := 0.25
## Angolo (dal centro della visuale) entro cui lo scudo protegge.
@export var block_angle_deg := 75.0

## Durante la parata: il player la usa per ridurre il danno.
var is_blocking := false

var _wants_block := false
var _attack_queued := false
var _block_pressed_at := -100000


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
	_block_pressed_at = Time.get_ticks_msec()
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


func defend(source_position: Vector3) -> Combat.HitResult:
	if not is_blocking or not _is_frontal(source_position):
		return Combat.HitResult.HIT
	if Time.get_ticks_msec() - _block_pressed_at <= int(parry_window * 1000.0):
		_play_from_start(&"parry")
		parried.emit()
		return Combat.HitResult.PARRIED
	_play_from_start(&"block_hit")
	return Combat.HitResult.BLOCKED


func _slash() -> void:
	_play_from_start(&"slash")


func _start_block() -> void:
	is_blocking = true
	anim.play(&"block")


func _play_from_start(anim_name: StringName) -> void:
	anim.play(anim_name)
	anim.seek(0.0, true)


func _is_slashing() -> bool:
	return anim.is_playing() and anim.current_animation == &"slash"


func _is_frontal(source_position: Vector3) -> bool:
	var to_source := source_position - player.global_position
	var forward := -player.global_basis.z
	to_source.y = 0.0
	forward.y = 0.0
	if to_source.length_squared() < 0.0001:
		return true
	return forward.normalized().dot(to_source.normalized()) >= cos(deg_to_rad(block_angle_deg))


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
	var camera := get_viewport().get_camera_3d()
	var box := BoxShape3D.new()
	box.size = Vector3(slash_size.x, slash_size.y, slash_reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	# Box allineato alla camera, che parte dagli occhi e arriva a "slash_reach" metri.
	query.transform = Transform3D(camera.global_basis,
			camera.global_position - camera.global_basis.z * slash_reach * 0.5)
	if player:
		query.exclude = [player.get_rid()]

	var landed := false
	var already_hit := {}
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body: Object = hit.collider
		if already_hit.has(body) or not body.has_method("take_damage"):
			continue
		already_hit[body] = true
		if body.take_damage(slash_damage, player) != Combat.HitResult.IGNORED:
			landed = true

	if landed:
		Combat.hitstop(self, 0.06)
		if player and player.has_method("add_shake"):
			player.add_shake(0.25)
	slash_hit.emit()
