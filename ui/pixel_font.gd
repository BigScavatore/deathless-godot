class_name PixelFont
## Font bitmap 5x7 disegnato a mano, per la HUD in pixel art (vedi player/hud.gd).
## Solo maiuscole: il testo viene convertito e le lettere accentate perdono l'accento.
## I caratteri hanno larghezza variabile (si tolgono le colonne vuote), tranne le cifre,
## che restano larghe 5 così i numeri non "ballano" quando cambiano.
##
##   PixelFont.draw(canvas_item, Vector2(10, 10), "Vita 100", Color.WHITE)
##   PixelFont.width("Vita 100")
##
## Per aggiungere un carattere: una voce in GLYPHS con 7 righe da 5 colonne ("#" = pixel acceso).

const HEIGHT := 7
const SPACING := 1
const SPACE_WIDTH := 3

const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
	".": [".", ".", ".", ".", ".", "#", "#"],
	",": ["..", "..", "..", "..", ".#", ".#", "#."],
	":": [".", "#", "#", ".", "#", "#", "."],
	"!": ["#", "#", "#", "#", "#", ".", "#"],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"'": ["#", "#", ".", ".", ".", ".", "."],
	"-": ["....", "....", "....", "####", "....", "....", "...."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
	")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
	"[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
	"]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
	"<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
	">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
	"%": ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"],
}

const ACCENTS := {"À": "A", "Á": "A", "È": "E", "É": "E", "Ì": "I", "Í": "I", "Ò": "O", "Ó": "O", "Ù": "U", "Ú": "U"}

static var _texture: ImageTexture
static var _regions := {}  # carattere -> Rect2 nella texture


## Larghezza in pixel del testo (prima della scala).
static func width(text: String) -> int:
	_build()
	var w := 0
	for ch in _normalize(text):
		w += (SPACE_WIDTH if ch == " " or not _regions.has(ch) else int(_regions[ch].size.x)) + SPACING
	return maxi(w - SPACING, 0)


## Disegna il testo con l'angolo in alto a sinistra in `pos`. `scale` intero = pixel più grossi.
## `shadow`: colore dell'ombra (spostata di 1 pixel in basso a destra), trasparente = niente ombra.
static func draw(ci: CanvasItem, pos: Vector2, text: String, color: Color, scale := 1,
		shadow := Color(0, 0, 0, 0.85)) -> void:
	_build()
	if shadow.a > 0.0:
		_draw_run(ci, pos + Vector2(scale, scale), text, shadow, scale)
	_draw_run(ci, pos, text, color, scale)


## Come draw(), ma con un contorno di 1 pixel tutto intorno (scritte grandi, es. "PARRY").
static func draw_outlined(ci: CanvasItem, pos: Vector2, text: String, color: Color, outline: Color, scale := 1) -> void:
	_build()
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_draw_run(ci, pos + o * scale, text, outline, scale)
	_draw_run(ci, pos + Vector2(0, scale), text, outline, scale)
	_draw_run(ci, pos, text, color, scale)


static func _draw_run(ci: CanvasItem, pos: Vector2, text: String, color: Color, scale: int) -> void:
	var x := pos.x
	for ch in _normalize(text):
		if ch == " " or not _regions.has(ch):
			x += (SPACE_WIDTH + SPACING) * scale
			continue
		var region: Rect2 = _regions[ch]
		ci.draw_texture_rect_region(_texture, Rect2(Vector2(x, pos.y), region.size * scale), region, color)
		x += (region.size.x + SPACING) * scale


static func _normalize(text: String) -> String:
	var up := text.to_upper()
	for k in ACCENTS:
		up = up.replace(k, ACCENTS[k])
	return up


## Tutti i caratteri in una texture bianca (una riga), colorata poi con il modulate.
static func _build() -> void:
	if _texture:
		return
	var total := 0
	for ch in GLYPHS:
		total += _trimmed(ch).y + 1
	var img := Image.create(maxi(total, 1), HEIGHT, false, Image.FORMAT_RGBA8)
	var x := 0
	for ch in GLYPHS:
		var cols := _trimmed(ch)  # (prima colonna, larghezza)
		var rows: Array = GLYPHS[ch]
		for y in HEIGHT:
			var row: String = rows[y]
			for c in cols.y:
				if row[cols.x + c] == "#":
					img.set_pixel(x + c, y, Color.WHITE)
		_regions[ch] = Rect2(x, 0, cols.y, HEIGHT)
		x += cols.y + 1
	_texture = ImageTexture.create_from_image(img)


## Colonne usate dal carattere: Vector2i(prima, larghezza). Le cifre restano intere.
static func _trimmed(ch: String) -> Vector2i:
	var rows: Array = GLYPHS[ch]
	var w: int = (rows[0] as String).length()
	if ch >= "0" and ch <= "9":
		return Vector2i(0, w)
	var first := w
	var last := -1
	for row in rows:
		for c in w:
			if (row as String)[c] == "#":
				first = mini(first, c)
				last = maxi(last, c)
	if last < 0:
		return Vector2i(0, w)
	return Vector2i(first, last - first + 1)
