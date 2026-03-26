extends SceneTree
func _dump(mi: MeshInstance3D, label: String) -> void:
	print("=== ", label, " ===")
	var mesh := mi.mesh
	if mesh == null:
		print("no mesh")
		return
	for i in range(mesh.get_surface_count()):
		var mat: Material = mi.get_surface_override_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		print("surface", i, " mat=", mat)
		if mat is BaseMaterial3D:
			var b := mat as BaseMaterial3D
			print("  albedo=", b.albedo_color, " transp=", b.transparency, " alpha_scissor=", b.alpha_scissor_threshold, " cull=", b.cull_mode)
			print("  albedo_tex=", b.albedo_texture)
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
	var chest := _find(inst, "Mesh1_0")
	var sword := _find(inst, "Mesh")
	if chest is MeshInstance3D:
		_dump(chest as MeshInstance3D, "chest")
	if sword is MeshInstance3D:
		_dump(sword as MeshInstance3D, "sword")
	quit(0)
