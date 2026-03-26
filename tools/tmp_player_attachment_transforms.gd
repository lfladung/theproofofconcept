extends SceneTree
func _p(n: Node, label: String) -> void:
	if n is Node3D:
		var d := n as Node3D
		print(label, " path=", d.get_path(), " pos=", d.global_position, " scale=", d.global_basis.get_scale(), " lscale=", d.transform.basis.get_scale())
func _find(root: Node, path: String) -> Node:
	return root.get_node_or_null(NodePath(path))
func _init() -> void:
	var vw := Node3D.new(); vw.name = "VisualWorld3D"; root.add_child(vw)
	var gw := Node2D.new(); gw.name = "GameWorld2D"; root.add_child(gw)
	var ps := load("res://scenes/entities/player.tscn") as PackedScene
	var p := ps.instantiate() as Node2D
	gw.add_child(p)
	for i in range(8): await physics_frame
	await process_frame
	var pv := vw.get_node_or_null("PlayerVisual_Player") as Node3D
	if pv == null:
		print("no pv")
		quit(1)
		return
	_p(pv, "pv")
	_p(_find(pv, "Meshy/Armature/Skeleton3D"), "skel")
	_p(_find(pv, "ArmorAttachment"), "armor_root")
	_p(_find(pv, "ArmorAttachment/ChestOffset"), "chest_offset")
	_p(_find(pv, "ArmorAttachment/ChestOffset/EquipmentChestMesh"), "chest_mesh")
	_p(_find(pv, "HelmetAttachment"), "helmet_root")
	_p(_find(pv, "HelmetAttachment/HelmetOffset"), "helmet_offset")
	_p(_find(pv, "HelmetAttachment/HelmetOffset/EquipmentHelmetMesh"), "helmet_mesh")
	quit(0)
