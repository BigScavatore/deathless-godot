class_name Sfx
## Effetti sonori one-shot. I file sono in assets/sounds/<nome>_<n>.wav (generati da
## tools/generate_sounds.py): ogni volta si sceglie una variante a caso con un pitch
## leggermente diverso, così i suoni ripetuti non stancano.
##
##   Sfx.play(self, &"swing")                       # suono "in testa" (player, arma)
##   Sfx.play_at(self, &"hit_armor", position)      # suono 3D nel mondo (nemici, impatti)
##
## Tutti gli effetti passano dal bus audio "SFX" (default_bus_layout.tres): il volume
## generale degli effetti si regola lì, dal pannello Audio in basso nell'editor.

const SOUND_DIR := "res://assets/sounds/"
const BUS := &"SFX"

static var _cache := {}


## Tutte le varianti di un effetto (caricate una volta sola).
static func variants(sound: StringName) -> Array[AudioStream]:
	if _cache.has(sound):
		return _cache[sound]
	var list: Array[AudioStream] = []
	var i := 1
	while ResourceLoader.exists(SOUND_DIR + "%s_%d.wav" % [sound, i]):
		list.append(load(SOUND_DIR + "%s_%d.wav" % [sound, i]))
		i += 1
	if list.is_empty():
		push_warning("Sfx: nessun file per '%s' in %s" % [sound, SOUND_DIR])
	_cache[sound] = list
	return list


static func pick(sound: StringName) -> AudioStream:
	var list := variants(sound)
	return list.pick_random() if not list.is_empty() else null


## Suono non posizionale (del player: arma, passi, danno subito).
static func play(context: Node, sound: StringName, volume_db := 0.0, pitch_jitter := 0.08) -> AudioStreamPlayer:
	var stream := pick(sound)
	if stream == null or not context.is_inside_tree():
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	player.bus = BUS
	player.finished.connect(player.queue_free)
	player.autoplay = true
	# Differito: funziona anche se chiamato mentre la scena si sta ancora costruendo (_ready).
	context.get_tree().root.add_child.call_deferred(player)
	return player


## Suono 3D in un punto del mondo (si sente più piano da lontano).
static func play_at(context: Node, sound: StringName, position: Vector3, volume_db := 0.0,
		pitch_jitter := 0.08) -> AudioStreamPlayer3D:
	var stream := pick(sound)
	if stream == null or not context.is_inside_tree():
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 8.0
	player.max_distance = 60.0
	player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	player.bus = BUS
	player.finished.connect(player.queue_free)
	player.autoplay = true
	player.position = position  # figlio diretto della root: posizione locale = globale
	context.get_tree().root.add_child.call_deferred(player)
	return player


## Stream in loop (es. scivolata): la stessa risorsa viene impostata per ripetersi.
static func looping(sound: StringName) -> AudioStream:
	var stream := pick(sound)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return stream
