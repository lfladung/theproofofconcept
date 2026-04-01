extends RefCounted
class_name ProceduralAssemblyV1

const _PLACE_EPSILON := 0.01
const _OVERLAP_MARGIN := 0.05


func build_catalog(rooms_root: Node2D) -> Dictionary:
	var by_name: Dictionary = {}
	var metadata: Array[Dictionary] = []
	if rooms_root == null:
		return {"by_name": by_name, "metadata": metadata}
	for child in rooms_root.get_children():
		if child is not RoomBase:
			continue
		var room: RoomBase = child as RoomBase
		by_name[room.name] = room
		metadata.append(_room_metadata(room))
	return {"by_name": by_name, "metadata": metadata}


func assemble_from_connection_graph(
	rooms_root: Node2D, start_room_name: StringName, links: Array[Dictionary]
) -> Dictionary:
	var catalog: Dictionary = build_catalog(rooms_root)
	var by_name: Dictionary = catalog.get("by_name", {})
	var errors: PackedStringArray = []
	if not by_name.has(start_room_name):
		errors.append("Start room '%s' is missing from the catalog." % String(start_room_name))
		return {"ok": false, "errors": errors, "catalog": catalog}

	var placed: Dictionary = {}
	placed[start_room_name] = true
	var pending: Array[Dictionary] = []
	for link in links:
		pending.append(link)

	while not pending.is_empty():
		var progressed: bool = false
		var next_pending: Array[Dictionary] = []
		for link in pending:
			var from_name: StringName = StringName(String(link.get("from", "")))
			var to_name: StringName = StringName(String(link.get("to", "")))
			var from_dir: String = String(link.get("from_dir", ""))
			var to_dir: String = String(link.get("to_dir", _opposite_direction(from_dir)))
			if from_name == StringName() or to_name == StringName():
				errors.append("Invalid connection link found: %s" % [link])
				continue
			if not by_name.has(from_name) or not by_name.has(to_name):
				errors.append("Connection link references unknown room(s): %s" % [link])
				continue
			var from_placed: bool = bool(placed.get(from_name, false))
			var to_placed: bool = bool(placed.get(to_name, false))
			if from_placed and to_placed:
				if not _validate_existing_connection(
					by_name[from_name] as RoomBase, by_name[to_name] as RoomBase, from_dir, to_dir
				):
					errors.append("Placed rooms '%s' and '%s' failed marker validation." % [from_name, to_name])
				progressed = true
				continue
			if not from_placed and not to_placed:
				next_pending.append(link)
				continue
			var anchor_name: StringName = from_name if from_placed else to_name
			var place_name: StringName = to_name if from_placed else from_name
			var anchor_dir: String = from_dir if from_placed else to_dir
			var place_dir: String = to_dir if from_placed else from_dir
			var anchor_room: RoomBase = by_name[anchor_name] as RoomBase
			var place_room: RoomBase = by_name[place_name] as RoomBase
			if not _place_room_from_marker(anchor_room, place_room, anchor_dir, place_dir):
				errors.append(
					"Failed to place '%s' from '%s' using marker %s -> %s." % [
						place_name,
						anchor_name,
						anchor_dir,
						place_dir,
					]
				)
				continue
			placed[place_name] = true
			progressed = true
		pending = next_pending
		if not progressed and not pending.is_empty():
			errors.append("Connection graph has unresolved links (possible disconnected branch or cycle mismatch).")
			break

	var overlap_errors: PackedStringArray = _validate_no_overlaps(_placed_rooms(by_name, placed))
	for msg in overlap_errors:
		errors.append(msg)
	var connectivity_errors: PackedStringArray = _validate_connectivity(by_name, placed, start_room_name, links)
	for msg in connectivity_errors:
		errors.append(msg)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"catalog": catalog,
		"placed_count": placed.size(),
		"total_rooms": by_name.size(),
}


func assemble_from_socket_graph(rooms_root: Node2D, start_room_name: StringName, links: Array[Dictionary]) -> Dictionary:
	return assemble_from_connection_graph(rooms_root, start_room_name, links)


func _room_metadata(room: RoomBase) -> Dictionary:
	var markers: Array[Dictionary] = []
	for marker in room.get_connection_markers():
		var sig: Dictionary = marker.marker_signature()
		sig["name"] = marker.name
		sig["active"] = marker.connection_tag != &"inactive"
		markers.append(sig)
	return {
		"name": room.name,
		"room_id": room.room_id,
		"room_type": room.room_type,
		"size_class": room.size_class,
		"room_size_tiles": room.room_size_tiles,
		"allowed_rotations": room.allowed_rotations,
		"room_tags": room.room_tags,
		"connection_markers": markers,
	}


func _validate_existing_connection(from_room: RoomBase, to_room: RoomBase, from_dir: String, to_dir: String) -> bool:
	var from_marker: ConnectorMarker2D = _first_active_marker(from_room, from_dir, "exit")
	var to_marker: ConnectorMarker2D = _first_active_marker(to_room, to_dir, "entrance")
	if from_marker == null or to_marker == null:
		return false
	if not from_marker.is_compatible_with(to_marker):
		return false
	var from_world: Vector2 = from_room.global_position + from_marker.position
	var to_world: Vector2 = to_room.global_position + to_marker.position
	return from_world.distance_to(to_world) <= _PLACE_EPSILON


func _place_room_from_marker(anchor_room: RoomBase, place_room: RoomBase, anchor_dir: String, place_dir: String) -> bool:
	var anchor_marker: ConnectorMarker2D = _first_active_marker(anchor_room, anchor_dir, "exit")
	var place_marker: ConnectorMarker2D = _first_active_marker(place_room, place_dir, "entrance")
	if anchor_marker == null or place_marker == null:
		return false
	if not anchor_marker.is_compatible_with(place_marker):
		return false
	var marker_world: Vector2 = anchor_room.global_position + anchor_marker.position
	place_room.global_position = marker_world - place_marker.position
	return true


func _first_active_marker(room: RoomBase, direction: String, marker_kind: String = "") -> ConnectorMarker2D:
	for marker in room.get_connection_markers_by_direction(direction):
		if marker.connection_tag == &"inactive":
			continue
		if marker_kind != "" and marker.marker_kind != marker_kind:
			continue
		return marker
	return null


func _placed_rooms(by_name: Dictionary, placed: Dictionary) -> Array[RoomBase]:
	var out: Array[RoomBase] = []
	for room_name in placed.keys():
		if bool(placed.get(room_name, false)) and by_name.has(room_name):
			out.append(by_name[room_name] as RoomBase)
	return out


func _validate_no_overlaps(rooms: Array[RoomBase]) -> PackedStringArray:
	var errors: PackedStringArray = []
	for i in range(rooms.size()):
		var a: RoomBase = rooms[i]
		var rect_a: Rect2 = _room_world_rect(a).grow(-_OVERLAP_MARGIN)
		for j in range(i + 1, rooms.size()):
			var b: RoomBase = rooms[j]
			var rect_b: Rect2 = _room_world_rect(b).grow(-_OVERLAP_MARGIN)
			if rect_a.intersects(rect_b, true):
				errors.append("Room overlap detected: '%s' intersects '%s'." % [a.name, b.name])
	return errors


func _room_world_rect(room: RoomBase) -> Rect2:
	var local_rect: Rect2 = room.get_room_rect_world()
	return Rect2(room.global_position - local_rect.size * 0.5, local_rect.size)


func _validate_connectivity(
	by_name: Dictionary, placed: Dictionary, start_room_name: StringName, links: Array[Dictionary]
) -> PackedStringArray:
	var errors: PackedStringArray = []
	var adj: Dictionary = {}
	for room_name in by_name.keys():
		adj[room_name] = []
	for link in links:
		var a: StringName = StringName(String(link.get("from", "")))
		var b: StringName = StringName(String(link.get("to", "")))
		if by_name.has(a) and by_name.has(b):
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)
	var seen: Dictionary = {}
	var queue: Array[StringName] = []
	queue.append(start_room_name)
	while not queue.is_empty():
		var cur: StringName = queue.pop_front()
		if bool(seen.get(cur, false)):
			continue
		seen[cur] = true
		for next_room in adj.get(cur, []):
			var n: StringName = next_room as StringName
			if bool(placed.get(n, false)) and not bool(seen.get(n, false)):
				queue.append(n)
	for room_name in placed.keys():
		if bool(placed.get(room_name, false)) and not bool(seen.get(room_name, false)):
			errors.append("Connectivity check failed: room '%s' is disconnected from '%s'." % [room_name, start_room_name])
	return errors


func _opposite_direction(direction: String) -> String:
	match direction:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		"west":
			return "east"
		"up":
			return "down"
		"down":
			return "up"
		_:
			return ""
