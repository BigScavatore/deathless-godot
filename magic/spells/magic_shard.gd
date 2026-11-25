class_name MagicShardSpell
extends Spell
## Scheggia magica: un frammento di cristallo veloce che vola dritto verso il mirino.
## Danno basso, costo basso, si può lanciare a raffica tenendo premuto.

const Projectile := preload("res://magic/projectiles/magic_shard_projectile.gd")

@export var damage := 14.0
## Velocità (m/s).
@export var speed := 55.0
## Piccola dispersione casuale (gradi), così la raffica non sembra un laser.
@export var spread_deg := 0.8


func _init() -> void:
	id = &"magic_shard"
	display_name = "Scheggia magica"
	description = "Un frammento di cristallo che trafigge il nemico."
	mana_cost = 8.0
	cooldown = 0.22
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


func cast(caster: Node3D, aim: Transform3D) -> void:
	var shard := Projectile.new()
	shard.damage = damage
	shard.speed = speed
	shard.color = color
	shard.caster = caster
	var spread := deg_to_rad(spread_deg)
	var basis := aim.basis.rotated(aim.basis.x, randf_range(-spread, spread)).rotated(aim.basis.y, randf_range(-spread, spread))
	var root := caster.get_tree().current_scene
	root.add_child(shard)
	shard.global_transform = Transform3D(basis, aim.origin)
