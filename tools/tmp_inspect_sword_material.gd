extends SceneTree

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == "Mesh":
		return node
	for c in node.get_children():
		var f := _find_mesh(c)
		if f != null:
			return f
	return null

func _init() -> void:
	var ps := load("res://art/equipment/weapons/Sword_texture.glb") as PackedScene
	var inst := ps.instantiate()
	root.add_child(inst)
	var mi := _find_mesh(inst)
	if mi == null or mi.mesh == null:
		print("no mesh")
		quit(0)
		return
	print("surface_count=", mi.mesh.get_surface_count())
	for i in range(mi.mesh.get_surface_count()):
		var mat := mi.mesh.surface_get_material(i)
		if mat == null:
			print("surface", i, " mat=null")
			continue
		print("surface", i, " mat_class=", mat.get_class())
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			print("  transparency=", bm.transparency, " albedo=", bm.albedo_color, " alpha_scissor=", bm.alpha_scissor_threshold, " cull=", bm.cull_mode)
			print("  tex_albedo=", bm.albedo_texture)
	quit(0)
