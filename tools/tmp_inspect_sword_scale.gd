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
	for i in range(5):
		await process_frame
	var meshy := _find(inst, "Meshy") as Node3D
	var skel := _find(inst, "Skeleton3D") as Skeleton3D
	var ba := _find(inst, "SwordBoneAttachment") as BoneAttachment3D
	var sword := _find(inst, "SwordMesh") as Node3D
	var mesh := _find(inst, "Mesh") as MeshInstance3D
	print("PlayerVisual global=", inst.global_position, " scale=", inst.global_basis.get_scale())
	if meshy: print("Meshy global=", meshy.global_position, " scale=", meshy.global_basis.get_scale())
	if skel: print("Skeleton global=", skel.global_position, " scale=", skel.global_basis.get_scale(), " bones=", skel.get_bone_count())
	if ba: print("BoneAttach global=", ba.global_position, " scale=", ba.global_basis.get_scale(), " bone=", ba.get("bone_name"), " idx=", ba.get("bone_idx"))
	if sword: print("SwordMesh global=", sword.global_position, " scale=", sword.global_basis.get_scale())
	if mesh:
		print("Sword raw aabb=", mesh.mesh.get_aabb())
	quit(0)
