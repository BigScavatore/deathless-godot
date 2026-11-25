extends CanvasLayer
## HUD minimale e consumata, da boomer shooter: niente pannelli, solo numeri, barre sottili e
## piccoli modelli delle armi, lontani dalle armi in prima persona. Le scritte usano un font serif
## di sistema con contorno, e tutto passa da uno shader "grime" (graffi e scheggiature in spazio
## schermo) che fa sembrare la HUD stampata su metallo rovinato. Le texture sono generate all'avvio.
##
##   in basso a sinistra   vita (numero grande, barra sottile con la parte persa che si svuota
##                         in ritardo), mana, cariche del dash
##   in basso al centro    le due mani: il modello 3D dell'arma che ruota (sinistra a sinistra,
##                         destra a destra), le tacche delle armi della mano e il tasto per cambiarla;
##                         quando cambi arma o incantesimo il nome compare per un attimo sopra.
##                         Sopra ancora, la sinergia attiva tra le due armi con il suo contatore.
##   al centro             mirino (col bastone: rombo del colore dell'incantesimo e ricarica),
##                         "PARRY", messaggi
##
## Il player chiama set_health(), flash_damage(), flash_parry() e show_message();
## mana, dash e armi vengono letti dal player a ogni frame (vedi _process).

const GRIME_SHADER := """
shader_type canvas_item;
// Graffi e scheggiature fissi sullo schermo: scuriscono e "mangiano" un po' la HUD.
uniform sampler2D grime : repeat_enable, filter_linear;
uniform float grime_size = 256.0;
uniform float erosion = 0.22;
void fragment() {
	float n = texture(grime, FRAGCOORD.xy / grime_size).r;
	COLOR.rgb *= mix(0.7, 1.06, n);
	COLOR.a *= smoothstep(erosion - 0.12, erosion + 0.04, n);
}
"""

const BONE := Color(0.84, 0.78, 0.66)
const GOLD := Color(0.88, 0.68, 0.36)
const DIM := Color(0.55, 0.5, 0.44)
const BLOOD := Color(1.0, 0.92, 0.92)       # tinta sopra la texture del sangue (già rossa)
const MANA := Color(0.95, 0.95, 1.0)        # tinta sopra la texture del mana (già viola)
const GHOST := Color(0.78, 0.66, 0.5, 0.9)
const DASH := Color(0.62, 0.8, 0.92)
const BRASS := Color(0.5, 0.38, 0.18)
const WARN := Color(1.0, 0.35, 0.28)

const RIGHT := Weapon.Hand.RIGHT
const LEFT := Weapon.Hand.LEFT

var _player: Node
var _canvas: Control
var _font: Font
var _blood_tex: ImageTexture
var _mana_tex: ImageTexture
var _vignette: GradientTexture2D
var _previews := {}  # Weapon.Hand -> WeaponPreview

var _health := 100.0
var _max_health := 100.0
var _ghost := 100.0
var _ghost_wait := 0.0
var _damage_flash := 0.0
var _parry_flash := 0.0
var _parry_time := -1.0
var _message := ""
var _message_sub := ""
var _message_color := BONE
var _message_time := 0.0
var _clock := 0.0
var _last_ticks := 0
var _connected := false
## Per far comparire il nome quando cambi arma o incantesimo: ultima "firma" vista e tempo rimasto.
var _hand_seen := {}
var _hand_name_time := {}


func _ready() -> void:
	_player = get_parent()
	# Prima i modelli delle armi (senza shader), sopra tutto il resto (con lo shader "grime").
	var previews := PreviewCanvas.new()
	previews.hud = self
	previews.mouse_filter = Control.MOUSE_FILTER_IGNORE
	previews.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(previews)
	var canvas := Canvas.new()
	canvas.hud = self
	_canvas = canvas
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = GRIME_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("grime", _make_grime_texture())
	_canvas.material = mat
	add_child(_canvas)
	_font = _make_font()
	_blood_tex = _make_bar_texture(Color(0.42, 0.03, 0.02), Color(0.75, 0.1, 0.06), 11)
	_mana_tex = _make_bar_texture(Color(0.22, 0.12, 0.5), Color(0.55, 0.4, 0.98), 23)
	_vignette = _make_vignette()
	for hand in [RIGHT, LEFT]:
		var preview := WeaponPreview.new()
		add_child(preview)
		_previews[hand] = preview
		_hand_seen[hand] = ""
		_hand_name_time[hand] = 0.0
	_last_ticks = Time.get_ticks_msec()


# --- API usata dal player ----------------------------------------------------

func set_health(health: float, max_health: float) -> void:
	if health < _health:
		_ghost_wait = 0.45  # la parte persa resta visibile un attimo, poi si svuota
	else:
		_ghost = maxf(_ghost, health)
	_health = health
	_max_health = max_health


func flash_damage(strength: float) -> void:
	_damage_flash = maxf(_damage_flash, clampf(strength, 0.0, 0.6))


func flash_parry() -> void:
	_parry_flash = 0.3
	_parry_time = 0.0


## Messaggio al centro dello schermo, con una riga più piccola sotto (facoltativa).
func show_message(text: String, color := BONE, duration := 2.5, subtitle := "") -> void:
	_message = text
	_message_sub = subtitle
	_message_color = color
	_message_time = duration


# --- Aggiornamento -----------------------------------------------------------

func _process(_delta: float) -> void:
	# Tempo reale: la HUD non deve rallentare durante l'hitstop (Engine.time_scale).
	var now := Time.get_ticks_msec()
	var dt := minf((now - _last_ticks) / 1000.0, 0.1)
	_last_ticks = now
	_clock += dt

	if _ghost_wait > 0.0:
		_ghost_wait -= dt
	else:
		_ghost = move_toward(_ghost, _health, _max_health * 0.8 * dt)
	_damage_flash = maxf(_damage_flash - dt * 1.4, 0.0)
	_parry_flash = maxf(_parry_flash - dt * 1.2, 0.0)
	if _parry_time >= 0.0:
		_parry_time += dt
		if _parry_time > 0.8:
			_parry_time = -1.0
	_message_time = maxf(_message_time - dt, 0.0)

	if not _connected and _player and _player.has_signal("spell_learned"):
		_connected = true
		_player.spell_learned.connect(func(spell: Spell) -> void:
			show_message("Nuovo incantesimo: " + spell.display_name, spell.color.lightened(0.3), 3.5)
		)
		var synergies := _synergies()
		if synergies:
			synergies.changed.connect(func(_s: StringName) -> void:
				if synergies.active != &"":
					show_message("Sinergia: " + synergies.display_name(), GOLD, 3.0, synergies.hint())
			)

	# Modelli che ruotano: aggiorna quello di ogni mano se l'arma è cambiata.
	# Se cambia l'arma o l'incantesimo, il nome compare per un paio di secondi.
	for hand in [RIGHT, LEFT]:
		var preview: WeaponPreview = _previews[hand]
		var weapon := _hand(hand)
		if preview.shown != weapon:
			preview.show_weapon(weapon)
		var label := _hand_label(weapon)
		if label != _hand_seen[hand]:
			if _hand_seen[hand] != "":
				_hand_name_time[hand] = 2.2
			_hand_seen[hand] = label
		_hand_name_time[hand] = maxf(_hand_name_time[hand] - dt, 0.0)
	for child in get_children():
		if child is Control:
			(child as Control).queue_redraw()


func _hand(hand: Weapon.Hand) -> Weapon:
	if _player and _player.has_method("hand_item"):
		return _player.hand_item(hand)
	return null


func _synergies() -> Synergies:
	if _player and _player.has_method("viewmodel"):
		var vm: Node = _player.viewmodel()
		if vm and "synergies" in vm:
			return vm.synergies
	return null


# --- Disegno -----------------------------------------------------------------

class Canvas extends Control:
	var hud: Node

	func _draw() -> void:
		hud._draw_hud(self)


class PreviewCanvas extends Control:
	var hud: Node

	func _draw() -> void:
		hud._draw_previews(self)


func _draw_hud(ci: Control) -> void:
	var size := ci.size
	var right := _hand(RIGHT)
	var left := _hand(LEFT)
	# Il mirino segue il primo bastone in mano (la destra prima).
	var info: Dictionary = {}
	for weapon in [right, left]:
		if weapon and (weapon as Weapon).hud_info().has("spell"):
			info = (weapon as Weapon).hud_info()
			break

	# Lampi a tutto schermo (danno, parry) e bordo rosso con poca vita.
	var low := 1.0 - clampf(_health / maxf(_max_health, 1.0) / 0.3, 0.0, 1.0)
	var red := _damage_flash * 1.4
	if low > 0.0 and _health > 0.0:
		red = maxf(red, low * (0.45 + 0.25 * sin(_clock * 6.0)))
	if red > 0.0:
		ci.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(0.55, 0.0, 0.0, clampf(red, 0.0, 1.0)))
	if _damage_flash > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.0, 0.0, _damage_flash * 0.3))
	if _parry_flash > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.9, 0.7, _parry_flash))

	_draw_crosshair(ci, size, info)
	_draw_vitals(ci, size)
	_draw_hands(ci, size, right, left)

	if _parry_time >= 0.0:
		var pop := 1.0 + 0.5 * clampf(1.0 - _parry_time / 0.08, 0.0, 1.0)
		var alpha := clampf((0.8 - _parry_time) / 0.3, 0.0, 1.0)
		var center := Vector2(size.x / 2.0, size.y * 0.3)
		ci.draw_set_transform(center, 0.0, Vector2.ONE * pop)
		_text(ci, Vector2(-300, 20), "PARRY", 56, Color(1.0, 0.82, 0.4, alpha), HORIZONTAL_ALIGNMENT_CENTER, 600, 12)
		ci.draw_set_transform(Vector2.ZERO)
	if _message_time > 0.0:
		var alpha := clampf(_message_time / 0.5, 0.0, 1.0)
		var y := size.y * 0.62
		_text(ci, Vector2(0, y), _message, 22, Color(_message_color, alpha), HORIZONTAL_ALIGNMENT_CENTER, size.x, 7)
		if _message_sub != "":
			_text(ci, Vector2(0, y + 22), _message_sub, 15, Color(BONE, alpha * 0.85), HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)


func _draw_crosshair(ci: Control, size: Vector2, info: Dictionary) -> void:
	var c := (size / 2.0).floor()
	var spell: Spell = info.get("spell")
	if spell:
		# Rombo del colore dell'incantesimo (spento senza mana) e arco della ricarica.
		var enough: bool = _player.mana >= spell.mana_cost
		var col := spell.color.lightened(0.35) if enough else Color(0.45, 0.45, 0.5)
		var d := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0), c + Vector2(0, -6)])
		ci.draw_polyline(d, Color(0, 0, 0, 0.75), 4.0)
		ci.draw_polyline(d, col, 2.0)
		var charge: float = info.get("ready", 1.0)
		if charge < 1.0:
			ci.draw_arc(c, 13, -PI / 2, -PI / 2 + TAU * charge, 24, Color(0, 0, 0, 0.6), 4.0)
			ci.draw_arc(c, 13, -PI / 2, -PI / 2 + TAU * charge, 24, col, 2.0)
	else:
		for r in [Rect2(-11, -1, 7, 2), Rect2(4, -1, 7, 2), Rect2(-1, -11, 2, 7), Rect2(-1, 4, 2, 7)]:
			ci.draw_rect(Rect2(c + r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Color(0, 0, 0, 0.7))
			ci.draw_rect(Rect2(c + r.position, r.size), Color(0.92, 0.88, 0.8, 0.9))


## Angolo in basso a sinistra: mana (piccolo) sopra, vita (numero grande) sotto, dash accanto.
func _draw_vitals(ci: Control, size: Vector2) -> void:
	var m := 26.0
	var max_mana: float = _player.max_mana if _player else 100.0
	var mana: float = _player.mana if _player else 0.0
	var hp_color := BONE if _health > _max_health * 0.3 else WARN

	# Mana: cristallo, numero, barra sottile.
	var my := size.y - 78.0
	_draw_crystal_icon(ci, Vector2(m + 7, my - 7), 7.0)
	_text(ci, Vector2(m + 22, my), str(floori(mana)), 20, Color(0.78, 0.7, 1.0))
	_draw_bar(ci, Rect2(m + 68, my - 9, 96, 4), mana / maxf(max_mana, 1.0), 0.0, _mana_tex, MANA)

	# Vita: goccia di sangue, numero grande, barra sottile sotto.
	var hy := size.y - 30.0
	_draw_blood_icon(ci, Vector2(m + 7, hy - 14), 9.0)
	_text(ci, Vector2(m + 22, hy), str(ceili(_health)), 40, hp_color, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 7)
	_draw_bar(ci, Rect2(m, size.y - 20, 164, 5), _health / maxf(_max_health, 1.0),
			_ghost / maxf(_max_health, 1.0), _blood_tex, BLOOD)

	# Cariche del dash: tacche inclinate a destra della barra della vita.
	if _player and _player.has_method("dash_charges"):
		var charges: float = _player.dash_charges()
		var count: int = _player.dash_charges_max
		for i in count:
			var p := Vector2(m + 174 + i * 15, size.y - 23)
			var shape := PackedVector2Array([p + Vector2(4, 0), p + Vector2(13, 0), p + Vector2(9, 9), p + Vector2(0, 9)])
			ci.draw_colored_polygon(shape, Color(0, 0, 0, 0.6))
			var fill := clampf(charges - i, 0.0, 1.0)
			if fill >= 1.0:
				ci.draw_colored_polygon(shape, DASH)
			elif fill > 0.0:
				var h := 9.0 * fill
				var part := PackedVector2Array([p + Vector2(4.0 * h / 9.0, 9.0 - h), p + Vector2(9.0 + 4.0 * h / 9.0, 9.0 - h), p + Vector2(9, 9), p + Vector2(0, 9)])
				ci.draw_colored_polygon(part, DASH.darkened(0.5))


## In basso al centro: la mano sinistra a sinistra del centro, la destra a destra. Il modello che ruota
## lo disegna _draw_previews(); qui tacche, tasti, gemma dell'incantesimo, nome (quando cambia), sinergia.
func _draw_hands(ci: Control, size: Vector2, right: Weapon, left: Weapon) -> void:
	var cx := size.x / 2.0
	for hand in [LEFT, RIGHT]:
		var weapon: Weapon = right if hand == RIGHT else left
		var box := _preview_rect(size, hand)
		var outer := 1.0 if hand == RIGHT else -1.0  # verso il bordo dello schermo
		# Tacche delle armi della mano e tasto per cambiarla (solo se ce n'è più d'una).
		var list: Array = _player.hand_items(hand) if _player and _player.has_method("hand_items") else []
		if list.size() > 1:
			var total := list.size() * 9.0 - 3.0
			for i in list.size():
				var dot := Rect2(box.get_center().x - total / 2.0 + i * 9.0, box.end.y + 3, 6, 3)
				ci.draw_rect(dot, GOLD if list[i] == weapon else Color(0.3, 0.27, 0.24, 0.7))
			var key := "E" if hand == RIGHT else "Q"
			var kx := box.end.x + 6 if hand == RIGHT else box.position.x - 18
			_text(ci, Vector2(kx, box.get_center().y + 5), key, 13, DIM, HORIZONTAL_ALIGNMENT_CENTER, 12, 4)
		# Gemma dell'incantesimo nell'angolo in alto, verso il bordo.
		var info: Dictionary = weapon.hud_info() if weapon else {}
		var spell: Spell = info.get("spell")
		if spell:
			var gem := Vector2(box.end.x - 4 if hand == RIGHT else box.position.x + 4, box.position.y + 6)
			_draw_gem(ci, gem, 5.5, spell.color if _player.mana >= spell.mana_cost else Color(0.35, 0.35, 0.4),
					info.get("ready", 1.0))
		# Nome dell'arma (e dell'incantesimo) appena cambiati: compare sopra e svanisce.
		var t: float = _hand_name_time[hand]
		if t > 0.0 and weapon:
			var alpha := clampf(t / 0.5, 0.0, 1.0)
			var label := _hand_label(weapon)
			var w := 220.0
			var lx := box.get_center().x - w / 2.0 + outer * 40.0
			_text(ci, Vector2(lx, box.position.y - 8), label, 15, Color(GOLD, alpha), HORIZONTAL_ALIGNMENT_CENTER, w, 5)

	# Sinergia attiva: nome e contatore (globi evocati o cariche), sopra le due mani.
	var synergies := _synergies()
	var syn: Dictionary = synergies.hud_info() if synergies else {}
	if not syn.is_empty():
		var col: Color = syn["color"]
		var y := _preview_rect(size, RIGHT).position.y - 30.0
		var title := String(syn["name"]).to_upper()
		var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var max_count: int = syn["max"]
		var total := tw + 10.0 + max_count * 13.0
		var x := cx - total / 2.0
		_text(ci, Vector2(x, y), title, 13, col.lightened(0.45), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)
		for i in max_count:
			var c := Vector2(x + tw + 16.0 + i * 13.0, y - 5)
			ci.draw_circle(c, 4.5, Color(0, 0, 0, 0.7))
			if i < int(syn["count"]):
				ci.draw_circle(c, 5.5 + 1.2 * sin(_clock * 6.0 + i), Color(col, 0.25))
				ci.draw_circle(c, 3.5, col.lightened(0.25))
			else:
				ci.draw_circle(c, 3.0, Color(0.2, 0.18, 0.16))


## I modelli 3D delle armi che ruotano (disegnati sotto lo strato con lo shader).
func _draw_previews(ci: Control) -> void:
	for hand in [LEFT, RIGHT]:
		if _hand(hand) == null:
			continue
		var box := _preview_rect(ci.size, hand)
		var preview: WeaponPreview = _previews[hand]
		ci.draw_circle(box.get_center(), box.size.x * 0.42, Color(0, 0, 0, 0.28))
		ci.draw_texture_rect(preview.get_texture(), box, false)


## Dove sta il modello di una mano: in basso, appena a sinistra o a destra del centro.
func _preview_rect(size: Vector2, hand: Weapon.Hand) -> Rect2:
	var s := 54.0
	var gap := 10.0
	var x := size.x / 2.0 + gap if hand == RIGHT else size.x / 2.0 - gap - s
	return Rect2(x, size.y - 18.0 - s, s, s)


## Testo che identifica arma e incantesimo (per accorgersi quando cambiano).
func _hand_label(weapon: Weapon) -> String:
	if weapon == null:
		return ""
	var spell: Spell = weapon.hud_info().get("spell")
	return weapon.display_name + ("  ·  " + spell.display_name if spell else "")


# --- Mattoni di disegno ------------------------------------------------------

func _text(ci: CanvasItem, pos: Vector2, text: String, font_size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 5) -> void:
	ci.draw_string_outline(_font, pos, text, align, width, font_size, outline, Color(0.02, 0.015, 0.01, 0.9 * color.a))
	ci.draw_string(_font, pos, text, align, width, font_size, color)


## Barra sottile con texture che scorre piano e parte "fantasma" (vita appena persa).
func _draw_bar(ci: Control, r: Rect2, value: float, ghost: float, tex: Texture2D, tint: Color) -> void:
	ci.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.75))
	ci.draw_rect(r, Color(0.06, 0.05, 0.045, 0.8))
	var w := roundf(r.size.x * clampf(value, 0.0, 1.0))
	var gw := roundf(r.size.x * clampf(ghost, 0.0, 1.0))
	if gw > w:
		ci.draw_rect(Rect2(r.position + Vector2(w, 0), Vector2(gw - w, r.size.y)), GHOST)
	if w > 0.0:
		var scroll := fmod(_clock * 14.0, float(tex.get_width()))
		ci.draw_texture_rect_region(tex, Rect2(r.position, Vector2(w, r.size.y)),
				Rect2(scroll, 4, w, maxf(r.size.y, 4.0)), tint)
		ci.draw_rect(Rect2(r.position + Vector2(w - 1, 0), Vector2(1, r.size.y)), Color(1, 0.9, 0.8, 0.4))


## Goccia di sangue (icona della vita).
func _draw_blood_icon(ci: Control, c: Vector2, radius: float) -> void:
	# Arco dal lato in alto a destra, giù per il fondo, fino in alto a sinistra; poi la punta.
	var pts := PackedVector2Array()
	for i in 13:
		var a := -PI / 4.0 + 1.5 * PI * i / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	pts.append(c + Vector2(0, -radius * 2.0))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(1.5, 1.5))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.7))
	ci.draw_colored_polygon(pts, Color(0.6, 0.06, 0.04))
	ci.draw_circle(c + Vector2(-radius * 0.35, -radius * 0.2), radius * 0.25, Color(1, 0.6, 0.5, 0.5))


## Cristallo (icona del mana).
func _draw_crystal_icon(ci: Control, c: Vector2, radius: float) -> void:
	var top := c + Vector2(0, -radius * 1.3)
	var bottom := c + Vector2(0, radius * 1.3)
	var l := c + Vector2(-radius * 0.65, 0)
	var r := c + Vector2(radius * 0.65, 0)
	ci.draw_colored_polygon(PackedVector2Array([top + Vector2(1.5, 1.5), r + Vector2(1.5, 1.5), bottom + Vector2(1.5, 1.5), l + Vector2(1.5, 1.5)]), Color(0, 0, 0, 0.7))
	ci.draw_colored_polygon(PackedVector2Array([top, r, c]), Color(0.75, 0.62, 1.0))
	ci.draw_colored_polygon(PackedVector2Array([top, c, l]), Color(0.55, 0.42, 0.95))
	ci.draw_colored_polygon(PackedVector2Array([l, c, bottom]), Color(0.32, 0.22, 0.7))
	ci.draw_colored_polygon(PackedVector2Array([c, r, bottom]), Color(0.42, 0.3, 0.82))


## Gemma dell'incantesimo: rombo sfaccettato; durante la ricarica è spenta e un arco la circonda.
func _draw_gem(ci: Control, c: Vector2, radius: float, color: Color, charge: float) -> void:
	var top := c + Vector2(0, -radius)
	var right := c + Vector2(radius, 0)
	var bottom := c + Vector2(0, radius)
	var left := c + Vector2(-radius, 0)
	ci.draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), Color(0, 0, 0, 0.8))
	var lit := color if charge >= 1.0 else color.darkened(0.6)
	ci.draw_colored_polygon(PackedVector2Array([top, right, c]), lit.lightened(0.45))
	ci.draw_colored_polygon(PackedVector2Array([top, c, left]), lit.lightened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([left, c, bottom]), lit.darkened(0.25))
	ci.draw_colored_polygon(PackedVector2Array([c, right, bottom]), lit.darkened(0.45))
	if charge < 1.0:
		ci.draw_arc(c, radius + 4, -PI / 2, -PI / 2 + TAU * charge, 16, color.lightened(0.3), 2.0)
	ci.draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(0, 0, 0, 0.9), 1.5)


# --- Risorse generate --------------------------------------------------------

## Font serif di sistema (il primo che c'è tra quelli elencati), con lettere un po' spaziate.
func _make_font() -> Font:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua",
			"Georgia", "Times New Roman", "DejaVu Serif", "Liberation Serif", "serif"])
	sys.font_weight = 600
	var v := FontVariation.new()
	v.base_font = sys
	v.spacing_glyph = 1
	return v


## Sporco in spazio schermo per lo shader: quasi tutto chiaro, con graffi e puntini scuri
## (dove la HUD si "scheggia"). 256x256, ripetuta.
func _make_grime_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	for y in n:
		for x in n:
			var v := 0.62 + 0.38 * (noise.get_noise_2d(x, y) * 0.5 + 0.5) - rng.randf() * 0.08
			img.set_pixel(x, y, Color(v, v, v))
	for i in 140:  # graffi sottili
		var p := Vector2(rng.randf_range(0, n), rng.randf_range(0, n))
		var dir := Vector2.from_angle(rng.randf_range(-0.5, 0.5) + (PI / 2.0 if rng.randf() < 0.3 else 0.0))
		var dark := rng.randf_range(0.0, 0.3)
		for t in rng.randi_range(4, 22):
			var q := p + dir * t
			img.set_pixel(posmod(int(q.x), n), posmod(int(q.y), n), Color(dark, dark, dark))
	for i in 900:  # puntini e piccole scheggiature
		var px := rng.randi_range(0, n - 1)
		var py := rng.randi_range(0, n - 1)
		var dark := rng.randf_range(0.0, 0.25)
		img.set_pixel(px, py, Color(dark, dark, dark))
		if rng.randf() < 0.3:
			img.set_pixel(posmod(px + 1, n), py, Color(dark, dark, dark))
	return ImageTexture.create_from_image(img)


## Texture di una barra: striature orizzontali tra due colori, con grumi più scuri (256x16).
func _make_bar_texture(dark: Color, light: Color, seed_value: int) -> ImageTexture:
	var w := 256
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	for y in h:
		for x in w:
			# Rumore stirato in orizzontale (striature), più chiaro in alto e più scuro in basso.
			var v := noise.get_noise_2d(x * 0.35, y * 3.0) * 0.5 + 0.5
			var shade := 1.0 - absf(float(y) / h - 0.3) * 0.9
			img.set_pixel(x, y, dark.lerp(light, clampf(v * shade * 1.3, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Vignetta: trasparente al centro, piena ai bordi (si colora con il modulate).
func _make_vignette() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 1))
	gradient.add_point(0.55, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


# --- Anteprima 3D delle armi -------------------------------------------------

## Mini scena 3D (mondo a parte) con il modello dell'arma che ruota piano; la HUD ne disegna la texture.
class WeaponPreview extends SubViewport:
	var shown: Weapon
	var _camera: Camera3D
	var _tilt: Node3D
	var _spinner: Node3D

	func _init() -> void:
		size = Vector2i(160, 160)
		transparent_bg = true
		own_world_3d = true
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
		msaa_3d = Viewport.MSAA_2X
		_camera = Camera3D.new()
		_camera.fov = 32.0
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.4, 0.36, 0.32)
		env.ambient_light_energy = 0.7
		_camera.environment = env
		add_child(_camera)
		var key := DirectionalLight3D.new()
		key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(40), 0)
		key.light_color = Color(1.0, 0.85, 0.65)
		key.light_energy = 1.6
		add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation = Vector3(deg_to_rad(-10), deg_to_rad(-150), 0)
		rim.light_color = Color(0.55, 0.62, 1.0)
		rim.light_energy = 1.0
		add_child(rim)
		_tilt = Node3D.new()
		add_child(_tilt)
		_spinner = Node3D.new()
		_tilt.add_child(_spinner)

	## Mostra il modello dell'arma (null = niente).
	func show_weapon(weapon: Weapon) -> void:
		shown = weapon
		for child in _spinner.get_children():
			child.queue_free()
		if weapon == null:
			return
		var source := weapon.get_node_or_null("Model")
		if source == null or source.scene_file_path == "":
			return
		var model := (load(source.scene_file_path) as PackedScene).instantiate() as Node3D
		# La mesh più grande è il corpo dell'arma: la si mette dritta (asse Y in su) e centrata.
		var best: MeshInstance3D
		for child in model.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh and (best == null or mi.mesh.get_aabb().size.length() > best.mesh.get_aabb().size.length()):
				best = mi
		if best == null:
			model.free()
			return
		var rel := Transform3D.IDENTITY
		var n: Node = best
		while n != model:
			rel = (n as Node3D).transform * rel
			n = n.get_parent()
		model.transform = rel.affine_inverse()
		var aabb := best.mesh.get_aabb()
		var holder := Node3D.new()
		holder.position = -aabb.get_center()
		holder.add_child(model)
		_spinner.add_child(holder)
		# Le armi lunghe (spada, bastone) stanno in diagonale, così riempiono il riquadro.
		var long := aabb.size.y > 1.8 * maxf(aabb.size.x, aabb.size.z)
		_tilt.rotation = Vector3(0.2, 0.0, -0.75 if long else 0.0)
		var extent := aabb.size.length() * 0.5
		_camera.position = Vector3(0, 0, extent / tan(deg_to_rad(_camera.fov * 0.5)) * 1.08)

	func _process(delta: float) -> void:
		_spinner.rotate_y(delta * 1.1)
