@tool
extends RefCounted
class_name DungeonRoomSerializer

const LayoutScript = preload("res://addons/dungeon_room_editor/resources/room_layout_data.gd")
const ItemScript = preload("res://addons/dungeon_room_editor/resources/room_placed_item_data.gd")
const _RUNTIME_FLOOR_MASK_SMALL: StringName = &"floor_mask_small"
const _RUNTIME_FLOOR_MASK_LARGE: StringName = &"floor_mask_large"
const _RUNTIME_FLOOR_MASK_EXTRA_LARGE: StringName = &"floor_mask_extra_large"
const _LEGACY_GENERIC_FLOOR_PREFIXES := ["floor_dirt_", "floor_tile_", "floor_wood_"]
const _LEGACY_GENERIC_FLOOR_EXCLUDES := ["corner", "spike", "foundation", "grate"]

## Sidecar layouts live next to the room scene under `layouts/<scene_basename>.layout.tres`.
## Legacy sibling `/<basename>.layout.tres` is still loaded if present.
const _LAYOUT_SUBDIR := "layouts"


func layout_path_for_scene(scene_path: String) -> String:
	if scene_path.is_empty():
		return ""
	var base_dir := scene_path.get_base_dir()
	var stem := scene_path.get_basename().get_file()
	var nested := "%s/%s/%s.layout.tres" % [base_dir, _LAYOUT_SUBDIR, stem]
	if ResourceLoader.exists(nested):
		return nested
	var legacy := "%s/%s.layout.tres" % [base_dir, stem]
	if ResourceLoader.exists(legacy):
		return legacy
	return nested


func ensure_layout_for_room(room: RoomBase) -> Dictionary:
	var scene_path := room.scene_file_path
	var layout_path := layout_path_for_scene(scene_path)
	var layout = room.get(&"authored_layout")
	var original_tile_size: Vector2i = room.tile_size
	var original_room_size_tiles: Vector2i = room.room_size_tiles
	if layout == null and not layout_path.is_empty() and ResourceLoader.exists(layout_path):
		layout = ResourceLoader.load(layout_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if layout == null:
		layout = LayoutScript.new()
		layout.room_id = room.room_id if room.room_id != "" else room.name
		layout.room_tags = room.room_tags.duplicate()
		layout.recommended_enemy_groups = []
		layout.grid_size = Vector2i(3, 3)
	elif layout.grid_size == Vector2i.ZERO:
		layout.grid_size = Vector2i(3, 3)
	if layout.room_id == "":
		layout.room_id = room.room_id if room.room_id != "" else room.name
	if layout.room_tags.is_empty() and not room.room_tags.is_empty():
		layout.room_tags = room.room_tags.duplicate()
	var migrated_layout := _migrate_legacy_runtime_floor_items(layout)
	var normalized_masks := _normalize_runtime_floor_masks(layout)
	room.set(&"authored_layout", layout)
	room.room_id = layout.room_id
	room.room_tags = layout.room_tags.duplicate()
	if original_tile_size == Vector2i.ZERO:
		room.tile_size = layout.grid_size
	elif original_tile_size != layout.grid_size:
		var world_width := maxi(original_tile_size.x * maxi(original_room_size_tiles.x, 1), layout.grid_size.x)
		var world_height := maxi(original_tile_size.y * maxi(original_room_size_tiles.y, 1), layout.grid_size.y)
		room.room_size_tiles = Vector2i(
			maxi(1, roundi(float(world_width) / float(layout.grid_size.x))),
			maxi(1, roundi(float(world_height) / float(layout.grid_size.y)))
		)
		room.tile_size = layout.grid_size
	if (migrated_layout or normalized_masks) and not layout_path.is_empty():
		_ensure_directory_for_file(layout_path)
		ResourceSaver.save(layout, layout_path)
	elif not layout_path.is_empty() and (layout.resource_path.is_empty() or not ResourceLoader.exists(layout_path)):
		_ensure_directory_for_file(layout_path)
		ResourceSaver.save(layout, layout_path)
	return {"layout": layout, "layout_path": layout_path}


func save_layout(room: RoomBase, layout, target_path: String = "") -> bool:
	if layout == null:
		return false
	var path := target_path
	if path.is_empty():
		path = layout.resource_path
	if path.is_empty() and room != null:
		path = layout_path_for_scene(room.scene_file_path)
	if path.is_empty():
		return false
	_ensure_directory_for_file(path)
	return ResourceSaver.save(layout, path) == OK


func _ensure_directory_for_file(resource_path: String) -> void:
	if resource_path.is_empty() or not resource_path.begins_with("res://"):
		return
	var abs_path := ProjectSettings.globalize_path(resource_path.get_base_dir())
	var err := DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("DungeonRoomSerializer: could not create directory %s (err %s)" % [abs_path, err])


func _migrate_legacy_runtime_floor_items(layout) -> bool:
	if layout == null:
		return false
	var changed := false
	for item in layout.items:
		if item == null:
			continue
		if item.category != &"floor":
			continue
		if not _is_legacy_generic_floor_piece_id(String(item.piece_id)):
			continue
		if item.piece_id != _RUNTIME_FLOOR_MASK_SMALL:
			item.piece_id = _RUNTIME_FLOOR_MASK_SMALL
			changed = true
		item.category = &"floor"
	return changed


func _normalize_runtime_floor_masks(layout) -> bool:
	if layout == null:
		return false
	var runtime_mask_items: Array = []
	var has_explicit_large_masks := false
	for item in layout.items:
		if item == null or item.category != &"floor":
			continue
		var piece_id := StringName(item.piece_id)
		if piece_id == _RUNTIME_FLOOR_MASK_LARGE or piece_id == _RUNTIME_FLOOR_MASK_EXTRA_LARGE:
			has_explicit_large_masks = true
		if piece_id == _RUNTIME_FLOOR_MASK_SMALL or piece_id == _RUNTIME_FLOOR_MASK_LARGE or piece_id == _RUNTIME_FLOOR_MASK_EXTRA_LARGE:
			runtime_mask_items.append(item)
	if runtime_mask_items.is_empty() or has_explicit_large_masks:
		return false
	var occupied_small_cells: Dictionary = {}
	for item_v in runtime_mask_items:
		var item = item_v
		if item == null:
			continue
		occupied_small_cells[item.grid_position] = true
	if occupied_small_cells.is_empty():
		return false
	var retained_items: Array[Resource] = []
	for item in layout.items:
		if item == null:
			continue
		var piece_id := StringName(item.piece_id)
		if piece_id == _RUNTIME_FLOOR_MASK_SMALL or piece_id == _RUNTIME_FLOOR_MASK_LARGE or piece_id == _RUNTIME_FLOOR_MASK_EXTRA_LARGE:
			continue
		retained_items.append(item)
	var rebuilt_masks := _repack_runtime_floor_mask_cells(occupied_small_cells)
	retained_items.append_array(rebuilt_masks)
	layout.items = retained_items
	return true


func _repack_runtime_floor_mask_cells(occupied_small_cells: Dictionary) -> Array[Resource]:
	var remaining: Dictionary = occupied_small_cells.duplicate(true)
	var rebuilt: Array[Resource] = []
	var counter := 1
	while not remaining.is_empty():
		var origin := _top_left_cell_in_keys(remaining.keys())
		var size := 1
		if _runtime_floor_mask_region_fits(origin, 3, remaining):
			size = 3
		elif _runtime_floor_mask_region_fits(origin, 2, remaining):
			size = 2
		var piece_id := _RUNTIME_FLOOR_MASK_SMALL
		if size == 2:
			piece_id = _RUNTIME_FLOOR_MASK_LARGE
		elif size == 3:
			piece_id = _RUNTIME_FLOOR_MASK_EXTRA_LARGE
		rebuilt.append(_make_runtime_floor_mask_item(piece_id, origin, counter))
		counter += 1
		for gx in range(origin.x, origin.x + size):
			for gy in range(origin.y, origin.y + size):
				remaining.erase(Vector2i(gx, gy))
	return rebuilt


func _runtime_floor_mask_region_fits(origin: Vector2i, size: int, remaining: Dictionary) -> bool:
	for gx in range(origin.x, origin.x + size):
		for gy in range(origin.y, origin.y + size):
			if not remaining.has(Vector2i(gx, gy)):
				return false
	return true


func _top_left_cell_in_keys(keys: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var found := false
	for key_v in keys:
		if key_v is not Vector2i:
			continue
		var cell := key_v as Vector2i
		if not found or cell.y < best.y or (cell.y == best.y and cell.x < best.x):
			best = cell
			found = true
	return best


func _make_runtime_floor_mask_item(piece_id: StringName, grid_position: Vector2i, counter: int):
	var item = ItemScript.new()
	item.item_id = "%s_%03d" % [String(piece_id), counter]
	item.piece_id = piece_id
	item.category = &"floor"
	item.grid_position = grid_position
	item.rotation_steps = 0
	item.tags = PackedStringArray(["floor", "runtime_mask"])
	item.encounter_group_id = &""
	item.enemy_id = &""
	item.placement_layer = &"ground"
	item.blocks_movement = false
	item.blocks_projectiles = false
	return item


func _is_legacy_generic_floor_piece_id(piece_id: String) -> bool:
	var normalized := piece_id.to_lower()
	if normalized.begins_with("floor_mask_"):
		return false
	for excluded in _LEGACY_GENERIC_FLOOR_EXCLUDES:
		if normalized.contains(excluded):
			return false
	for prefix in _LEGACY_GENERIC_FLOOR_PREFIXES:
		if normalized.begins_with(prefix):
			return true
	return false


func export_layout_json(layout, path: String) -> bool:
	if layout == null or path.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(layout_to_dictionary(layout), "\t"))
	return true


func import_layout_json(path: String):
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed := JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return null
	return dictionary_to_layout(parsed as Dictionary)


func layout_to_dictionary(layout) -> Dictionary:
	var items: Array[Dictionary] = []
	for item in layout.items:
		if item == null:
			continue
		items.append(
			{
				"item_id": item.item_id,
				"piece_id": String(item.piece_id),
				"category": String(item.category),
				"grid_position": {"x": item.grid_position.x, "y": item.grid_position.y},
				"rotation_steps": item.normalized_rotation_steps(),
				"tags": item.tags,
				"encounter_group_id": String(item.encounter_group_id),
				"enemy_id": String(item.enemy_id),
				"placement_layer": String(item.resolved_placement_layer()),
				"blocks_movement": item.blocks_movement,
				"blocks_projectiles": item.blocks_projectiles,
			}
		)
	return {
		"room_id": layout.room_id,
		"room_tags": layout.room_tags,
		"recommended_enemy_groups": layout.recommended_enemy_groups,
		"grid_size": {"x": layout.grid_size.x, "y": layout.grid_size.y},
		"items": items,
	}


func dictionary_to_layout(data: Dictionary):
	var layout = LayoutScript.new()
	layout.room_id = String(data.get("room_id", ""))
	layout.room_tags = PackedStringArray(data.get("room_tags", PackedStringArray()))
	layout.recommended_enemy_groups = PackedStringArray(
		data.get("recommended_enemy_groups", PackedStringArray())
	)
	var grid_size_data := data.get("grid_size", {}) as Dictionary
	layout.grid_size = Vector2i(
		int(grid_size_data.get("x", 3)),
		int(grid_size_data.get("y", 3))
	)
	for raw_item in data.get("items", []) as Array:
		if raw_item is not Dictionary:
			continue
		var item_data := raw_item as Dictionary
		var item = ItemScript.new()
		item.item_id = String(item_data.get("item_id", ""))
		item.piece_id = StringName(String(item_data.get("piece_id", "")))
		item.category = StringName(String(item_data.get("category", "")))
		var grid_data := item_data.get("grid_position", {}) as Dictionary
		item.grid_position = Vector2i(int(grid_data.get("x", 0)), int(grid_data.get("y", 0)))
		item.rotation_steps = posmod(int(item_data.get("rotation_steps", 0)), 4)
		item.tags = PackedStringArray(item_data.get("tags", PackedStringArray()))
		item.encounter_group_id = StringName(String(item_data.get("encounter_group_id", "")))
		item.enemy_id = StringName(String(item_data.get("enemy_id", "")))
		item.placement_layer = StringName(String(item_data.get("placement_layer", "")))
		item.blocks_movement = bool(item_data.get("blocks_movement", false))
		item.blocks_projectiles = bool(item_data.get("blocks_projectiles", false))
		layout.items.append(item)
	return layout
