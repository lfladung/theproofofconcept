extends SceneTree

func _initialize() -> void:
	_dump_scene("res://assets/structure/floors/floor_dirt_small_A.gltf")
	_dump_scene("res://art/environment/floors/dirt_brick_ground_texture.glb")
	quit()

func _dump_scene(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		print("SCENE_FAIL %s" % path)
		return
	var root := scene.instantiate()
	print("SCENE %s" % path)
	for mesh_instance in _mesh_instances(root):
		print("  NODE %s" % mesh_instance.name)
		print("  MAT_OVERRIDE %s" % [mesh_instance.material_override])
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				print("  SURFACE %d MAT %s" % [surface_index, mesh_instance.mesh.surface_get_material(surface_index)])

func _mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		out.append(child)
	return out
