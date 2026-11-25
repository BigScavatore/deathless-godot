class_name ArcaneOrb
extends Node3D
## Globo arcano della sinergia "Globi arcani" (bastone nella sinistra + spada nella destra,
## vedi player/weapons/synergies.gd).
## Prima gira attorno al player (la posizione la decide Synergies), poi un fendente lo lancia:
## vola dritto, e all'impatto esplode colpendo il bersaglio e tutti i nemici vicini.

var color := Color(0.62, 0.42, 1.0)
var damage := 30.0
var blast_damage := 18.0
var blast_radius := 2.6
var speed := 38.0
## Chi l'ha evocato: non viene colpito.
var caster: Node3D

var flying := false
var _dissipating := false
var _lifetime := 3.0
var _exclude: Array[RID] = []
var _visual: Node3D
var _trail: CPUParticles3D


func _ready() -> void:
	if caster is CollisionObject3D:
		_exclude.append((caster as CollisionObject3D).get_rid())
	_visual = Node3D.new()
	add_child(_visual)

	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 10
	sphere.rings = 5
	sphere.material = MagicFX.glow(color, 6.0)
	core.mesh = sphere
	_visual.add_child(core)

	var halo := MeshInstance3D.new()
	var outer := SphereMesh.new()
	outer.radius = 0.2
	outer.height = 0.4
	outer.radial_segments = 10
	outer.rings = 5
	outer.material = MagicFX.additive(color, 0.3)
	halo.mesh = outer
	_visual.add_child(halo)

	for mi in [core, halo]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).layers = Gore.NO_BLOOD_LAYER

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 2.5
	_visual.add_child(light)

	_trail = CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.04
	box.material = MagicFX.glow(color.lightened(0.3), 3.0)
	_trail.mesh = box
	_trail.layers = Gore.NO_BLOOD_LAYER
	_trail.amount = 16
	_trail.lifetime = 0.4
	_trail.local_coords = false
	_trail.spread = 180.0
	_trail.initial_velocity_min = 0.2
	_trail.initial_velocity_max = 0.8
	_trail.gravity = Vector3(0, 0.5, 0)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	_trail.scale_amount_curve = shrink
	add_child(_trail)

	# Comparsa: cresce dal nulla con un lampo.
	_visual.scale = Vector3.ONE * 0.01  # poi _process lo fa crescere
	MagicFX.flash(get_tree().current_scene, global_position, color, 3.0, 3.0, 0.2)
	MagicFX.sparks(get_tree().current_scene, global_position, Vector3.UP, color, 12, 180.0, Vector2(1.0, 3.0), 0.035, 0.4)


func _process(_delta: float) -> void:
	# Pulsa piano mentre aspetta.
	if not flying and not _dissipating:
		var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008 + get_instance_id())
		_visual.scale = _visual.scale.lerp(Vector3.ONE * pulse, 0.2)


## Lancia il globo verso `target`.
func launch(target: Vector3) -> void:
	flying = true
	var dir := (target - global_position).normalized()
	if dir.length() < 0.5:
		dir = Vector3.FORWARD
	look_at(global_position + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	_trail.amount = 40
	_trail.initial_velocity_max = 2.0
	Sfx.play_at(self, &"orb_launch", global_position, 0.0, 0.1, 6.0)
	MagicFX.flash(get_tree().current_scene, global_position, color, 4.0, 4.0, 0.15)


func _physics_process(delta: float) -> void:
	if not flying:
		return
	_lifetime -= delta
	var from := global_position
	var to := from - global_basis.z * speed * delta
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		_explode(hit.position, hit.normal, hit.collider as Node)
	elif _lifetime <= 0.0:
		_explode(to, global_basis.z, null)
	else:
		global_position = to


func _explode(at: Vector3, normal: Vector3, direct: Node) -> void:
	set_physics_process(false)
	var source := caster if is_instance_valid(caster) else self
	var landed := false
	if direct and direct.has_method("take_damage"):
		landed = direct.take_damage(damage, source) != Combat.HitResult.IGNORED
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var body := enemy as Node3D
		if body == null or body == direct or not body.has_method("take_damage"):
			continue
		if (body.global_position + Vector3.UP).distance_to(at) <= blast_radius + 0.4:  # dal busto
			if body.take_damage(blast_damage, source) != Combat.HitResult.IGNORED:
				landed = true

	var root := get_tree().current_scene
	Sfx.play_at(self, &"orb_blast", at, 2.0, 0.1, 8.0)
	MagicFX.shockwave(root, at + normal * 0.05, normal, color, 0.3, blast_radius * 2.0, 0.35)
	MagicFX.shockwave(root, at + normal * 0.05, Vector3.UP, color.lightened(0.3), 0.2, blast_radius * 1.4, 0.25)
	MagicFX.sparks(root, at + normal * 0.1, normal, color, 40, 85.0, Vector2(4.0, 12.0), 0.06, 0.7)
	MagicFX.sparks(root, at + normal * 0.1, normal, Color.WHITE, 14, 50.0, Vector2(8.0, 16.0), 0.035, 0.3)
	MagicFX.flash(root, at + normal * 0.5, color, 9.0, blast_radius * 3.0, 0.3)
	if landed:
		Combat.hitstop(self, 0.06)
	if is_instance_valid(caster) and caster.has_method("add_shake"):
		caster.add_shake(0.3 if landed else 0.15)
	queue_free()


## Svanisce senza esplodere (sinergia interrotta).
func dissipate() -> void:
	_dissipating = true
	flying = false
	set_physics_process(false)
	_trail.emitting = false
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(queue_free)
