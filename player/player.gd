extends CharacterBody3D
## Controller in prima persona stile ULTRAKILL: movimento veloce, dash a cariche, wall jump,
## scivolata e slam.
## WASD / stick sinistro = movimento, Spazio / A = salto (anche wall jump),
## Shift / B = dash, Ctrl / C / LB = scivolata (a terra) o slam (in aria),
## mouse / stick destro = camera, Esc = rilascia il mouse.
## Scivolata: velocità costante finché tieni premuto; saltando durante la scivolata
## mantieni lo slancio (salto lungo).
## Slam: picchiata verso il basso; all'impatto danneggia e lancia i nemici vicini.
## Saltando subito dopo lo slam fai un salto molto più alto (slam jump).
## Vita e danno: vedi take_damage() (convenzione in combat/combat.gd).
## Mana: lo usano gli incantesimi (vedi use_mana()), si ricarica da solo dopo una breve pausa.

signal health_changed(health: float, max_health: float)
signal died
signal mana_changed(mana: float, max_mana: float)

## Scala del progetto: 1 unità = 1 metro.
@export_group("Size")
@export var player_height := 1.8
@export var player_radius := 0.4
## Altezza degli occhi (camera) dai piedi.
@export var eye_height := 1.6

@export_group("Movement")
@export var speed := 14.0
@export var jump_velocity := 10.0
@export var gravity_scale := 2.5
## Accelerazione a terra (m/s²): più alta = risposta più immediata.
@export var acceleration := 150.0
## Frenata a terra quando non premi niente.
@export var friction := 120.0
## Frenata extra quando premi nella direzione opposta a quella in cui vai (cambi di direzione secchi).
@export var turn_braking := 140.0
## Controllo in aria.
@export var air_acceleration := 45.0
@export var air_friction := 4.0
## In aria, sopra la velocità normale (dopo dash o scivolata): quanto curva lo slancio
## verso i tasti premuti (radianti al secondo) e quanto rallenta verso la velocità normale.
@export var air_turn_rate := 4.0
@export var air_overspeed_drag := 3.0
@export var jump_buffer_time := 0.1
@export var coyote_time := 0.1

@export_group("Dash")
@export var dash_speed := 45.0
@export var dash_duration := 0.15
## Velocità mantenuta subito dopo il dash (poi decade verso "speed").
@export var dash_exit_speed := 20.0
@export var dash_charges_max := 3
## Secondi necessari per ricaricare una singola carica.
@export var dash_recharge_time := 1.0

@export_group("Slide")
@export var slide_speed := 18.0
## Altezza della capsula e degli occhi durante la scivolata.
@export var slide_height := 1.0
@export var slide_eye_height := 0.75
@export var slide_fov_boost := 6.0

@export_group("Slam")
@export var slam_speed := 45.0
@export var slam_radius := 4.0
@export var slam_damage := 20.0
## Velocità verso l'alto data ai nemici colpiti dallo slam.
@export var slam_launch := 7.0
## Salto potenziato se premi salto entro questo tempo dall'atterraggio dello slam.
@export var slam_jump_window := 0.25
@export var slam_jump_velocity := 19.0

@export_group("Wall Jump")
@export var max_wall_jumps := 3
@export var wall_jump_push := 14.0
@export var wall_jump_up := 10.0
## Tempo di tolleranza dopo aver toccato un muro in cui il wall jump è ancora valido.
@export var wall_grace_time := 0.12

@export_group("Camera")
@export_range(0.0, 0.02, 0.0005) var mouse_sensitivity := 0.002
@export var stick_sensitivity := 3.0
@export var base_fov := 90.0
@export var dash_fov := 105.0
@export var fov_lerp_speed := 12.0

@export_group("Health")
@export var max_health := 100.0
## Frazione del danno che passa quando si para con lo scudo (senza parry).
@export_range(0.0, 1.0) var block_damage_factor := 0.25
## Massima rotazione (radianti) della camera durante lo shake.
@export var max_shake := 0.045

@export_group("Mana")
@export var max_mana := 100.0
## Mana recuperato al secondo.
@export var mana_regen := 9.0
## Secondi dopo l'ultimo incantesimo prima che il mana inizi a ricaricarsi.
@export var mana_regen_delay := 0.8

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _viewmodel: Node3D = $Head/Camera3D/Viewmodel
@onready var _hud: CanvasLayer = $HUD

var health := 0.0
var mana := 0.0
var _mana_regen_wait := 0.0
var _dead := false
var _shake := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _dash_charges := 0.0
var _dash_time_left := 0.0
var _dash_dir := Vector3.ZERO

var _wall_jumps_left := 0
var _wall_normal := Vector3.ZERO
var _wall_time := 0.0

var _coyote := 0.0
var _jump_buffer := 0.0

var _sliding := false
var _slide_dir := Vector3.ZERO
var _crouch := 0.0  # 0 = in piedi, 1 = abbassato (scivolata)
var _slamming := false
var _slam_jump_time := 0.0
var _locked_time := 0.0

var _was_on_floor := true
var _slide_audio: AudioStreamPlayer


func _ready() -> void:
	_apply_size()
	_register_input_actions()
	_dash_charges = float(dash_charges_max)
	_wall_jumps_left = max_wall_jumps
	_camera.fov = base_fov
	health = max_health
	mana = max_mana
	add_to_group("player")
	_hud.set_health(health, max_health)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_slide_audio = AudioStreamPlayer.new()
	_slide_audio.stream = Sfx.looping(&"slide_loop")
	_slide_audio.volume_db = -7.0
	_slide_audio.bus = Sfx.BUS
	add_child(_slide_audio)


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _locked_time <= 0.0:
		_rotate_camera(event.relative * mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_update_shake(delta)
	_update_mana(delta)


func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		velocity.y -= _gravity * gravity_scale * delta
		move_and_slide()
		return

	if _locked_time > 0.0:
		_process_locked(delta)
		return

	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_rotate_camera(look * stick_sensitivity * delta)

	_update_timers(delta)

	if Input.is_action_just_pressed("dash") and _dash_time_left <= 0.0 and _dash_charges >= 1.0:
		_sliding = false
		_slamming = false
		_start_dash()

	if _dash_time_left <= 0.0 and not _slamming:
		if Input.is_action_just_pressed("slide") and not is_on_floor():
			_start_slam()
		elif Input.is_action_pressed("slide") and is_on_floor() and not _sliding:
			_start_slide()

	if _slamming:
		_process_slam()
	elif _dash_time_left > 0.0:
		_process_dash(delta)
	elif _sliding:
		_process_slide(delta)
	else:
		_process_movement(delta)

	var fall_speed := velocity.y
	move_and_slide()
	if _slamming and is_on_floor():
		_land_slam()
	elif is_on_floor() and not _was_on_floor and fall_speed < -7.0:
		Sfx.play(self, &"land", -10.0)
	_was_on_floor = is_on_floor()
	_update_slide_audio()
	_update_wall_contact()
	_update_crouch(delta)
	_update_fov(delta)


## true durante la scivolata (lo usa il viewmodel).
func is_sliding() -> bool:
	return _sliding


## Blocca movimento e visuale per "duration" secondi (colpi critici): il player scivola
## in "stand_at" e si gira verso "look_at_point".
func lock_for(duration: float, stand_at: Vector3, look_at_point: Vector3) -> void:
	_locked_time = duration
	_sliding = false
	_slamming = false
	_dash_time_left = 0.0
	velocity = Vector3.ZERO
	var to_target := look_at_point - stand_at
	to_target.y = 0.0
	var target_yaw := atan2(-to_target.x, -to_target.z) if to_target.length_squared() > 0.0001 else rotation.y
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position:x", stand_at.x, 0.15)
	tween.tween_property(self, "global_position:z", stand_at.z, 0.15)
	tween.tween_property(self, "rotation:y", rotation.y + wrapf(target_yaw - rotation.y, -PI, PI), 0.15)
	tween.tween_property(_head, "rotation:x", deg_to_rad(-8.0), 0.2)


func _process_locked(delta: float) -> void:
	_locked_time -= delta
	_update_slide_audio()
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta
	move_and_slide()
	_update_crouch(delta)
	_update_fov(delta)


# --- Dimensioni ------------------------------------------------------------

func _apply_size() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.height = player_height
	capsule.radius = player_radius
	_collision.shape = capsule
	_collision.position.y = player_height / 2.0
	_head.position.y = eye_height


# Abbassa capsula e camera durante la scivolata (e resta giù se sopra c'è un soffitto basso).
func _update_crouch(delta: float) -> void:
	var want_low := _sliding or (_crouch > 0.01 and not _can_stand())
	_crouch = move_toward(_crouch, 1.0 if want_low else 0.0, delta * 8.0)
	var t := smoothstep(0.0, 1.0, _crouch)
	var capsule := _collision.shape as CapsuleShape3D
	capsule.height = lerpf(player_height, slide_height, t)
	_collision.position.y = capsule.height / 2.0
	_head.position.y = lerpf(eye_height, slide_eye_height, t)
	_head.rotation.z = lerp_angle(_head.rotation.z, deg_to_rad(-4.0) if _sliding else 0.0, 1.0 - exp(-10.0 * delta))


func _can_stand() -> bool:
	var shape := CapsuleShape3D.new()
	shape.height = player_height
	shape.radius = player_radius * 0.95
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (player_height / 2.0 + 0.05))
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- Vita e danno ---------------------------------------------------------

## Chiamato da chi attacca il player. L'arma in mano può parare o fare parry.
func take_damage(amount: float, source: Node3D) -> Combat.HitResult:
	if _dead:
		return Combat.HitResult.IGNORED
	var result := Combat.HitResult.HIT
	var weapon: Weapon = _viewmodel.current_weapon()
	# Invincibile durante i colpi critici (comandi bloccati) e subito dopo un parry.
	if _locked_time > 0.0 or (weapon and weapon.is_invulnerable()):
		return Combat.HitResult.IGNORED
	if weapon and source:
		result = weapon.defend(source.global_position)

	match result:
		Combat.HitResult.PARRIED:
			Combat.hitstop(self, 0.18)
			add_shake(0.55)
			_hud.flash_parry()
			return result
		Combat.HitResult.BLOCKED:
			amount *= block_damage_factor
			add_shake(0.35)
			_hud.flash_damage(0.15)
		_:
			add_shake(0.7)
			_hud.flash_damage(0.45)
			Sfx.play(self, &"player_hurt", 0.0)

	health = maxf(health - amount, 0.0)
	_hud.set_health(health, max_health)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
	return result


## Spende mana: false (e niente speso) se non basta.
func use_mana(amount: float) -> bool:
	if _dead or mana < amount:
		return false
	mana -= amount
	_mana_regen_wait = mana_regen_delay
	mana_changed.emit(mana, max_mana)
	return true


func restore_mana(amount: float) -> void:
	mana = minf(mana + amount, max_mana)
	mana_changed.emit(mana, max_mana)


func _update_mana(delta: float) -> void:
	if _mana_regen_wait > 0.0:
		_mana_regen_wait -= delta
	elif mana < max_mana and not _dead:
		mana = minf(mana + mana_regen * delta, max_mana)
		mana_changed.emit(mana, max_mana)


## Per la HUD: l'arma in mano, tutte le armi e le cariche del dash.
func current_weapon() -> Weapon:
	return _viewmodel.current_weapon()


func all_weapons() -> Array[Weapon]:
	return _viewmodel.all_weapons()


func dash_charges() -> float:
	return _dash_charges


## "Trauma" della camera da 0 a 1 (si somma e decade da solo).
func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)


func _die() -> void:
	_dead = true
	died.emit()
	_slide_audio.stop()
	Sfx.play(self, &"body_fall", -2.0)
	_viewmodel.visible = false
	# Camera che cade a terra, poi si ricarica il livello.
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(_head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_head, "rotation:z", deg_to_rad(70.0), 0.5)
	await get_tree().create_timer(2.5).timeout
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _update_shake(delta: float) -> void:
	_shake = move_toward(_shake, 0.0, delta * 2.0)
	var amount := _shake * _shake * max_shake
	_camera.rotation = Vector3(
		randf_range(-amount, amount), randf_range(-amount, amount), randf_range(-amount, amount) * 0.5)


# --- Movimento -------------------------------------------------------------

func _process_movement(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_wall_jumps_left = max_wall_jumps
	else:
		velocity.y -= _gravity * gravity_scale * delta

	# Salto e wall jump (con jump buffer: premere poco prima di toccare conta)
	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			velocity.y = slam_jump_velocity if _slam_jump_time > 0.0 else jump_velocity
			Sfx.play(self, &"jump", -10.0 if _slam_jump_time <= 0.0 else -4.0)
			_slam_jump_time = 0.0
			_jump_buffer = 0.0
			_coyote = 0.0
		elif _wall_time > 0.0 and _wall_jumps_left > 0:
			_wall_jump()

	# Movimento orizzontale
	var wish := _wish_direction()
	var wish2 := Vector2(wish.x, wish.z)
	var horizontal := Vector2(velocity.x, velocity.z)
	if on_floor:
		if wish2 == Vector2.ZERO:
			horizontal = horizontal.move_toward(Vector2.ZERO, friction * delta)
		else:
			var rate := acceleration
			if horizontal.dot(wish2) < 0.0:
				rate += turn_braking  # stai invertendo: frena di più
			horizontal = horizontal.move_toward(wish2 * speed, rate * delta)
	elif wish2 != Vector2.ZERO and horizontal.length() > speed:
		# Slancio oltre la velocità normale: curva verso i tasti senza perderlo di colpo.
		var turn := clampf(horizontal.angle_to(wish2), -air_turn_rate * delta, air_turn_rate * delta)
		horizontal = horizontal.rotated(turn)
		horizontal = horizontal.move_toward(horizontal.normalized() * speed, air_overspeed_drag * delta)
	elif wish2 != Vector2.ZERO:
		horizontal = horizontal.move_toward(wish2 * speed, air_acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector2.ZERO, air_friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _wish_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Il corpo ruota solo in yaw, quindi la sua base è già "orizzontale".
	return global_basis * Vector3(input.x, 0.0, input.y)


# --- Scivolata -------------------------------------------------------------

func _update_slide_audio() -> void:
	var should_play := _sliding and is_on_floor() and _locked_time <= 0.0
	if should_play and not _slide_audio.playing:
		_slide_audio.pitch_scale = randf_range(0.92, 1.05)
		_slide_audio.play()
	elif not should_play and _slide_audio.playing:
		_slide_audio.stop()


func _start_slide() -> void:
	var dir := _wish_direction()
	if dir == Vector3.ZERO:
		dir = -global_basis.z
	_slide_dir = dir.normalized()
	_sliding = true


func _process_slide(delta: float) -> void:
	if not Input.is_action_pressed("slide"):
		_sliding = false
		_process_movement(delta)
		return
	# Velocità costante (o quella attuale, se più alta: es. uscendo da un dash).
	var current := Vector2(velocity.x, velocity.z).length()
	var slide := maxf(slide_speed, current)
	velocity.x = _slide_dir.x * slide
	velocity.z = _slide_dir.z * slide
	velocity.y -= _gravity * gravity_scale * delta
	if is_on_floor():
		if _jump_buffer > 0.0:
			# Salto lungo: si esce dalla scivolata tenendo lo slancio.
			velocity.y = slam_jump_velocity if _slam_jump_time > 0.0 else jump_velocity
			Sfx.play(self, &"jump", -8.0)
			_slam_jump_time = 0.0
			_jump_buffer = 0.0
			_coyote = 0.0
			_sliding = false
	else:
		_sliding = false  # finito il pavimento: si continua in aria con lo slancio


# --- Slam ------------------------------------------------------------------

func _start_slam() -> void:
	_slamming = true
	_sliding = false
	Sfx.play(self, &"slam_dive", -4.0)


func _process_slam() -> void:
	velocity = Vector3(0.0, -slam_speed, 0.0)


func _land_slam() -> void:
	_slamming = false
	_slam_jump_time = slam_jump_window
	velocity = Vector3.ZERO
	add_shake(0.6)
	Sfx.play(self, &"slam_impact", 0.0, 0.06)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var target := enemy as Node3D
		if target == null or not target.has_method("take_damage"):
			continue
		var offset := target.global_position - global_position
		if absf(offset.y) > 2.5:
			continue
		offset.y = 0.0
		if offset.length() > slam_radius:
			continue
		if target.take_damage(slam_damage, self) != Combat.HitResult.IGNORED and target is CharacterBody3D:
			(target as CharacterBody3D).velocity.y = slam_launch


# --- Dash ------------------------------------------------------------------

func _start_dash() -> void:
	var dir := _wish_direction()
	if dir == Vector3.ZERO:
		dir = -global_basis.z  # senza input: dash in avanti
	_dash_dir = dir.normalized()
	_dash_time_left = dash_duration
	_dash_charges -= 1.0
	Sfx.play(self, &"dash", -6.0)


func _process_dash(delta: float) -> void:
	_dash_time_left -= delta
	if _dash_time_left <= 0.0:
		# Fine dash: si mantiene un po' di slancio, senza gravità accumulata.
		velocity = _dash_dir * dash_exit_speed
	else:
		velocity = _dash_dir * dash_speed  # niente gravità durante il dash


# --- Wall jump -------------------------------------------------------------

func _wall_jump() -> void:
	# Togli la componente verso il muro, mantieni quella laterale e spingi via dal muro.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal -= horizontal.project(_wall_normal)
	horizontal += _wall_normal * wall_jump_push

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = wall_jump_up
	Sfx.play(self, &"jump", -8.0)

	_wall_jumps_left -= 1
	_wall_time = 0.0
	_jump_buffer = 0.0


func _update_wall_contact() -> void:
	if is_on_wall():
		var normal := get_wall_normal()
		normal.y = 0.0
		if normal.length() > 0.01:
			_wall_normal = normal.normalized()
			_wall_time = wall_grace_time


# --- Timer, camera ---------------------------------------------------------

func _update_timers(delta: float) -> void:
	_coyote = coyote_time if is_on_floor() else maxf(_coyote - delta, 0.0)
	_wall_time = maxf(_wall_time - delta, 0.0)
	_slam_jump_time = maxf(_slam_jump_time - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_dash_charges = minf(_dash_charges + delta / dash_recharge_time, float(dash_charges_max))


func _rotate_camera(amount: Vector2) -> void:
	rotate_y(-amount.x)
	_head.rotation.x = clampf(_head.rotation.x - amount.y, deg_to_rad(-89.0), deg_to_rad(89.0))


func _update_fov(delta: float) -> void:
	var target := base_fov
	if _dash_time_left > 0.0:
		target = dash_fov
	elif _sliding:
		target = base_fov + slide_fov_boost
	_camera.fov = lerpf(_camera.fov, target, 1.0 - exp(-fov_lerp_speed * delta))


# --- Input -----------------------------------------------------------------

# Registra le azioni da codice, così non serve toccare project.godot.
# Un'azione già definita nella Mappa input dell'editor viene lasciata com'è
# (quindi puoi rimappare tutto da lì senza modificare questo script).
func _register_input_actions() -> void:
	_add_action("move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add_action("look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_add_action("look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add_action("look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_add_action("jump", [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_add_action("dash", [_key(KEY_SHIFT), _button(JOY_BUTTON_B)])
	_add_action("slide", [_key(KEY_CTRL), _key(KEY_C), _button(JOY_BUTTON_LEFT_SHOULDER)])

	# Armi (usate da viewmodel.gd)
	_add_action("attack", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add_action("block", [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add_action("parry", [_key(KEY_F), _mouse(MOUSE_BUTTON_XBUTTON1), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("next_mode", [_key(KEY_R), _button(JOY_BUTTON_X)])
	_add_action("weapon_next", [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _button(JOY_BUTTON_Y)])
	_add_action("weapon_prev", [_mouse(MOUSE_BUTTON_WHEEL_UP)])
	for i in 9:
		_add_action("weapon_%d" % (i + 1), [_key((KEY_1 + i) as Key)])


func _add_action(action: StringName, events: Array[InputEvent]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for ev in events:
		InputMap.action_add_event(action, ev)


func _key(keycode: Key) -> InputEvent:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	return ev


func _mouse(button: MouseButton) -> InputEvent:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	return ev


func _axis(axis: JoyAxis, value: float) -> InputEvent:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev


func _button(button: JoyButton) -> InputEvent:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	return ev
