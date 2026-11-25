extends Node3D
## Proiettile della scheggia magica (vedi magic/spells/magic_shard.gd).
## Vola lungo il suo -Z; a ogni frame fisico controlla con un raggio il tratto percorso,
## così anche a velocità alte non attraversa muri o nemici sottili.
## Tutto (mesh, luce, scia) è costruito da codice: nessuna scena da mantenere.

var damage := 14.0
var speed := 55.0
var color := Color(0.62, 0.42, 1.0)
## Chi l'ha lanciata: non viene colpito.
var caster: Node3D
## Secondi prima che sparisca se non colpisce niente.
var lifetime := 2.5

var _exclude: Array[RID] = []
var _trail: CPUParticles3D


func _ready() -> void:
	if caster is CollisionObject3D:
		_exclude.append((caster as CollisionObject3D).get_rid())

	var shard := MeshInstance3D.new()
	shard.mesh = _shard_mesh()
	shard.material_override = _glow_material(color, 4.0)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shard.layers = Gore.NO_BLOOD_LAYER
	add_child(shard)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 3.5
	add_child(light)

	_trail = CPUParticles3D.new()
	_trail.mesh = _spark_mesh(color)
	_trail.layers = Gore.NO_BLOOD_LAYER
	_trail.amount = 24
	_trail.lifetime = 0.25
	_trail.local_coords = false
	_trail.direction = Vector3.BACK
	_trail.spread = 25.0
	_trail.initial_velocity_min = 0.5
	_trail.initial_velocity_max = 2.0
	_trail.gravity = Vector3.ZERO
	_trail.scale_amount_min = 0.5
	_trail.scale_amount_max = 1.2
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	_trail.scale_amount_curve = shrink
	add_child(_trail)


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from - global_basis.z * speed * delta
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		global_position = to
		return
	var target := hit.collider as Node
	if target and target.has_method("take_damage"):
		target.take_damage(damage, caster if is_instance_valid(caster) else self)
	_impact(hit.position, hit.normal)
	queue_free()


func _impact(at: Vector3, normal: Vector3) -> void:
	var root := get_tree().current_scene
	Sfx.play_at(self, &"shard_hit", at, -2.0, 0.12, 5.0)

	# Schegge che rimbalzano dal punto d'impatto + lampo di luce.
	var burst := CPUParticles3D.new()
	burst.mesh = _spark_mesh(color)
	burst.layers = Gore.NO_BLOOD_LAYER
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 18
	burst.lifetime = 0.45
	burst.direction = normal
	burst.spread = 70.0
	burst.initial_velocity_min = 3.0
	burst.initial_velocity_max = 8.0
	burst.gravity = Vector3(0, -12, 0)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	burst.scale_amount_curve = shrink
	burst.finished.connect(burst.queue_free)
	root.add_child(burst)
	burst.global_position = at + normal * 0.05
	burst.emitting = true

	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 4.0
	flash.omni_range = 4.0
	root.add_child(flash)
	flash.global_position = at + normal * 0.3
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.2)
	tween.tween_callback(flash.queue_free)


# --- Mesh e materiali (condivisi tra tutte le schegge) ---------------------

static var _shard: ArrayMesh
static var _sparks := {}


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


static func _spark_mesh(c: Color) -> Mesh:
	var key := c.to_html()
	if not _sparks.has(key):
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.05
		box.material = _glow_material(c.lightened(0.3), 3.0)
		_sparks[key] = box
	return _sparks[key]


static func _glow_material(c: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c.lightened(0.35)
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = energy
	return mat
