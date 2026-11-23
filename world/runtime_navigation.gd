extends NavigationRegion3D
## Calcola la navmesh all'avvio a partire dalle collisioni dei nodi nel gruppo "navigation_source"
## (e dei loro figli; per le CSG serve "use_collision"). Così puoi modificare il livello senza ricordarti di rifare il bake:
## basta mettere i nodi del livello in quel gruppo (pannello Nodo > Gruppi).
## In alternativa puoi fare il bake dall'editor e togliere questo script.

signal navigation_ready

@export var source_group := &"navigation_source"


func _ready() -> void:
	if navigation_mesh == null:
		navigation_mesh = NavigationMesh.new()
	navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navigation_mesh.geometry_source_group_name = source_group
	# Le collisioni sono già sulla CPU: molto più veloce che leggere le mesh visive.
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	bake_finished.connect(navigation_ready.emit)
	# Le CSG generano la loro mesh un frame dopo: aspetta prima di leggere la geometria.
	await get_tree().physics_frame
	await get_tree().physics_frame
	bake_navigation_mesh(true)
