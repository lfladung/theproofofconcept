@tool
extends RefCounted
class_name DungeonRoomSerializer

const LayoutScript = preload("res://addons/dungeon_room_editor/resources/room_layout_data.gd")
const ItemScript = preload("res://addons/dungeon_room_editor/resources/room_placed_item_data.gd")


func layout_path_for_scene(scene_path: String) -> String:
	if scene_path.is_empty():
		return ""
	return "%s.layout.tres" % [scene_path.get_basename()]


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
	if not layout_path.is_empty() and (layout.resource_path.is_empty() or not ResourceLoader.exists(layout_path)):
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
	return ResourceSaver.save(layout, path) == OK


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
