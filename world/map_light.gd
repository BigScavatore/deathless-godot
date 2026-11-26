extends OmniLight3D
## Luce delle mappe (entità "light_torch" di TrenchBroom): luce calda che tremola, con una
## piccola fiamma (facoltativa) per le torce appese ai muri.
##
## Proprietà dell'entità:
##   color     colore "r g b" 0-255 (default arancio fuoco)
##   energy    intensità (default 1.6)
##   range     raggio in metri (default 9)
##   flicker   1 = tremola come una fiamma, 0 = fissa
##   flame     1 = mostra la fiamma, 0 = solo luce
##   shadows   1 = proietta ombre (più pesante), 0 = no

var _base_energy := 1.6
var _flicker := true
var _time := 0.0
var _flame: CPUParticles3D


func _init() -> void:
	light_color = Color(1.0, 0.62, 0.32)
	light_energy = _base_energy
	omni_range = 9.0
	omni_attenuation = 1.4
	shadow_enabled = false
	_time = randf() * 100.0


func _func_godot_apply_properties(properties: Dictionary) -> void:
	if properties.get("color") is Color:
		light_color = properties["color"]
	_base_energy = float(properties.get("energy", _base_energy))
	light_energy = _base_energy
	omni_range = float(properties.get("range", omni_range))
	_flicker = bool(properties.get("flicker", true))
	shadow_enabled = bool(properties.get("shadows", false))
	if bool(properties.get("flame", true)):
		_add_flame()


func _process(delta: float) -> void:
	if not _flicker:
		return
	_time += delta
	var n := sin(_time * 9.0) * 0.5 + sin(_time * 23.0 + 1.3) * 0.3 + sin(_time * 3.7) * 0.2
	light_energy = _base_energy * (0.88 + 0.12 * n)


func _add_flame() -> void:
	if _flame:
		return
	_flame = CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.07
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = light_color
	mat.emission_energy_multiplier = 2.0
	box.material = mat
	_flame.mesh = box
	_flame.amount = 18
	_flame.lifetime = 0.5
	_flame.direction = Vector3.UP
	_flame.spread = 15.0
	_flame.initial_velocity_min = 0.4
	_flame.initial_velocity_max = 0.9
	_flame.gravity = Vector3(0, 0.6, 0)
	_flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flame.emission_sphere_radius = 0.06
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	_flame.scale_amount_curve = shrink
	var colors := Gradient.new()
	colors.set_color(0, Color(1.0, 0.85, 0.4))
	colors.set_color(1, Color(0.8, 0.2, 0.05))
	_flame.color_ramp = colors
	_flame.layers = 2
	add_child(_flame)
