extends SceneTree

func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for c in node.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null

func _init() -> void:
	var ps := load("res://scenes/visuals/player_visual.tscn") as PackedScene
	var inst := ps.instantiate() as Node3D
	root.add_child(inst)
	for i in range(8):
		await process_frame
	var helmet := _find(inst, "HelmetOffset") as Node3D
	if helmet:
		print("helmet global rot=", helmet.global_rotation_degrees)
		print("helmet basis x=", helmet.global_basis.x.normalized(), " y=", helmet.global_basis.y.normalized(), " z=", helmet.global_basis.z.normalized())
	quit(0)
