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
	for i in range(20):
		await process_frame
	var sword_mesh_node := _find(inst, "Mesh") as MeshInstance3D
	if sword_mesh_node == null:
		print("Sword mesh node missing")
		quit(0)
		return
	print("Sword MeshInstance global=", sword_mesh_node.global_position, " visible=", sword_mesh_node.visible, " transp=", sword_mesh_node.transparency)
	if sword_mesh_node.mesh != null:
		print("surface_count=", sword_mesh_node.mesh.get_surface_count())
		for i in range(sword_mesh_node.mesh.get_surface_count()):
			var src := sword_mesh_node.mesh.surface_get_material(i)
			var over := sword_mesh_node.get_surface_override_material(i)
			print("surface", i, " src=", src, " override=", over)
			if over is BaseMaterial3D:
				var bm := over as BaseMaterial3D
				print("  over transparency=", bm.transparency, " cull=", bm.cull_mode, " unshaded=", bm.shading_mode, " albedo_tex=", bm.albedo_texture)
			if src is BaseMaterial3D:
				var sm := src as BaseMaterial3D
				print("  src transparency=", sm.transparency, " cull=", sm.cull_mode, " albedo_tex=", sm.albedo_texture, " alpha_scissor=", sm.alpha_scissor_threshold)
	quit(0)
