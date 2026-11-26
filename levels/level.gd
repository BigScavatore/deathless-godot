extends Node3D
## Livello fatto con TrenchBroom: la geometria e le entità vengono da una mappa .map tramite il
## plugin func_godot (nodo FuncGodotMap, qui "Map").
##
## Dall'editor: seleziona "Map" e premi "Build Map" nell'ispettore per vedere il livello e salvarlo
## nella scena. Se la mappa non è stata costruita (nodo "Map" vuoto), viene costruita all'avvio del
## gioco: così basta salvare la mappa in TrenchBroom e premere Play.
## Se il player cade fuori dal livello (sotto kill_height) il livello ricomincia.

@export var map: Node3D
## Altezza (m) sotto cui il player è considerato caduto fuori dal livello.
@export var kill_height := -30.0


func _ready() -> void:
	if map == null:
		map = get_node_or_null("Map") as Node3D
	if map and map.get_child_count() == 0 and map.has_method("build"):
		map.build()


func _physics_process(_delta: float) -> void:
	for player in get_tree().get_nodes_in_group("player"):
		if (player as Node3D).global_position.y < kill_height:
			get_tree().reload_current_scene()
			return
