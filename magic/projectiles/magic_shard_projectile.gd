extends Node3D
## Proiettile della scheggia magica (vedi magic/spells/magic_shard.gd).
## Vola lungo il suo -Z; a ogni frame fisico controlla con un raggio il tratto percorso,
## così anche a velocità alte non attraversa muri o nemici sottili.
## Dietro di sé lascia un raggio di luce che parte dal bastone: quando colpisce, il raggio
## resta acceso un attimo e poi svanisce. Mesh, luce e scia sono costruiti da codice.
##
## Rimbalzi (sinergia "Specchio arcano", bastone + scudo): con `bounces` > 0 la scheggia rimbalza
## sui muri invece di fermarsi (ogni tratto lascia il suo raggio). Se torna verso chi l'ha lanciata
## e lui la respinge con lo scudo (parata o parry, vedi player.reflect_strength), riparte verso il
## mirino più veloce e più forte, con i rimbalzi ricaricati.

const RenderLayers := preload("res://effects/layers.gd")
const Beam := preload("res://magic/magic_beam.gd")

var damage := 28.0
var speed := 75.0
var color := Color(0.62, 0.42, 1.0)
## Chi l'ha lanciata: non viene colpito.
var caster: Node3D
## Secondi prima che sparisca se non colpisce niente.
var lifetime := 2.0
## Quante volte può ancora rimbalzare sui muri (0 = si ferma al primo impatto).
var bounces := 0
## Se true, lo scudo di chi l'ha lanciata può respingerla.
var reflectable := false

var _exclude: Array[RID] = []
var _start := Vector3.ZERO
var _beam: Beam
var _done := false
var _max_bounces := 0
var _travelled := 0.0


func _ready() -> void:
	if caster is CollisionObject3D:
		_exclude.append((caster as CollisionObject3D).get_rid())
	_start = global_position

	var shard := MeshInstance3D.new()
	shard.mesh = _shard_mesh()
	shard.material_override = MagicFX.glow(color, 5.0)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shard.layers = RenderLayers.NO_BLOOD
	shard.scale = Vector3.ONE * 1.6
	add_child(shard)

	var halo := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = MagicFX.additive(color, 0.35)
	halo.mesh = sphere
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.layers = RenderLayers.NO_BLOOD
	add_child(halo)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.5
	light.omni_range = 4.5
	add_child(light)

	var trail := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.05
	box.material = MagicFX.glow(color.lightened(0.3), 3.0)
	trail.mesh = box
	trail.layers = RenderLayers.NO_BLOOD
	trail.amount = 40
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.direction = Vector3.BACK
	trail.spread = 35.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 2.5
	trail.gravity = Vector3(0, -2, 0)
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	trail.scale_amount_curve = shrink
	add_child(trail)

	_max_bounces = bounces
	if bounces > 0:
		lifetime += 0.6 * bounces
	_new_beam()


func _physics_process(delta: float) -> void:
	if _done:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_finish()
		return
	if reflectable and _try_reflect():
		return
	var from := global_position
	var to := from - global_basis.z * speed * delta
	_travelled += speed * delta
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		global_position = to
		_beam.set_points(_start, to)
		return
	global_position = hit.position
	_beam.set_points(_start, hit.position)
	var target := hit.collider as Node
	var damageable := target != null and target.has_method("take_damage")
	if not damageable and bounces > 0:
		_bounce(hit.position, hit.normal)
		return
	if damageable:
		var result = target.take_damage(damage, caster if is_instance_valid(caster) else self)
		if result != Combat.HitResult.IGNORED:
			Combat.hitstop(self, 0.05)
			if is_instance_valid(caster) and caster.has_method("add_shake"):
				caster.add_shake(0.15)
	_impact(hit.position, hit.normal)
	_finish()


## Rimbalza sul muro: nuova direzione riflessa, nuovo tratto di raggio, scintille piccole.
func _bounce(at: Vector3, normal: Vector3) -> void:
	bounces -= 1
	var dir := (-global_basis.z).bounce(normal).normalized()
	global_position = at + normal * 0.05
	_look_along(dir)
	_new_beam()
	var root := get_tree().current_scene
	Sfx.play_at(self, &"shard_hit", at, -8.0, 0.2, 4.0)
	MagicFX.sparks(root, at + normal * 0.05, normal, color, 12, 60.0, Vector2(2.0, 6.0), 0.04, 0.35)
	MagicFX.flash(root, at + normal * 0.3, color, 3.0, 3.0, 0.15)


## Se sta tornando verso chi l'ha lanciata, ed è vicina, prova a farsi respingere dal suo scudo.
func _try_reflect() -> bool:
	if not is_instance_valid(caster) or not caster.has_method("reflect_strength") or _travelled < 3.0:
		return false
	var chest := caster.global_position + Vector3.UP * 1.2
	var to_caster := chest - global_position
	if to_caster.length() > 1.8 or (-global_basis.z).dot(to_caster) <= 0.0:
		return false
	var strength: float = caster.reflect_strength(global_position)
	if strength <= 0.0:
		return false
	# Respinta: riparte verso il mirino, più veloce e più forte, con i rimbalzi ricaricati.
	speed *= strength
	damage *= strength
	bounces = _max_bounces
	lifetime = maxf(lifetime, 1.5 + 0.6 * bounces)
	_travelled = 0.0
	var camera := get_viewport().get_camera_3d()
	var target := camera.global_position - camera.global_basis.z * 100.0
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(camera.global_position, target, 1, _exclude))
	if not hit.is_empty():
		target = hit.position
	_look_along((target - global_position).normalized())
	color = color.lightened(0.15)
	_new_beam()
	var root := get_tree().current_scene
	MagicFX.shockwave(root, global_position, -global_basis.z, color, 0.2, 1.6, 0.25)
	MagicFX.sparks(root, global_position, -global_basis.z, Color.WHITE, 18, 50.0, Vector2(4.0, 10.0), 0.04, 0.35)
	MagicFX.flash(root, global_position, color, 6.0, 5.0, 0.2)
	Sfx.play_at(self, &"parry" if strength > 1.5 else &"block", global_position, -2.0, 0.08, 6.0)
	Combat.hitstop(self, 0.05)
	if caster.has_method("add_shake"):
		caster.add_shake(0.25)
	return true


func _look_along(dir: Vector3) -> void:
	if dir.length() < 0.5:
		return
	global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)


## Chiude il tratto di raggio attuale (che svanisce) e ne inizia uno nuovo da qui.
func _new_beam() -> void:
	if is_instance_valid(_beam):
		_beam.fade(0.4)
	_start = global_position
	_beam = Beam.new(color)
	get_tree().current_scene.add_child(_beam)


## Si ferma: il raggio svanisce, la scheggia sparisce poco dopo (la scia finisce di dissolversi).
func _finish() -> void:
	_done = true
	if is_instance_valid(_beam):
		_beam.fade(0.4)
	for child in get_children():
		if child is MeshInstance3D or child is OmniLight3D:
			child.queue_free()
		elif child is CPUParticles3D:
			(child as CPUParticles3D).emitting = false
	get_tree().create_timer(0.5).timeout.connect(queue_free)


func _impact(at: Vector3, normal: Vector3) -> void:
	var root := get_tree().current_scene
	Sfx.play_at(self, &"shard_hit", at, 0.0, 0.12, 6.0)
	MagicFX.sparks(root, at + normal * 0.05, normal, color, 30, 75.0, Vector2(3.0, 10.0), 0.06, 0.6)
	MagicFX.sparks(root, at + normal * 0.05, normal, Color(1, 1, 1), 10, 40.0, Vector2(6.0, 14.0), 0.035, 0.3)
	MagicFX.shockwave(root, at + normal * 0.04, normal, color, 0.2, 2.4, 0.3)
	MagicFX.flash(root, at + normal * 0.4, color, 7.0, 6.0, 0.25)


# --- Mesh (condivisa tra tutte le schegge) ---------------------------------

static var _shard: ArrayMesh


## Bipiramide allungata a 4 lati lungo -Z: una scheggia di cristallo.
static func _shard_mesh() -> ArrayMesh:
	if _shard:
		return _shard
	var tip := Vector3(0, 0, -0.32)
	var tail := Vector3(0, 0, 0.12)
	var ring := [Vector3(0.045, 0, 0), Vector3(0, 0.045, 0), Vector3(-0.045, 0, 0), Vector3(0, -0.045, 0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		for tri in [[tip, b, a], [tail, a, b]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	_shard = st.commit()
	return _shard
