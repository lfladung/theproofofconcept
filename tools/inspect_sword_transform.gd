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
	await process_frame
	var sk := _find(inst, "Skeleton3D") as Skeleton3D
	var sword_mesh := _find(inst, "SwordMesh") as Node3D
	var sword_root := _find(inst, "SwordAttachment") as Node3D
	print("player global=", inst.global_position)
	if sk != null:
		print("skeleton global=", sk.global_position)
		var idx := sk.find_bone("LeftHand")
		print("LeftHand idx=", idx)
		if idx >= 0:
			print("LeftHand pose origin=", sk.get_bone_global_pose(idx).origin)
	if sword_root != null:
		print("SwordAttachment global=", sword_root.global_position, " visible=", sword_root.visible)
	if sword_mesh != null:
		print("SwordMesh global=", sword_mesh.global_position, " rot=", sword_mesh.global_rotation_degrees, " scale=", sword_mesh.global_scale)
	quit(0)
