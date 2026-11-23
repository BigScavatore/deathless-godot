class_name KnightEnemy
extends CharacterBody3D
## Cavaliere nemico: insegue il player e attacca con un fendente dall'alto.
##
## L'attacco ha un segnale visivo (lampo giallo) poco prima del colpo: se in quel momento
## premi "parata" fai parry e il cavaliere resta stordito; i colpi durante lo stordimento
## fanno danno doppio. Mentre attacca non viene interrotto dai colpi (solo il parry lo ferma).
## Animazioni nell'AnimationPlayer: idle, walk, attack, hurt, stagger, death.
## Per muoversi usa la navmesh (NavigationAgent3D); se non c'è, va dritto verso il player.

signal died

enum State { IDLE, CHASE, ATTACK, HURT, STAGGER, DEAD }

@export_group("Stats")
@export var max_health := 100.0
@export var move_speed := 3.2
@export var turn_speed := 6.0
@export var detect_range := 30.0

@export_group("Attack")
## Sotto questa distanza inizia ad attaccare.
@export var attack_range := 2.2
## Fin dove arriva il colpo (metri).
@export var attack_reach := 2.8
## Apertura del colpo davanti a sé (gradi dal centro).
@export var attack_angle_deg := 60.0
@export var attack_damage := 25.0
@export var attack_cooldown := 0.8
## Fino a che punto dell'animazione "attack" continua a girarsi verso il player (poi il colpo è deciso).
@export var attack_tracking_time := 0.45

@export_group("Reactions")
## Moltiplicatore del danno ricevuto mentre è stordito (riposte).
@export var stagger_damage_mult := 2.0
@export var knockback := 3.5
## Secondi prima che il corpo sparisca.
@export var corpse_time := 5.0

var health := 0.0
var state := State.IDLE

var _player: Node3D
var _cooldown := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _flash_material: StandardMaterial3D
var _flash_tween: Tween
var _repath_time := 0.0

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	health = max_health
	anim.animation_finished.connect(_on_animation_finished)
	_setup_flash()
	anim.play(&"idle")


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			if _player and _distance_to_player() < detect_range:
				state = State.CHASE
		State.CHASE:
			var distance := _distance_to_player()
			if distance <= attack_range and _cooldown <= 0.0 and _can_see_player():
				_face_player(delta)
				_start_attack()
			else:
				var direction := _chase_direction(delta)
				if distance > attack_range * 0.8 or not _can_see_player():
					desired = direction * move_speed
				# Da vicino guarda il player, altrimenti la direzione in cui cammina.
				if distance < 4.0 and _can_see_player():
					_face_player(delta)
				else:
					_face_direction(direction, delta)
				_play_loop(&"walk" if desired != Vector3.ZERO else &"idle")
		State.ATTACK:
			if anim.current_animation_position < attack_tracking_time:
				_face_player(delta)

	# La velocità orizzontale va verso quella desiderata (così il knockback si smorza da solo).
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(desired.x, desired.z), 20.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


# --- Danno -----------------------------------------------------------------

func take_damage(amount: float, source: Node3D) -> Combat.HitResult:
	if state == State.DEAD:
		return Combat.HitResult.IGNORED
	if state == State.STAGGER:
		amount *= stagger_damage_mult
	health -= amount
	_flash(Color(1.0, 0.1, 0.05))
	if source:
		_push_away_from(source.global_position, knockback)

	if health <= 0.0:
		_die()
	elif state != State.ATTACK and state != State.STAGGER:
		state = State.HURT
		_play_from_start(&"hurt")
	return Combat.HitResult.HIT


func _die() -> void:
	state = State.DEAD
	collision_layer = 0  # il player ci passa sopra, ma il corpo resta appoggiato al pavimento
	_play_from_start(&"death")
	died.emit()
	await get_tree().create_timer(corpse_time).timeout
	queue_free()


func _stagger() -> void:
	state = State.STAGGER
	_play_from_start(&"stagger")
	_flash(Color(1.0, 0.85, 0.3), 0.5)
	if _player:
		_push_away_from(_player.global_position, knockback * 1.5)


# --- Attacco ---------------------------------------------------------------

func _start_attack() -> void:
	state = State.ATTACK
	_play_from_start(&"attack")


# Chiamato dall'animazione "attack" poco prima del colpo: è il momento di fare parry.
func _telegraph() -> void:
	_flash(Color(1.0, 0.9, 0.4), 0.3)


# Chiamato dall'animazione "attack" nel frame d'impatto.
func _attack_hit() -> void:
	if state != State.ATTACK or _player == null:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > attack_reach:
		return
	var forward := -global_basis.z
	if to_player.length() > 0.01 and forward.dot(to_player.normalized()) < cos(deg_to_rad(attack_angle_deg)):
		return
	if _player.has_method("take_damage"):
		var result: Combat.HitResult = _player.take_damage(attack_damage, self)
		if result == Combat.HitResult.PARRIED:
			_stagger()


func _on_animation_finished(anim_name: StringName) -> void:
	if state == State.DEAD:
		return
	match anim_name:
		&"attack":
			_cooldown = attack_cooldown
			state = State.CHASE
		&"hurt", &"stagger":
			state = State.CHASE


# --- Utility ---------------------------------------------------------------

func _distance_to_player() -> float:
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	return to_player.length()


func _face_player(delta: float) -> void:
	_face_direction(_player.global_position - global_position, delta)


func _face_direction(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)  # il modello guarda verso -Z
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


## Direzione (orizzontale, normalizzata) per avvicinarsi al player seguendo la navmesh.
func _chase_direction(delta: float) -> Vector3:
	var direct := _player.global_position - global_position
	direct.y = 0.0
	direct = direct.normalized()
	# Niente navmesh (o non ancora pronta): si va dritti.
	if NavigationServer3D.map_get_iteration_id(_agent.get_navigation_map()) == 0:
		return direct
	_repath_time -= delta
	if _repath_time <= 0.0:
		_repath_time = 0.25
		_agent.target_position = _player.global_position
	if _agent.is_navigation_finished():
		return direct
	var to_next := _agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0025:
		return direct
	return to_next.normalized()


## true se tra il knight e il player non ci sono muri (raggio all'altezza del busto).
func _can_see_player() -> bool:
	var from := global_position + Vector3.UP * 1.4
	var ray := PhysicsRayQueryParameters3D.create(from, _player.global_position + Vector3.UP * 1.2)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == _player


func _push_away_from(from: Vector3, strength: float) -> void:
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() > 0.0001:
		var push := away.normalized() * strength
		velocity.x = push.x
		velocity.z = push.z


func _play_loop(anim_name: StringName) -> void:
	if anim.current_animation != anim_name:
		anim.play(anim_name)


func _play_from_start(anim_name: StringName) -> void:
	anim.play(anim_name)
	anim.seek(0.0, true)


# Un materiale "overlay" su tutte le mesh, normalmente trasparente: lampeggia quando serve.
func _setup_flash() -> void:
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1, 1, 1, 0)
	for child in $Model.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_overlay = _flash_material


func _flash(color: Color, duration := 0.25) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_material.albedo_color = Color(color, 0.7)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, duration)
