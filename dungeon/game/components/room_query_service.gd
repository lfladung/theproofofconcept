extends Node
class_name RoomQueryService

var rooms_root: Node2D


func room_by_name(room_name: StringName) -> RoomBase:
	if rooms_root == null:
		return null
	var room := rooms_root.get_node_or_null(String(room_name))
	if room is RoomBase:
		return room as RoomBase
	return null


func room_half_extents(room: RoomBase) -> Vector2:
	if room == null:
		return Vector2.ZERO
	return Vector2(
		float(room.room_size_tiles.x * room.tile_size.x) * 0.5,
		float(room.room_size_tiles.y * room.tile_size.y) * 0.5
	)


func room_center_2d(room_name: StringName) -> Vector2:
	var room := room_by_name(room_name)
	return room.global_position if room != null else Vector2.ZERO


func connection_marker_world_position(room_name: StringName, direction: String, marker_kind: String = "") -> Vector2:
	var room := room_by_name(room_name)
	if room == null:
		return Vector2.ZERO
	for marker in room.get_connection_markers_by_direction(direction):
		if marker.connection_tag == &"inactive":
			continue
		if marker_kind != "" and marker.marker_kind != marker_kind:
			continue
		return room.global_position + marker.position
	return room.global_position


func socket_world_position(room_name: StringName, direction: String) -> Vector2:
	return connection_marker_world_position(room_name, direction)


func is_point_inside_any_room(world_pos: Vector2, margin: float = 0.0) -> bool:
	if rooms_root == null:
		return false
	for room in rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var local_rect := r.get_room_rect_world()
		var rect := Rect2(r.global_position - local_rect.size * 0.5, local_rect.size).grow(margin)
		if rect.has_point(world_pos):
			return true
	return false


func room_name_at(world_pos: Vector2, margin: float = 0.0) -> String:
	if rooms_root == null:
		return ""
	for room in rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var local_rect := r.get_room_rect_world()
		var rect := Rect2(r.global_position - local_rect.size * 0.5, local_rect.size).grow(margin)
		if rect.has_point(world_pos):
			return String(r.name)
	return ""


func room_type_at(world_pos: Vector2, margin: float = 0.0) -> String:
	if rooms_root == null:
		return ""
	for room in rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var local_rect := r.get_room_rect_world()
		var rect := Rect2(r.global_position - local_rect.size * 0.5, local_rect.size).grow(margin)
		if rect.has_point(world_pos):
			return String(r.room_type)
	return ""
