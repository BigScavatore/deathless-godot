extends Weapon
## Claymore e brocchiero.
##   click sinistro            = fendente orizzontale (colpisce ciò che è davanti alla camera)
##   click destro (tenuto)     = parata frontale: il danno è ridotto
##   F / tasto laterale / RB   = parry: un colpo di brocchiero in avanti. Se un attacco arriva
##                               entro "parry_window" secondi, nessun danno e il nemico resta stordito
##                               Se lo sbagli, c'è un piccolo cooldown.
##   colpi critici (stile Dark Souls), sempre col click sinistro:
##     - riposte: davanti a un nemico stordito dal parry -> affondo che lo trafigge
##     - backstab: alle spalle di un nemico -> pugnalata alla schiena
## Le pose sono nell'AnimationPlayer della scena: modificale dall'editor (pannello Animazione).

## Emesso nel frame d'impatto del fendente (chiave "method" nell'animazione "slash").
signal slash_hit
signal parried
signal critical_hit(target: Node3D, kind: StringName)

@export_group("Slash")
@export var slash_damage := 35.0
## Portata del fendente davanti alla camera (metri).
@export var slash_reach := 2.8
## Larghezza e altezza del box del fendente.
@export var slash_size := Vector2(2.6, 1.4)

@export_group("Critical")
@export var riposte_damage := 120.0
@export var backstab_damage := 90.0
## Distanza massima dal nemico stordito per la riposte.
@export var riposte_range := 3.0
## Distanza massima per il backstab.
@export var backstab_range := 2.0
## Quanto il nemico deve essere al centro della visuale (coseno dell'angolo).
@export_range(0.0, 1.0) var critical_aim := 0.6

@export_group("Block / parry")
## Secondi dopo la pressione di "parry" in cui un colpo viene parato con parry.
@export var parry_window := 0.25
## Tempo minimo tra due parry (così non si può premere a raffica).
@export var parry_cooldown := 0.5
## Dopo un parry riuscito il player è invincibile per questo tempo (secondi),
## così un altro nemico non lo colpisce durante il colpo di brocchiero o la riposte.
@export var parry_invulnerability := 0.6
## Angolo (dal centro della visuale) entro cui il brocchiero protegge.
@export var block_angle_deg := 75.0

## Durante la parata: il player la usa per ridurre il danno.
var is_blocking := false

var _wants_block := false
var _attack_queued := false
var _parry_until := 0
var _parry_ready_at := 0
var _invulnerable_until := 0
var _critical_target: Node3D
var _critical_kind := &""


func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)


func primary_pressed() -> void:
	if _is_parrying():
		_attack_queued = true  # riposte subito dopo il parry: parte appena finisce il colpo di brocchiero
		return
	if is_blocking or _is_critical():
		return
	if not _is_slashing():
		var target := _find_critical_target()
		if target:
			_start_critical(target)
			return
	if _is_slashing():
		_attack_queued = true  # input buffer: il prossimo fendente parte appena finisce questo
	else:
		_slash()


func secondary_pressed() -> void:
	_wants_block = true
	if not _is_slashing() and not _is_parrying() and not _is_critical():
		_start_block()


func secondary_released() -> void:
	_wants_block = false
	if is_blocking:
		is_blocking = false
		if not _is_parrying():
			anim.play(&"unblock")


func parry_pressed() -> void:
	var now := Time.get_ticks_msec()
	if now < _parry_ready_at or _is_slashing() or _is_critical():
		return
	_parry_until = now + int(parry_window * 1000.0)
	_parry_ready_at = now + int(parry_cooldown * 1000.0)
	_play_from_start(&"parry")
	Sfx.play(self, &"parry_whiff", -8.0)


## Invincibile durante riposte/backstab e per poco dopo un parry riuscito.
func is_invulnerable() -> bool:
	return _is_critical() or Time.get_ticks_msec() < _invulnerable_until


func can_switch() -> bool:
	return not _is_slashing() and not _is_critical()


func reset_state() -> void:
	_critical_target = null
	is_blocking = false
	_wants_block = false
	_attack_queued = false
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
		return Combat.HitResult.PARRIED
	if is_blocking:
		_play_from_start(&"block_hit")
		Sfx.play(self, &"block", 0.0)
		return Combat.HitResult.BLOCKED
	return Combat.HitResult.HIT


func _slash() -> void:
	_play_from_start(&"slash")
	Sfx.play(self, &"swing", -3.0, 0.1)


func _start_block() -> void:
	is_blocking = true
	anim.play(&"block")


func _play_from_start(anim_name: StringName) -> void:
	anim.play(anim_name)
	anim.seek(0.0, true)


func _is_slashing() -> bool:
	return anim.is_playing() and anim.current_animation == &"slash"


func _is_parrying() -> bool:
	return anim.is_playing() and anim.current_animation == &"parry"


func _is_critical() -> bool:
	return anim.is_playing() and (anim.current_animation == &"riposte" or anim.current_animation == &"backstab")


# --- Colpi critici ---------------------------------------------------------

## Il nemico più vicino davanti alla camera su cui si può fare riposte o backstab.
func _find_critical_target() -> Node3D:
	if player == null:
		return null
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Node3D
	var best_distance := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var target := enemy as Node3D
		if target == null or not target.has_method("can_be_riposted"):
			continue
		var to_target := target.global_position - player.global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance < 0.01 or forward.dot(to_target / distance) < critical_aim:
			continue
		var kind := &""
		if distance <= riposte_range and target.can_be_riposted():
			kind = &"riposte"
		elif distance <= backstab_range and target.can_be_backstabbed(player.global_position):
			kind = &"backstab"
		if kind != &"" and distance < best_distance:
			best = target
			best_distance = distance
			_critical_kind = kind
	return best


func _start_critical(target: Node3D) -> void:
	_critical_target = target
	target.begin_critical(_critical_kind, player)
	_play_from_start(_critical_kind)
	# Il player si mette in posizione (davanti o dietro al nemico) e resta fermo per tutta l'animazione.
	var stand_at: Vector3
	if _critical_kind == &"backstab":
		stand_at = target.global_position + target.global_basis.z.normalized() * 1.15
	else:
		var away := player.global_position - target.global_position
		away.y = 0.0
		stand_at = target.global_position + away.normalized() * 1.3
	if player.has_method("lock_for"):
		player.lock_for(anim.current_animation_length, stand_at, target.global_position)


# Chiamato dalle animazioni "riposte"/"backstab" quando la lama entra.
func _on_critical_hit() -> void:
	if _critical_target == null or not is_instance_valid(_critical_target):
		return
	var damage := backstab_damage if _critical_kind == &"backstab" else riposte_damage
	_critical_target.take_critical_damage(damage, player)
	Sfx.play(self, &"stab", 0.0, 0.05)
	critical_hit.emit(_critical_target, _critical_kind)
	Combat.hitstop(self, 0.12)
	if player and player.has_method("add_shake"):
		player.add_shake(0.5)


# Chiamato quando la lama viene estratta.
func _on_critical_release() -> void:
	Sfx.play(self, &"stab_out", 0.0)
	if player and player.has_method("add_shake"):
		player.add_shake(0.3)
	_critical_target = null


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
		&"slash":
			if _attack_queued and not _wants_block:
				_attack_queued = false
				_slash()
			elif _wants_block:
				_attack_queued = false
				_start_block()
		&"riposte", &"backstab":
			_critical_target = null
			if _wants_block:
				_start_block()
		&"parry":
			# Dopo il colpo di brocchiero: attacco in coda (es. riposte) oppure torna in parata.
			if _attack_queued:
				_attack_queued = false
				is_blocking = false
				primary_pressed()
			elif _wants_block:
				_start_block()
			else:
				is_blocking = false


# Chiamato dall'animazione "slash" (traccia metodo) nel frame dell'impatto.
func _on_slash_hit() -> void:
	var camera := get_viewport().get_camera_3d()
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(slash_size.x, slash_size.y, slash_reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	# Box allineato alla camera, che parte dagli occhi e arriva a "slash_reach" metri.
	query.transform = Transform3D(camera.global_basis,
			camera.global_position - camera.global_basis.z * slash_reach * 0.5)
	var exclude: Array[RID] = []
	if player:
		exclude.append(player.get_rid())
	query.exclude = exclude

	# Prima raccoglie tutti i bersagli, poi controlla che non ci sia un muro in mezzo.
	var targets: Array[CollisionObject3D] = []
	for hit in space.intersect_shape(query, 32):
		var body := hit.collider as CollisionObject3D
		if body and body.has_method("take_damage") and not targets.has(body):
			targets.append(body)
	var ray_exclude := exclude.duplicate()
	for body in targets:
		ray_exclude.append(body.get_rid())

	var landed := false
	for body in targets:
		if not _in_line_of_sight(space, camera.global_position, body, ray_exclude):
			continue
		if body.take_damage(slash_damage, player) != Combat.HitResult.IGNORED:
			landed = true

	if landed:
		Combat.hitstop(self, 0.06)
		if player and player.has_method("add_shake"):
			player.add_shake(0.25)
	slash_hit.emit()


# Il bersaglio è visibile se almeno un raggio (verso il busto o la testa) non incontra ostacoli.
func _in_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, body: Node3D, exclude: Array[RID]) -> bool:
	for height in [1.0, 1.6, 0.4]:
		var ray := PhysicsRayQueryParameters3D.create(from, body.global_position + Vector3.UP * height)
		ray.exclude = exclude
		if space.intersect_ray(ray).is_empty():
			return true
	return false
