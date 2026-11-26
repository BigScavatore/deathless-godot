extends Marker3D
## Crea un nemico qui e (se "respawn") lo ricrea qualche secondo dopo la sua morte.
## Si usa anche dalle mappe di TrenchBroom: è l'entità "monster_knight" (vedi maps/deathless_fgd.tres),
## con le proprietà "respawn" (0/1) e "respawn_delay" (secondi).

const DEFAULT_ENEMY := preload("res://enemies/knight/knight.tscn")

## Scena del nemico (vuota = cavaliere).
@export var enemy_scene: PackedScene
@export var respawn := true
@export var respawn_delay := 6.0


func _ready() -> void:
	# Differito: dalle mappe le proprietà arrivano subito dopo l'ingresso nella scena.
	_spawn.call_deferred()


## Proprietà dell'entità della mappa (func_godot).
func _func_godot_apply_properties(properties: Dictionary) -> void:
	respawn = bool(properties.get("respawn", respawn))
	respawn_delay = float(properties.get("respawn_delay", respawn_delay))


func _spawn() -> void:
	var scene := enemy_scene if enemy_scene else DEFAULT_ENEMY
	var enemy := scene.instantiate() as Node3D
	add_child(enemy)
	if respawn and enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died, CONNECT_ONE_SHOT)


func _on_enemy_died() -> void:
	await get_tree().create_timer(respawn_delay).timeout
	_spawn()
