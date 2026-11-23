extends Marker3D
## Crea un nemico qui e lo ricrea qualche secondo dopo la sua morte (utile per i test).

@export var enemy_scene: PackedScene
@export var respawn := true
@export var respawn_delay := 6.0


func _ready() -> void:
	_spawn()


func _spawn() -> void:
	if enemy_scene == null:
		return
	var enemy := enemy_scene.instantiate() as Node3D
	add_child(enemy)
	if respawn and enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died, CONNECT_ONE_SHOT)


func _on_enemy_died() -> void:
	await get_tree().create_timer(respawn_delay).timeout
	_spawn()
