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
	var sword_root := _find(inst, "SwordAttachment") as Node3D
	var sword_mesh_node := _find(inst, "SwordMesh") as Node3D
	var sword_mesh := _find(inst, "Mesh") as MeshInstance3D
	if sword_root:
		print("SwordRoot global=", sword_root.global_position, " vis=", sword_root.visible)
	if sword_mesh_node:
		print("SwordMeshNode global=", sword_mesh_node.global_position, " scale=", sword_mesh_node.global_basis.get_scale())
	if sword_mesh:
		print("SwordMesh(global) layers=", sword_mesh.layers, " vis=", sword_mesh.visible, " transp=", sword_mesh.transparency, " overlay=", sword_mesh.material_overlay)
	quit(0)
