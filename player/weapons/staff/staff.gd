extends Weapon
## Bastone magico: lancia l'incantesimo selezionato.
##   click sinistro (tenuto)  = lancia; tenendo premuto continua al ritmo del "cooldown" dell'incantesimo
##   R / X (pad)              = incantesimo successivo (tra quelli sbloccati)
## Ogni incantesimo costa mana (player.use_mana); senza mana il cristallo "sfrigola" e non succede niente.
##
## Incantesimi: la lista "spells" contiene tutti quelli che il bastone conosce, "unlocked" gli id di
## quelli già disponibili. Per sbloccarne uno durante il gioco (es. raccogliendo un tomo):
##     staff.unlock_spell(&"id_incantesimo")
## Le pose sono nell'AnimationPlayer della scena: "equip", "cast", "fizzle", "switch".

signal spell_changed(spell: Spell)
signal spell_unlocked(spell: Spell)

## Tutti gli incantesimi che il bastone conosce (anche quelli ancora bloccati).
@export var spells: Array[Spell] = [MagicShardSpell.new()]
@export var unlocked: Array[StringName] = [&"magic_shard"]
## Energia della luce del cristallo a riposo e nel lampo del lancio.
@export var glow_idle := 1.2
@export var glow_cast := 6.0

var _index := 0
var _holding := false
var _ready_at := 0
var _crystal_material: ShaderMaterial
var _glow_tween: Tween

@onready var _light: OmniLight3D = get_node_or_null("Model/StaffModel/StaffArm/Staff/Crystal/Glow")


func _process(_delta: float) -> void:
	if _holding and visible:
		_try_cast()
	# Il cristallo "respira" piano.
	if _crystal() and (_glow_tween == null or not _glow_tween.is_running()):
		var pulse := glow_idle * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.004))
		_crystal_material.set_shader_parameter("emission_energy", pulse)


# --- Input -----------------------------------------------------------------

func primary_pressed() -> void:
	_holding = true
	_try_cast()


func primary_released() -> void:
	_holding = false


func next_mode_pressed() -> void:
	var list := _available()
	if list.size() < 2:
		Sfx.play(self, &"spell_switch", -10.0, 0.1)
		return
	_index = (_index + 1) % list.size()
	_play_from_start(&"switch")
	Sfx.play(self, &"spell_switch", -4.0, 0.05)
	_apply_spell_color()
	_flash(glow_cast * 0.6, 0.3)
	spell_changed.emit(current_spell())


func can_switch() -> bool:
	return not (anim.is_playing() and anim.current_animation == &"cast")


func reset_state() -> void:
	_holding = false


func equip() -> void:
	_apply_spell_color()
	await super.equip()


# --- Incantesimi -----------------------------------------------------------

## L'incantesimo selezionato (null se nessuno è sbloccato).
func current_spell() -> Spell:
	var list := _available()
	if list.is_empty():
		return null
	return list[clampi(_index, 0, list.size() - 1)]


func unlock_spell(id: StringName) -> void:
	if unlocked.has(id):
		return
	unlocked.append(id)
	for spell in spells:
		if spell.id == id:
			spell_unlocked.emit(spell)


func hud_info() -> Dictionary:
	var charge := 1.0
	var spell := current_spell()
	if spell:
		var left := float(_ready_at - Time.get_ticks_msec()) / 1000.0
		charge = clampf(1.0 - left / maxf(spell.cooldown, 0.01), 0.0, 1.0)
	return {"spell": spell, "spells": _available(), "ready": charge}


func _available() -> Array[Spell]:
	var list: Array[Spell] = []
	for spell in spells:
		if spell and unlocked.has(spell.id):
			list.append(spell)
	return list


func _try_cast() -> void:
	var spell := current_spell()
	var now := Time.get_ticks_msec()
	if spell == null or now < _ready_at or player == null:
		return
	if not player.has_method("use_mana") or not player.use_mana(spell.mana_cost):
		_ready_at = now + 350
		_play_from_start(&"fizzle")
		Sfx.play(self, &"spell_fizzle", -6.0)
		return
	_ready_at = now + int(spell.cooldown * 1000.0)
	spell.cast(player, _aim())
	_play_from_start(&"cast")
	Sfx.play(self, &"spell_shard", -4.0, 0.08)
	_flash(glow_cast, 0.25)
	if player.has_method("add_shake"):
		player.add_shake(0.06)


## Da dove parte l'incantesimo e verso dove va: parte poco davanti e a destra della camera
## (vicino al cristallo) e punta a ciò che c'è sotto il mirino, così si colpisce dove si mira.
func _aim() -> Transform3D:
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var target := eye + forward * 100.0
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(eye, target, 1, exclude))
	if not hit.is_empty():
		target = hit.position
	var origin := eye + forward * 0.6 + camera.global_basis.x * 0.18 - camera.global_basis.y * 0.1
	# Se il bersaglio è vicinissimo (o dietro il punto di partenza) si parte dagli occhi.
	if (target - origin).dot(forward) < 0.5:
		origin = eye
	return Transform3D(Basis.looking_at(target - origin, camera.global_basis.y), origin)


# --- Cristallo -------------------------------------------------------------

func _crystal() -> ShaderMaterial:
	if _crystal_material == null:
		var mesh := get_node_or_null("Model/StaffModel/StaffArm/Staff/Crystal") as MeshInstance3D
		if mesh:
			_crystal_material = mesh.get_surface_override_material(0) as ShaderMaterial
	return _crystal_material


func _apply_spell_color() -> void:
	var spell := current_spell()
	var c := spell.color if spell else Color(0.5, 0.5, 0.5)
	if _crystal():
		_crystal_material.set_shader_parameter("emission_color", c)
	if _light:
		_light.light_color = c


func _flash(energy: float, duration: float) -> void:
	if _glow_tween:
		_glow_tween.kill()
	if _crystal() == null and _light == null:
		return  # un Tween senza animazioni darebbe errore
	_glow_tween = create_tween().set_parallel()
	if _crystal():
		_crystal_material.set_shader_parameter("emission_energy", energy)
		_glow_tween.tween_method(func(v: float) -> void: _crystal_material.set_shader_parameter("emission_energy", v),
				energy, glow_idle, duration)
	if _light:
		_light.light_energy = energy * 0.5
		_glow_tween.tween_property(_light, "light_energy", 0.4, duration)


func _play_from_start(anim_name: StringName) -> void:
	anim.play(anim_name)
	anim.seek(0.0, true)
