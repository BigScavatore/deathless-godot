extends Node3D
## Porta-armi in prima persona: due mani (come in Dark Souls), oscillazioni di movimento, cambio arma e input.
## Va messo come figlio della Camera3D (vedi player.tscn).
##
## Ogni mano ha una lista di armi ("right_hand", "left_hand") e ne impugna una alla volta;
## qualsiasi arma va in qualsiasi mano: se è modellata per l'altra mano viene specchiata
## (vedi player/weapons/weapon.gd). Il sway sta qui, le animazioni dentro ogni arma.
##
## Comandi:
##   click sinistro / RT        = arma nella mano destra (fendente, lancio, parata...)
##   click destro / LT          = arma nella mano sinistra
##   F / tasto laterale / RB    = parry (con lo scudo, in qualunque mano)
##   R / X (pad)                = modalità successiva (es. incantesimo del bastone)
##   E / rotella giù / croce dx = arma successiva nella mano destra
##   Q / rotella su / croce sx  = arma successiva nella mano sinistra
## Per cambiare l'equipaggiamento da codice (inventario, oggetti raccolti): set_hand_items().
## Certe coppie di armi hanno una sinergia (vedi player/weapons/synergies.gd): il nodo "synergies"
## viene aggiornato a ogni cambio d'arma.
##
## Le armi usano viewmodel.gdshader: FOV proprio e sempre disegnate davanti al mondo
## (non entrano nei muri e non si deformano col FOV del dash).

const RenderLayers := preload("res://effects/layers.gd")

signal hand_changed(hand: Weapon.Hand, weapon: Weapon)

const VIEWMODEL_SHADER := preload("res://player/viewmodel.gdshader")
const RIGHT := Weapon.Hand.RIGHT
const LEFT := Weapon.Hand.LEFT

## Armi a disposizione della mano destra / sinistra (la radice di ognuna deve estendere Weapon).
## La stessa scena può stare in entrambe le liste: ogni mano ha la sua copia.
@export var right_hand: Array[PackedScene] = []
@export var left_hand: Array[PackedScene] = []
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

## Per ogni mano: le armi istanziate, l'indice di quella in mano, se sta cambiando arma.
var _slots := {}
var _index := {RIGHT: 0, LEFT: 0}
var _switching := {RIGHT: false, LEFT: false}

## Sinergie tra le armi delle due mani.
var synergies: Synergies


func _ready() -> void:
	_base_position = position
	var n := get_parent()
	while n != null and not n is CharacterBody3D:
		n = n.get_parent()
	_player = n as CharacterBody3D
	var empty_right: Array[Weapon] = []
	var empty_left: Array[Weapon] = []
	_slots = {RIGHT: empty_right, LEFT: empty_left}
	synergies = Synergies.new()
	synergies.name = "Synergies"
	synergies.player = _player
	add_child(synergies)
	set_hand_items(RIGHT, right_hand)
	set_hand_items(LEFT, left_hand)


# --- Equipaggiamento -------------------------------------------------------

## Sostituisce le armi di una mano (e impugna la prima).
func set_hand_items(hand: Weapon.Hand, scenes: Array[PackedScene]) -> void:
	for old: Weapon in _slots[hand]:
		old.queue_free()
	var list: Array[Weapon] = []
	for scene in scenes:
		if scene == null:
			continue
		var weapon := scene.instantiate() as Weapon
		if weapon == null:
			push_error("Viewmodel: la scena %s non estende Weapon" % scene.resource_path)
			continue
		weapon.player = _player
		weapon.hand = hand
		weapon.synergies = synergies
		weapon.visible = false
		# Modellata per l'altra mano: specchiata.
		weapon.scale = Vector3(-1, 1, 1) if weapon.native_hand != hand else Vector3.ONE
		add_child(weapon)
		_apply_style(weapon)
		list.append(weapon)
	_slots[hand] = list
	_index[hand] = 0
	if not list.is_empty():
		_equip(hand, list[0])


## L'arma impugnata da una mano (null se la mano è vuota).
func item(hand: Weapon.Hand) -> Weapon:
	if not _slots.has(hand):
		return null
	var list: Array = _slots[hand]
	return list[_index[hand]] if not list.is_empty() else null


## Tutte le armi di una mano, nell'ordine in cui si ciclano.
func items(hand: Weapon.Hand) -> Array[Weapon]:
	return _slots[hand]


func slot_index(hand: Weapon.Hand) -> int:
	return _index[hand]


## Impugna l'arma successiva della mano.
func cycle(hand: Weapon.Hand) -> void:
	var list: Array = _slots[hand]
	if list.size() < 2 or _switching[hand] or _any_exclusive():
		return
	var current := item(hand)
	if current and not current.can_switch():
		return
	_switching[hand] = true
	if current:
		await current.unequip()
	_index[hand] = (_index[hand] + 1) % list.size()
	await _equip(hand, list[_index[hand]])
	_switching[hand] = false


func _equip(hand: Weapon.Hand, weapon: Weapon) -> void:
	synergies.refresh(item(RIGHT), item(LEFT))
	hand_changed.emit(hand, weapon)
	await weapon.equip()


# --- Difesa (chiamate dal player quando viene colpito) ----------------------

## Chiede alle armi in mano se parano il colpo: un parry vince su una parata.
func defend(source_position: Vector3) -> Combat.HitResult:
	var result := Combat.HitResult.HIT
	for hand in [LEFT, RIGHT]:
		var weapon := item(hand)
		if weapon == null:
			continue
		var r := weapon.defend(source_position)
		if r == Combat.HitResult.PARRIED:
			return r
		if r == Combat.HitResult.BLOCKED:
			result = r
	return result


## Il moltiplicatore più alto tra le armi in mano che possono respingere un proiettile amico (0 = nessuna).
func reflect_strength(source_position: Vector3) -> float:
	var best := 0.0
	for hand in [LEFT, RIGHT]:
		var weapon := item(hand)
		if weapon:
			best = maxf(best, weapon.reflect_strength(source_position))
	return best


func is_invulnerable() -> bool:
	for hand in [RIGHT, LEFT]:
		var weapon := item(hand)
		if weapon and weapon.is_invulnerable():
			return true
	return false


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Col mouse libero il click serve solo a ricatturarlo (lo gestisce player.gd).
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("cycle_right"):
		cycle(RIGHT)
	elif event.is_action_pressed("cycle_left"):
		cycle(LEFT)
	elif event.is_action("attack"):
		_use(RIGHT, event.is_pressed())
	elif event.is_action("block"):
		_use(LEFT, event.is_pressed())
	elif event.is_action_pressed("parry"):
		for hand in [LEFT, RIGHT]:
			var weapon := _usable(hand)
			if weapon and weapon.can_parry():
				weapon.parry_pressed()
				break
	elif event.is_action_pressed("next_mode"):
		# Va alla prima mano con più modalità (es. un bastone), la destra prima.
		for hand in [RIGHT, LEFT]:
			var weapon := _usable(hand)
			if weapon and weapon.hud_info().has("spell"):
				weapon.next_mode_pressed()
				break


func _use(hand: Weapon.Hand, pressed: bool) -> void:
	var weapon := _usable(hand)
	if weapon == null:
		return
	if pressed:
		weapon.use_pressed()
	else:
		weapon.use_released()


## L'arma della mano, se in questo momento può ricevere input.
func _usable(hand: Weapon.Hand) -> Weapon:
	var weapon := item(hand)
	if weapon == null or _switching[hand]:
		return null
	var other := item(LEFT if hand == RIGHT else RIGHT)
	if other and other.is_exclusive():
		return null
	return weapon


func _any_exclusive() -> bool:
	for hand in [RIGHT, LEFT]:
		var weapon := item(hand)
		if weapon and weapon.is_exclusive():
			return true
	return false


func _process(delta: float) -> void:
	# Se una mano fa un'azione ampia (fendente, critico), l'altra si abbassa per lasciarle spazio.
	var right := item(RIGHT)
	var left := item(LEFT)
	if right and left:
		left.set_lowered(right.wants_other_hand_lowered())
		right.set_lowered(left.wants_other_hand_lowered())

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
		mi.layers = RenderLayers.NO_BLOOD  # le macchie di sangue (Decal) non si proiettano sulle armi
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
