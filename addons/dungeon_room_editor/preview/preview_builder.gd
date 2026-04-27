@tool
extends RefCounted
class_name DungeonRoomPreviewBuilder

const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const RUNTIME_DIRT_FLOOR_SCENE := preload("res://art/environment/floors/dirt_brick_ground_texture.glb")
const RUNTIME_METAL_FLOOR_SCENE := preload("res://art/environment/floors/metal_tile_floor_texture.glb")
const RUNTIME_GRATE_FLOOR_SCENE := preload("res://art/environment/floors/grated_ground_floor_texture.glb")
const RUNTIME_WOOD_FLOOR_SCENE := preload("res://assets/structure/floors/floor_wood_small.gltf")
const RUNTIME_DARK_WOOD_FLOOR_SCENE := preload("res://assets/structure/floors/floor_wood_small_dark.gltf")
const CANONICAL_DIRT_SMALL_SCENE := preload("res://assets/structure/floors/floor_dirt_small_A.gltf")
const CANONICAL_DIRT_LARGE_SCENE := preload("res://assets/structure/floors/floor_dirt_large.gltf")
const CANONICAL_TILE_SMALL_SCENE := preload("res://assets/structure/floors/floor_tile_small.gltf")
const CANONICAL_TILE_LARGE_SCENE := preload("res://assets/structure/floors/floor_tile_large.gltf")
const FLOOR_SHELL_THICKNESS := 0.35
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 1.25
const FLOOR_COLOR := Color(0.48, 0.43, 0.37, 1.0)
const WALL_COLOR := Color(0.30, 0.27, 0.24, 1.0)
const ROOM_FLOOR_THEME_META := &"runtime_floor_theme"
const ROOM_FLOOR_SEED_META := &"runtime_floor_seed"

var _preview_aabb_by_scene_path: Dictionary = {}
var _runtime_floor_material_cache: Dictionary = {}
var _runtime_floor_surface_cache: Dictionary = {}
var _runtime_floor_detail_overlay_cache: Dictionary = {}


func rebuild_preview(
	root: Node3D,
	room: RoomBase,
	layout,
	catalog,
	visible_layer_filter: StringName = &"all",
	prefer_top_only_floors := false,
	optimize_runtime_floor_batches := false
) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.free()
	if room == null or layout == null or catalog == null:
		return
	var has_floor := _layout_has_category(layout, catalog, &"floor", visible_layer_filter)
	var has_wall := _layout_has_category(layout, catalog, &"wall", visible_layer_filter)
	var consumed_floor_item_ids: Dictionary = {}
	if _layer_visible(visible_layer_filter, &"ground") and not has_floor:
		root.add_child(_build_floor_shell(room))
	elif optimize_runtime_floor_batches:
		var floor_batch := _build_runtime_floor_batch_preview(layout, catalog, room, visible_layer_filter)
		var batched_nodes := floor_batch.get("nodes", []) as Array
		for node_v in batched_nodes:
			if node_v is Node3D:
				root.add_child(node_v as Node3D)
		consumed_floor_item_ids = floor_batch.get("consumed_item_ids", {}) as Dictionary
	if _layer_visible(visible_layer_filter, &"overlay") and not has_wall:
		root.add_child(_build_wall_shell(room))
	for item in layout.items:
		if item == null:
			continue
		if consumed_floor_item_ids.has(item.item_id):
			continue
		var piece = catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		if not _item_visible(item, piece, visible_layer_filter):
			continue
		if not _should_render_piece_preview(piece):
			continue
		var node := _build_piece_preview(item, piece, layout, room, prefer_top_only_floors)
		if node == null:
			continue
		root.add_child(node)


func _build_runtime_floor_batch_preview(layout, catalog, room: RoomBase, visible_layer_filter: StringName) -> Dictionary:
	var runtime_floor_items: Array = []
	var covered_floor_cells: Dictionary = {}
	var supplemental_support_cells: Dictionary = {}
	for item in layout.items:
		if item == null:
			continue
		var piece = catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		if _can_batch_runtime_floor_item(item, piece, visible_layer_filter):
			runtime_floor_items.append({"item": item, "piece": piece})
			_add_item_footprint_cells(covered_floor_cells, item, piece)
	for item in layout.items:
		if item == null:
			continue
		var piece = catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		if not _item_visible(item, piece, visible_layer_filter):
			continue
		if not _should_add_runtime_floor_support(piece):
			continue
		_add_uncovered_item_footprint_cells(supplemental_support_cells, covered_floor_cells, item, piece)
	var nodes: Array = []
	var consumed_item_ids: Dictionary = {}
	if runtime_floor_items.is_empty() and supplemental_support_cells.is_empty():
		return {
			"nodes": nodes,
			"consumed_item_ids": consumed_item_ids,
		}
	var family := _runtime_room_floor_family(room)
	var family_pieces := _runtime_floor_family_piece_sets(catalog, family)
	var support_family_pieces := _runtime_floor_support_family_piece_sets(catalog, family)
	var rng := RandomNumberGenerator.new()
	rng.seed = _runtime_room_floor_seed(room)
	for entry_v in runtime_floor_items:
		var entry := entry_v as Dictionary
		var item = entry.get("item", null)
		var piece = entry.get("piece", null)
		if item == null or piece == null:
			continue
		var footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
		var region_size := maxi(1, footprint.x)
		var region_node := _build_runtime_floor_region_preview(
			family_pieces,
			item.grid_position,
			region_size,
			layout,
			room,
			rng
		)
		if region_node != null:
			nodes.append(region_node)
		var item_id := String(item.item_id)
		if not item_id.is_empty():
			consumed_item_ids[item_id] = true
	for merged_region in _greedy_merge_grid_cells(supplemental_support_cells):
		var origin := merged_region.get("origin", Vector2i.ZERO) as Vector2i
		var size := merged_region.get("size", Vector2i.ONE) as Vector2i
		var region_node := _build_runtime_floor_support_region_preview(
			support_family_pieces,
			origin,
			size,
			layout,
			room
		)
		if region_node != null:
			nodes.append(region_node)
	return {
		"nodes": nodes,
		"consumed_item_ids": consumed_item_ids,
	}


func _can_batch_runtime_floor_item(item, piece, visible_layer_filter: StringName) -> bool:
	if item == null or piece == null:
		return false
	if piece.category != &"floor":
		return false
	if not _item_visible(item, piece, visible_layer_filter):
		return false
	if item.normalized_rotation_steps() != 0:
		return false
	return _is_generic_runtime_room_floor_piece(String(piece.piece_id))


func _should_add_runtime_floor_support(piece) -> bool:
	if piece == null:
		return false
	if piece.category != &"wall":
		return false
	var piece_id := String(piece.piece_id).to_lower()
	return not piece_id.contains("doorway")


func _add_item_footprint_cells(out_cells: Dictionary, item, piece) -> void:
	if out_cells == null or item == null or piece == null:
		return
	var footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	for gx in range(maxi(footprint.x, 1)):
		for gy in range(maxi(footprint.y, 1)):
			out_cells[item.grid_position + Vector2i(gx, gy)] = true


func _add_uncovered_item_footprint_cells(out_cells: Dictionary, covered_cells: Dictionary, item, piece) -> void:
	if out_cells == null or covered_cells == null or item == null or piece == null:
		return
	var footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	for gx in range(maxi(footprint.x, 1)):
		for gy in range(maxi(footprint.y, 1)):
			var cell: Vector2i = item.grid_position + Vector2i(gx, gy)
			if covered_cells.has(cell):
				continue
			out_cells[cell] = true




func _greedy_merge_grid_cells(cells: Dictionary) -> Array[Dictionary]:
	var remaining: Dictionary = cells.duplicate(true)
	var merged: Array[Dictionary] = []
	while not remaining.is_empty():
		var start := _top_left_cell_in_keys(remaining.keys())
		var width := 1
		while remaining.has(Vector2i(start.x + width, start.y)):
			width += 1
		var height := 1
		var can_extend := true
		while can_extend:
			for dx in range(width):
				if not remaining.has(Vector2i(start.x + dx, start.y + height)):
					can_extend = false
					break
			if can_extend:
				height += 1
		for dx in range(width):
			for dy in range(height):
				remaining.erase(Vector2i(start.x + dx, start.y + dy))
		merged.append({
			"origin": start,
			"size": Vector2i(width, height),
		})
	return merged


func _top_left_cell_in_keys(keys: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var found := false
	for key_v in keys:
		if not key_v is Vector2i:
			continue
		var cell := key_v as Vector2i
		if not found or cell.y < best.y or (cell.y == best.y and cell.x < best.x):
			best = cell
			found = true
	return best


func _build_runtime_floor_rect_preview(piece, origin: Vector2i, size: Vector2i, layout, room: RoomBase) -> Node3D:
	if piece == null or room == null:
		return null
	var render_scene := _runtime_floor_render_scene(piece, size)
	var instance = render_scene.instantiate() as Node3D if render_scene != null else null
	if instance == null:
		instance = _build_fallback_runtime_floor_preview(size, layout, room)
	if instance == null:
		return null
	for mesh in _mesh_instances_in_root(instance):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Skip detail overlay for pieces larger than 1x1 — at 2x+ scale they look wrong and cost extra draw calls.
	if size.x <= 1 and size.y <= 1:
		var detail_overlay := _build_runtime_floor_detail_overlay(piece)
		if detail_overlay != null:
			instance.add_child(detail_overlay)
	_apply_runtime_floor_piece_transform(instance, origin, size, piece, layout, room, render_scene)
	return instance


func _build_fallback_runtime_floor_preview(size: Vector2i, layout, room: RoomBase) -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	var step := GridMath.grid_step(layout, room)
	box.size = Vector3(
		maxf(step.x * float(maxi(size.x, 1)), 0.01),
		maxf(minf(step.x, step.y) * 0.05, 0.05),
		maxf(step.y * float(maxi(size.y, 1)), 0.01)
	)
	mesh_instance.mesh = box
	mesh_instance.material_override = _fallback_material(FLOOR_COLOR)
	mesh_instance.position.y = -box.size.y * 0.5
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh_instance)
	return root


func _is_generic_runtime_room_floor_piece(piece_id: String) -> bool:
	var normalized := piece_id.to_lower()
	if normalized.begins_with("floor_mask_"):
		return true
	if normalized.contains("corner") or normalized.contains("spike") or normalized.contains("foundation"):
		return false
	if normalized.contains("grate"):
		return false
	return (
		normalized.begins_with("floor_dirt_")
		or normalized.begins_with("floor_tile_")
		or normalized.begins_with("floor_wood_")
	)


func _runtime_room_floor_family(room: RoomBase) -> StringName:
	if room != null and room.has_meta(ROOM_FLOOR_THEME_META):
		return StringName(String(room.get_meta(ROOM_FLOOR_THEME_META, "dirt")))
	return &"dirt"


func _runtime_room_floor_seed(room: RoomBase) -> int:
	if room != null and room.has_meta(ROOM_FLOOR_SEED_META):
		return int(room.get_meta(ROOM_FLOOR_SEED_META, 1))
	var room_key := ""
	if room != null:
		room_key = "%s|%s|%s" % [String(room.name), String(room.room_id), String(room.scene_file_path)]
	return int(room_key.hash())


func _runtime_floor_family_piece_sets(catalog, family: StringName) -> Dictionary:
	var small_ids: Array[StringName] = []
	var large_ids: Array[StringName] = []
	var extra_large_ids: Array[StringName] = []
	match String(family):
		"wood":
			small_ids = [&"floor_wood_small"]
			large_ids = [&"floor_wood_large"]
			extra_large_ids = [&"floor_wood_large"]
		"dark_wood":
			small_ids = [&"floor_wood_small_dark"]
			large_ids = [&"floor_wood_large_dark"]
			extra_large_ids = [&"floor_wood_large_dark"]
		"tile":
			small_ids = [
				&"floor_tile_small",
				&"floor_tile_small_broken_a",
				&"floor_tile_small_broken_b",
			]
			large_ids = [&"floor_tile_large", &"floor_tile_large_rocks"]
			extra_large_ids = [&"floor_tile_large", &"floor_tile_large_rocks"]
		_:
			small_ids = [
				&"floor_dirt_small_a",
				&"floor_dirt_small_b",
				&"floor_dirt_small_c",
				&"floor_dirt_small_d",
			]
			large_ids = [&"floor_dirt_large"]
			extra_large_ids = [&"floor_dirt_large"]
	return {
		"small": _resolve_floor_piece_list(catalog, small_ids),
		"large": _resolve_floor_piece_list(catalog, large_ids),
		"extra_large": _resolve_floor_piece_list(catalog, extra_large_ids),
	}


func _runtime_floor_support_family_piece_sets(catalog, family: StringName) -> Dictionary:
	var small_ids: Array[StringName] = []
	var large_ids: Array[StringName] = []
	var extra_large_ids: Array[StringName] = []
	match String(family):
		"wood":
			small_ids = [&"floor_wood_small"]
			large_ids = [&"floor_wood_large"]
			extra_large_ids = [&"floor_wood_large"]
		"dark_wood":
			small_ids = [&"floor_wood_small_dark"]
			large_ids = [&"floor_wood_large_dark"]
			extra_large_ids = [&"floor_wood_large_dark"]
		"tile":
			small_ids = [&"floor_tile_small"]
			large_ids = [&"floor_tile_large"]
			extra_large_ids = [&"floor_tile_large"]
		_:
			small_ids = [&"floor_dirt_small_a"]
			large_ids = [&"floor_dirt_large"]
			extra_large_ids = [&"floor_dirt_large"]
	return {
		"small": _resolve_floor_piece_list(catalog, small_ids),
		"large": _resolve_floor_piece_list(catalog, large_ids),
		"extra_large": _resolve_floor_piece_list(catalog, extra_large_ids),
	}


func _resolve_floor_piece_list(catalog, piece_ids: Array[StringName]) -> Array:
	var pieces: Array = []
	for piece_id in piece_ids:
		var piece = catalog.find_piece(piece_id)
		if piece != null:
			pieces.append(piece)
	return pieces


func _build_runtime_floor_region_preview(
	family_pieces: Dictionary,
	origin: Vector2i,
	size: int,
	layout,
	room: RoomBase,
	rng: RandomNumberGenerator
) -> Node3D:
	var root := Node3D.new()
	root.name = "RuntimeFloor_%s_%s_%s" % [origin.x, origin.y, size]
	_add_runtime_floor_tile(root, family_pieces, origin, size, layout, room, rng)
	return root if root.get_child_count() > 0 else null


func _build_runtime_floor_merged_region_preview(
	family_pieces: Dictionary,
	origin: Vector2i,
	footprint_tiles: Vector2i,
	layout,
	room: RoomBase,
	rng: RandomNumberGenerator
) -> Node3D:
	var root := Node3D.new()
	root.name = "RuntimeFloor_%s_%s_%s_%s" % [origin.x, origin.y, footprint_tiles.x, footprint_tiles.y]
	if _should_render_runtime_floor_region_as_tiles(footprint_tiles):
		for gx in range(footprint_tiles.x):
			for gy in range(footprint_tiles.y):
				_add_runtime_floor_tile(
					root,
					family_pieces,
					origin + Vector2i(gx, gy),
					1,
					layout,
					room,
					rng
				)
	else:
		var piece_list := _runtime_floor_piece_list_for_footprint(family_pieces, footprint_tiles)
		_add_runtime_floor_piece_node(root, piece_list, origin, footprint_tiles, layout, room, rng)
	return root if root.get_child_count() > 0 else null


func _build_runtime_floor_support_region_preview(
	family_pieces: Dictionary,
	origin: Vector2i,
	footprint_tiles: Vector2i,
	layout,
	room: RoomBase
) -> Node3D:
	var root := _build_fallback_runtime_floor_preview(footprint_tiles, layout, room)
	if root == null:
		return null
	root.name = "RuntimeFloorSupport_%s_%s_%s_%s" % [origin.x, origin.y, footprint_tiles.x, footprint_tiles.y]
	var piece_list := _runtime_floor_piece_list_for_footprint(family_pieces, footprint_tiles)
	if not piece_list.is_empty():
		var piece = piece_list[0]
		var material := _runtime_floor_material_with_tiling_for_piece(piece, origin, footprint_tiles)
		if material != null:
			_apply_material_override(root, material)
	var local_position := GridMath.grid_to_local(origin, layout, room)
	var step := GridMath.grid_step(layout, room)
	root.position = Vector3(
		local_position.x + step.x * float(footprint_tiles.x - 1) * 0.5,
		0.0,
		local_position.y + step.y * float(footprint_tiles.y - 1) * 0.5
	)
	return root


func _add_runtime_floor_tile(
	root: Node3D,
	family_pieces: Dictionary,
	origin: Vector2i,
	size: int,
	layout,
	room: RoomBase,
	rng: RandomNumberGenerator
) -> void:
	var key := "small"
	if size >= 3:
		key = "extra_large"
	elif size >= 2:
		key = "large"
	var footprint := Vector2i(size, size)
	var piece_list := family_pieces.get(key, []) as Array
	if piece_list.is_empty() and key != "small":
		for gx in range(origin.x, origin.x + size):
			for gy in range(origin.y, origin.y + size):
				_add_runtime_floor_tile(root, family_pieces, Vector2i(gx, gy), 1, layout, room, rng)
		return
	_add_runtime_floor_piece_node(root, piece_list, origin, footprint, layout, room, rng)


func _runtime_floor_piece_list_for_footprint(family_pieces: Dictionary, footprint_tiles: Vector2i) -> Array:
	var max_dim := maxi(maxi(footprint_tiles.x, footprint_tiles.y), 1)
	var key := "small"
	if max_dim >= 3:
		key = "extra_large"
	elif max_dim >= 2:
		key = "large"
	var piece_list := family_pieces.get(key, []) as Array
	return piece_list if not piece_list.is_empty() else family_pieces.get("small", []) as Array


func _should_render_runtime_floor_region_as_tiles(footprint_tiles: Vector2i) -> bool:
	var width := maxi(footprint_tiles.x, 1)
	var height := maxi(footprint_tiles.y, 1)
	if width == 1 and height == 1:
		return false
	return width != height or width > 3


func _add_runtime_floor_piece_node(
	root: Node3D,
	piece_list: Array,
	anchor: Vector2i,
	footprint_tiles: Vector2i,
	layout,
	room: RoomBase,
	rng: RandomNumberGenerator
) -> void:
	if root == null or piece_list.is_empty():
		return
	var piece = piece_list[rng.randi_range(0, piece_list.size() - 1)]
	if piece == null:
		return
	var instance := _build_runtime_floor_rect_preview(piece, anchor, footprint_tiles, layout, room)
	if instance == null:
		return
	instance.name = "%s_%s_%s" % [String(piece.piece_id), anchor.x, anchor.y]
	root.add_child(instance)


func _runtime_floor_material_with_tiling(material: Material, origin: Vector2i, size: Vector2i) -> Material:
	if material == null:
		return _fallback_material(FLOOR_COLOR)
	if material is BaseMaterial3D:
		var dup := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
		dup.uv1_scale = Vector3(float(maxi(size.x, 1)), 1.0, float(maxi(size.y, 1)))
		dup.uv1_offset = Vector3(float(origin.x), 0.0, float(origin.y))
		return dup
	return material.duplicate()


func _runtime_floor_material_with_tiling_for_piece(piece, origin: Vector2i, size: Vector2i) -> Material:
	var surface_info := _runtime_floor_surface_info_for_piece(piece)
	if not surface_info.is_empty():
		var material := surface_info.get("material", null) as BaseMaterial3D
		if material != null:
			var uv_offset := surface_info.get("uv_offset", Vector2.ZERO) as Vector2
			var uv_scale := surface_info.get("uv_scale", Vector2.ONE) as Vector2
			var dup := material.duplicate() as BaseMaterial3D
			dup.uv1_scale = Vector3(
				float(maxi(size.x, 1)) * maxf(uv_scale.x, 0.0001),
				1.0,
				float(maxi(size.y, 1)) * maxf(uv_scale.y, 0.0001)
			)
			dup.uv1_offset = Vector3(uv_offset.x, 0.0, uv_offset.y)
			return dup
	var runtime_floor_material := _runtime_floor_material_for_piece(piece)
	return _runtime_floor_material_with_tiling(runtime_floor_material, origin, size)


func _build_piece_preview(
	item, piece, layout, room: RoomBase, prefer_top_only_floors := false
) -> Node3D:
	if prefer_top_only_floors and piece != null and piece.category == &"floor":
		var top_only := _build_top_only_floor_preview(piece)
		if top_only != null:
			top_only.name = "%s_%s" % [String(piece.piece_id), item.item_id]
			configure_piece_instance(top_only, item, piece, layout, room)
			return top_only
	var instance = piece.preview_scene.instantiate() as Node3D if piece.preview_scene != null else null
	if instance == null:
		instance = _build_fallback_preview(piece, layout, room, item)
	if instance == null:
		return null
	instance.name = "%s_%s" % [String(piece.piece_id), item.item_id]
	configure_piece_instance(instance, item, piece, layout, room)
	return instance


func _should_render_piece_preview(piece) -> bool:
	if piece == null:
		return false
	if piece.is_connection_marker():
		return false
	if not piece.is_zone_marker():
		return true
	return not _zone_marker_preview_hidden(piece.zone_type)


func _zone_marker_preview_hidden(zone_type: String) -> bool:
	return (
		zone_type == "enemy_spawn"
		or zone_type == "spawn_player"
		or zone_type == "spawn_exit"
		or zone_type == "floor_exit"
	)


func _build_top_only_floor_preview(piece) -> Node3D:
	if piece == null or piece.category != &"floor":
		return null
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	mesh_instance.mesh = plane
	var runtime_floor_material := _runtime_floor_material_for_piece(piece)
	if runtime_floor_material != null:
		mesh_instance.material_override = runtime_floor_material
	else:
		mesh_instance.material_override = _fallback_material(FLOOR_COLOR)
	root.add_child(mesh_instance)
	return root


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
	# Connection markers stretch to footprint so the 3-wide opening reads correctly in preview.
	return piece.is_door_socket() or piece.is_connection_marker()


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
		"wood":
			source_scene = RUNTIME_WOOD_FLOOR_SCENE
		"dark_wood":
			source_scene = RUNTIME_DARK_WOOD_FLOOR_SCENE
		_:
			source_scene = null
	if source_scene == null:
		return null
	var material := _extract_first_surface_material(source_scene)
	if material != null:
		_runtime_floor_material_cache[theme_key] = material
	return material


func _runtime_floor_surface_info_for_piece(piece) -> Dictionary:
	if piece == null or piece.preview_scene == null:
		return {}
	var path_key := String(piece.preview_scene.resource_path)
	if path_key.is_empty():
		return {}
	if _runtime_floor_surface_cache.has(path_key):
		return _runtime_floor_surface_cache[path_key] as Dictionary
	var info := _extract_runtime_floor_surface_info(piece.preview_scene)
	_runtime_floor_surface_cache[path_key] = info
	return info


func _runtime_floor_theme_for_piece(piece) -> String:
	var piece_id := String(piece.piece_id).to_lower()
	if piece_id.contains("foundation"):
		return ""
	if piece_id.contains("wood_small_dark") or piece_id.contains("wood_large_dark"):
		return "dark_wood"
	if piece_id.contains("wood"):
		return "wood"
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


func _extract_runtime_floor_surface_info(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	var root := scene.instantiate() as Node3D
	if root == null:
		return {}
	var material := _extract_first_surface_material(scene)
	if not material is BaseMaterial3D:
		root.free()
		return {}
	var slab_top_y := INF
	var found_slab_top := false
	for mesh_instance in _mesh_instances_in_root(root):
		if mesh_instance.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor(mesh_instance, root)
		var normal_basis := root_to_mesh.basis
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var positions_v: Variant = arrays[Mesh.ARRAY_VERTEX]
			var normals_v: Variant = arrays[Mesh.ARRAY_NORMAL]
			if not positions_v is PackedVector3Array:
				continue
			if not normals_v is PackedVector3Array:
				continue
			var positions := positions_v as PackedVector3Array
			var normals := normals_v as PackedVector3Array
			var count := mini(positions.size(), normals.size())
			for index in range(count):
				var transformed_normal := (normal_basis * normals[index]).normalized()
				if transformed_normal.y < 0.85:
					continue
				var transformed_position := root_to_mesh * positions[index]
				if not found_slab_top or transformed_position.y < slab_top_y:
					slab_top_y = transformed_position.y
					found_slab_top = true
	if not found_slab_top:
		root.free()
		return {}
	var uv_bounds := Rect2()
	var has_uv_bounds := false
	for mesh_instance in _mesh_instances_in_root(root):
		if mesh_instance.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor(mesh_instance, root)
		var normal_basis := root_to_mesh.basis
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var positions: Variant = arrays[Mesh.ARRAY_VERTEX]
			var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			if not positions is PackedVector3Array:
				continue
			if not normals is PackedVector3Array:
				continue
			if not uvs is PackedVector2Array:
				continue
			var packed_positions := positions as PackedVector3Array
			var packed_normals := normals as PackedVector3Array
			var packed_uvs := uvs as PackedVector2Array
			var count := mini(packed_positions.size(), mini(packed_normals.size(), packed_uvs.size()))
			for index in range(count):
				var transformed_normal := (normal_basis * packed_normals[index]).normalized()
				if transformed_normal.y < 0.85:
					continue
				var transformed_position := root_to_mesh * packed_positions[index]
				if absf(transformed_position.y - slab_top_y) > 0.03:
					continue
				var uv := packed_uvs[index]
				if not has_uv_bounds:
					uv_bounds = Rect2(uv, Vector2.ZERO)
					has_uv_bounds = true
				else:
					var min_v := Vector2(
						minf(uv_bounds.position.x, uv.x),
						minf(uv_bounds.position.y, uv.y)
					)
					var max_v := Vector2(
						maxf(uv_bounds.end.x, uv.x),
						maxf(uv_bounds.end.y, uv.y)
					)
					uv_bounds = Rect2(min_v, max_v - min_v)
	root.free()
	if not has_uv_bounds:
		return {}
	var safe_material := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
	return {
		"material": safe_material,
		"uv_offset": uv_bounds.position,
		"uv_scale": uv_bounds.size,
	}


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
	_apply_grid_fit_transform_for_anchor(
		instance,
		item.grid_position,
		GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps()),
		item.normalized_rotation_steps(),
		piece,
		layout,
		room
	)


func _apply_grid_fit_transform_for_anchor(
	instance: Node3D,
	grid_position: Vector2i,
	footprint_tiles: Vector2i,
	rotation_steps: int,
	piece,
	layout,
	room: RoomBase
) -> void:
	var source_bounds := _get_preview_scene_aabb(instance, piece)
	var rotation := Vector3(0.0, -float(rotation_steps) * PI * 0.5, 0.0)
	if source_bounds.size.length_squared() < 1e-8:
		var fallback_position := GridMath.grid_to_local(grid_position, layout, room)
		instance.position = Vector3(fallback_position.x, 0.0, fallback_position.y)
		instance.rotation = rotation
		return
	var step := GridMath.grid_step(layout, room)
	var target_size := Vector2(
		maxf(step.x * float(maxi(footprint_tiles.x, 1)), 0.01),
		maxf(step.y * float(maxi(footprint_tiles.y, 1)), 0.01)
	)
	var sx := target_size.x / maxf(source_bounds.size.x, 0.01)
	var sz := target_size.y / maxf(source_bounds.size.z, 0.01)
	var sy: float
	if piece.is_door_socket() or piece.is_connection_marker():
		# Keep a stable preview height; only stretch width/depth to match footprint.
		sy = WALL_HEIGHT / maxf(source_bounds.size.y, 0.01)
	else:
		sy = minf(sx, sz)
	instance.scale = Vector3(sx, sy, sz)
	instance.rotation = rotation
	var source_center := source_bounds.get_center()
	var top_y := source_bounds.position.y + source_bounds.size.y
	var anchor_local := Vector3(source_center.x * sx, top_y * sy, source_center.z * sz)
	var local_target := GridMath.grid_to_local(grid_position, layout, room)
	var target := Vector3(local_target.x, 0.0, local_target.y)
	var basis := Basis.from_euler(rotation)
	instance.position = target - basis * anchor_local


func _apply_runtime_floor_piece_transform(
	instance: Node3D,
	grid_position: Vector2i,
	footprint_tiles: Vector2i,
	piece,
	layout,
	room: RoomBase,
	scene_override: PackedScene = null
) -> void:
	if instance == null:
		return
	var source_bounds := _get_preview_scene_aabb(instance, piece, scene_override)
	var align_bounds := _runtime_floor_alignment_bounds(piece, source_bounds, footprint_tiles)
	if source_bounds.size.length_squared() < 1e-8:
		var fallback_position := GridMath.grid_to_local(grid_position, layout, room)
		instance.position = Vector3(fallback_position.x, 0.0, fallback_position.y)
		return
	var step := GridMath.grid_step(layout, room)
	var target_size := Vector2(
		maxf(step.x * float(maxi(footprint_tiles.x, 1)), 0.01),
		maxf(step.y * float(maxi(footprint_tiles.y, 1)), 0.01)
	)
	var sx := target_size.x / maxf(align_bounds.size.x, 0.01)
	var sz := target_size.y / maxf(align_bounds.size.z, 0.01)
	var sy := minf(sx, sz)
	instance.scale = Vector3(sx, sy, sz)
	instance.rotation = Vector3.ZERO
	var min_corner_2d := GridMath.grid_to_local(grid_position, layout, room) - step * 0.5
	var target_min_corner := Vector3(min_corner_2d.x, 0.0, min_corner_2d.y)
	var source_anchor := Vector3(
		align_bounds.position.x * sx,
		(source_bounds.position.y + source_bounds.size.y) * sy,
		align_bounds.position.z * sz
	)
	instance.position = target_min_corner - source_anchor


func _runtime_floor_alignment_bounds(piece, source_bounds: AABB, footprint_tiles: Vector2i) -> AABB:
	if source_bounds.size.length_squared() < 1e-8:
		return source_bounds
	var piece_id := String(piece.piece_id).to_lower() if piece != null else ""
	if piece_id.begins_with("floor_dirt_"):
		var canonical_dirt_scene := CANONICAL_DIRT_SMALL_SCENE
		if maxi(footprint_tiles.x, footprint_tiles.y) >= 2:
			canonical_dirt_scene = CANONICAL_DIRT_LARGE_SCENE
		var canonical_dirt_bounds := _get_packed_scene_aabb(canonical_dirt_scene)
		if canonical_dirt_bounds.size.length_squared() > 1e-8:
			return canonical_dirt_bounds
	if piece_id.begins_with("floor_tile_"):
		var canonical_scene := CANONICAL_TILE_SMALL_SCENE
		if maxi(footprint_tiles.x, footprint_tiles.y) >= 2:
			canonical_scene = CANONICAL_TILE_LARGE_SCENE
		var canonical_bounds := _get_packed_scene_aabb(canonical_scene)
		if canonical_bounds.size.length_squared() > 1e-8:
			return canonical_bounds
	return source_bounds


func _runtime_floor_render_scene(piece, footprint_tiles: Vector2i) -> PackedScene:
	if piece == null:
		return null
	var piece_id := String(piece.piece_id).to_lower()
	if piece_id.begins_with("floor_dirt_"):
		return CANONICAL_DIRT_LARGE_SCENE if maxi(footprint_tiles.x, footprint_tiles.y) >= 2 else CANONICAL_DIRT_SMALL_SCENE
	if piece_id.begins_with("floor_tile_"):
		return CANONICAL_TILE_LARGE_SCENE if maxi(footprint_tiles.x, footprint_tiles.y) >= 2 else CANONICAL_TILE_SMALL_SCENE
	return piece.preview_scene


func _build_runtime_floor_detail_overlay(piece) -> Node3D:
	if piece == null or piece.preview_scene == null:
		return null
	var piece_id := String(piece.piece_id).to_lower()
	if not piece_id.begins_with("floor_tile_") and not piece_id.begins_with("floor_dirt_"):
		return null
	var overlay_info := _runtime_floor_detail_overlay_info_for_piece(piece)
	if overlay_info.is_empty():
		return null
	var mesh := overlay_info.get("mesh", null) as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var root := Node3D.new()
	root.name = "%s_DetailOverlay" % String(piece.piece_id)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := overlay_info.get("material", null) as Material
	if material != null:
		mesh_instance.material_override = material
	root.add_child(mesh_instance)
	return root


func _runtime_floor_detail_overlay_info_for_piece(piece) -> Dictionary:
	if piece == null or piece.preview_scene == null:
		return {}
	var scene: PackedScene = piece.preview_scene
	var path_key := String(scene.resource_path)
	if path_key.is_empty():
		return {}
	if _runtime_floor_detail_overlay_cache.has(path_key):
		return _runtime_floor_detail_overlay_cache[path_key] as Dictionary
	var info := _extract_runtime_floor_detail_overlay(piece)
	_runtime_floor_detail_overlay_cache[path_key] = info
	return info


func _extract_runtime_floor_detail_overlay(piece) -> Dictionary:
	if piece == null or piece.preview_scene == null:
		return {}
	var scene: PackedScene = piece.preview_scene
	if scene == null:
		return {}
	var root := scene.instantiate() as Node3D
	if root == null:
		return {}
	var slab_top_y := INF
	var found_slab_top := false
	for mesh_instance in _mesh_instances_in_root(root):
		if mesh_instance.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor(mesh_instance, root)
		var normal_basis := root_to_mesh.basis
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var positions_v: Variant = arrays[Mesh.ARRAY_VERTEX]
			var normals_v: Variant = arrays[Mesh.ARRAY_NORMAL]
			if not positions_v is PackedVector3Array:
				continue
			if not normals_v is PackedVector3Array:
				continue
			var positions := positions_v as PackedVector3Array
			var normals := normals_v as PackedVector3Array
			var count := mini(positions.size(), normals.size())
			for index in range(count):
				var transformed_normal := (normal_basis * normals[index]).normalized()
				if transformed_normal.y < 0.85:
					continue
				var transformed_position := root_to_mesh * positions[index]
				if not found_slab_top or transformed_position.y < slab_top_y:
					slab_top_y = transformed_position.y
					found_slab_top = true
	if not found_slab_top:
		root.free()
		return {}
	var overlay_mesh := ArrayMesh.new()
	var overlay_material: Material = null
	const DETAIL_EPSILON := 0.03
	var detail_min_raise := 0.08
	var piece_id := String(piece.piece_id).to_lower()
	if piece_id.begins_with("floor_tile_"):
		detail_min_raise = 0.14
	for mesh_instance in _mesh_instances_in_root(root):
		if mesh_instance.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor(mesh_instance, root)
		var normal_basis := root_to_mesh.basis
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var positions_v: Variant = arrays[Mesh.ARRAY_VERTEX]
			var normals_v: Variant = arrays[Mesh.ARRAY_NORMAL]
			var uvs_v: Variant = arrays[Mesh.ARRAY_TEX_UV]
			var indices_v: Variant = arrays[Mesh.ARRAY_INDEX]
			if not positions_v is PackedVector3Array:
				continue
			if not normals_v is PackedVector3Array:
				continue
			if not uvs_v is PackedVector2Array:
				continue
			var positions := positions_v as PackedVector3Array
			var normals := normals_v as PackedVector3Array
			var uvs := uvs_v as PackedVector2Array
			var indices := indices_v as PackedInt32Array if indices_v is PackedInt32Array else PackedInt32Array()
			var tri_indices: PackedInt32Array = indices
			if tri_indices.is_empty():
				tri_indices.resize(positions.size())
				for vertex_index in range(positions.size()):
					tri_indices[vertex_index] = vertex_index
			var out_vertices := PackedVector3Array()
			var out_normals := PackedVector3Array()
			var out_uvs := PackedVector2Array()
			var out_indices := PackedInt32Array()
			for tri_start in range(0, tri_indices.size(), 3):
				if tri_start + 2 >= tri_indices.size():
					break
				var ia := tri_indices[tri_start]
				var ib := tri_indices[tri_start + 1]
				var ic := tri_indices[tri_start + 2]
				if ia < 0 or ib < 0 or ic < 0:
					continue
				if ia >= positions.size() or ib >= positions.size() or ic >= positions.size():
					continue
				var pa := root_to_mesh * positions[ia]
				var pb := root_to_mesh * positions[ib]
				var pc := root_to_mesh * positions[ic]
				var min_y := minf(pa.y, minf(pb.y, pc.y))
				var max_y := maxf(pa.y, maxf(pb.y, pc.y))
				if max_y <= slab_top_y + DETAIL_EPSILON:
					continue
				if min_y <= slab_top_y + detail_min_raise:
					continue
				var base_index := out_vertices.size()
				out_vertices.push_back(pa)
				out_vertices.push_back(pb)
				out_vertices.push_back(pc)
				out_normals.push_back((normal_basis * normals[ia]).normalized())
				out_normals.push_back((normal_basis * normals[ib]).normalized())
				out_normals.push_back((normal_basis * normals[ic]).normalized())
				out_uvs.push_back(uvs[ia] if ia < uvs.size() else Vector2.ZERO)
				out_uvs.push_back(uvs[ib] if ib < uvs.size() else Vector2.ZERO)
				out_uvs.push_back(uvs[ic] if ic < uvs.size() else Vector2.ZERO)
				out_indices.push_back(base_index)
				out_indices.push_back(base_index + 1)
				out_indices.push_back(base_index + 2)
			if out_vertices.is_empty():
				continue
			var surface_arrays := []
			surface_arrays.resize(Mesh.ARRAY_MAX)
			surface_arrays[Mesh.ARRAY_VERTEX] = out_vertices
			surface_arrays[Mesh.ARRAY_NORMAL] = out_normals
			surface_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
			surface_arrays[Mesh.ARRAY_INDEX] = out_indices
			overlay_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
			var source_material := mesh_instance.get_active_material(surface_index)
			if source_material != null:
				overlay_mesh.surface_set_material(overlay_mesh.get_surface_count() - 1, source_material)
				if overlay_material == null:
					overlay_material = source_material
	root.free()
	if overlay_mesh.get_surface_count() == 0:
		return {}
	return {
		"mesh": overlay_mesh,
		"material": overlay_material,
	}


func _get_packed_scene_aabb(scene: PackedScene) -> AABB:
	if scene == null:
		return AABB()
	var path_key := String(scene.resource_path)
	if not path_key.is_empty() and _preview_aabb_by_scene_path.has(path_key):
		return _preview_aabb_by_scene_path[path_key] as AABB
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return AABB()
	var computed := _merged_mesh_aabb_in_root(instance)
	instance.free()
	if not path_key.is_empty():
		_preview_aabb_by_scene_path[path_key] = computed
	return computed


func _get_preview_scene_aabb(instance: Node3D, piece, scene_override: PackedScene = null) -> AABB:
	var effective_scene := scene_override
	if effective_scene == null and piece != null:
		effective_scene = piece.preview_scene
	if effective_scene == null:
		return _merged_mesh_aabb_in_root(instance)
	var path_key: String = effective_scene.resource_path
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
