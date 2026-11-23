extends CharacterBody3D
## Third-person character controller.
## WASD / frecce / stick sinistro = movimento, Spazio / A = salto,
## Shift / L3 = corsa, mouse / stick destro = camera, Esc = rilascia il mouse.

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 5.0
@export var acceleration := 25.0
@export var air_acceleration := 8.0
@export var friction := 30.0
@export var turn_speed := 12.0

@export_group("Camera")
@export_range(0.0, 0.02, 0.0005) var mouse_sensitivity := 0.003
@export var stick_sensitivity := 2.5
@export_range(-89.0, 0.0) var min_pitch_deg := -70.0
@export_range(0.0, 89.0) var max_pitch_deg := 30.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _model: Node3D = $Model

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_register_input_actions()
	_spring_arm.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative * mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# Camera con stick destro
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		_rotate_camera(look * stick_sensitivity * delta)

	# Gravità e salto
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Direzione di movimento relativa alla camera (solo yaw)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _camera_pivot.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var horizontal := Vector2(velocity.x, velocity.z)

	if direction != Vector3.ZERO:
		var accel := acceleration if is_on_floor() else air_acceleration
		var target := Vector2(direction.x, direction.z) * speed
		horizontal = horizontal.move_toward(target, accel * delta)

		# Ruota il modello verso la direzione di movimento (il fronte è -Z)
		var target_yaw := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, turn_speed * delta)
	else:
		var decel := friction if is_on_floor() else air_acceleration
		horizontal = horizontal.move_toward(Vector2.ZERO, decel * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


func _rotate_camera(amount: Vector2) -> void:
	_camera_pivot.rotate_y(-amount.x)
	_spring_arm.rotation.x = clampf(
		_spring_arm.rotation.x - amount.y,
		deg_to_rad(min_pitch_deg),
		deg_to_rad(max_pitch_deg)
	)


# Registra le azioni di input da codice, così non serve toccare project.godot.
# Se preferisci definirle in Progetto > Impostazioni progetto > Mappa input,
# basta creare un'azione "move_forward": in quel caso questa funzione non fa nulla.
func _register_input_actions() -> void:
	if InputMap.has_action("move_forward"):
		return
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("sprint", [KEY_SHIFT])

	_add_axis_action("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis_action("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_axis_action("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis_action("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis_action("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_axis_action("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_axis_action("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_axis_action("look_right", JOY_AXIS_RIGHT_X, 1.0)

	_add_button_action("jump", JOY_BUTTON_A)
	_add_button_action("sprint", JOY_BUTTON_LEFT_STICK)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _add_key_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
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
