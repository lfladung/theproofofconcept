extends SceneTree

func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		print(mi.name, " global=", mi.global_position, " scale=", mi.global_basis.get_scale(), " vis=", mi.visible, " transp=", mi.transparency)
	for c in node.get_children():
		_walk(c)

func _init() -> void:
	var ps := load("res://scenes/visuals/player_visual.tscn") as PackedScene
	var inst := ps.instantiate() as Node3D
	root.add_child(inst)
	for i in range(20):
		await process_frame
	_walk(inst)
	quit(0)
