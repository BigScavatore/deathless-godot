extends Node3D
## Porta-armi in prima persona: oscillazioni di movimento (sway/bob), cambio arma e input.
## Va messo come figlio della Camera3D (vedi player.tscn).
##
## Le armi sono scene separate (vedi player/weapons/weapon.gd): aggiungile alla lista "weapons".
## Il sway sta qui, le animazioni dentro ogni arma: i due movimenti si sommano senza pestarsi i piedi.
## Comandi: click sinistro / RT = primario, click destro / LT = secondario (parata),
## F / tasto laterale del mouse / RB = parry, R / X (pad) = modalità successiva (es. incantesimo del bastone),
## rotella o 1-9 = cambio arma, Y (pad) = arma successiva.
##
## Le armi usano viewmodel.gdshader: FOV proprio e sempre disegnate davanti al mondo
## (non entrano nei muri e non si deformano col FOV del dash).

const VIEWMODEL_SHADER := preload("res://player/viewmodel.gdshader")

## Scene delle armi disponibili (la radice di ognuna deve estendere Weapon).
@export var weapons: Array[PackedScene] = []
@export var start_weapon := 0
## FOV con cui vengono disegnate le armi (indipendente da quello della camera).
@export_range(30.0, 120.0) var viewmodel_fov := 75.0

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

var _weapons: Array[Weapon] = []
var _current: Weapon
var _switching := false


func _ready() -> void:
	_base_position = position
	var n := get_parent()
	while n != null and not n is CharacterBody3D:
		n = n.get_parent()
	_player = n as CharacterBody3D

	for scene in weapons:
		var weapon := scene.instantiate() as Weapon
		if weapon == null:
			push_error("Viewmodel: la scena %s non estende Weapon" % scene.resource_path)
			continue
		weapon.player = _player
		weapon.visible = false
		add_child(weapon)
		_apply_style(weapon)
		_weapons.append(weapon)
	if not _weapons.is_empty():
		switch_to(clampi(start_weapon, 0, _weapons.size() - 1))


## L'arma attualmente impugnata (null se nessuna).
func current_weapon() -> Weapon:
	return _current


## Tutte le armi, nell'ordine dei tasti 1-9 (per la HUD).
func all_weapons() -> Array[Weapon]:
	return _weapons


func switch_to(index: int) -> void:
	if index < 0 or index >= _weapons.size() or _switching:
		return
	var next := _weapons[index]
	if next == _current or (_current and not _current.can_switch()):
		return
	_switching = true
	if _current:
		await _current.unequip()
	_current = next
	await _current.equip()
	_switching = false


func cycle(step: int) -> void:
	if _weapons.size() < 2:
		return
	var index := _weapons.find(_current)
	switch_to(posmod(index + step, _weapons.size()))


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Col mouse libero il click serve solo a ricatturarlo (lo gestisce player.gd).
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("weapon_next"):
		cycle(1)
	elif event.is_action_pressed("weapon_prev"):
		cycle(-1)
	for i in mini(_weapons.size(), 9):
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			switch_to(i)

	if _current == null or _switching:
		return
	if event.is_action_pressed("attack"):
		_current.primary_pressed()
	elif event.is_action_released("attack"):
		_current.primary_released()
	elif event.is_action_pressed("block"):
		_current.secondary_pressed()
	elif event.is_action_released("block"):
		_current.secondary_released()
	elif event.is_action_pressed("parry"):
		_current.parry_pressed()
	elif event.is_action_pressed("next_mode"):
		_current.next_mode_pressed()


func _process(delta: float) -> void:
	_idle_time += delta
	var velocity := _player.velocity if _player else Vector3.ZERO
	var grounded := _player != null and _player.is_on_floor()
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var sliding: bool = _player != null and _player.has_method("is_sliding") and _player.is_sliding()
	var run := clampf(horizontal / 14.0, 0.0, 1.0) if grounded and not sliding else 0.0

	_bob_time += delta * (7.0 + 5.0 * run)
	var target_pos := _base_position
	target_pos.x += sin(_bob_time * 0.5) * bob_amount * run
	target_pos.y += -absf(sin(_bob_time)) * bob_amount * run
	target_pos.y += sin(_idle_time * 1.6) * 0.004                       # respiro
	target_pos.y -= clampf(velocity.y * air_sway, -0.03, 0.03)          # salto / caduta
	if sliding:
		target_pos += Vector3(0.03, -0.05, 0.03)                          # armi basse in scivolata

	var mouse := Input.get_last_mouse_velocity() if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Vector2.ZERO
	var limit := deg_to_rad(max_mouse_sway_deg)
	var target_yaw := clampf(mouse.x * mouse_sway * 0.001, -limit, limit)
	var target_pitch := clampf(mouse.y * mouse_sway * 0.001, -limit, limit)

	var t := 1.0 - exp(-smoothing * delta)
	position = position.lerp(target_pos, t)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)
	rotation.x = lerp_angle(rotation.x, target_pitch, t)
	rotation.z = lerp_angle(rotation.z, 0.12 if sliding else 0.0, t)


# Materiale delle armi: viewmodel.gdshader (texture pixelate, FOV proprio, niente compenetrazioni)
# e nessuna ombra proiettata.
func _apply_style(weapon: Node) -> void:
	for child in weapon.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = Gore.NO_BLOOD_LAYER  # le macchie di sangue (Decal) non si proiettano sulle armi
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				var base := mat as BaseMaterial3D
				var styled := ShaderMaterial.new()
				styled.shader = VIEWMODEL_SHADER
				styled.set_shader_parameter("albedo_texture", base.albedo_texture)
				styled.set_shader_parameter("albedo_color", base.albedo_color)
				styled.set_shader_parameter("roughness", base.roughness)
				styled.set_shader_parameter("metallic", base.metallic)
				styled.set_shader_parameter("viewmodel_fov", viewmodel_fov)
				if base.emission_enabled:
					styled.set_shader_parameter("emission_color", base.emission)
					styled.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
				mi.set_surface_override_material(i, styled)
