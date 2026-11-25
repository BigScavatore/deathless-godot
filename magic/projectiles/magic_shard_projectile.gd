extends Node3D
## Proiettile della scheggia magica (vedi magic/spells/magic_shard.gd).
## Vola lungo il suo -Z; a ogni frame fisico controlla con un raggio il tratto percorso,
## così anche a velocità alte non attraversa muri o nemici sottili.
## Dietro di sé lascia un raggio di luce che parte dal bastone: quando colpisce, il raggio
## resta acceso un attimo e poi svanisce. Mesh, luce e scia sono costruiti da codice.

var damage := 28.0
var speed := 75.0
var color := Color(0.62, 0.42, 1.0)
## Chi l'ha lanciata: non viene colpito.
var caster: Node3D
## Secondi prima che sparisca se non colpisce niente.
var lifetime := 2.0

var _exclude: Array[RID] = []
var _start := Vector3.ZERO
var _beam: MagicFX.Beam
var _done := false


func _ready() -> void:
	if caster is CollisionObject3D:
		_exclude.append((caster as CollisionObject3D).get_rid())
	_start = global_position

	var shard := MeshInstance3D.new()
	shard.mesh = _shard_mesh()
	shard.material_override = MagicFX.glow(color, 5.0)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shard.layers = Gore.NO_BLOOD_LAYER
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
	halo.layers = Gore.NO_BLOOD_LAYER
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
	trail.layers = Gore.NO_BLOOD_LAYER
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

	_beam = MagicFX.beam(get_tree().current_scene, color)


func _physics_process(delta: float) -> void:
	if _done:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_finish()
		return
	var from := global_position
	var to := from - global_basis.z * speed * delta
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		global_position = to
		_beam.set_points(_start, to)
		return
	global_position = hit.position
	_beam.set_points(_start, hit.position)
	var target := hit.collider as Node
	if target and target.has_method("take_damage"):
		var result = target.take_damage(damage, caster if is_instance_valid(caster) else self)
		if result != Combat.HitResult.IGNORED:
			Combat.hitstop(self, 0.05)
			if is_instance_valid(caster) and caster.has_method("add_shake"):
				caster.add_shake(0.15)
	_impact(hit.position, hit.normal)
	_finish()


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
