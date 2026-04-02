extends SceneTree

const TILE_SCENES := {
	"floor_tile_large": preload("res://assets/structure/floors/floor_tile_large.gltf"),
	"floor_tile_large_rocks": preload("res://assets/structure/floors/floor_tile_large_rocks.gltf"),
	"floor_tile_small": preload("res://assets/structure/floors/floor_tile_small.gltf"),
	"floor_tile_small_decorated": preload("res://assets/structure/floors/floor_tile_small_decorated.gltf"),
}


func _init() -> void:
	for key in TILE_SCENES.keys():
		var scene := TILE_SCENES[key] as PackedScene
		var instance := scene.instantiate() as Node3D
		if instance == null:
			print("TILE_BOUNDS %s failed_to_instantiate" % key)
			continue
		var bounds := _merged_mesh_aabb_in_root(instance)
		instance.free()
		print(
			"TILE_BOUNDS %s pos=(%.6f,%.6f,%.6f) size=(%.6f,%.6f,%.6f)"
			% [
				key,
				bounds.position.x,
				bounds.position.y,
				bounds.position.z,
				bounds.size.x,
				bounds.size.y,
				bounds.size.z,
			]
		)
	quit()


func _merged_mesh_aabb_in_root(root: Node3D) -> AABB:
	var merged := AABB()
	var has_any := false
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor(mesh_instance, root)
		var transformed := _transform_aabb(root_to_mesh, mesh_instance.mesh.get_aabb())
		if not has_any:
			merged = transformed
			has_any = true
		else:
			merged = merged.merge(transformed)
	return merged if has_any else AABB()


static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform_to_ancestor := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform_to_ancestor = (current as Node3D).transform * transform_to_ancestor
		current = current.get_parent()
	return transform_to_ancestor


static func _transform_aabb(transform_to_apply: Transform3D, aabb: AABB) -> AABB:
	var position := aabb.position
	var size := aabb.size
	var corners: Array[Vector3] = [
		Vector3(position.x, position.y, position.z),
		Vector3(position.x + size.x, position.y, position.z),
		Vector3(position.x, position.y + size.y, position.z),
		Vector3(position.x, position.y, position.z + size.z),
		Vector3(position.x + size.x, position.y + size.y, position.z),
		Vector3(position.x + size.x, position.y, position.z + size.z),
		Vector3(position.x, position.y + size.y, position.z + size.z),
		Vector3(position.x + size.x, position.y + size.y, position.z + size.z),
	]
	var transformed := AABB()
	var has_point := false
	for corner in corners:
		var transformed_corner := transform_to_apply * corner
		if not has_point:
			transformed = AABB(transformed_corner, Vector3.ZERO)
			has_point = true
		else:
			transformed = transformed.expand(transformed_corner)
	return transformed if has_point else AABB()
