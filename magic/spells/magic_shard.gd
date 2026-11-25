class_name MagicShardSpell
extends Spell
## Scheggia magica: un frammento di cristallo che parte con un lampo, vola dritto verso il mirino
## lasciando dietro di sé un raggio di luce, e si frantuma sul bersaglio con un'onda d'urto.
## Lenta da lanciare ma colpisce forte: due/tre schegge per abbattere un cavaliere.

const Projectile := preload("res://magic/projectiles/magic_shard_projectile.gd")

@export var damage := 34.0
## Velocità (m/s).
@export var speed := 75.0
## Piccola dispersione casuale (gradi).
@export var spread_deg := 0.3


func _init() -> void:
	id = &"magic_shard"
	display_name = "Scheggia magica"
	description = "Un frammento di cristallo che trafigge il nemico."
	mana_cost = 15.0
	cooldown = 0.65
	cast_sound = &"spell_shard"
	color = Color(0.62, 0.42, 1.0)
	icon = PackedStringArray([
		"........aa.",
		".......adda",
		"......acdca",
		".....acdcba",
		"....acdcba.",
		"...acccba..",
		"..acccba...",
		".abccba....",
		"abbbba.....",
		"abbba......",
		".aaa.......",
	])


func cast(caster: Node3D, aim: Transform3D, mods := {}) -> void:
	var shard := Projectile.new()
	shard.bounces = int(mods.get("bounces", 0))
	shard.reflectable = bool(mods.get("reflectable", false))
	shard.damage = damage
	shard.speed = speed
	shard.color = color
	shard.caster = caster
	var spread := deg_to_rad(spread_deg)
	var basis := aim.basis.rotated(aim.basis.x, randf_range(-spread, spread)).rotated(aim.basis.y, randf_range(-spread, spread))
	var root := caster.get_tree().current_scene
	# Posizione impostata prima di entrare nella scena: il proiettile in _ready() si segna da dove parte.
	var world := Transform3D(basis, aim.origin)
	shard.transform = (root as Node3D).global_transform.affine_inverse() * world if root is Node3D else world
	root.add_child(shard)

	# Lampo e onda d'urto dove parte la scheggia, scintille in avanti.
	var forward := -aim.basis.z
	MagicFX.flash(root, aim.origin, color, 5.0, 5.0, 0.15)
	MagicFX.shockwave(root, aim.origin + forward * 0.15, forward, color, 0.15, 1.0, 0.2)
	MagicFX.sparks(root, aim.origin, forward, color, 16, 30.0, Vector2(4.0, 10.0), 0.04, 0.3)
