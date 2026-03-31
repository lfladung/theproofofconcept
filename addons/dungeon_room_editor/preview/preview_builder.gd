@tool
extends RefCounted
class_name DungeonRoomPreviewBuilder

const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const RUNTIME_DIRT_FLOOR_SCENE := preload("res://art/environment/floors/dirt_brick_ground_texture.glb")
const RUNTIME_METAL_FLOOR_SCENE := preload("res://art/environment/floors/metal_tile_floor_texture.glb")
const RUNTIME_GRATE_FLOOR_SCENE := preload("res://art/environment/floors/grated_ground_floor_texture.glb")
const FLOOR_SHELL_THICKNESS := 0.35
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 1.25
const FLOOR_COLOR := Color(0.48, 0.43, 0.37, 1.0)
const WALL_COLOR := Color(0.30, 0.27, 0.24, 1.0)

var _preview_aabb_by_scene_path: Dictionary = {}
var _runtime_floor_material_cache: Dictionary = {}


func rebuild_preview(root: Node3D, room: RoomBase, layout, catalog, visible_layer_filter: StringName = &"all") -> void:
	if root == null:
		return
	for child in root.get_children():
		child.free()
	if room == null or layout == null or catalog == null:
		return
	var has_floor := _layout_has_category(layout, catalog, &"floor", visible_layer_filter)
	var has_wall := _layout_has_category(layout, catalog, &"wall", visible_layer_filter)
	if _layer_visible(visible_layer_filter, &"ground") and not has_floor:
		root.add_child(_build_floor_shell(room))
	if _layer_visible(visible_layer_filter, &"overlay") and not has_wall:
		root.add_child(_build_wall_shell(room))
	for item in layout.items:
		if item == null:
			continue
		var piece = catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		if not _item_visible(item, piece, visible_layer_filter):
			continue
		var node := _build_piece_preview(item, piece, layout, room)
		if node == null:
			continue
		root.add_child(node)


func _build_piece_preview(
	item, piece, layout, room: RoomBase
) -> Node3D:
	var instance = piece.preview_scene.instantiate() as Node3D if piece.preview_scene != null else null
	if instance == null:
		instance = _build_fallback_preview(piece, layout, room, item)
	if instance == null:
		return null
	instance.name = "%s_%s" % [String(piece.piece_id), item.item_id]
	configure_piece_instance(instance, item, piece, layout, room)
	return instance


func configure_piece_instance(
	instance: Node3D,
	item,
	piece,
	layout,
	room: RoomBase
) -> void:
	if instance == null:
		return
	apply_piece_visual_overrides(instance, piece)
	if _should_fit_preview_to_grid(piece):
		_apply_grid_fit_transform(instance, item, piece, layout, room)
		return
	var local_position := GridMath.grid_to_local(item.grid_position, layout, room)
	instance.position = Vector3(local_position.x, 0.0, local_position.y)
	instance.rotation = Vector3(0.0, -float(item.normalized_rotation_steps()) * PI * 0.5, 0.0)


func apply_piece_visual_overrides(instance: Node3D, piece) -> void:
	if instance == null or piece == null:
		return
	var runtime_floor_material := _runtime_floor_material_for_piece(piece)
	if runtime_floor_material == null:
		return
	_apply_material_override(instance, runtime_floor_material)


func _build_fallback_preview(
	piece, layout, room: RoomBase, item
) -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	var footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	var step := GridMath.grid_step(layout, room)
	box.size = Vector3(
		maxf(step.x * float(footprint.x), 1.0),
		maxf(minf(step.x, step.y) * 0.45, 0.6),
		maxf(step.y * float(footprint.y), 1.0)
	)
	mesh_instance.mesh = box
	mesh_instance.material_override = _fallback_material(_fallback_color_for_piece(piece))
	mesh_instance.position.y = box.size.y * 0.5
	root.add_child(mesh_instance)
	return root


func _build_floor_shell(room: RoomBase) -> Node3D:
	var root := Node3D.new()
	root.name = "RoomShellFloor"
	var rect := room.get_room_rect_world()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(
		maxf(rect.size.x, 1.0),
		FLOOR_SHELL_THICKNESS,
		maxf(rect.size.y, 1.0)
	)
	mesh_instance.mesh = box
	mesh_instance.material_override = _fallback_material(FLOOR_COLOR)
	mesh_instance.position = Vector3(
		rect.get_center().x,
		-FLOOR_SHELL_THICKNESS * 0.5,
		rect.get_center().y
	)
	root.add_child(mesh_instance)
	return root


func _build_wall_shell(room: RoomBase) -> Node3D:
	var root := Node3D.new()
	root.name = "RoomShellWalls"
	var rect := room.get_room_rect_world()
	root.add_child(
		_build_wall_segment(
			Vector3(rect.get_center().x, WALL_HEIGHT * 0.5, rect.position.y - WALL_THICKNESS * 0.5),
			Vector3(rect.size.x + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS)
		)
	)
	root.add_child(
		_build_wall_segment(
			Vector3(rect.get_center().x, WALL_HEIGHT * 0.5, rect.end.y + WALL_THICKNESS * 0.5),
			Vector3(rect.size.x + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS)
		)
	)
	root.add_child(
		_build_wall_segment(
			Vector3(rect.position.x - WALL_THICKNESS * 0.5, WALL_HEIGHT * 0.5, rect.get_center().y),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, rect.size.y)
		)
	)
	root.add_child(
		_build_wall_segment(
			Vector3(rect.end.x + WALL_THICKNESS * 0.5, WALL_HEIGHT * 0.5, rect.get_center().y),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, rect.size.y)
		)
	)
	return root


func _build_wall_segment(position: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = _fallback_material(WALL_COLOR)
	mesh_instance.position = position
	return mesh_instance


func _fallback_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material


func _fallback_color_for_piece(piece) -> Color:
	match String(piece.category):
		"floor":
			return Color(0.80, 0.80, 0.80, 0.9)
		"wall":
			return Color(0.42, 0.27, 0.16, 0.92)
		"door":
			return Color(0.58, 0.27, 0.84, 0.92)
		"spawn":
			return Color(0.95, 0.33, 0.20, 0.92)
		"exit":
			return Color(0.23, 0.74, 0.97, 0.92)
		"trap":
			return Color(0.97, 0.80, 0.20, 0.92)
		"treasure":
			return Color(0.98, 0.73, 0.20, 0.92)
		_:
			return Color(0.32, 0.75, 0.40, 0.92)


func _should_fit_preview_to_grid(piece) -> bool:
	if piece == null:
		return false
	if piece.category == &"floor":
		return true
	# Door / hall sockets: stretch `wall_doorway` preview to `footprint` (e.g. 2×1 double hall).
	return piece.is_door_socket()


func _runtime_floor_material_for_piece(piece) -> Material:
	if piece == null or piece.category != &"floor":
		return null
	var theme_key := _runtime_floor_theme_for_piece(piece)
	if theme_key.is_empty():
		return null
	if _runtime_floor_material_cache.has(theme_key):
		return _runtime_floor_material_cache[theme_key] as Material
	var source_scene: PackedScene = null
	match theme_key:
		"dirt":
			source_scene = RUNTIME_DIRT_FLOOR_SCENE
		"metal":
			source_scene = RUNTIME_METAL_FLOOR_SCENE
		"grate":
			source_scene = RUNTIME_GRATE_FLOOR_SCENE
		_:
			source_scene = null
	if source_scene == null:
		return null
	var material := _extract_first_surface_material(source_scene)
	if material != null:
		_runtime_floor_material_cache[theme_key] = material
	return material


func _runtime_floor_theme_for_piece(piece) -> String:
	var piece_id := String(piece.piece_id).to_lower()
	if piece_id.contains("wood") or piece_id.contains("foundation"):
		return ""
	if piece_id.contains("grate") or piece_id.contains("spike"):
		return "grate"
	if piece_id.contains("tile"):
		return "metal"
	if piece_id.contains("dirt"):
		return "dirt"
	return ""


func _extract_first_surface_material(scene: PackedScene) -> Material:
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	if root == null:
		return null
	var material: Material = null
	for mesh_instance in _mesh_instances_in_root(root):
		if mesh_instance.material_override != null:
			material = mesh_instance.material_override
			break
		if mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			material = mesh_instance.mesh.surface_get_material(surface_index)
			if material != null:
				break
		if material != null:
			break
	root.free()
	return material


func _apply_material_override(root: Node3D, material: Material) -> void:
	if root == null or material == null:
		return
	for mesh_instance in _mesh_instances_in_root(root):
		if mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			mesh_instance.set_surface_override_material(surface_index, material)


func _mesh_instances_in_root(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance != null:
			out.append(mesh_instance)
	return out


func _apply_grid_fit_transform(
	instance: Node3D,
	item,
	piece,
	layout,
	room: RoomBase
) -> void:
	var source_bounds := _get_preview_scene_aabb(instance, piece)
	var rotation := Vector3(0.0, -float(item.normalized_rotation_steps()) * PI * 0.5, 0.0)
	if source_bounds.size.length_squared() < 1e-8:
		var fallback_position := GridMath.grid_to_local(item.grid_position, layout, room)
		instance.position = Vector3(fallback_position.x, 0.0, fallback_position.y)
		instance.rotation = rotation
		return
	var step := GridMath.grid_step(layout, room)
	var ft := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	var target_size := Vector2(
		maxf(step.x * float(maxi(ft.x, 1)), 0.01),
		maxf(step.y * float(maxi(ft.y, 1)), 0.01)
	)
	var sx := target_size.x / maxf(source_bounds.size.x, 0.01)
	var sz := target_size.y / maxf(source_bounds.size.z, 0.01)
	var sy: float
	if piece.is_door_socket():
		# Keep a stable preview height; only stretch width/depth to match footprint.
		sy = WALL_HEIGHT / maxf(source_bounds.size.y, 0.01)
	else:
		sy = minf(sx, sz)
	instance.scale = Vector3(sx, sy, sz)
	instance.rotation = rotation
	var source_center := source_bounds.get_center()
	var top_y := source_bounds.position.y + source_bounds.size.y
	var anchor_local := Vector3(source_center.x * sx, top_y * sy, source_center.z * sz)
	var local_target := GridMath.grid_to_local(item.grid_position, layout, room)
	var target := Vector3(local_target.x, 0.0, local_target.y)
	var basis := Basis.from_euler(rotation)
	instance.position = target - basis * anchor_local


func _get_preview_scene_aabb(instance: Node3D, piece) -> AABB:
	if piece == null or piece.preview_scene == null:
		return _merged_mesh_aabb_in_root(instance)
	var path_key: String = piece.preview_scene.resource_path
	if path_key.is_empty():
		return _merged_mesh_aabb_in_root(instance)
	if _preview_aabb_by_scene_path.has(path_key):
		return _preview_aabb_by_scene_path[path_key] as AABB
	var computed := _merged_mesh_aabb_in_root(instance)
	_preview_aabb_by_scene_path[path_key] = computed
	return computed


## Merges all MeshInstance3D AABBs under [param subtree_root] into that node's local space (no global_transform).
func merged_mesh_bounds_under_root(subtree_root: Node3D) -> AABB:
	return _merged_mesh_aabb_in_root(subtree_root)


func _merged_mesh_aabb_in_root(root: Node3D) -> AABB:
	if root == null:
		return AABB()
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


func _layout_has_category(layout, catalog, category: StringName, visible_layer_filter: StringName = &"all") -> bool:
	if layout == null or catalog == null:
		return false
	for item in layout.items:
		if item == null:
			continue
		var piece = catalog.find_piece(item.piece_id)
		if piece != null and piece.category == category and _item_visible(item, piece, visible_layer_filter):
			return true
	return false


func _item_visible(item, piece, visible_layer_filter: StringName) -> bool:
	return visible_layer_filter == &"all" or item.resolved_placement_layer(piece) == visible_layer_filter


func _layer_visible(visible_layer_filter: StringName, layer: StringName) -> bool:
	return visible_layer_filter == &"all" or visible_layer_filter == layer
