extends Panel
class_name MinimapPanel

const MAP_PADDING := 14.0
const WORLD_BOUNDS_PADDING := 3.0
const ROOM_OUTLINE_WIDTH := 2.0
const ROOM_SEPARATOR_WIDTH := 2.0
const PLAYER_MARKER_RADIUS := 4.5
const PLAYER_MARKER_OUTLINE := 2.0
const ROOM_OUTLINE_COLOR := Color(0.21, 0.16, 0.11, 0.95)
const CURRENT_ROOM_TINT := Color(1.0, 0.97, 0.88, 1.0)
const PLAYER_MARKER_FILL := Color(0.98, 0.95, 0.88, 1.0)
const PLAYER_MARKER_BORDER := Color(0.11, 0.09, 0.07, 1.0)
const DEFAULT_ROOM_COLOR := Color(0.48, 0.46, 0.43, 0.84)
const ROOM_COLORS := {
	"spawn": Color(0.42, 0.62, 0.47, 0.9),
	"safe": Color(0.42, 0.62, 0.47, 0.86),
	"connector": Color(0.56, 0.53, 0.47, 0.84),
	"combat": Color(0.72, 0.43, 0.28, 0.9),
	"chokepoint": Color(0.67, 0.47, 0.23, 0.9),
	"arena": Color(0.72, 0.43, 0.28, 0.88),
	"puzzle": Color(0.33, 0.54, 0.67, 0.88),
	"treasure": Color(0.83, 0.69, 0.27, 0.9),
	"boss": Color(0.77, 0.24, 0.2, 0.9),
	"trap": Color(0.8, 0.48, 0.18, 0.9),
}
const PLAYER_REDRAW_MOVE_THRESHOLD := 0.75

var rooms_root: Node2D
var tracked_player: CharacterBody2D
var _observed_rooms_root: Node2D
var _rooms_dirty := true
var _cached_rooms: Array[Dictionary] = []
var _cached_world_bounds := Rect2()
var _redraw_requested := true
var _last_player_world_pos := Vector2.INF
@export var minimap_player_redraw_interval := 0.08
var _player_redraw_time_remaining := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func bind_rooms_root(root: Node2D) -> void:
	_disconnect_rooms_root(_observed_rooms_root)
	rooms_root = root
	_observed_rooms_root = root
	_connect_rooms_root(_observed_rooms_root)
	_rooms_dirty = true
	_request_redraw()


func bind_player(player: CharacterBody2D) -> void:
	tracked_player = player
	_last_player_world_pos = Vector2.INF
	_request_redraw()


func refresh() -> void:
	_rooms_dirty = true
	_request_redraw()


func _exit_tree() -> void:
	_disconnect_rooms_root(_observed_rooms_root)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_request_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_player_redraw_time_remaining = maxf(0.0, _player_redraw_time_remaining - delta)
	if _rooms_dirty:
		_request_redraw()
		return
	if tracked_player == null or not is_instance_valid(tracked_player):
		if _redraw_requested:
			queue_redraw()
			_redraw_requested = false
		return
	if _player_redraw_time_remaining > 0.0:
		return
	var player_world_pos := tracked_player.global_position
	if _last_player_world_pos == Vector2.INF:
		_last_player_world_pos = player_world_pos
		_request_redraw()
		return
	if player_world_pos.distance_squared_to(_last_player_world_pos) < (
		PLAYER_REDRAW_MOVE_THRESHOLD * PLAYER_REDRAW_MOVE_THRESHOLD
	) and not _redraw_requested:
		return
	_last_player_world_pos = player_world_pos
	_request_redraw()


func _draw() -> void:
	var content_rect := Rect2(
		Vector2(MAP_PADDING, MAP_PADDING),
		size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	)
	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		return
	_ensure_room_cache()
	if _cached_rooms.is_empty():
		return
	if _cached_world_bounds.size.x <= 0.0 or _cached_world_bounds.size.y <= 0.0:
		return
	var draw_scale := minf(
		content_rect.size.x / maxf(_cached_world_bounds.size.x, 1.0),
		content_rect.size.y / maxf(_cached_world_bounds.size.y, 1.0)
	)
	var used_size := _cached_world_bounds.size * draw_scale
	var draw_origin := content_rect.position + (content_rect.size - used_size) * 0.5

	var player_world_pos := Vector2.ZERO
	var has_player := tracked_player != null and is_instance_valid(tracked_player)
	if has_player:
		player_world_pos = tracked_player.global_position

	for room_entry in _cached_rooms:
		var fill_color := room_entry.get("color", DEFAULT_ROOM_COLOR) as Color
		if has_player and _room_entry_contains_world_point(room_entry, player_world_pos):
			fill_color = fill_color.lerp(CURRENT_ROOM_TINT, 0.35)
		var cells = room_entry.get("cells", []) as Array
		if not cells.is_empty():
			var tile_size := room_entry.get("tile_size", Vector2i(3, 3)) as Vector2i
			for cell_value in cells:
				if cell_value is not Vector2i:
					continue
				var world_rect := _world_cell_rect(cell_value as Vector2i, tile_size)
				var draw_rect_local := _map_world_rect_to_draw_rect(
					world_rect,
					_cached_world_bounds,
					draw_origin,
					draw_scale
				)
				draw_rect(draw_rect_local, fill_color, true)
				draw_rect(draw_rect_local, ROOM_OUTLINE_COLOR, false, ROOM_OUTLINE_WIDTH)
			continue
		var world_rect := room_entry.get("rect", Rect2()) as Rect2
		var draw_rect_local := _map_world_rect_to_draw_rect(
			world_rect,
			_cached_world_bounds,
			draw_origin,
			draw_scale
		)
		draw_rect(draw_rect_local, fill_color, true)
		draw_rect(draw_rect_local, ROOM_OUTLINE_COLOR, false, ROOM_OUTLINE_WIDTH)

	_draw_room_separators(_cached_rooms, _cached_world_bounds, draw_origin, draw_scale)

	if has_player:
		var marker_pos := _map_world_point_to_draw_point(
			player_world_pos,
			_cached_world_bounds,
			draw_origin,
			draw_scale
		)
		marker_pos.x = clampf(
			marker_pos.x,
			content_rect.position.x + PLAYER_MARKER_RADIUS,
			content_rect.end.x - PLAYER_MARKER_RADIUS
		)
		marker_pos.y = clampf(
			marker_pos.y,
			content_rect.position.y + PLAYER_MARKER_RADIUS,
			content_rect.end.y - PLAYER_MARKER_RADIUS
		)
		draw_circle(marker_pos, PLAYER_MARKER_RADIUS + PLAYER_MARKER_OUTLINE, PLAYER_MARKER_BORDER)
		draw_circle(marker_pos, PLAYER_MARKER_RADIUS, PLAYER_MARKER_FILL)
	_last_player_world_pos = player_world_pos
	_player_redraw_time_remaining = minimap_player_redraw_interval
	_redraw_requested = false


func _collect_rooms() -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	if rooms_root == null:
		return rooms
	for child in rooms_root.get_children():
		if child is not RoomBase:
			continue
		var room := child as RoomBase
		var authored_cells := _authored_cells(room)
		var role := _room_role(room)
		if not authored_cells.is_empty():
			var tile_size := _room_tile_size(room)
			rooms.append(
				{
					"name": String(room.name),
					"cells": authored_cells,
					"tile_size": tile_size,
					"rect": _rect_from_cells(authored_cells, tile_size),
					"color": _color_for_room_role(role, room.room_type),
				}
			)
			continue
		var local_rect := room.get_room_rect_world()
		var world_rect := Rect2(room.global_position - local_rect.size * 0.5, local_rect.size)
		rooms.append(
			{
				"name": String(room.name),
				"rect": world_rect,
				"color": _color_for_room_role(role, room.room_type),
			}
		)
	return rooms


func _combined_world_bounds(rooms: Array[Dictionary]) -> Rect2:
	if rooms.is_empty():
		return Rect2()
	var bounds := rooms[0].get("rect", Rect2()) as Rect2
	for i in range(1, rooms.size()):
		bounds = bounds.merge(rooms[i].get("rect", Rect2()) as Rect2)
	return bounds.grow(WORLD_BOUNDS_PADDING)


func _map_world_point_to_draw_point(
	world_point: Vector2,
	world_bounds: Rect2,
	draw_origin: Vector2,
	draw_scale: float
) -> Vector2:
	var mirrored := world_bounds.end - world_point
	return draw_origin + mirrored * draw_scale


func _map_world_rect_to_draw_rect(
	world_rect: Rect2,
	world_bounds: Rect2,
	draw_origin: Vector2,
	draw_scale: float
) -> Rect2:
	var p0 := _map_world_point_to_draw_point(world_rect.position, world_bounds, draw_origin, draw_scale)
	var p1 := _map_world_point_to_draw_point(world_rect.end, world_bounds, draw_origin, draw_scale)
	var top_left := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var draw_size := Vector2(absf(p1.x - p0.x), absf(p1.y - p0.y))
	return Rect2(top_left, draw_size)


func _color_for_room_role(role: String, room_type: String) -> Color:
	if ROOM_COLORS.has(role):
		return ROOM_COLORS[role] as Color
	if ROOM_COLORS.has(room_type):
		return ROOM_COLORS[room_type] as Color
	return DEFAULT_ROOM_COLOR


func _room_role(room: RoomBase) -> String:
	if room != null and room.has_meta(&"authored_room_role"):
		return String(room.get_meta(&"authored_room_role"))
	return String(room.room_type)


func _authored_cells(room: RoomBase) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if room == null or not room.has_meta(&"authored_room_occupied_cells_world"):
		return cells
	var raw_cells = room.get_meta(&"authored_room_occupied_cells_world")
	if raw_cells is Array:
		for value in raw_cells:
			if value is Vector2i:
				cells.append(value as Vector2i)
	return cells


func _room_tile_size(room: RoomBase) -> Vector2i:
	if room != null and room.has_meta(&"authored_room_tile_size"):
		var meta_value = room.get_meta(&"authored_room_tile_size")
		if meta_value is Vector2i:
			return meta_value as Vector2i
	return room.tile_size if room != null else Vector2i.ONE


func _rect_from_cells(cells: Array[Vector2i], tile_size: Vector2i) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var bounds := _world_cell_rect(cells[0], tile_size)
	for i in range(1, cells.size()):
		bounds = bounds.merge(_world_cell_rect(cells[i], tile_size))
	return bounds


func _world_cell_rect(cell: Vector2i, tile_size: Vector2i) -> Rect2:
	var center := Vector2(cell * tile_size)
	return Rect2(center - Vector2(tile_size) * 0.5, Vector2(tile_size))


func _room_entry_contains_world_point(room_entry: Dictionary, world_pos: Vector2) -> bool:
	var cells = room_entry.get("cells", []) as Array
	if not cells.is_empty():
		var tile_size := room_entry.get("tile_size", Vector2i(3, 3)) as Vector2i
		for cell_value in cells:
			if cell_value is not Vector2i:
				continue
			if _world_cell_rect(cell_value as Vector2i, tile_size).has_point(world_pos):
				return true
		return false
	var world_rect := room_entry.get("rect", Rect2()) as Rect2
	return world_rect.has_point(world_pos)


func _draw_room_separators(
	rooms: Array[Dictionary],
	world_bounds: Rect2,
	draw_origin: Vector2,
	draw_scale: float
) -> void:
	var owner_by_cell: Dictionary = {}
	var tile_size_by_room: Dictionary = {}
	for room_entry in rooms:
		var room_name := String(room_entry.get("name", ""))
		var tile_size := room_entry.get("tile_size", Vector2i(3, 3)) as Vector2i
		tile_size_by_room[room_name] = tile_size
		for cell_value in room_entry.get("cells", []) as Array:
			if cell_value is Vector2i:
				owner_by_cell[cell_value as Vector2i] = room_name

	if owner_by_cell.is_empty():
		return

	var separator_width := maxf(ROOM_SEPARATOR_WIDTH, ROOM_OUTLINE_WIDTH)
	var cardinal_steps := [
		Vector2i.RIGHT,
		Vector2i.DOWN,
	]
	for cell_value in owner_by_cell.keys():
		if cell_value is not Vector2i:
			continue
		var cell := cell_value as Vector2i
		var owner := String(owner_by_cell[cell])
		var tile_size := tile_size_by_room.get(owner, Vector2i.ONE) as Vector2i
		for step in cardinal_steps:
			var neighbor: Vector2i = cell + step
			if not owner_by_cell.has(neighbor):
				continue
			var neighbor_owner := String(owner_by_cell[neighbor])
			if neighbor_owner == owner:
				continue
			var cell_rect := _world_cell_rect(cell, tile_size)
			var from_world := Vector2.ZERO
			var to_world := Vector2.ZERO
			if step == Vector2i.RIGHT:
				from_world = Vector2(cell_rect.end.x, cell_rect.position.y)
				to_world = Vector2(cell_rect.end.x, cell_rect.end.y)
			else:
				from_world = Vector2(cell_rect.position.x, cell_rect.end.y)
				to_world = Vector2(cell_rect.end.x, cell_rect.end.y)
			var from_draw := _map_world_point_to_draw_point(
				from_world,
				world_bounds,
				draw_origin,
				draw_scale
			)
			var to_draw := _map_world_point_to_draw_point(
				to_world,
				world_bounds,
				draw_origin,
				draw_scale
			)
			draw_line(from_draw, to_draw, ROOM_OUTLINE_COLOR, separator_width, true)


func _ensure_room_cache() -> void:
	if not _rooms_dirty:
		return
	_cached_rooms = _collect_rooms()
	_cached_world_bounds = _combined_world_bounds(_cached_rooms)
	_rooms_dirty = false


func _request_redraw() -> void:
	_redraw_requested = true
	queue_redraw()


func _connect_rooms_root(root: Node2D) -> void:
	if root == null:
		return
	if not root.child_entered_tree.is_connected(_on_rooms_root_tree_changed):
		root.child_entered_tree.connect(_on_rooms_root_tree_changed)
	if not root.child_exiting_tree.is_connected(_on_rooms_root_tree_changed):
		root.child_exiting_tree.connect(_on_rooms_root_tree_changed)
	if not root.child_order_changed.is_connected(_on_rooms_root_order_changed):
		root.child_order_changed.connect(_on_rooms_root_order_changed)


func _disconnect_rooms_root(root: Node2D) -> void:
	if root == null:
		return
	if root.child_entered_tree.is_connected(_on_rooms_root_tree_changed):
		root.child_entered_tree.disconnect(_on_rooms_root_tree_changed)
	if root.child_exiting_tree.is_connected(_on_rooms_root_tree_changed):
		root.child_exiting_tree.disconnect(_on_rooms_root_tree_changed)
	if root.child_order_changed.is_connected(_on_rooms_root_order_changed):
		root.child_order_changed.disconnect(_on_rooms_root_order_changed)


func _on_rooms_root_tree_changed(_node: Node) -> void:
	_rooms_dirty = true
	_request_redraw()


func _on_rooms_root_order_changed() -> void:
	_rooms_dirty = true
	_request_redraw()
