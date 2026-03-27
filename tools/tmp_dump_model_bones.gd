extends SceneTree

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _init() -> void:
	var ps := load("res://scenes/visuals/player_visual.tscn") as PackedScene
	if ps == null:
		print("load failed")
		quit(1)
		return
	var inst := ps.instantiate()
	root.add_child(inst)
	await process_frame
	var skeleton := _find_skeleton(inst)
	if skeleton == null:
		print("no skeleton")
		quit(1)
		return
	print("BONES:")
	for i in range(skeleton.get_bone_count()):
		print(i, ": ", skeleton.get_bone_name(i))
	quit(0)
