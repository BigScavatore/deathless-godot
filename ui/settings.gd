extends Node
## Impostazioni e menu di pausa (autoload "Settings", vedi project.godot).
## Esc apre/chiude il menu: il gioco va in pausa e il mouse si libera.
## Le impostazioni si applicano subito e si salvano in user://settings.cfg
## (su Windows: %APPDATA%/Godot/app_userdata/Deathless/settings.cfg), poi vengono ricaricate
## a ogni avvio.
##
##   Modalità finestra    finestra / schermo intero / schermo intero esclusivo
##   Risoluzione          dimensione della finestra (in modalità finestra)
##   Scala di rendering   percentuale della risoluzione a cui si disegna il 3D (più bassa = più
##                        "sgranato" e più veloce); la HUD resta nitida
##   FPS massimi          30 ... 240 o illimitati
##   VSync                sincronizzazione verticale
##   Sensibilità mouse, volume
##
## Da codice: Settings.values["max_fps"], Settings.set_value("vsync", false) ecc.

const PATH := "user://settings.cfg"
const WINDOW_MODES := ["Finestra", "Schermo intero", "Schermo intero esclusivo"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const FPS_OPTIONS := [30, 60, 75, 120, 144, 165, 240, 0]  # 0 = illimitati

const BONE := Color(0.84, 0.78, 0.66)
const GOLD := Color(0.88, 0.68, 0.36)
const DIM := Color(0.55, 0.5, 0.44)

var values := {
	"window_mode": 0,
	"resolution": Vector2i(1600, 900),
	"render_scale": 1.0,
	"max_fps": 144,
	"vsync": true,
	"mouse_sensitivity": 1.0,  # moltiplicatore della sensibilità del player
	"volume": 1.0,
}

var _layer: CanvasLayer
var _menu: Control
var _font: Font
var _scale_label: Label
var _sens_label: Label
var _volume_label: Label
var _base_sensitivity := {}  # player -> sensibilità originale (export del player)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_menu()
	apply()
	# Ogni volta che entra un player (es. ricaricando il livello) gli si applica la sensibilità.
	get_tree().node_added.connect(_on_node_added)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_menu()
		get_viewport().set_input_as_handled()


## Apre o chiude il menu di pausa.
func toggle_menu() -> void:
	var open := not _menu.visible
	_menu.visible = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	apply()
	_save()


## Applica tutte le impostazioni.
func apply() -> void:
	var mode: int = values["window_mode"]
	match mode:
		0:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size: Vector2i = values["resolution"]
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			size = Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = values["max_fps"]
	var root := get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = clampf(values["render_scale"], 0.25, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(values["volume"], 0.0001)))
	for player in get_tree().get_nodes_in_group("player"):
		_apply_sensitivity(player)


func _apply_sensitivity(player: Node) -> void:
	if not "mouse_sensitivity" in player:
		return
	if not _base_sensitivity.has(player):
		_base_sensitivity[player] = player.mouse_sensitivity
	player.mouse_sensitivity = _base_sensitivity[player] * float(values["mouse_sensitivity"])


func _on_node_added(node: Node) -> void:
	if node is CharacterBody3D and "mouse_sensitivity" in node:
		# Aspetta che entri nel gruppo "player" (succede nel suo _ready).
		node.ready.connect(_on_player_ready.bind(node), CONNECT_ONE_SHOT)


func _on_player_ready(node: Node) -> void:
	if is_instance_valid(node) and node.is_in_group("player"):
		_apply_sensitivity(node)


# --- Salvataggio -------------------------------------------------------------

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in values:
		values[key] = cfg.get_value("settings", key, values[key])


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("settings", key, values[key])
	cfg.save(PATH)


# --- Menu --------------------------------------------------------------------

func _build_menu() -> void:
	_font = _make_font()
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)

	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.theme = _make_theme()
	_menu.visible = false
	_layer.add_child(_menu)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	# Modalità finestra
	var mode := OptionButton.new()
	for i in WINDOW_MODES.size():
		mode.add_item(WINDOW_MODES[i], i)
	mode.selected = values["window_mode"]
	mode.item_selected.connect(func(i: int) -> void: set_value("window_mode", i))
	_row(grid, "Modalità", mode)

	# Risoluzione (solo quelle che stanno nello schermo)
	var res := OptionButton.new()
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var listed: Array[Vector2i] = []
	for r: Vector2i in RESOLUTIONS:
		if r.x <= screen_size.x and r.y <= screen_size.y:
			listed.append(r)
	if not listed.has(values["resolution"]):
		listed.append(values["resolution"])
	for i in listed.size():
		res.add_item("%d x %d" % [listed[i].x, listed[i].y], i)
		if listed[i] == values["resolution"]:
			res.selected = i
	res.item_selected.connect(func(i: int) -> void: set_value("resolution", listed[i]))
	_row(grid, "Risoluzione", res)

	# Scala di rendering 3D
	var scale_box := HBoxContainer.new()
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.25
	scale_slider.max_value = 1.0
	scale_slider.step = 0.05
	scale_slider.value = values["render_scale"]
	scale_slider.custom_minimum_size = Vector2(180, 0)
	scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scale_label = Label.new()
	_scale_label.custom_minimum_size = Vector2(56, 0)
	_scale_label.text = "%d%%" % roundi(scale_slider.value * 100)
	scale_slider.value_changed.connect(func(v: float) -> void:
		_scale_label.text = "%d%%" % roundi(v * 100)
		set_value("render_scale", v)
	)
	scale_box.add_child(scale_slider)
	scale_box.add_child(_scale_label)
	_row(grid, "Scala di rendering", scale_box)

	# FPS massimi
	var fps := OptionButton.new()
	for i in FPS_OPTIONS.size():
		var f: int = FPS_OPTIONS[i]
		fps.add_item("Illimitati" if f == 0 else str(f), i)
		if f == values["max_fps"]:
			fps.selected = i
	fps.item_selected.connect(func(i: int) -> void: set_value("max_fps", FPS_OPTIONS[i]))
	_row(grid, "FPS massimi", fps)

	# VSync
	var vsync := CheckButton.new()
	vsync.button_pressed = values["vsync"]
	vsync.toggled.connect(func(on: bool) -> void: set_value("vsync", on))
	_row(grid, "VSync", vsync)

	# Sensibilità mouse
	var sens_box := HBoxContainer.new()
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = values["mouse_sensitivity"]
	sens.custom_minimum_size = Vector2(180, 0)
	sens.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sens_label = Label.new()
	_sens_label.custom_minimum_size = Vector2(56, 0)
	_sens_label.text = "%.2f" % sens.value
	sens.value_changed.connect(func(v: float) -> void:
		_sens_label.text = "%.2f" % v
		set_value("mouse_sensitivity", v)
	)
	sens_box.add_child(sens)
	sens_box.add_child(_sens_label)
	_row(grid, "Sensibilità mouse", sens_box)

	# Volume
	var vol_box := HBoxContainer.new()
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = values["volume"]
	vol.custom_minimum_size = Vector2(180, 0)
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_label = Label.new()
	_volume_label.custom_minimum_size = Vector2(56, 0)
	_volume_label.text = "%d%%" % roundi(vol.value * 100)
	vol.value_changed.connect(func(v: float) -> void:
		_volume_label.text = "%d%%" % roundi(v * 100)
		set_value("volume", v)
	)
	vol_box.add_child(vol)
	vol_box.add_child(_volume_label)
	_row(grid, "Volume", vol_box)

	box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var resume := Button.new()
	resume.text = "Riprendi"
	resume.custom_minimum_size = Vector2(160, 0)
	resume.pressed.connect(toggle_menu)
	buttons.add_child(resume)
	var quit := Button.new()
	quit.text = "Esci dal gioco"
	quit.custom_minimum_size = Vector2(160, 0)
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)

	var hint := Label.new()
	hint.text = "Esc per tornare al gioco"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", DIM)
	box.add_child(hint)


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


## Stile del menu: ferro scuro, bordi color ruggine, font serif (lo stesso della HUD).
func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 18

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.06, 0.055, 0.96)
	panel.border_color = Color(0.32, 0.22, 0.14)
	panel.set_border_width_all(2)
	panel.set_content_margin_all(26)
	panel.shadow_color = Color(0, 0, 0, 0.6)
	panel.shadow_size = 12
	theme.set_stylebox("panel", "PanelContainer", panel)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.11, 0.09)
	normal.border_color = Color(0.28, 0.21, 0.14)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.15, 0.1)
	hover.border_color = GOLD.darkened(0.3)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.09, 0.07, 0.06)
	for type in ["Button", "OptionButton", "CheckButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("focus", type, hover)
		theme.set_color("font_color", type, BONE)
		theme.set_color("font_hover_color", type, GOLD)
		theme.set_color("font_pressed_color", type, GOLD)
	theme.set_color("font_color", "Label", BONE)

	var popup := StyleBoxFlat.new()
	popup.bg_color = Color(0.09, 0.08, 0.07)
	popup.border_color = Color(0.32, 0.22, 0.14)
	popup.set_border_width_all(1)
	popup.set_content_margin_all(6)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_color("font_color", "PopupMenu", BONE)
	theme.set_color("font_hover_color", "PopupMenu", GOLD)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.04, 0.035)
	track.set_content_margin_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.5, 0.12, 0.08)
	fill.set_content_margin_all(3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return theme


func _make_font() -> Font:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua",
			"Georgia", "Times New Roman", "DejaVu Serif", "Liberation Serif", "serif"])
	sys.font_weight = 600
	return sys
