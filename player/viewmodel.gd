extends Node3D
## Spada e scudo in prima persona: stile low-poly "gritty" + oscillazioni di movimento.
## Va messo come figlio della Camera3D (vedi player.tscn).

@export_group("Movement sway")
## Ampiezza dell'oscillazione mentre si corre.
@export var bob_amount := 0.014
## Quanto l'arma "resta indietro" quando muovi il mouse (radianti per 1000 px/s).
@export var mouse_sway := 0.03
@export var max_mouse_sway_deg := 6.0
## Quanto si abbassa/alza con la velocità verticale (salto, caduta).
@export var air_sway := 0.002
@export var smoothing := 14.0

var _player: CharacterBody3D
var _base_position := Vector3.ZERO
var _bob_time := 0.0
var _idle_time := 0.0


func _ready() -> void:
	_base_position = position
	var n := get_parent()
	while n != null and not n is CharacterBody3D:
		n = n.get_parent()
	_player = n as CharacterBody3D
	_apply_style()


func _process(delta: float) -> void:
	_idle_time += delta
	var velocity := _player.velocity if _player else Vector3.ZERO
	var grounded := _player != null and _player.is_on_floor()
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var run := clampf(horizontal / 14.0, 0.0, 1.0) if grounded else 0.0

	_bob_time += delta * (7.0 + 5.0 * run)
	var target_pos := _base_position
	target_pos.x += sin(_bob_time * 0.5) * bob_amount * run
	target_pos.y += -absf(sin(_bob_time)) * bob_amount * run
	target_pos.y += sin(_idle_time * 1.6) * 0.004                       # respiro
	target_pos.y -= clampf(velocity.y * air_sway, -0.03, 0.03)          # salto / caduta

	var mouse := Input.get_last_mouse_velocity() if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Vector2.ZERO
	var limit := deg_to_rad(max_mouse_sway_deg)
	var target_yaw := clampf(mouse.x * mouse_sway * 0.001, -limit, limit)
	var target_pitch := clampf(mouse.y * mouse_sway * 0.001, -limit, limit)

	var t := 1.0 - exp(-smoothing * delta)
	position = position.lerp(target_pos, t)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)
	rotation.x = lerp_angle(rotation.x, target_pitch, t)


# Texture pixelate (niente filtro) e niente ombre proiettate dalle armi.
func _apply_style() -> void:
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				var styled := mat.duplicate() as BaseMaterial3D
				styled.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mi.set_surface_override_material(i, styled)
