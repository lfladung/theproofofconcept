extends SceneTree
func _init() -> void:
	var ps: PackedScene = load("res://scenes/equipment/weapons/sword_texture.tscn") as PackedScene
	var n: Node3D = ps.instantiate() as Node3D
	root.add_child(n)
	await process_frame
	print("root:", n.name, " class=", n.get_class())
	for c in n.get_children():
		if c is Node3D:
			var c3 := c as Node3D
			print("child:", c3.name, " transform=", c3.transform)
		if c is MeshInstance3D:
			var mi:=c as MeshInstance3D
			print("mesh aabb=", mi.mesh.get_aabb())
			print("mesh transform=", mi.transform)
		var mi2 := _find_mesh(c)
		if mi2 != null:
			print("desc mesh:", mi2.name, " aabb=", mi2.mesh.get_aabb(), " tr=", mi2.transform)
	quit(0)

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null