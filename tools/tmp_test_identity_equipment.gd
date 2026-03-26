extends SceneTree
func _find(node: Node, name: String) -> Node:
	if node.name == name: return node
	for c in node.get_children():
		var f := _find(c, name)
		if f != null: return f
	return null
func _init() -> void:
	var vw := Node3D.new(); vw.name = "VisualWorld3D"; root.add_child(vw)
	var gw := Node2D.new(); gw.name = "GameWorld2D"; root.add_child(gw)
	var p := (load("res://scenes/entities/player.tscn") as PackedScene).instantiate() as Node2D
	gw.add_child(p)
	for i in range(8): await physics_frame
	await process_frame
	var pv := _find(root, "PlayerVisual_Player") as Node3D
	var chest := _find(pv, "EquipmentChestMesh") as Node3D
	var helmet := _find(pv, "EquipmentHelmetMesh") as Node3D
	if chest != null:
		chest.transform = Transform3D.IDENTITY
	if helmet != null:
		helmet.transform = Transform3D.IDENTITY
	await process_frame
	var cmesh := _find(pv, "Mesh1_0") as MeshInstance3D
	print("chest mesh global=", cmesh.global_position, " scale=", cmesh.global_basis.get_scale())
	quit(0)
