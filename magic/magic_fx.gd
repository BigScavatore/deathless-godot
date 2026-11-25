class_name MagicFX
## Effetti visivi riusabili dagli incantesimi: lampi di luce, onde d'urto, scintille, raggi.
## Tutto è costruito da codice (mesh semplici, materiali additivi, niente texture da importare)
## e si distrugge da solo quando ha finito.
##
##   MagicFX.flash(root, pos, color)                  lampo di luce che si spegne
##   MagicFX.shockwave(root, pos, normal, color)      anello che si allarga e svanisce
##   MagicFX.sparks(root, pos, dir, color)            schizzo di scintille
##   var beam := MagicFX.beam(root, color)            raggio tra due punti (vedi la classe Beam)


## Luce puntiforme che parte forte e si spegne in `duration` secondi.
static func flash(root: Node, pos: Vector3, color: Color, energy := 5.0, light_range := 5.0, duration := 0.18) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	root.add_child(light)
	light.global_position = pos
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)


## Anello luminoso orientato lungo `normal` che si allarga da `size_from` a `size_to` metri e svanisce.
static func shockwave(root: Node, pos: Vector3, normal: Vector3, color: Color,
		size_from := 0.3, size_to := 2.2, duration := 0.28) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 4
	var mat := additive(color, 0.9)
	torus.material = mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.layers = Gore.NO_BLOOD_LAYER
	root.add_child(ring)
	# Il toro sta nel piano XZ: il suo asse Y va lungo la normale.
	ring.global_transform = Transform3D(basis_along(normal), pos)
	ring.scale = Vector3.ONE * size_from
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(size_to, size_to * 0.4, size_to), duration) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(ring.queue_free)


## Scintille a cubetti sparate lungo `direction` (con apertura `spread` gradi), con gravità.
static func sparks(root: Node, pos: Vector3, direction: Vector3, color: Color, amount := 24,
		spread := 60.0, speed := Vector2(3.0, 9.0), size := 0.05, lifetime := 0.5) -> void:
	var p := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	box.material = glow(color.lightened(0.3), 3.0)
	p.mesh = box
	p.layers = Gore.NO_BLOOD_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = direction.normalized() if direction.length() > 0.001 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -14, 0)
	p.damping_min = 2.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	p.finished.connect(p.queue_free)
	root.add_child(p)
	p.global_position = pos
	p.emitting = true


## Crea un raggio (vedi Beam) e lo aggiunge alla scena.
static func beam(root: Node, color: Color, core_radius := 0.022, halo_radius := 0.085) -> Beam:
	var b := Beam.new(color, core_radius, halo_radius)
	root.add_child(b)
	return b


## Materiale luminoso pieno (nuclei, schegge).
static func glow(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.35)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


## Materiale additivo semitrasparente (aloni, raggi, anelli): si somma alla luce della scena.
static func additive(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.albedo_color = Color(color, alpha)
	return mat


## Base ortonormale con l'asse Y lungo `dir`.
static func basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized() if dir.length() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## Raggio luminoso tra due punti: un nucleo chiaro e un alone colorato (cilindri additivi).
## Si aggiorna con set_points() e si spegne con fade(), che poi lo distrugge.
class Beam extends Node3D:
	var _core: MeshInstance3D
	var _halo: MeshInstance3D
	var _core_mat: StandardMaterial3D
	var _halo_mat: StandardMaterial3D
	var _time := 0.0

	func _init(color: Color, core_radius := 0.022, halo_radius := 0.085) -> void:
		_core_mat = MagicFX.additive(color.lightened(0.7), 1.0)
		_halo_mat = MagicFX.additive(color, 0.45)
		_core = _cylinder(core_radius, _core_mat)
		_halo = _cylinder(halo_radius, _halo_mat)
		add_child(_core)
		add_child(_halo)
		visible = false

	func _cylinder(radius: float, mat: Material) -> MeshInstance3D:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 1.0
		cyl.radial_segments = 6
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = Gore.NO_BLOOD_LAYER
		return mi

	## Il raggio va da `from` a `to`.
	func set_points(from: Vector3, to: Vector3) -> void:
		var length := from.distance_to(to)
		if length < 0.01:
			visible = false
			return
		visible = true
		var b := MagicFX.basis_along(to - from)
		global_transform = Transform3D(Basis(b.x, b.y * length, b.z), (from + to) / 2.0)

	func _process(delta: float) -> void:
		# L'alone "trema" un po': sembra energia, non un tubo.
		_time += delta
		var wobble := 1.0 + 0.25 * sin(_time * 70.0)
		_halo.scale = Vector3(wobble, 1.0, wobble)

	## Il raggio si assottiglia e svanisce in `duration` secondi, poi si distrugge.
	func fade(duration := 0.35) -> void:
		var tween := create_tween().set_parallel()
		tween.tween_property(_core_mat, "albedo_color:a", 0.0, duration)
		tween.tween_property(_halo_mat, "albedo_color:a", 0.0, duration * 0.8)
		tween.tween_property(_core, "scale", Vector3(0.2, 1.0, 0.2), duration)
		tween.chain().tween_callback(queue_free)
