extends SceneTree

const TILE_SCENES := {
	"floor_tile_large": preload("res://assets/structure/floors/floor_tile_large.gltf"),
	"floor_tile_large_rocks": preload("res://assets/structure/floors/floor_tile_large_rocks.gltf"),
}


func _init() -> void:
	for key in TILE_SCENES.keys():
		var scene := TILE_SCENES[key] as PackedScene
		var instance := scene.instantiate() as Node3D
		if instance == null:
			print("TILE_UV %s failed_to_instantiate" % key)
			continue
		var uv_bounds := _top_surface_uv_bounds(instance)
		instance.free()
		print(
			"TILE_UV %s pos=(%.6f,%.6f) size=(%.6f,%.6f)"
			% [key, uv_bounds.position.x, uv_bounds.position.y, uv_bounds.size.x, uv_bounds.size.y]
		)
	quit()


func _top_surface_uv_bounds(root: Node3D) -> Rect2:
	var uv_bounds := Rect2()
	var has_uv_bounds := false
	for mesh_instance_v in _mesh_instances_in_root(root):
		var mesh_instance := mesh_instance_v as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor(mesh_instance, root)
		var normal_basis := root_to_mesh.basis
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			if not normals is PackedVector3Array or not uvs is PackedVector2Array:
				continue
			var packed_normals := normals as PackedVector3Array
			var packed_uvs := uvs as PackedVector2Array
			var count := mini(packed_normals.size(), packed_uvs.size())
			for index in range(count):
				var transformed_normal := (normal_basis * packed_normals[index]).normalized()
				if transformed_normal.y < 0.85:
					continue
				var uv := packed_uvs[index]
				if not has_uv_bounds:
					uv_bounds = Rect2(uv, Vector2.ZERO)
					has_uv_bounds = true
				else:
					var min_v := Vector2(minf(uv_bounds.position.x, uv.x), minf(uv_bounds.position.y, uv.y))
					var max_v := Vector2(maxf(uv_bounds.end.x, uv.x), maxf(uv_bounds.end.y, uv.y))
					uv_bounds = Rect2(min_v, max_v - min_v)
	return uv_bounds


func _mesh_instances_in_root(root: Node3D) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		if candidate is MeshInstance3D:
			out.append(candidate)
	return out


static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform_to_ancestor := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform_to_ancestor = (current as Node3D).transform * transform_to_ancestor
		current = current.get_parent()
	return transform_to_ancestor
