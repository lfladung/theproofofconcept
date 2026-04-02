extends RefCounted
class_name AuthoredRoomCatalog

const AuthoredRoomDataScript = preload("res://dungeon/game/floor_generation/authored_room_data.gd")
const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const PIECE_CATALOG = preload("res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres")

const _SPAWN_ROOM_PATH := "res://dungeon/rooms/authored/spawn_room.tscn"
const _V3_ROOM_DIR := "res://dungeon/rooms/authored/outlines/v3"

var _rooms: Array = []
var _rooms_by_role := {}


func build() -> void:
	_rooms.clear()
	_rooms_by_role.clear()
	var scene_paths: Array[String] = [_SPAWN_ROOM_PATH]
	for file_name in DirAccess.get_files_at(_V3_ROOM_DIR):
		if not String(file_name).ends_with(".tscn"):
			continue
		scene_paths.append("%s/%s" % [_V3_ROOM_DIR, file_name])
	scene_paths.sort()
	for scene_path in scene_paths:
		var room_data: RefCounted = _build_room_data(scene_path)
		if room_data == null:
			continue
		_rooms.append(room_data)
		if not _rooms_by_role.has(room_data.role):
			_rooms_by_role[room_data.role] = []
		var role_rooms: Array = _rooms_by_role[room_data.role] as Array
		role_rooms.append(room_data)
		_rooms_by_role[room_data.role] = role_rooms


func all_rooms() -> Array:
	return _rooms.duplicate()


func rooms_for_role(role: String) -> Array:
	var raw: Array = _rooms_by_role.get(role, []) as Array
	return raw.duplicate()


func _build_room_data(scene_path: String):
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("AuthoredRoomCatalog could not load scene: %s" % scene_path)
		return null
	var room := packed.instantiate() as RoomBase
	if room == null:
		push_warning("AuthoredRoomCatalog scene is not a RoomBase: %s" % scene_path)
		return null
	var layout = room.authored_layout
	if layout == null:
		room.free()
		push_warning("AuthoredRoomCatalog missing authored_layout on %s" % scene_path)
		return null

	var room_data = AuthoredRoomDataScript.new()
	room_data.scene_path = scene_path
	room_data.room_id = String(room.room_id)
	room_data.role = _derive_role(scene_path, room)
	room_data.room_type = String(room.room_type)
	room_data.room_tags = room.room_tags.duplicate()
	room_data.tile_size = room.tile_size
	room_data.room_size_tiles = room.room_size_tiles
	room_data.allowed_rotations = room.allowed_rotations.duplicate()

	var occupied_seen := {}
	var walkable_seen := {}
	var connection_markers: Array[Dictionary] = []
	var spawn_markers: Array[Dictionary] = []
	var zone_markers: Array[Dictionary] = []
	var floor_exit_marker := {}
	var items: Array = layout.items if layout != null else []
	for item_value in items:
		if item_value == null:
			continue
		var piece = PIECE_CATALOG.find_piece(item_value.piece_id)
		if piece == null:
			continue
		_collect_piece_cells(item_value, piece, room, occupied_seen, walkable_seen)
		if piece.is_connection_marker():
			connection_markers.append(_connection_marker_from_item(item_value, piece, room))
		elif piece.is_zone_marker():
			var zone_marker := _zone_marker_from_item(item_value, piece, room)
			zone_markers.append(zone_marker)
			var zone_type := String(zone_marker.get("zone_type", ""))
			if zone_type == "spawn_player":
				spawn_markers.append(zone_marker)
			elif zone_type == "floor_exit":
				floor_exit_marker = zone_marker

	connection_markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("item_id", "")) < String(b.get("item_id", ""))
	)
	spawn_markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("item_id", "")) < String(b.get("item_id", ""))
	)
	zone_markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("item_id", "")) < String(b.get("item_id", ""))
	)

	room_data.connection_markers = connection_markers
	room_data.spawn_markers = spawn_markers
	room_data.floor_exit_marker = floor_exit_marker
	room_data.zone_markers = zone_markers
	room_data.occupied_cells = _sorted_cells_from_lookup(occupied_seen)
	room_data.walkable_cells = _sorted_cells_from_lookup(walkable_seen)
	room.free()
	return room_data


func _derive_role(scene_path: String, room: RoomBase) -> String:
	if scene_path == _SPAWN_ROOM_PATH:
		return "spawn"
	if room.room_type == "boss":
		return "boss"
	if room.room_tags.has("chokepoint"):
		return "chokepoint"
	if room.room_type == "connector" or room.room_type == "corridor":
		return "connector"
	if room.room_type == "arena":
		return "combat"
	return "connector"


func _collect_piece_cells(
	item,
	piece,
	_room: RoomBase,
	occupied_seen: Dictionary,
	walkable_seen: Dictionary
) -> void:
	var footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	var placement_layer := String(item.resolved_placement_layer(piece))
	var is_ground := placement_layer == "ground"
	var blocks := bool(item.blocks_movement) or bool(piece.blocks_movement) or String(piece.category) == "wall"
	for x in range(footprint.x):
		for y in range(footprint.y):
			var cell: Vector2i = item.grid_position + Vector2i(x, y)
			var key := _cell_key(cell)
			if is_ground:
				occupied_seen[key] = cell
				walkable_seen[key] = cell
			elif blocks:
				occupied_seen[key] = cell


func _connection_marker_from_item(item, piece, room: RoomBase) -> Dictionary:
	var footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	var local_cell: Vector2i = item.grid_position + Vector2i(
		(footprint.x - 1) / 2,
		(footprint.y - 1) / 2
	)
	var local_position := Vector2(local_cell * room.tile_size)
	var local_cells: Array[Vector2i] = []
	for x in range(footprint.x):
		for y in range(footprint.y):
			local_cells.append(item.grid_position + Vector2i(x, y))
	return {
		"item_id": String(item.item_id),
		"piece_id": String(piece.piece_id),
		"marker_kind": String(piece.marker_kind),
		"direction": GridMath.direction_from_rotation(item.normalized_rotation_steps()),
		"width_tiles": int(piece.marker_width_tiles),
		"connector_type": String(piece.connector_type),
		"allow_room_rotation": true,
		"local_cell": local_cell,
		"local_cells": local_cells,
		"local_position": local_position,
	}


func _zone_marker_from_item(item, piece, room: RoomBase) -> Dictionary:
	var footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	var center_offset := Vector2(
		float(footprint.x - 1) * float(room.tile_size.x) * 0.5,
		float(footprint.y - 1) * float(room.tile_size.y) * 0.5
	)
	var local_position := Vector2(item.grid_position * room.tile_size) + center_offset
	var local_cell: Vector2i = item.grid_position + Vector2i(
		int((footprint.x - 1) / 2),
		int((footprint.y - 1) / 2)
	)
	return {
		"item_id": String(item.item_id),
		"piece_id": String(piece.piece_id),
		"zone_type": String(piece.zone_type),
		"zone_role": piece.zone_role,
		"enemy_id": item.resolved_enemy_id(piece),
		"tags": item.tags.duplicate(),
		"local_cell": local_cell,
		"local_position": local_position,
	}


func _sorted_cells_from_lookup(lookup: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for value in lookup.values():
		if value is Vector2i:
			cells.append(value as Vector2i)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	return cells


func _cell_key(cell: Vector2i) -> String:
	return "%s,%s" % [cell.x, cell.y]
