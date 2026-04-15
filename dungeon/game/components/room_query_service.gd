extends Node
class_name RoomQueryService

var rooms_root: Node2D
var _room_cache_dirty := true
var _observed_rooms_root: Node2D
var _cached_room_entries: Array[Dictionary] = []
var _last_room_hit: RoomBase


func room_by_name(room_name: StringName) -> RoomBase:
	if rooms_root == null:
		return null
	var room := rooms_root.get_node_or_null(String(room_name))
	if room is RoomBase:
		return room as RoomBase
	return null


func room_half_extents(room: RoomBase) -> Vector2:
	var bounds := room_bounds_rect(room)
	return bounds.size * 0.5


func room_center_2d(room_name: StringName) -> Vector2:
	var room := room_by_name(room_name)
	return room.global_position if room != null else Vector2.ZERO


func connection_marker_world_position(room_name: StringName, direction: String, marker_kind: String = "") -> Vector2:
	var room := room_by_name(room_name)
	if room == null:
		return Vector2.ZERO
	var authored_markers := _authored_connection_markers(room)
	if not authored_markers.is_empty():
		for marker in authored_markers:
			if String(marker.get("direction", "")) != direction:
				continue
			if marker_kind != "" and String(marker.get("marker_kind", "")) != marker_kind:
				continue
			return marker.get("world_position", room.global_position) as Vector2
	for marker in room.get_connection_markers_by_direction(direction):
		if marker.connection_tag == &"inactive":
			continue
		if marker_kind != "" and marker.marker_kind != marker_kind:
			continue
		return marker.global_position
	return room.global_position


func socket_world_position(room_name: StringName, direction: String) -> Vector2:
	return connection_marker_world_position(room_name, direction)


func zone_marker_world_position(room_name: StringName, zone_type: String, zone_role: StringName = &"") -> Vector2:
	var result := find_zone_marker_world_position(room_name, zone_type, zone_role)
	return result.get("position", Vector2.ZERO)


func zone_marker_world_positions(
	room_name: StringName,
	zone_type: String,
	zone_role: StringName = &""
) -> Array[Vector2]:
	var room := room_by_name(room_name)
	var positions: Array[Vector2] = []
	if room == null:
		return positions
	var authored_zones := _authored_zone_markers(room)
	if not authored_zones.is_empty():
		for zone in authored_zones:
			if String(zone.get("zone_type", "")) != zone_type:
				continue
			if zone_role != &"" and zone.get("zone_role", &"") != zone_role:
				continue
			positions.append(zone.get("world_position", Vector2.ZERO) as Vector2)
		return positions
	for zone in room.get_zone_markers():
		if zone.zone_type != zone_type:
			continue
		if zone_role != &"" and zone.zone_role != zone_role:
			continue
		positions.append(zone.global_position)
	return positions


func zone_markers(
	room_name: StringName,
	zone_type: String,
	zone_role: StringName = &""
) -> Array[Dictionary]:
	var room := room_by_name(room_name)
	var markers: Array[Dictionary] = []
	if room == null:
		return markers
	var authored_zones := _authored_zone_markers(room)
	if not authored_zones.is_empty():
		for zone in authored_zones:
			if String(zone.get("zone_type", "")) != zone_type:
				continue
			if zone_role != &"" and zone.get("zone_role", &"") != zone_role:
				continue
			markers.append(zone.duplicate(true))
		return markers
	for zone in room.get_zone_markers():
		if zone.zone_type != zone_type:
			continue
		if zone_role != &"" and zone.zone_role != zone_role:
			continue
		var metadata := zone.get_zone_metadata()
		metadata["world_position"] = zone.global_position
		markers.append(metadata)
	return markers


func find_zone_marker_world_position(
	room_name: StringName,
	zone_type: String,
	zone_role: StringName = &""
) -> Dictionary:
	var positions := zone_marker_world_positions(room_name, zone_type, zone_role)
	if positions.is_empty():
		return {"found": false, "position": Vector2.ZERO}
	return {"found": true, "position": positions[0]}


func room_bounds_rect(room: RoomBase) -> Rect2:
	if room == null:
		return Rect2()
	_ensure_room_cache()
	for entry in _cached_room_entries:
		if entry.get("room", null) == room:
			return entry.get("bounds", Rect2()) as Rect2
	if room.has_meta(&"authored_room_bounds_rect"):
		var cached = room.get_meta(&"authored_room_bounds_rect")
		if cached is Rect2:
			return cached as Rect2
	var authored_cells := _authored_occupied_cells(room)
	if authored_cells.is_empty():
		var local_rect := room.get_room_rect_world()
		return Rect2(room.global_position - local_rect.size * 0.5, local_rect.size)
	var bounds := _room_world_cell_rect(room, authored_cells[0])
	for i in range(1, authored_cells.size()):
		bounds = bounds.merge(_room_world_cell_rect(room, authored_cells[i]))
	room.set_meta(&"authored_room_bounds_rect", bounds)
	return bounds


func clamp_pos_to_room(room: RoomBase, pos: Vector2) -> Vector2:
	if room == null:
		return pos
	var walkable_rects := _authored_walkable_world_cell_rects(room)
	if not walkable_rects.is_empty():
		return _closest_point_in_rects(pos, walkable_rects, 0.9)
	var room_rect := room_bounds_rect(room)
	if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
		var fallback_rect := room.get_room_rect_world()
		room_rect = Rect2(room.global_position - fallback_rect.size * 0.5, fallback_rect.size)
	var inset := 0.9
	return Vector2(
		clampf(pos.x, room_rect.position.x + inset, room_rect.end.x - inset),
		clampf(pos.y, room_rect.position.y + inset, room_rect.end.y - inset)
	)


func is_point_inside_any_room(world_pos: Vector2, margin: float = 0.0) -> bool:
	return _find_room_entry_at(world_pos, margin).get("room", null) != null


func room_name_at(world_pos: Vector2, margin: float = 0.0) -> String:
	var room := _find_room_entry_at(world_pos, margin).get("room", null) as RoomBase
	return String(room.name) if room != null else ""


func room_type_at(world_pos: Vector2, margin: float = 0.0) -> String:
	var room := _find_room_entry_at(world_pos, margin).get("room", null) as RoomBase
	return String(room.room_type) if room != null else ""


func invalidate_cache() -> void:
	_clear_cached_room_meta()
	_room_cache_dirty = true
	_last_room_hit = null


func _room_contains_world_point(room: RoomBase, world_pos: Vector2, margin: float) -> bool:
	var entry := _room_entry_for(room)
	if entry.is_empty():
		return false
	return _room_entry_contains_world_point(entry, world_pos, margin)


func _room_world_cell_rect(room: RoomBase, cell: Vector2i) -> Rect2:
	var tile_size := _room_tile_size(room)
	var center := Vector2(cell * tile_size)
	return Rect2(center - Vector2(tile_size) * 0.5, Vector2(tile_size))


func _room_tile_size(room: RoomBase) -> Vector2i:
	if room != null and room.has_meta(&"authored_room_tile_size"):
		var meta_value = room.get_meta(&"authored_room_tile_size")
		if meta_value is Vector2i:
			return meta_value as Vector2i
	return room.tile_size if room != null else Vector2i.ONE


func _authored_occupied_cells(room: RoomBase) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if room == null or not room.has_meta(&"authored_room_occupied_cells_world"):
		return cells
	var raw_cells = room.get_meta(&"authored_room_occupied_cells_world")
	if raw_cells is Array:
		for value in raw_cells:
			if value is Vector2i:
				cells.append(value as Vector2i)
	return cells


func _authored_walkable_cells(room: RoomBase) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if room == null or not room.has_meta(&"authored_room_walkable_cells_world"):
		return cells
	var raw_cells = room.get_meta(&"authored_room_walkable_cells_world")
	if raw_cells is Array:
		for value in raw_cells:
			if value is Vector2i:
				cells.append(value as Vector2i)
	return cells


func _authored_blocked_cells(room: RoomBase) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if room == null or not room.has_meta(&"authored_room_blocked_cells_world"):
		return cells
	var raw_cells = room.get_meta(&"authored_room_blocked_cells_world")
	if raw_cells is Array:
		for value in raw_cells:
			if value is Vector2i:
				cells.append(value as Vector2i)
	return cells


func _authored_connection_markers(room: RoomBase) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if room == null or not room.has_meta(&"authored_connection_markers_world"):
		return markers
	var raw_markers = room.get_meta(&"authored_connection_markers_world")
	if raw_markers is Array:
		for value in raw_markers:
			if value is Dictionary:
				markers.append(value as Dictionary)
	return markers


func _authored_zone_markers(room: RoomBase) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if room == null or not room.has_meta(&"authored_zone_markers_world"):
		return markers
	var raw_markers = room.get_meta(&"authored_zone_markers_world")
	if raw_markers is Array:
		for value in raw_markers:
			if value is Dictionary:
				markers.append(value as Dictionary)
	return markers


func _ensure_room_cache() -> void:
	if rooms_root != _observed_rooms_root:
		_disconnect_rooms_root_signals(_observed_rooms_root)
		_observed_rooms_root = rooms_root
		_connect_rooms_root_signals(_observed_rooms_root)
		_room_cache_dirty = true
	if rooms_root == null:
		_cached_room_entries.clear()
		_last_room_hit = null
		return
	if not _room_cache_dirty:
		return
	_cached_room_entries.clear()
	for child in rooms_root.get_children():
		if child is not RoomBase:
			continue
		_cached_room_entries.append(_build_room_entry(child as RoomBase))
	_room_cache_dirty = false
	if _last_room_hit != null and _room_entry_for(_last_room_hit).is_empty():
		_last_room_hit = null


func _build_room_entry(room: RoomBase) -> Dictionary:
	var entry := {
		"room": room,
		"bounds": Rect2(),
		"cell_rects": [],
	}
	var authored_cell_rects := _authored_world_cell_rects(room)
	entry["cell_rects"] = authored_cell_rects
	if authored_cell_rects.is_empty():
		var local_rect := room.get_room_rect_world()
		entry["bounds"] = Rect2(room.global_position - local_rect.size * 0.5, local_rect.size)
	else:
		var bounds := authored_cell_rects[0] as Rect2
		for i in range(1, authored_cell_rects.size()):
			bounds = bounds.merge(authored_cell_rects[i] as Rect2)
		entry["bounds"] = bounds
	room.set_meta(&"authored_room_bounds_rect", entry["bounds"])
	return entry


func _find_room_entry_at(world_pos: Vector2, margin: float) -> Dictionary:
	_ensure_room_cache()
	if _last_room_hit != null:
		var last_entry := _room_entry_for(_last_room_hit)
		if not last_entry.is_empty() and _room_entry_contains_world_point(last_entry, world_pos, margin):
			return last_entry
	for entry in _cached_room_entries:
		if _room_entry_contains_world_point(entry, world_pos, margin):
			_last_room_hit = entry.get("room", null) as RoomBase
			return entry
	_last_room_hit = null
	return {}


func _room_entry_for(room: RoomBase) -> Dictionary:
	_ensure_room_cache()
	for entry in _cached_room_entries:
		if entry.get("room", null) == room:
			return entry
	return {}


func _room_entry_contains_world_point(entry: Dictionary, world_pos: Vector2, margin: float) -> bool:
	var cell_rects: Array = entry.get("cell_rects", [])
	if cell_rects.is_empty():
		return (entry.get("bounds", Rect2()) as Rect2).grow(margin).has_point(world_pos)
	for rect_value in cell_rects:
		var cell_rect := rect_value as Rect2
		if cell_rect.grow(margin).has_point(world_pos):
			return true
	return false


func _authored_world_cell_rects(room: RoomBase) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if room == null:
		return rects
	if room.has_meta(&"authored_room_cell_rects_world"):
		var cached_rects = room.get_meta(&"authored_room_cell_rects_world")
		if cached_rects is Array:
			for value in cached_rects:
				if value is Rect2:
					rects.append(value as Rect2)
			if not rects.is_empty():
				return rects
	var authored_cells := _authored_occupied_cells(room)
	if authored_cells.is_empty():
		return rects
	for cell in authored_cells:
		rects.append(_room_world_cell_rect(room, cell))
	room.set_meta(&"authored_room_cell_rects_world", rects)
	return rects


func _authored_walkable_world_cell_rects(room: RoomBase) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if room == null:
		return rects
	if room.has_meta(&"authored_room_walkable_cell_rects_world"):
		var cached_rects = room.get_meta(&"authored_room_walkable_cell_rects_world")
		if cached_rects is Array:
			for value in cached_rects:
				if value is Rect2:
					rects.append(value as Rect2)
			if not rects.is_empty():
				return rects
	var walkable_cells := _authored_walkable_cells(room)
	if walkable_cells.is_empty():
		return rects
	var blocked_lookup := {}
	for blocked_cell in _authored_blocked_cells(room):
		blocked_lookup[_cell_key(blocked_cell)] = true
	for cell in walkable_cells:
		if blocked_lookup.has(_cell_key(cell)):
			continue
		rects.append(_room_world_cell_rect(room, cell))
	room.set_meta(&"authored_room_walkable_cell_rects_world", rects)
	return rects


func _closest_point_in_rects(pos: Vector2, rects: Array[Rect2], inset: float) -> Vector2:
	var best_pos := pos
	var best_dist_sq := INF
	for rect in rects:
		var candidate := _clamp_point_to_rect(pos, rect, inset)
		var dist_sq := candidate.distance_squared_to(pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_pos = candidate
	return best_pos


func _clamp_point_to_rect(pos: Vector2, rect: Rect2, inset: float) -> Vector2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return pos
	var max_inset := minf(inset, minf(rect.size.x, rect.size.y) * 0.5)
	var min_pos := rect.position + Vector2(max_inset, max_inset)
	var max_pos := rect.end - Vector2(max_inset, max_inset)
	return Vector2(
		clampf(pos.x, min_pos.x, max_pos.x),
		clampf(pos.y, min_pos.y, max_pos.y)
	)


func _cell_key(cell: Vector2i) -> String:
	return "%s,%s" % [cell.x, cell.y]


func _connect_rooms_root_signals(root: Node2D) -> void:
	if root == null:
		return
	if not root.child_entered_tree.is_connected(_on_rooms_root_child_tree_changed):
		root.child_entered_tree.connect(_on_rooms_root_child_tree_changed)
	if not root.child_exiting_tree.is_connected(_on_rooms_root_child_tree_changed):
		root.child_exiting_tree.connect(_on_rooms_root_child_tree_changed)
	if not root.child_order_changed.is_connected(_on_rooms_root_child_order_changed):
		root.child_order_changed.connect(_on_rooms_root_child_order_changed)


func _disconnect_rooms_root_signals(root: Node2D) -> void:
	if root == null:
		return
	if root.child_entered_tree.is_connected(_on_rooms_root_child_tree_changed):
		root.child_entered_tree.disconnect(_on_rooms_root_child_tree_changed)
	if root.child_exiting_tree.is_connected(_on_rooms_root_child_tree_changed):
		root.child_exiting_tree.disconnect(_on_rooms_root_child_tree_changed)
	if root.child_order_changed.is_connected(_on_rooms_root_child_order_changed):
		root.child_order_changed.disconnect(_on_rooms_root_child_order_changed)


func _clear_cached_room_meta() -> void:
	if rooms_root == null:
		return
	for child in rooms_root.get_children():
		if child is not RoomBase:
			continue
		var room := child as RoomBase
		for meta_key in [
			&"authored_room_bounds_rect",
			&"authored_room_cell_rects_world",
			&"authored_room_walkable_cell_rects_world",
		]:
			if room.has_meta(meta_key):
				room.remove_meta(meta_key)


func _on_rooms_root_child_tree_changed(_node: Node) -> void:
	invalidate_cache()


func _on_rooms_root_child_order_changed() -> void:
	invalidate_cache()
