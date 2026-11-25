extends CanvasLayer
## HUD in pixel art, nello stile del gioco: pannelli di ferro arrugginito con rivetti, barre a
## segmenti, font bitmap (ui/pixel_font.gd). Tutto è disegnato da codice in un SubViewport a bassa
## risoluzione (1 pixel della HUD = "pixel_scale" pixel dello schermo), poi ingrandito senza filtro:
## così ogni elemento, anche le animazioni, resta allineato alla griglia dei pixel.
##
##   in basso a sinistra   vita (con la parte persa che si svuota in ritardo), mana, cariche del dash
##   in basso a destra     le due mani: arma impugnata, quante armi ha la mano e il tasto per cambiarla;
##                         con un bastone anche incantesimo, costo e ricarica
##   al centro             mirino (col bastone prende il colore dell'incantesimo), "PARRY", messaggi
##
## Il player chiama set_health(), flash_damage(), flash_parry() e show_message();
## mana, dash e armi delle due mani vengono letti dal player a ogni frame (vedi _process).

## Grandezza dei pixel della HUD (3 = a 1080p la HUD è disegnata a 640x360).
@export_range(1, 8) var pixel_scale := 3

const GOLD := Color(0.86, 0.66, 0.32)
const BONE := Color(0.82, 0.76, 0.64)
const DIM := Color(0.5, 0.45, 0.4)
const BLOOD := Color(0.66, 0.07, 0.05)
const MANA := Color(0.46, 0.32, 0.92)
const GHOST := Color(0.92, 0.82, 0.62)
const DASH := Color(0.62, 0.82, 0.95)
const BRASS := Color(0.62, 0.48, 0.22)

var _player: Node
var _canvas: Control
var _iron: ImageTexture
var _icons := {}  # Spell -> ImageTexture

var _health := 100.0
var _max_health := 100.0
var _ghost := 100.0
var _ghost_wait := 0.0
var _damage_flash := 0.0
var _parry_flash := 0.0
var _parry_time := -1.0
var _message := ""
var _message_color := BONE
var _message_time := 0.0
var _clock := 0.0
var _last_ticks := 0
var _connected := false


func _ready() -> void:
	_player = get_parent()
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = pixel_scale
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	container.add_child(viewport)
	var canvas := Canvas.new()
	canvas.hud = self
	_canvas = canvas
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(_canvas)
	_iron = _make_iron_texture()
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
	_parry_flash = 0.35
	_parry_time = 0.0


## Messaggio al centro dello schermo (es. "Hai ottenuto: Scheggia magica").
func show_message(text: String, color := BONE, duration := 2.5) -> void:
	_message = text
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
	_canvas.queue_redraw()


# --- Disegno -----------------------------------------------------------------

class Canvas extends Control:
	var hud: Node

	func _draw() -> void:
		hud._draw_hud(self)


func _draw_hud(ci: Control) -> void:
	var size := ci.size
	var right: Weapon = _hand(Weapon.Hand.RIGHT)
	var left: Weapon = _hand(Weapon.Hand.LEFT)
	# Il mirino segue il primo bastone in mano (la destra prima).
	var info: Dictionary = {}
	for weapon in [right, left]:
		if weapon and (weapon as Weapon).hud_info().has("spell"):
			info = (weapon as Weapon).hud_info()
			break

	# Lampi a tutto schermo (danno, parry) e bordo rosso con poca vita.
	if _damage_flash > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.7, 0.0, 0.0, _damage_flash))
	if _parry_flash > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.92, 0.7, _parry_flash))
	var low := 1.0 - clampf(_health / maxf(_max_health, 1.0) / 0.3, 0.0, 1.0)
	if low > 0.0 and _health > 0.0:
		var pulse := 0.6 + 0.4 * sin(_clock * 6.0)
		for i in 8:
			ci.draw_rect(Rect2(Vector2(i, i), size - Vector2(i, i) * 2.0), Color(0.6, 0.0, 0.0, low * pulse * 0.35 * (1.0 - i / 8.0)), false, 1.0)

	_draw_crosshair(ci, size, info)
	_draw_vitals(ci, size)
	_draw_hands(ci, size, right, left)

	if _parry_time >= 0.0:
		var big := 4 if _parry_time < 0.07 else 3
		var alpha := clampf((0.8 - _parry_time) / 0.3, 0.0, 1.0)
		var w := PixelFont.width("PARRY") * big
		PixelFont.draw_outlined(ci, Vector2(roundf((size.x - w) / 2.0), roundf(size.y * 0.27)), "PARRY",
				Color(1.0, 0.85, 0.35, alpha), Color(0.1, 0.03, 0.0, alpha), big)
	if _message_time > 0.0:
		var alpha := clampf(_message_time / 0.5, 0.0, 1.0)
		var w := PixelFont.width(_message)
		var pos := Vector2(roundf((size.x - w) / 2.0), roundf(size.y * 0.66))
		ci.draw_rect(Rect2(pos - Vector2(4, 3), Vector2(w + 8, 13)), Color(0, 0, 0, 0.55 * alpha))
		PixelFont.draw(ci, pos, _message, Color(_message_color, alpha))


func _draw_crosshair(ci: Control, size: Vector2, info: Dictionary) -> void:
	var c := (size / 2.0).floor()
	var spell: Spell = info.get("spell")
	if spell:
		# Rombo del colore dell'incantesimo; spento se non c'è abbastanza mana.
		var enough: bool = _player.mana >= spell.mana_cost
		var col := spell.color.lightened(0.3) if enough else Color(0.4, 0.4, 0.45)
		for p in [Vector2(0, -2), Vector2(-1, -1), Vector2(1, -1), Vector2(-2, 0), Vector2(2, 0), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 2)]:
			ci.draw_rect(Rect2(c + p + Vector2(1, 1), Vector2.ONE), Color(0, 0, 0, 0.7))
			ci.draw_rect(Rect2(c + p, Vector2.ONE), col)
		var charge: float = info.get("ready", 1.0)
		if charge < 1.0:  # ricarica: barretta sotto il mirino
			ci.draw_rect(Rect2(c + Vector2(-3, 5), Vector2(7, 1)), Color(0, 0, 0, 0.6))
			ci.draw_rect(Rect2(c + Vector2(-3, 5), Vector2(roundf(7 * charge), 1)), col)
	else:
		for r in [Rect2(-4, 0, 3, 1), Rect2(2, 0, 3, 1), Rect2(0, -4, 1, 3), Rect2(0, 2, 1, 3)]:
			ci.draw_rect(Rect2(c + r.position + Vector2(1, 1), r.size), Color(0, 0, 0, 0.7))
			ci.draw_rect(Rect2(c + r.position, r.size), Color(1, 1, 1, 0.85))


func _draw_vitals(ci: Control, size: Vector2) -> void:
	var panel := Rect2(6, size.y - 40, 132, 34)
	_draw_panel(ci, panel)
	var x := panel.position.x + 6
	var y := panel.position.y + 6
	var max_mana: float = _player.max_mana if _player else 100.0
	var mana: float = _player.mana if _player else 0.0

	PixelFont.draw(ci, Vector2(x, y), "VITA", BONE)
	_draw_bar(ci, Rect2(x + 30, y, 70, 7), _health / maxf(_max_health, 1.0), _ghost / maxf(_max_health, 1.0), BLOOD)
	PixelFont.draw(ci, Vector2(x + 104, y), "%3d" % ceili(_health), BONE if _health > _max_health * 0.3 else Color(1, 0.3, 0.25))
	y += 12
	PixelFont.draw(ci, Vector2(x, y), "MANA", BONE)
	_draw_bar(ci, Rect2(x + 30, y, 70, 7), mana / maxf(max_mana, 1.0), 0.0, MANA)
	PixelFont.draw(ci, Vector2(x + 104, y), "%3d" % floori(mana), BONE)

	# Cariche del dash: tacche sopra il pannello.
	if _player and _player.has_method("dash_charges"):
		var charges: float = _player.dash_charges()
		var count: int = _player.dash_charges_max
		for i in count:
			var r := Rect2(panel.position.x + 2 + i * 13, panel.position.y - 7, 11, 3)
			ci.draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
			ci.draw_rect(r, Color(0.12, 0.12, 0.14))
			var fill := clampf(charges - i, 0.0, 1.0)
			if fill > 0.0:
				ci.draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * fill), r.size.y)), DASH if fill >= 1.0 else DASH.darkened(0.5))


func _hand(hand: Weapon.Hand) -> Weapon:
	if _player and _player.has_method("hand_item"):
		return _player.hand_item(hand)
	return null


## Pannello delle mani: una riga per mano ("DX" sopra, "SX" sotto) con l'arma, le tacche delle
## armi disponibili in quella mano e il tasto per cambiarla. Sotto a un bastone, la riga dell'incantesimo.
func _draw_hands(ci: Control, size: Vector2, right: Weapon, left: Weapon) -> void:
	var rows := [[Weapon.Hand.RIGHT, right, "DX", "[E]"], [Weapon.Hand.LEFT, left, "SX", "[Q]"]]
	# Larghezza e altezza in base al contenuto.
	var width := 132
	var height := 8
	var has_shield := false
	for row in rows:
		var weapon: Weapon = row[1]
		height += 11
		if weapon == null:
			continue
		width = maxi(width, 30 + PixelFont.width(weapon.display_name) + 40)
		var info := weapon.hud_info()
		if info.has("spell") and info["spell"] != null:
			height += 14
			width = maxi(width, 30 + PixelFont.width((info["spell"] as Spell).display_name) + 44)
		if weapon.can_parry():
			has_shield = true
	var panel := Rect2(size.x - 6 - width, size.y - 6 - height, width, height)
	_draw_panel(ci, panel)
	var x := panel.position.x + 6
	var y := panel.position.y + 5

	for row in rows:
		var hand: Weapon.Hand = row[0]
		var weapon: Weapon = row[1]
		# Etichetta della mano.
		var tag := Rect2(x, y - 1, 13, 9)
		ci.draw_rect(tag.grow(1), Color(0, 0, 0, 0.9))
		ci.draw_rect(tag, Color(0.25, 0.18, 0.08) if hand == Weapon.Hand.RIGHT else Color(0.12, 0.11, 0.13))
		PixelFont.draw(ci, tag.position + Vector2(1, 1), row[2], GOLD if hand == Weapon.Hand.RIGHT else BONE, 1, Color(0, 0, 0, 0))
		var label := weapon.display_name if weapon else "-"
		PixelFont.draw(ci, Vector2(x + 18, y), label, GOLD if weapon else DIM)
		# Tacche: quante armi ha la mano e quale è impugnata, poi il tasto per cambiarla.
		var list: Array = _player.hand_items(hand) if _player and _player.has_method("hand_items") else []
		var key_w := PixelFont.width(row[3])
		var kx := panel.end.x - 6 - key_w
		if list.size() > 1:
			PixelFont.draw(ci, Vector2(kx, y), row[3], DIM)
			for i in list.size():
				var dot := Rect2(kx - 4 - (list.size() - i) * 5, y + 2, 3, 3)
				ci.draw_rect(dot.grow(1), Color(0, 0, 0, 0.9))
				ci.draw_rect(dot, GOLD if list[i] == weapon else Color(0.2, 0.18, 0.16))
		y += 11

		if weapon == null:
			continue
		var info := weapon.hud_info()
		var spell: Spell = info.get("spell")
		if spell == null:
			continue
		# Riga dell'incantesimo: icona, nome, costo; [R] e i quadratini se ce n'è più d'uno.
		var icon_pos := Vector2(x + 18, y)
		ci.draw_rect(Rect2(icon_pos - Vector2(1, 1), Vector2(13, 13)), Color(0, 0, 0, 0.9))
		ci.draw_rect(Rect2(icon_pos, Vector2(11, 11)), Color(0.08, 0.06, 0.1))
		ci.draw_texture(_spell_icon(spell), icon_pos)
		var charge: float = info.get("ready", 1.0)
		if charge < 1.0:  # ricarica: l'icona si "riempie" dal basso
			var h := roundf(11.0 * (1.0 - charge))
			ci.draw_rect(Rect2(icon_pos, Vector2(11, h)), Color(0, 0, 0, 0.6))
		var enough: bool = _player.mana >= spell.mana_cost
		PixelFont.draw(ci, Vector2(x + 34, y), spell.display_name, spell.color.lightened(0.35))
		var spells: Array = info.get("spells", [])
		var cost := "%d MANA" % roundi(spell.mana_cost)
		PixelFont.draw(ci, Vector2(x + 34, y + 7), cost, BONE if enough else Color(1, 0.3, 0.25))
		if spells.size() > 1:
			var sx := panel.end.x - 6 - spells.size() * 7
			for i in spells.size():
				var s: Spell = spells[i]
				var r := Rect2(sx + i * 7, y + 8, 5, 5)
				ci.draw_rect(r.grow(1), Color.WHITE if s == spell else Color(0, 0, 0, 0.9))
				ci.draw_rect(r, s.color)
			PixelFont.draw(ci, Vector2(sx - 3 - PixelFont.width("[R]"), y + 7), "[R]", DIM)
		y += 14

	if has_shield:
		var hint := "[F] PARRY"
		PixelFont.draw(ci, Vector2(panel.end.x - PixelFont.width(hint), panel.position.y - 10), hint, DIM)


## Pannello di ferro: bordo nero, bevel chiaro/scuro e quattro rivetti d'ottone.
func _draw_panel(ci: Control, r: Rect2) -> void:
	ci.draw_rect(r.grow(1), Color(0, 0, 0, 0.9))
	ci.draw_texture_rect(_iron, r, true, Color(1, 1, 1, 0.94))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(0.42, 0.37, 0.33))
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), Color(0.36, 0.32, 0.29))
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Color(0.05, 0.04, 0.04))
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), Color(0.07, 0.06, 0.05))
	for corner in [Vector2(2, 2), Vector2(r.size.x - 4, 2), Vector2(2, r.size.y - 4), Vector2(r.size.x - 4, r.size.y - 4)]:
		ci.draw_rect(Rect2(r.position + corner, Vector2(2, 2)), BRASS)
		ci.draw_rect(Rect2(r.position + corner, Vector2.ONE), BRASS.lightened(0.4))


## Barra a segmenti: fondo scuro, parte "fantasma" (vita appena persa), riempimento con riga chiara in alto.
func _draw_bar(ci: Control, r: Rect2, value: float, ghost: float, color: Color) -> void:
	ci.draw_rect(r.grow(1), Color(0, 0, 0, 0.95))
	ci.draw_rect(r, Color(0.06, 0.05, 0.05))
	var w := roundf(r.size.x * clampf(value, 0.0, 1.0))
	var gw := roundf(r.size.x * clampf(ghost, 0.0, 1.0))
	if gw > w:
		ci.draw_rect(Rect2(r.position + Vector2(w, 0), Vector2(gw - w, r.size.y)), GHOST)
	if w > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), color)
		ci.draw_rect(Rect2(r.position, Vector2(w, 1)), color.lightened(0.35))
		ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(w, 2)), color.darkened(0.35))
	for sx in range(5, int(r.size.x), 6):  # tacche
		ci.draw_rect(Rect2(r.position + Vector2(sx, 0), Vector2(1, r.size.y)), Color(0, 0, 0, 0.45))


# --- Texture generate --------------------------------------------------------

## Ferro scuro e graffiato con macchie di ruggine (32x32, ripetuta sui pannelli).
func _make_iron_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.12
	for y in n:
		for x in n:
			var v := noise.get_noise_2d(x, y) * 0.5 + 0.5 + rng.randf_range(-0.12, 0.12)
			var col := Color(0.10, 0.09, 0.09)
			if v > 0.68:
				col = Color(0.21, 0.10, 0.05)   # ruggine
			elif v > 0.52:
				col = Color(0.14, 0.12, 0.11)
			elif v < 0.25:
				col = Color(0.07, 0.06, 0.06)
			img.set_pixel(x, y, col)
	for i in 6:  # graffi
		var sx := rng.randi_range(0, n - 1)
		var sy := rng.randi_range(0, n - 1)
		for t in rng.randi_range(3, 9):
			img.set_pixel((sx + t) % n, (sy + int(t / 3.0)) % n, Color(0.22, 0.2, 0.19))
	return ImageTexture.create_from_image(img)


## Icona 11x11 dell'incantesimo dalla sua pixel art (vedi magic/spell.gd).
func _spell_icon(spell: Spell) -> ImageTexture:
	if _icons.has(spell):
		return _icons[spell]
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	var palette := spell.icon_palette()
	for y in mini(spell.icon.size(), 11):
		var row := spell.icon[y]
		for x in mini(row.length(), 11):
			if palette.has(row[x]):
				img.set_pixel(x, y, palette[row[x]])
	var tex := ImageTexture.create_from_image(img)
	_icons[spell] = tex
	return tex
