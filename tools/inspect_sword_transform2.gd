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
	for i in range(10):
		await process_frame
	var ba := _find(inst, "@BoneAttachment3D@3") as BoneAttachment3D
	var sword_mesh := _find(inst, "SwordMesh") as Node3D
	if ba != null:
		print("BoneAttachment bone_name=", ba.get("bone_name"), " bone_idx=", ba.get("bone_idx"), " global=", ba.global_position)
	else:
		print("BoneAttachment not found by generated name")
	if sword_mesh != null:
		print("SwordMesh global=", sword_mesh.global_position)
	quit(0)
