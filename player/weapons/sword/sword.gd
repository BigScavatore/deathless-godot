extends Weapon
## Claymore. Funziona in entrambe le mani (nella sinistra è specchiata: i fendenti vanno al contrario).
##   tasto della mano   = fendente orizzontale (colpisce ciò che è davanti alla camera).
##                        I colpi in sequenza alternano dritto e rovescio; dopo una pausa si riparte dal dritto.
##   colpi critici (stile Dark Souls), sempre col tasto della mano:
##     - riposte: davanti a un nemico stordito dal parry -> affondo che lo trafigge
##     - backstab: alle spalle di un nemico -> pugnalata alla schiena
##   sinergia "Assalto" (spada + brocchiero): tenendo premuto la spada si carica; rilasciando dopo
##     Synergies.assault_hold_time parte un affondo in dash che trafigge chi incontra (un tocco
##     breve resta un fendente). Vedi player/weapons/synergies.gd.
## Durante fendenti e critici l'altra mano si abbassa (vedi Weapon.wants_other_hand_lowered).
## Le pose sono nell'AnimationPlayer della scena: modificale dall'editor (pannello Animazione).

## Emesso nel frame d'impatto del fendente (chiave "method" nelle animazioni "slash"/"slash_back").
signal slash_hit
signal critical_hit(target: Node3D, kind: StringName)

@export_group("Slash")
@export var slash_damage := 35.0
## Portata del fendente davanti alla camera (metri).
@export var slash_reach := 2.8
## Larghezza e altezza del box del fendente.
@export var slash_size := Vector2(2.6, 1.4)
## Se passa più di questo tempo (secondi) dalla fine di un fendente, la combo riparte dal dritto.
@export var combo_reset := 0.6

@export_group("Critical")
@export var riposte_damage := 120.0
@export var backstab_damage := 90.0
## Distanza massima dal nemico stordito per la riposte.
@export var riposte_range := 3.0
## Distanza massima per il backstab.
@export var backstab_range := 2.0
## Quanto il nemico deve essere al centro della visuale (coseno dell'angolo).
@export_range(0.0, 1.0) var critical_aim := 0.6

var _attack_queued := false
var _critical_target: Node3D
var _critical_kind := &""
## 0 = dritto ("slash"), 1 = rovescio ("slash_back").
var _combo_step := 0
var _last_slash_end := 0
## Assalto: carica (tasto tenuto) e affondo in corso.
var _charging := false
var _charge_start := 0
var _charge_ready := false
var _lunging := false
var _lunge_hit: Array[Node] = []


func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)


func use_pressed() -> void:
	if _is_critical():
		return
	if not _is_slashing():
		var target := _find_critical_target()
		if target:
			_start_critical(target)
			return
	if _is_slashing():
		_attack_queued = true  # input buffer: il prossimo fendente parte appena finisce questo
	elif _lunging:
		return
	elif synergies and synergies.can_assault(self):
		# Assalto: si carica finché il tasto resta premuto (il fendente parte al rilascio).
		_charging = true
		_charge_ready = false
		_charge_start = Time.get_ticks_msec()
		anim.play(&"charge")
	else:
		_slash()


func use_released() -> void:
	if not _charging:
		return
	_charging = false
	var held := (Time.get_ticks_msec() - _charge_start) / 1000.0
	if synergies and held >= synergies.assault_hold_time and synergies.can_assault(self) and _start_lunge():
		return
	_slash()


func _process(_delta: float) -> void:
	if _charging and not _charge_ready and synergies \
			and (Time.get_ticks_msec() - _charge_start) / 1000.0 >= synergies.assault_hold_time:
		_charge_ready = true  # carica pronta: un rintocco e la camera trema appena
		Sfx.play(self, &"charge_gain", -6.0, 0.05)
		if player and player.has_method("add_shake"):
			player.add_shake(0.08)


func _physics_process(_delta: float) -> void:
	if not _lunging:
		return
	if player == null or not player.has_method("is_dashing") or not player.is_dashing():
		_lunging = false
		return
	# Durante l'affondo colpisce chiunque sia vicino alla punta (una volta sola per nemico).
	var shape := SphereShape3D.new()
	shape.radius = synergies.assault_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var forward := -player.global_basis.z
	query.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP * 1.0 + forward * 1.0)
	query.exclude = [player.get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var body := hit.collider as Node
		if body == null or _lunge_hit.has(body) or not body.has_method("take_damage"):
			continue
		_lunge_hit.append(body)
		if body.take_damage(synergies.assault_damage, player) != Combat.HitResult.IGNORED:
			Sfx.play(self, &"stab", 0.0, 0.08)
			Combat.hitstop(self, 0.08)
			if player.has_method("add_shake"):
				player.add_shake(0.4)


## Parte l'affondo (serve una carica del dash): false se non si può.
func _start_lunge() -> bool:
	if player == null or not player.has_method("lunge"):
		return false
	if not player.lunge(synergies.assault_speed, synergies.assault_duration):
		return false
	_lunging = true
	_lunge_hit.clear()
	_play_from_start(&"lunge")
	Sfx.play(self, &"swing_heavy", -2.0, 0.08)
	return true


func wants_other_hand_lowered() -> bool:
	return _is_slashing() or _is_critical()


func is_exclusive() -> bool:
	return _is_critical()


## Invincibile durante riposte, backstab e l'affondo dell'Assalto.
func is_invulnerable() -> bool:
	return _is_critical() or _lunging


func can_switch() -> bool:
	return not _is_slashing() and not _is_critical() and not _charging and not _lunging


func reset_state() -> void:
	_critical_target = null
	_attack_queued = false
	_charging = false
	_lunging = false


func _slash() -> void:
	if Time.get_ticks_msec() - _last_slash_end > int(combo_reset * 1000.0):
		_combo_step = 0
	_play_from_start(&"slash_back" if _combo_step == 1 else &"slash")
	_combo_step = 1 - _combo_step
	Sfx.play(self, &"swing", -3.0, 0.1)


func _is_slashing() -> bool:
	return anim.is_playing() and (anim.current_animation == &"slash" or anim.current_animation == &"slash_back")


func _is_critical() -> bool:
	return anim.is_playing() and (anim.current_animation == &"riposte" or anim.current_animation == &"backstab")


func _on_animation_finished(anim_name: StringName) -> void:
	match anim_name:
		&"slash", &"slash_back":
			_last_slash_end = Time.get_ticks_msec()
			if _attack_queued:
				_attack_queued = false
				_slash()
		&"riposte", &"backstab":
			_critical_target = null


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
	_attack_queued = false
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
	if is_instance_valid(_critical_target) and _critical_target.has_method("critical_released"):
		_critical_target.critical_released()  # se il critico l'ha ucciso, esplode adesso
	Sfx.play(self, &"stab_out", 0.0)
	if player and player.has_method("add_shake"):
		player.add_shake(0.3)
	_critical_target = null


# --- Fendente --------------------------------------------------------------

# Chiamato dalle animazioni "slash"/"slash_back" (traccia metodo) nel frame dell'impatto.
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
	if synergies:
		synergies.on_sword_slash(self, landed)  # es. lancia un globo arcano / carica il bastone
	slash_hit.emit()


# Il bersaglio è visibile se almeno un raggio (verso il busto o la testa) non incontra ostacoli.
func _in_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, body: Node3D, exclude: Array[RID]) -> bool:
	for height in [1.0, 1.6, 0.4]:
		var ray := PhysicsRayQueryParameters3D.create(from, body.global_position + Vector3.UP * height)
		ray.exclude = exclude
		if space.intersect_ray(ray).is_empty():
			return true
	return false
