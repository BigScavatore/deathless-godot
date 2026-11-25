class_name MagicBeam
extends Node3D
## Raggio luminoso tra due punti: un nucleo chiaro e un alone colorato (cilindri additivi).
##   var beam := MagicBeam.new(color)
##   root.add_child(beam)
##   beam.set_points(from, to)       # ogni frame, mentre serve
##   beam.fade()                     # si spegne e si distrugge da solo
## Non dipende da altre classi del gioco (solo Layers), così non crea riferimenti circolari.

var _core: MeshInstance3D
var _halo: MeshInstance3D
var _core_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _time := 0.0


func _init(color := Color(0.62, 0.42, 1.0), core_radius := 0.022, halo_radius := 0.085) -> void:
	_core_mat = _additive(color.lightened(0.7), 1.0)
	_halo_mat = _additive(color, 0.45)
	_core = _cylinder(core_radius, _core_mat)
	_halo = _cylinder(halo_radius, _halo_mat)
	add_child(_core)
	add_child(_halo)
	visible = false


## Il raggio va da `from` a `to` (coordinate globali).
func set_points(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		visible = false
		return
	visible = true
	var y := (to - from) / length
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	global_transform = Transform3D(Basis(x, y * length, z), (from + to) / 2.0)


## Il raggio si assottiglia e svanisce in `duration` secondi, poi si distrugge.
func fade(duration := 0.35) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_core_mat, "albedo_color:a", 0.0, duration)
	tween.tween_property(_halo_mat, "albedo_color:a", 0.0, duration * 0.8)
	tween.tween_property(_core, "scale", Vector3(0.2, 1.0, 0.2), duration)
	tween.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	# L'alone "trema" un po': sembra energia, non un tubo.
	_time += delta
	var wobble := 1.0 + 0.25 * sin(_time * 70.0)
	_halo.scale = Vector3(wobble, 1.0, wobble)


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
	mi.layers = Layers.NO_BLOOD
	return mi


func _additive(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, alpha)
	return mat
