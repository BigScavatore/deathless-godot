extends Node3D
## Scritta nel mondo (entità "info_text" delle mappe di TrenchBroom): parole incise o dipinte
## sui muri e sul pavimento, per spiegare i comandi senza popup.
## In TrenchBroom la freccia dell'entità ("angle") punta verso chi legge.
##
## Proprietà dell'entità:
##   message   il testo; "|" va a capo
##   size      grandezza del carattere (default 64)
##   color     colore "r g b" 0-255 (default color osso)
##   pitch     inclinazione in gradi: 0 = verticale (su un muro), -90 = sdraiata sul pavimento

var message := "..."
var size := 64.0
var color := Color(0.84, 0.78, 0.66)
var pitch := 0.0

var _label: Label3D


func _func_godot_apply_properties(properties: Dictionary) -> void:
	message = String(properties.get("message", message)).replace("|", "\n")
	size = float(properties.get("size", size))
	if properties.get("color") is Color:
		color = properties["color"]
	pitch = float(properties.get("pitch", pitch))
	_update()


func _ready() -> void:
	_update()


func _update() -> void:
	if _label == null:
		_label = Label3D.new()
		# La Label3D si legge dal suo +Z: girata, così la freccia di TrenchBroom punta verso chi legge.
		_label.rotation = Vector3(0, PI, 0)
		_label.font = _font()
		_label.pixel_size = 0.0035
		_label.outline_size = 10
		_label.outline_modulate = Color(0.03, 0.02, 0.02, 0.85)
		_label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.shaded = true
		_label.double_sided = false
		_label.layers = 2  # niente macchie di sangue sopra le scritte (effects/layers.gd)
		add_child(_label)
	_label.text = message
	_label.font_size = int(size)
	_label.modulate = Color(color, 0.92)
	_label.rotation.x = deg_to_rad(pitch)


static var _shared_font: Font


static func _font() -> Font:
	if _shared_font == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua",
				"Georgia", "Times New Roman", "DejaVu Serif", "Liberation Serif", "serif"])
		sys.font_weight = 700
		_shared_font = sys
	return _shared_font
