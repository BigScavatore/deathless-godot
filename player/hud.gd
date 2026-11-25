extends CanvasLayer
## HUD sporca e consumata, nello stile del gioco: pannelli di ferro arrugginito con i bordi
## scheggiati e i rivetti, barre con texture di sangue e di mana che scorrono, scritte con un font
## serif con contorno. Tutto è disegnato da codice e le texture sono generate all'avvio
## (nessun file da importare).
##
##   in basso a sinistra   vita (la parte persa si svuota in ritardo), mana, cariche del dash
##   in basso a destra     le due mani: il modello 3D dell'arma che ruota, il nome, quante armi ha la
##                         mano e il tasto per cambiarla; sotto un bastone l'incantesimo; in cima la
##                         sinergia attiva tra le due armi (vedi player/weapons/synergies.gd)
##   al centro             mirino (col bastone: rombo del colore dell'incantesimo e ricarica),
##                         "PARRY", messaggi
##
## Il player chiama set_health(), flash_damage(), flash_parry() e show_message();
## mana, dash e armi vengono letti dal player a ogni frame (vedi _process).

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
var _panel_tex: ImageTexture
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


func _ready() -> void:
	_player = get_parent()
	var canvas := Canvas.new()
	canvas.hud = self
	_canvas = canvas
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_font = _make_font()
	_panel_tex = _make_panel_texture()
	_blood_tex = _make_bar_texture(Color(0.42, 0.03, 0.02), Color(0.75, 0.1, 0.06), 11)
	_mana_tex = _make_bar_texture(Color(0.22, 0.12, 0.5), Color(0.55, 0.4, 0.98), 23)
	_vignette = _make_vignette()
	for hand in [RIGHT, LEFT]:
		var preview := WeaponPreview.new()
		add_child(preview)
		_previews[hand] = preview
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
	for hand in [RIGHT, LEFT]:
		var preview: WeaponPreview = _previews[hand]
		var weapon := _hand(hand)
		if preview.shown != weapon:
			preview.show_weapon(weapon)
	_canvas.queue_redraw()


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
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.0, 0.0, _damage_flash * 0.35))
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
		_text(ci, Vector2(-300, 20), "PARRY", 60, Color(1.0, 0.82, 0.4, alpha), HORIZONTAL_ALIGNMENT_CENTER, 600, 12)
		ci.draw_set_transform(Vector2.ZERO)
	if _message_time > 0.0:
		var alpha := clampf(_message_time / 0.5, 0.0, 1.0)
		var y := size.y * 0.66
		var w := _font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_smudge(ci, Rect2(size.x / 2.0 - w / 2.0 - 50, y - 26, w + 100, 38 + (22 if _message_sub != "" else 0)), 0.55 * alpha)
		_text(ci, Vector2(0, y), _message, 22, Color(_message_color, alpha), HORIZONTAL_ALIGNMENT_CENTER, size.x, 6)
		if _message_sub != "":
			_text(ci, Vector2(0, y + 22), _message_sub, 15, Color(BONE, alpha * 0.85), HORIZONTAL_ALIGNMENT_CENTER, size.x, 4)


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


func _draw_vitals(ci: Control, size: Vector2) -> void:
	var panel := Rect2(18, size.y - 18 - 90, 330, 90)
	_draw_panel(ci, panel, 1)
	var x := panel.position.x + 18
	var max_mana: float = _player.max_mana if _player else 100.0
	var mana: float = _player.mana if _player else 0.0
	var hp_color := BONE if _health > _max_health * 0.3 else WARN

	var y := panel.position.y + 20
	_text(ci, Vector2(x, y + 13), "VITA", 15, DIM)
	_draw_bar(ci, Rect2(x + 58, y, 190, 16), _health / maxf(_max_health, 1.0), _ghost / maxf(_max_health, 1.0), _blood_tex, BLOOD)
	_text(ci, Vector2(x + 256, y + 14), str(ceili(_health)), 18, hp_color)
	y += 34
	_text(ci, Vector2(x, y + 13), "MANA", 15, DIM)
	_draw_bar(ci, Rect2(x + 58, y, 190, 16), mana / maxf(max_mana, 1.0), 0.0, _mana_tex, MANA)
	_text(ci, Vector2(x + 256, y + 14), str(floori(mana)), 18, BONE)

	# Cariche del dash: tacche inclinate sopra il pannello.
	if _player and _player.has_method("dash_charges"):
		var charges: float = _player.dash_charges()
		var count: int = _player.dash_charges_max
		for i in count:
			var p := Vector2(panel.position.x + 12 + i * 34, panel.position.y - 16)
			var shape := PackedVector2Array([p + Vector2(4, 0), p + Vector2(30, 0), p + Vector2(26, 8), p + Vector2(0, 8)])
			ci.draw_colored_polygon(shape, Color(0.05, 0.05, 0.06, 0.85))
			var fill := clampf(charges - i, 0.0, 1.0)
			if fill > 0.0:
				var fw := 26.0 * fill
				var f := PackedVector2Array([p + Vector2(4, 0), p + Vector2(4 + fw, 0), p + Vector2(fw, 8), p + Vector2(0, 8)])
				ci.draw_colored_polygon(f, DASH if fill >= 1.0 else DASH.darkened(0.55))
			ci.draw_polyline(shape + PackedVector2Array([shape[0]]), Color(0, 0, 0, 0.9), 1.5)


## Pannello delle mani: in cima l'eventuale sinergia, poi una riga per mano (destra sopra) con il
## modello che ruota, il nome dell'arma, l'incantesimo se è un bastone, le armi della mano e il tasto.
func _draw_hands(ci: Control, size: Vector2, right: Weapon, left: Weapon) -> void:
	var synergies := _synergies()
	var syn: Dictionary = synergies.hud_info() if synergies else {}
	var row_h := 78.0
	var width := 380.0
	var height := 16.0 + row_h * 2.0 + (30.0 if not syn.is_empty() else 0.0)
	var panel := Rect2(size.x - 18 - width, size.y - 18 - height, width, height)
	_draw_panel(ci, panel, 2)
	var x := panel.position.x + 14
	var y := panel.position.y + 10

	if not syn.is_empty():
		var col: Color = syn["color"]
		_text(ci, Vector2(x + 2, y + 16), "SINERGIA", 12, DIM)
		_text(ci, Vector2(x + 76, y + 16), String(syn["name"]).to_upper(), 15, col.lightened(0.4))
		# Contatore (globi evocati o cariche): sfere che si accendono.
		var max_count: int = syn["max"]
		for i in max_count:
			var center := Vector2(panel.end.x - 22 - (max_count - 1 - i) * 18, y + 11)
			ci.draw_circle(center, 6.5, Color(0, 0, 0, 0.8))
			if i < int(syn["count"]):
				ci.draw_circle(center, 7.0 + 1.5 * sin(_clock * 6.0 + i), Color(col, 0.25))
				ci.draw_circle(center, 5.0, col.lightened(0.2))
				ci.draw_circle(center - Vector2(1.5, 1.5), 1.8, Color(1, 1, 1, 0.8))
			else:
				ci.draw_circle(center, 4.5, Color(0.15, 0.13, 0.12))
		y += 30
		ci.draw_line(Vector2(x, y - 4), Vector2(panel.end.x - 14, y - 4), Color(0, 0, 0, 0.6), 2.0)

	var has_shield := false
	for row in [[RIGHT, right, "MANO DESTRA", "E"], [LEFT, left, "MANO SINISTRA", "Q"]]:
		var hand: Weapon.Hand = row[0]
		var weapon: Weapon = row[1]
		if weapon and weapon.can_parry():
			has_shield = true
		# Modello 3D che ruota, in una cornice scura.
		var frame := Rect2(x, y + 4, 66, 66)
		ci.draw_rect(frame.grow(2), Color(0, 0, 0, 0.85))
		ci.draw_rect(frame, Color(0.04, 0.035, 0.03, 0.9))
		if weapon:
			var preview: WeaponPreview = _previews[hand]
			ci.draw_texture_rect(preview.get_texture(), frame, false)
		ci.draw_rect(frame, Color(0.35, 0.3, 0.24, 0.5), false, 1.0)

		var tx := x + 80
		_text(ci, Vector2(tx, y + 18), row[2], 11, DIM)
		_text(ci, Vector2(tx, y + 40), weapon.display_name if weapon else "a mani nude", 19, GOLD if weapon else DIM)
		# Tasto per cambiare arma e tacche delle armi di questa mano.
		var list: Array = _player.hand_items(hand) if _player and _player.has_method("hand_items") else []
		if list.size() > 1:
			_text(ci, Vector2(panel.end.x - 44, y + 18), "[" + row[3] + "]", 13, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 30)
			for i in list.size():
				var dot := Rect2(panel.end.x - 18 - (list.size() - i) * 11, y + 26, 7, 7)
				ci.draw_rect(dot.grow(1), Color(0, 0, 0, 0.9))
				ci.draw_rect(dot, GOLD if list[i] == weapon else Color(0.22, 0.19, 0.16))

		var info: Dictionary = weapon.hud_info() if weapon else {}
		var spell: Spell = info.get("spell")
		if spell:
			var enough: bool = _player.mana >= spell.mana_cost
			_draw_gem(ci, Vector2(tx + 7, y + 58), 7.0, spell.color, info.get("ready", 1.0))
			_text(ci, Vector2(tx + 20, y + 63), spell.display_name, 14, spell.color.lightened(0.4))
			var cost := "%d mana" % roundi(spell.mana_cost)
			_text(ci, Vector2(panel.end.x - 120, y + 63), cost, 13, BONE if enough else WARN, HORIZONTAL_ALIGNMENT_RIGHT, 100)
			var spells: Array = info.get("spells", [])
			if spells.size() > 1:
				_text(ci, Vector2(panel.end.x - 120, y + 48), "[R] cambia", 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 100)
		y += row_h

	if has_shield:
		_text(ci, Vector2(panel.end.x - 200, panel.position.y - 8), "[F] parry", 13, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 196)


# --- Mattoni di disegno ------------------------------------------------------

func _text(ci: CanvasItem, pos: Vector2, text: String, font_size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 5) -> void:
	ci.draw_string_outline(_font, pos, text, align, width, font_size, outline, Color(0.02, 0.015, 0.01, 0.9 * color.a))
	ci.draw_string(_font, pos, text, align, width, font_size, color)


## Pannello di ferro sporco: ombra, texture, bordo scheggiato scuro, riflesso sul bordo, rivetti.
func _draw_panel(ci: Control, r: Rect2, seed_value: int) -> void:
	var pts := _chipped_shape(r, seed_value)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(4, 5))
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.4))
	var uvs := PackedVector2Array()
	var tex_size := Vector2(_panel_tex.get_width(), _panel_tex.get_height())
	for p in pts:
		uvs.append((p - r.position + Vector2(seed_value * 61, seed_value * 37)) / tex_size)
	ci.draw_colored_polygon(pts, Color(1, 1, 1, 0.96), uvs, _panel_tex)
	var closed := pts + PackedVector2Array([pts[0]])
	ci.draw_polyline(closed, Color(0, 0, 0, 0.35), 9.0)    # sporco lungo i bordi
	ci.draw_polyline(closed, Color(0.02, 0.015, 0.01, 0.95), 2.5)
	var inner := PackedVector2Array()
	var c := r.get_center()
	for p in closed:
		inner.append(p + Vector2(signf(c.x - p.x), signf(c.y - p.y)) * 3.0)
	ci.draw_polyline(inner, Color(0.62, 0.52, 0.4, 0.18), 1.0)
	for corner in [Vector2(11, 11), Vector2(r.size.x - 11, 11), Vector2(11, r.size.y - 11), Vector2(r.size.x - 11, r.size.y - 11)]:
		var p: Vector2 = r.position + corner
		ci.draw_circle(p + Vector2(1, 1), 3.5, Color(0, 0, 0, 0.7))
		ci.draw_circle(p, 3.2, BRASS)
		ci.draw_circle(p - Vector2(1, 1), 1.2, BRASS.lightened(0.5))


## Contorno del pannello: angoli tagliati e bordi un po' irregolari (sempre uguali per lo stesso seed).
func _chipped_shape(r: Rect2, seed_value: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919
	var cut := 9.0
	var edges := [
		[r.position + Vector2(cut, 0), r.position + Vector2(r.size.x - cut, 0)],
		[r.position + Vector2(r.size.x, cut), r.end - Vector2(0, cut)],
		[r.end - Vector2(cut, 0), r.position + Vector2(cut, r.size.y)],
		[r.position + Vector2(0, r.size.y - cut), r.position + Vector2(0, cut)],
	]
	var pts := PackedVector2Array()
	for edge in edges:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var steps := maxi(int(a.distance_to(b) / 16.0), 1)
		var inward := (r.get_center() - (a + b) / 2.0).normalized()
		for i in steps:
			var t := float(i) / steps
			var jitter := rng.randf_range(0.0, 2.2) if i > 0 else 0.0
			if rng.randf() < 0.08 and i > 0:
				jitter += 3.5  # scheggiatura
			pts.append(a.lerp(b, t) + inward * jitter)
	return pts


## Barra con texture che scorre piano, parte "fantasma" (vita appena persa) e tacche ogni 10%.
func _draw_bar(ci: Control, r: Rect2, value: float, ghost: float, tex: Texture2D, tint: Color) -> void:
	ci.draw_rect(r.grow(3), Color(0, 0, 0, 0.85))
	ci.draw_rect(r, Color(0.05, 0.04, 0.035))
	var w := roundf(r.size.x * clampf(value, 0.0, 1.0))
	var gw := roundf(r.size.x * clampf(ghost, 0.0, 1.0))
	if gw > w:
		ci.draw_rect(Rect2(r.position + Vector2(w, 0), Vector2(gw - w, r.size.y)), GHOST)
	if w > 0.0:
		var scroll := fmod(_clock * 14.0, float(tex.get_width()))
		ci.draw_texture_rect_region(tex, Rect2(r.position, Vector2(w, r.size.y)),
				Rect2(scroll, 0, w, tex.get_height()), tint)
		ci.draw_rect(Rect2(r.position, Vector2(w, 2)), Color(1, 1, 1, 0.12))
		ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(w, 3)), Color(0, 0, 0, 0.3))
		ci.draw_rect(Rect2(r.position + Vector2(w - 2, 0), Vector2(2, r.size.y)), Color(1, 0.9, 0.8, 0.35))
	for i in range(1, 10):
		var tx := r.position.x + roundf(r.size.x * i / 10.0)
		ci.draw_rect(Rect2(tx, r.position.y, 1, r.size.y), Color(0, 0, 0, 0.35))
	ci.draw_rect(r, Color(0.4, 0.33, 0.25, 0.35), false, 1.0)


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


## Macchia scura sfumata ai lati (sotto i messaggi).
func _smudge(ci: Control, r: Rect2, alpha: float) -> void:
	var steps := 8
	for i in steps:
		var t := float(i) / steps
		var inset := r.size.x * 0.5 * t * 0.9
		ci.draw_rect(Rect2(r.position.x + inset, r.position.y, r.size.x - inset * 2.0, r.size.y), Color(0, 0, 0, alpha / steps * 1.6))


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


## Ferro scuro e sporco: macchie di ruggine, graffi, colature (192x192, ripetuta sui pannelli).
func _make_panel_texture() -> ImageTexture:
	var n := 192
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var base := FastNoiseLite.new()
	base.seed = 3
	base.frequency = 0.02
	base.fractal_octaves = 4
	var rust := FastNoiseLite.new()
	rust.seed = 11
	rust.frequency = 0.035
	rust.fractal_octaves = 3
	for y in n:
		for x in n:
			var v := base.get_noise_2d(x, y) * 0.5 + 0.5
			var col := Color(0.075, 0.07, 0.065).lerp(Color(0.17, 0.155, 0.14), v)
			var rv := rust.get_noise_2d(x, y) * 0.5 + 0.5
			if rv > 0.6:
				col = col.lerp(Color(0.26, 0.12, 0.05), clampf((rv - 0.6) * 3.0, 0.0, 0.75))
			col = col.darkened(rng.randf_range(0.0, 0.18))
			img.set_pixel(x, y, col)
	for i in 70:  # graffi chiari
		var p := Vector2(rng.randf_range(0, n), rng.randf_range(0, n))
		var dir := Vector2.from_angle(rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.5 else 0.0))
		for t in rng.randi_range(6, 26):
			var q := p + dir * t
			var px := posmod(int(q.x), n)
			var py := posmod(int(q.y), n)
			img.set_pixel(px, py, img.get_pixel(px, py).lightened(0.25))
	for i in 25:  # colature di ruggine verticali
		var x0 := rng.randi_range(0, n - 1)
		var y0 := rng.randi_range(0, n - 1)
		for t in rng.randi_range(8, 40):
			var py := posmod(y0 + t, n)
			img.set_pixel(x0, py, img.get_pixel(x0, py).lerp(Color(0.3, 0.13, 0.05), 0.35 * (1.0 - t / 40.0)))
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
