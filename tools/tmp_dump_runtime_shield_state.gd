extends SceneTree

func _find(node: Node, n: String) -> Node:
	if node.name == n:
		return node
	for c in node.get_children():
		var f := _find(c, n)
		if f != null:
			return f
	return null

func _dump_transform(label: String, node: Node) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		print(label, " path=", n3.get_path(), " local_pos=", n3.position, " local_rot=", n3.rotation_degrees, " global_pos=", n3.global_position)
	else:
		print(label, " path=", node.get_path(), " (not Node3D)")

func _init() -> void:
	var root3d := Node3D.new()
	root3d.name = "VisualWorld3D"
	root.add_child(root3d)
	var world2d := Node2D.new()
	world2d.name = "GameWorld2D"
	root.add_child(world2d)
	var ps := load("res://scenes/entities/player.tscn") as PackedScene
	var p := ps.instantiate() as Node2D
	p.name = "Player"
	world2d.add_child(p)
	p.position = Vector2.ZERO
	for i in range(12):
		await physics_frame
		await process_frame
	var pv := _find(root, "PlayerVisual_Player") as Node3D
	if pv == null:
		print("PlayerVisual not found")
		quit(1)
		return
	print("scene export shield offset property=", pv.get("equipment_shield_local_offset"))
	print("scene export shield rot property=", pv.get("equipment_shield_local_rotation_deg"))
	_dump_transform("shield attachment", pv.get_node("ShieldAttachment"))
	_dump_transform("shield offset", pv.get_node("ShieldAttachment/ShieldOffset"))
	_dump_transform("shield mesh", pv.get_node("ShieldAttachment/ShieldOffset/EquipmentShieldMesh"))
	quit(0)
