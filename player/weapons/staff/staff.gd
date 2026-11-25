extends Weapon
## Bastone magico: lancia l'incantesimo selezionato. Va in entrambe le mani (nella sinistra è specchiato
## e l'incantesimo parte dal lato sinistro).
##   tasto della mano (tenuto) = lancia; tenendo premuto continua al ritmo del "cooldown" dell'incantesimo.
##                               Il lancio ha una breve carica: l'incantesimo parte nel frame "_release_cast"
##                               dell'animazione "cast", quando il bastone scatta in avanti.
##   R / X (pad)               = incantesimo successivo (tra quelli sbloccati)
## Ogni incantesimo costa mana (player.use_mana); senza mana il cristallo "sfrigola" e non succede niente.
##
## Incantesimi: la lista "spells" contiene tutti quelli che il bastone sa lanciare; quali sono
## disponibili lo decide il player (player.known_spells), così valgono per ogni bastone in ogni mano.
## Per impararne uno durante il gioco (es. raccogliendo un tomo):
##     player.learn_spell(spell)          oppure, dal bastone, per id:   staff.unlock_spell(&"id")
## Le pose sono nell'AnimationPlayer della scena: "equip", "cast", "fizzle", "switch".

signal spell_changed(spell: Spell)

## Tutti gli incantesimi che il bastone sa lanciare (anche quelli che il player non conosce ancora).
@export var spells: Array[Spell] = [MagicShardSpell.new()]
## Usata solo se il bastone non è in mano al player (che ha la sua lista, known_spells).
@export var unlocked: Array[StringName] = [&"magic_shard"]
## Energia della luce del cristallo a riposo e nel lampo del lancio.
@export var glow_idle := 1.2
@export var glow_cast := 6.0

var _index := 0
var _holding := false
var _ready_at := 0
var _crystal_material: ShaderMaterial
var _glow_tween: Tween
var _casting_spell: Spell

@onready var _light: OmniLight3D = get_node_or_null("Model/StaffModel/StaffArm/Staff/Crystal/Glow")


func _process(_delta: float) -> void:
	if _holding and visible:
		_try_cast()
	# Il cristallo "respira" piano.
	if _crystal() and (_glow_tween == null or not _glow_tween.is_running()):
		var pulse := glow_idle * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.004))
		_crystal_material.set_shader_parameter("emission_energy", pulse)


# --- Input -----------------------------------------------------------------

func use_pressed() -> void:
	_holding = true
	_try_cast()


func use_released() -> void:
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
	return not _is_casting()


func _is_casting() -> bool:
	return anim.is_playing() and anim.current_animation == &"cast"


func reset_state() -> void:
	_holding = false
	_casting_spell = null


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
	for spell in spells:
		if spell.id == id:
			if player and player.has_method("learn_spell"):
				player.learn_spell(spell)
			elif not unlocked.has(id):
				unlocked.append(id)


func hud_info() -> Dictionary:
	var charge := 1.0
	var spell := current_spell()
	if spell:
		var left := float(_ready_at - Time.get_ticks_msec()) / 1000.0
		charge = clampf(1.0 - left / maxf(spell.cooldown, 0.01), 0.0, 1.0)
	return {"spell": spell, "spells": _available(), "ready": charge}


func _available() -> Array[Spell]:
	var list: Array[Spell] = []
	var learned := player != null and player.has_method("knows_spell")
	for spell in spells:
		if spell == null:
			continue
		if (learned and player.knows_spell(spell.id)) or (not learned and unlocked.has(spell.id)):
			list.append(spell)
	return list


func _try_cast() -> void:
	var spell := current_spell()
	var now := Time.get_ticks_msec()
	if spell == null or now < _ready_at or player == null or _is_casting():
		return
	if not player.has_method("use_mana") or not player.use_mana(spell.mana_cost):
		_ready_at = now + 350
		_play_from_start(&"fizzle")
		Sfx.play(self, &"spell_fizzle", -6.0)
		return
	_ready_at = now + int(spell.cooldown * 1000.0)
	_casting_spell = spell
	_play_from_start(&"cast")  # carica: il cristallo si illumina, poi _release_cast()
	_flash(glow_cast * 0.5, 0.12)


# Chiamato dall'animazione "cast" (traccia metodo) quando il bastone scatta in avanti.
func _release_cast() -> void:
	var spell := _casting_spell
	_casting_spell = null
	if spell == null or player == null:
		return
	spell.cast(player, _aim())
	if spell.cast_sound != &"":
		Sfx.play(self, spell.cast_sound, -2.0, 0.08)
	_flash(glow_cast, 0.3)
	if player.has_method("add_shake"):
		player.add_shake(spell.cast_shake)


## Da dove parte l'incantesimo e verso dove va: parte poco davanti alla camera, dal lato della mano
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
	var origin := eye + forward * 0.6 + camera.global_basis.x * 0.18 * side() - camera.global_basis.y * 0.1
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

