extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps: PackedScene = load("res://scenes/visuals/player_visual.tscn") as PackedScene
	var inst: Node3D = ps.instantiate() as Node3D
	root.add_child(inst)
	await process_frame
	await process_frame
	var skeleton: Skeleton3D = _find_skeleton(inst)
	var idx := skeleton.find_bone("RightHand")
	print("RightHand idx:", idx)
	var bone_world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(idx)
	print("Bone origin:", bone_world.origin)
	print("Bone basis x:", bone_world.basis.x)
	print("Bone basis y:", bone_world.basis.y)
	print("Bone basis z:", bone_world.basis.z)
	var sword_root := inst.get_node("SwordAttachment") as Node3D
	var sword_offset := sword_root.get_node("SwordOffset") as Node3D
	var sword_mesh := sword_offset.get_node("SwordMesh") as Node3D
	print("Sword root origin:", sword_root.global_position)
	print("Sword offset local pos:", sword_offset.position)
	print("Sword offset world origin:", sword_offset.global_position)
	print("Sword mesh local pos:", sword_mesh.position)
	print("Sword mesh world origin:", sword_mesh.global_position)
	var mi := _find_mesh(sword_mesh)
	if mi != null and mi.mesh != null:
		print("Sword AABB:", mi.mesh.get_aabb())
	quit(0)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null