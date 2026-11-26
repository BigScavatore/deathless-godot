class_name Gore
## Esplosioni di sangue alla morte dei nemici (stile boomer shooter):
##   - spruzzo di gocce (particelle a cubetti, niente filtro);
##   - gibs: i pezzi del modello (armatura, arti, spada) volano via come corpi fisici,
##     insieme a qualche pezzo di carne; dove atterrano lasciano una macchia;
##   - una pozza di sangue che si allarga sotto il punto dell'esplosione;
##   - schizzi su pavimento e muri tutto intorno (raggi in direzioni casuali).
##
##   Gore.explode(self, global_position + Vector3.UP, $Model, velocity)
##
## Il sangue è fatto di Decal con texture pixelate generate qui (nessun file da importare).
## Le Decal si proiettano solo sugli oggetti nel layer visivo 1 (pavimento, muri): armi in prima
## persona, nemici e gibs stanno nel layer 2 (NO_BLOOD_LAYER), così il sangue non ci "scivola" sopra.
## Le macchie restano a terra; oltre MAX_DECALS si cancellano le più vecchie.

const RenderLayers := preload("res://effects/layers.gd")

## Layer visivi (bitmask) che ricevono le macchie di sangue.
const BLOOD_LAYERS := RenderLayers.WORLD
## Layer visivo per ciò che NON deve ricevere sangue (viewmodel, nemici, gibs): vedi effects/layers.gd.
const NO_BLOOD_LAYER := RenderLayers.NO_BLOOD
const MAX_DECALS := 120
## Secondi prima che i gibs spariscano.
const GIB_TIME := 10.0

const BLOOD_CORE := Color(0.17, 0.0, 0.01)
const BLOOD_MID := Color(0.28, 0.015, 0.02)
const BLOOD_EDGE := Color(0.40, 0.035, 0.03)
const BLOOD_WET := Color(0.58, 0.14, 0.11)
const FLESH_COLORS = [Color(0.45, 0.06, 0.05), Color(0.30, 0.03, 0.03), Color(0.55, 0.16, 0.12)]

## Non tipizzato: può contenere Decal già liberate (livello ricaricato, ecc.), che vanno solo saltate.
static var _decals: Array = []
static var _textures := {}
static var _droplet_mesh: Mesh
static var _flesh_materials: Array[StandardMaterial3D] = []


## Fa esplodere un nemico in `origin` (centro del busto). `model`: i suoi pezzi diventano gibs
## (le mesh originali non vengono toccate: nasconderle o liberarle tocca al chiamante).
## `push`: velocità extra per gibs e schizzi (es. il knockback del colpo che lo ha ucciso).
static func explode(context: Node3D, origin: Vector3, model: Node3D = null, push := Vector3.ZERO) -> void:
	var tree := context.get_tree()
	var root := tree.current_scene if tree.current_scene else tree.root
	var space := context.get_world_3d().direct_space_state
	var exclude := _player_rids(tree)

	_spray(root, origin, push)
	if model:
		_gibs_from_model(root, model, origin, push)
	_flesh_chunks(root, origin, push, 8)
	_pool(root, space, origin, exclude)
	_splatter(root, space, origin, push, exclude, 16)
	Sfx.play_at(context, &"gore_burst", origin, 3.0, 0.1, 10.0)


# --- Spruzzo ---------------------------------------------------------------

static func _spray(root: Node, origin: Vector3, push: Vector3) -> void:
	for burst in 2:  # una nuvola fitta e veloce + gocce più grosse e lente
		var p := CPUParticles3D.new()
		p.mesh = _droplet()
		p.layers = NO_BLOOD_LAYER
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.one_shot = true
		p.explosiveness = 0.92
		p.amount = 110 if burst == 0 else 40
		p.lifetime = 0.9 if burst == 0 else 1.4
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.35
		p.direction = (Vector3.UP + push * 0.08).normalized()
		p.spread = 180.0
		p.initial_velocity_min = 4.0 if burst == 0 else 2.0
		p.initial_velocity_max = 11.0 if burst == 0 else 6.0
		p.gravity = Vector3(0, -22.0, 0)
		p.damping_min = 1.0
		p.damping_max = 4.0
		p.scale_amount_min = 0.6 if burst == 0 else 1.4
		p.scale_amount_max = 1.4 if burst == 0 else 2.6
		var shrink := Curve.new()
		shrink.add_point(Vector2(0.0, 1.0))
		shrink.add_point(Vector2(0.7, 0.8))
		shrink.add_point(Vector2(1.0, 0.0))
		p.scale_amount_curve = shrink
		var colors := Gradient.new()
		colors.set_color(0, BLOOD_EDGE)
		colors.set_color(1, BLOOD_CORE)
		p.color_initial_ramp = colors
		p.finished.connect(p.queue_free)
		root.add_child(p)
		p.global_position = origin
		p.emitting = true


static func _droplet() -> Mesh:
	if _droplet_mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.06
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE
		mat.roughness = 0.4
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		box.material = mat
		_droplet_mesh = box
	return _droplet_mesh


# --- Gibs ------------------------------------------------------------------

## Ogni MeshInstance3D del modello diventa un corpo rigido con la stessa mesh.
static func _gibs_from_model(root: Node, model: Node3D, origin: Vector3, push: Vector3) -> void:
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var src := child as MeshInstance3D
		if src.mesh == null or not src.is_visible_in_tree():
			continue
		var mesh := MeshInstance3D.new()
		mesh.mesh = src.mesh
		for i in src.get_surface_override_material_count():
			mesh.set_surface_override_material(i, src.get_surface_override_material(i))
		var xform := src.global_transform
		mesh.scale = xform.basis.get_scale()
		var aabb := src.mesh.get_aabb()
		var size := (aabb.size * mesh.scale * 0.8).max(Vector3.ONE * 0.06)
		var center := xform * aabb.get_center()
		var body := _make_gib(root, mesh, size, xform.basis.get_scale() * aabb.get_center(), 4.0)
		body.global_transform = Transform3D(xform.basis.orthonormalized(), xform.origin)
		var out := center - origin
		out.y = maxf(out.y, 0.0)
		body.linear_velocity = _scatter(out, push, 3.0, 7.0)


static func _flesh_chunks(root: Node, origin: Vector3, push: Vector3, count: int) -> void:
	if _flesh_materials.is_empty():
		for c in FLESH_COLORS:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = c
			mat.roughness = 0.35
			_flesh_materials.append(mat)
	for i in count:
		var size := Vector3(randf_range(0.1, 0.24), randf_range(0.08, 0.18), randf_range(0.1, 0.22))
		var box := BoxMesh.new()
		box.size = size
		box.material = _flesh_materials.pick_random()
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		var body := _make_gib(root, mesh, size, Vector3.ZERO, 1.5)
		var offset := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized()
		body.global_transform = Transform3D(Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU),
				origin + offset * 0.3)
		body.linear_velocity = _scatter(offset, push, 4.0, 9.0)


static func _scatter(direction: Vector3, push: Vector3, speed_min: float, speed_max: float) -> Vector3:
	var dir := direction.normalized() if direction.length() > 0.01 else Vector3.UP
	dir = (dir + Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 0.8), randf_range(-0.4, 0.4))).normalized()
	return dir * randf_range(speed_min, speed_max) + push * 0.6


static func _make_gib(root: Node, mesh: MeshInstance3D, size: Vector3, shape_offset: Vector3, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 0   # nessuno lo urta (player, nemici, raggi), ma lui rimbalza sul mondo
	body.collision_mask = 1
	body.mass = mass
	body.angular_damp = 1.5
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = shape_offset
	mesh.layers = NO_BLOOD_LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(shape)
	body.add_child(mesh)
	root.add_child(body)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 12.0

	# Le prime volte che tocca qualcosa lascia una macchia sotto di sé.
	var splats := [2]
	body.body_entered.connect(func(_other: Node) -> void:
		if splats[0] <= 0 or not body.is_inside_tree():
			return
		splats[0] -= 1
		var at := body.global_position
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 1.2, 1)
		var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			_add_decal(root, hit.position, hit.normal, randf_range(0.5, 1.0), &"splat")
			if splats[0] == 1:
				Sfx.play_at(body, &"gib_splat", at, -6.0, 0.15, 4.0)
	)

	# Dopo un po' si rimpicciolisce e sparisce.
	var tween := body.create_tween()
	tween.tween_interval(GIB_TIME + randf() * 2.0)
	tween.tween_callback(body.set.bind(&"freeze", true))
	tween.tween_property(mesh, "scale", Vector3.ZERO, 0.6)
	tween.tween_callback(body.queue_free)
	return body


# --- Pozza e schizzi -------------------------------------------------------

static func _pool(root: Node, space: PhysicsDirectSpaceState3D, origin: Vector3, exclude: Array[RID]) -> void:
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 4.0, 1, exclude)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return
	var size := randf_range(2.8, 3.6)
	var decal := _add_decal(root, hit.position, hit.normal, size, &"pool")
	# La pozza si allarga in fretta, poi piano piano.
	decal.size = Vector3(size * 0.3, decal.size.y, size * 0.3)
	var tween := decal.create_tween()
	tween.tween_property(decal, "size", Vector3(size * 0.8, decal.size.y, size * 0.8), 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(decal, "size", Vector3(size, decal.size.y, size), 2.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Raggi in direzioni casuali (soprattutto verso il basso e in avanti rispetto al colpo):
## dove colpiscono pavimento o muri compare uno schizzo, con un ritardo in base alla distanza.
static func _splatter(root: Node, space: PhysicsDirectSpaceState3D, origin: Vector3, push: Vector3,
		exclude: Array[RID], count: int) -> void:
	var bias := push.normalized() * 0.6 if push.length() > 0.1 else Vector3.ZERO
	var hits: Array[Dictionary] = []
	for i in count:
		var dir := (Vector3(randf_range(-1, 1), randf_range(-1.0, 0.5), randf_range(-1, 1)).normalized() + bias).normalized()
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + dir * randf_range(2.5, 6.0), 1, exclude)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			hit["delay"] = 0.04 + origin.distance_to(hit.position) / 14.0
			hits.append(hit)
	for hit in hits:
		var timer := root.get_tree().create_timer(hit["delay"])
		timer.timeout.connect(func() -> void:
			if is_instance_valid(root):
				_add_decal(root, hit.position, hit.normal, randf_range(0.6, 1.5), &"splat")
		)


static func _add_decal(root: Node, position: Vector3, normal: Vector3, size: float, kind: StringName) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = _blood_texture(kind)
	decal.size = Vector3(size, 0.5, size)
	decal.cull_mask = BLOOD_LAYERS
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	decal.normal_fade = 0.4   # niente strisce stirate sugli spigoli
	decal.albedo_mix = 1.0
	root.add_child(decal)
	decal.global_transform = Transform3D(_basis_from_normal(normal, randf() * TAU), position + normal * 0.02)
	_decals.append(decal)
	while _decals.size() > MAX_DECALS:
		var old: Variant = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return decal


## Base con +Y lungo la normale (la Decal proietta lungo il suo -Y), ruotata di `angle` attorno ad essa.
static func _basis_from_normal(normal: Vector3, angle: float) -> Basis:
	var y := normal.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z).rotated(y, angle)


static func _player_rids(tree: SceneTree) -> Array[RID]:
	var rids: Array[RID] = []
	for node in tree.get_nodes_in_group("player"):
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	return rids


# --- Texture del sangue ----------------------------------------------------

## Qualche variante per tipo, generate una volta sola: "pool" (pozza) e "splat" (schizzo).
static func _blood_texture(kind: StringName) -> Texture2D:
	if not _textures.has(kind):
		var list: Array[Texture2D] = []
		for i in 4:
			list.append(_make_blood_texture(kind == &"pool", 7000 + i * 31 + (500 if kind == &"pool" else 0)))
		_textures[kind] = list
	var variants: Array = _textures[kind]
	return variants.pick_random()


## Pochi pixel (48 o 32 di lato) e 3 tonalità: macchie "a blocchi" come il resto del gioco.
## Forma: somma di metaball (blob principale + lobi + goccioline), bordo reso irregolare dal rumore.
static func _make_blood_texture(pool: bool, seed_value: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := 48 if pool else 32
	var blobs: Array[Vector3] = []  # (x, y, raggio) in pixel
	var c := n / 2.0
	if pool:
		blobs.append(Vector3(c, c, n * 0.24))
		for i in 9:
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.08, 0.26) * n
			blobs.append(Vector3(c + cos(a) * d, c + sin(a) * d, rng.randf_range(0.07, 0.15) * n))
	else:
		blobs.append(Vector3(c, c, n * 0.16))
		var streak := rng.randf() * TAU  # gli schizzi hanno una direzione
		for i in 5:
			var d := rng.randf_range(0.08, 0.3) * n
			var a := streak + rng.randf_range(-0.5, 0.5)
			blobs.append(Vector3(c + cos(a) * d, c + sin(a) * d, rng.randf_range(0.04, 0.09) * n))
	for i in (6 if pool else 10):  # goccioline sparse
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.3, 0.46) * n
		blobs.append(Vector3(c + cos(a) * d, c + sin(a) * d, rng.randf_range(0.015, 0.035) * n))

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.15
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := 0.0
			for b in blobs:
				var d2 := (x + 0.5 - b.x) ** 2 + (y + 0.5 - b.y) ** 2
				v += b.z * b.z / maxf(d2, 0.01)
			v += noise.get_noise_2d(x, y) * 0.35
			var col := Color(0, 0, 0, 0)
			if v > 2.4:
				col = BLOOD_CORE
			elif v > 1.5:
				col = BLOOD_MID
			elif v > 1.0:
				col = BLOOD_EDGE
			if col.a > 0.0 and v > 1.5 and rng.randf() < 0.025:
				col = BLOOD_WET  # riflessi "bagnati"
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
