extends CharacterBody3D
## Controller in prima persona stile ULTRAKILL: movimento veloce, dash a cariche e wall jump.
## WASD / stick sinistro = movimento, Spazio / A = salto (anche wall jump),
## Shift / B = dash, mouse / stick destro = camera, Esc = rilascia il mouse.

@export_group("Movement")
@export var speed := 14.0
@export var jump_velocity := 10.0
@export var gravity_scale := 2.5
@export var acceleration := 90.0
@export var air_acceleration := 25.0
@export var friction := 70.0
@export var air_friction := 2.0
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

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _dash_charges := 0.0
var _dash_time_left := 0.0
var _dash_dir := Vector3.ZERO

var _wall_jumps_left := 0
var _wall_normal := Vector3.ZERO
var _wall_time := 0.0

var _coyote := 0.0
var _jump_buffer := 0.0


func _ready() -> void:
	_register_input_actions()
	_dash_charges = float(dash_charges_max)
	_wall_jumps_left = max_wall_jumps
	_camera.fov = base_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative * mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_rotate_camera(look * stick_sensitivity * delta)

	_update_timers(delta)

	if Input.is_action_just_pressed("dash") and _dash_time_left <= 0.0 and _dash_charges >= 1.0:
		_start_dash()

	if _dash_time_left > 0.0:
		_process_dash(delta)
	else:
		_process_movement(delta)

	move_and_slide()
	_update_wall_contact()
	_update_fov(delta)


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
			velocity.y = jump_velocity
			_jump_buffer = 0.0
			_coyote = 0.0
		elif _wall_time > 0.0 and _wall_jumps_left > 0:
			_wall_jump()

	# Movimento orizzontale
	var wish := _wish_direction()
	var horizontal := Vector2(velocity.x, velocity.z)
	if wish != Vector3.ZERO:
		var accel := acceleration if on_floor else air_acceleration
		horizontal = horizontal.move_toward(Vector2(wish.x, wish.z) * speed, accel * delta)
	else:
		var decel := friction if on_floor else air_friction
		horizontal = horizontal.move_toward(Vector2.ZERO, decel * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _wish_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Il corpo ruota solo in yaw, quindi la sua base è già "orizzontale".
	return global_basis * Vector3(input.x, 0.0, input.y)


# --- Dash ------------------------------------------------------------------

func _start_dash() -> void:
	var dir := _wish_direction()
	if dir == Vector3.ZERO:
		dir = -global_basis.z  # senza input: dash in avanti
	_dash_dir = dir.normalized()
	_dash_time_left = dash_duration
	_dash_charges -= 1.0


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
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_dash_charges = minf(_dash_charges + delta / dash_recharge_time, float(dash_charges_max))


func _rotate_camera(amount: Vector2) -> void:
	rotate_y(-amount.x)
	_head.rotation.x = clampf(_head.rotation.x - amount.y, deg_to_rad(-89.0), deg_to_rad(89.0))


func _update_fov(delta: float) -> void:
	var target := dash_fov if _dash_time_left > 0.0 else base_fov
	_camera.fov = lerpf(_camera.fov, target, 1.0 - exp(-fov_lerp_speed * delta))


# --- Input -----------------------------------------------------------------

# Registra le azioni da codice, così non serve toccare project.godot.
# Se preferisci la Mappa input dell'editor, crea un'azione "move_forward":
# in quel caso questa funzione non fa nulla (servono anche move_*, look_*, jump, dash).
func _register_input_actions() -> void:
	if InputMap.has_action("move_forward"):
		return
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("dash", [KEY_SHIFT])

	_add_axis_action("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis_action("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_axis_action("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis_action("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis_action("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_axis_action("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_axis_action("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_axis_action("look_right", JOY_AXIS_RIGHT_X, 1.0)

	_add_button_action("jump", JOY_BUTTON_A)
	_add_button_action("dash", JOY_BUTTON_B)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _add_key_action(action: StringName, keys: Array) -> void:
	_ensure_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _add_axis_action(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _add_button_action(action: StringName, button: JoyButton) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
