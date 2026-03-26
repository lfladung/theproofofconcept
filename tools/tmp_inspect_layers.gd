extends SceneTree

func _walk(node: Node, out: Array):
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_walk(c, out)

func _init() -> void:
	var ps := load("res://scenes/visuals/player_visual.tscn") as PackedScene
	var inst := ps.instantiate() as Node3D
	root.add_child(inst)
	for i in range(5):
		await process_frame
	var meshes: Array = []
	_walk(inst, meshes)
	for m in meshes:
		var mi := m as MeshInstance3D
		print(mi.name, " path=", mi.get_path(), " layers=", mi.layers, " vis=", mi.visible)
	quit(0)
