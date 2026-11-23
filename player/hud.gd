extends CanvasLayer
## HUD minimale costruita da codice: mirino, barra della vita, flash del danno, scritta "PARRY".

var _health_bar: ProgressBar
var _damage_flash: ColorRect
var _parry_label: Label


func _ready() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_damage_flash)

	var crosshair := ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.7)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -2
	crosshair.offset_top = -2
	crosshair.offset_right = 2
	crosshair.offset_bottom = 2
	add_child(crosshair)

	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.anchor_top = 1.0
	_health_bar.anchor_bottom = 1.0
	_health_bar.offset_left = 24
	_health_bar.offset_right = 324
	_health_bar.offset_top = -46
	_health_bar.offset_bottom = -24
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.06, 0.8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.08, 0.06)
	_health_bar.add_theme_stylebox_override("background", bg)
	_health_bar.add_theme_stylebox_override("fill", fill)
	add_child(_health_bar)

	_parry_label = Label.new()
	_parry_label.text = "PARRY"
	_parry_label.add_theme_font_size_override("font_size", 40)
	_parry_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_parry_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_parry_label.add_theme_constant_override("outline_size", 8)
	_parry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parry_label.set_anchors_preset(Control.PRESET_CENTER)
	_parry_label.offset_left = -150
	_parry_label.offset_right = 150
	_parry_label.offset_top = -110
	_parry_label.offset_bottom = -60
	_parry_label.modulate.a = 0.0
	add_child(_parry_label)


func set_health(health: float, max_health: float) -> void:
	_health_bar.max_value = max_health
	_health_bar.value = health


func flash_damage(strength: float) -> void:
	_damage_flash.color.a = clampf(strength, 0.0, 0.6)
	_tween().tween_property(_damage_flash, "color:a", 0.0, 0.45)


func flash_parry() -> void:
	_parry_label.modulate.a = 1.0
	_parry_label.scale = Vector2.ONE
	var tween := _tween()
	tween.tween_interval(0.25)
	tween.tween_property(_parry_label, "modulate:a", 0.0, 0.35)


# Tween che ignora l'hitstop (Engine.time_scale), altrimenti la HUD si "congela".
func _tween() -> Tween:
	return create_tween().set_ignore_time_scale(true)
