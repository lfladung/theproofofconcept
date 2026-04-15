extends RefCounted
class_name RoomPlacementValidator

const RoomTransformUtilsScript = preload("res://dungeon/game/floor_generation/room_transform_utils.gd")


static func markers_are_compatible(
	anchor_marker: Dictionary,
	anchor_rotation: int,
	candidate_marker: Dictionary,
	candidate_rotation: int
) -> bool:
	var anchor_kind := String(anchor_marker.get("marker_kind", ""))
	var candidate_kind := String(candidate_marker.get("marker_kind", ""))
	if anchor_kind == candidate_kind:
		return false
	if anchor_kind != "exit" or candidate_kind != "entrance":
		return false
	if int(anchor_marker.get("width_tiles", 0)) != int(candidate_marker.get("width_tiles", 0)):
		return false
	if String(anchor_marker.get("connector_type", "")) != String(candidate_marker.get("connector_type", "")):
		return false
	if anchor_rotation != 0 and not bool(anchor_marker.get("allow_room_rotation", true)):
		return false
	if candidate_rotation != 0 and not bool(candidate_marker.get("allow_room_rotation", true)):
		return false
	var anchor_dir := RoomTransformUtilsScript.rotate_direction(
		String(anchor_marker.get("direction", "")),
		anchor_rotation
	)
	var candidate_dir := RoomTransformUtilsScript.rotate_direction(
		String(candidate_marker.get("direction", "")),
		candidate_rotation
	)
	return _opposite_direction(anchor_dir) == candidate_dir


static func solve_candidate_center_cell(
	anchor_center_cell: Vector2i,
	anchor_exit_marker: Dictionary,
	anchor_rotation: int,
	anchor_tile_size: Vector2i,
	candidate_entrance_marker: Dictionary,
	candidate_rotation: int,
	candidate_tile_size: Vector2i
) -> Vector2i:
	var anchor_dir := RoomTransformUtilsScript.rotate_direction(
		String(anchor_exit_marker.get("direction", "")),
		anchor_rotation
	)
	var target_world := RoomTransformUtilsScript.marker_world_position(
		anchor_center_cell,
		anchor_exit_marker.get("local_position", Vector2.ZERO) as Vector2,
		anchor_rotation,
		anchor_tile_size
	) + Vector2(_direction_cell_offset(anchor_dir) * candidate_tile_size)
	return RoomTransformUtilsScript.solve_center_cell_from_marker_alignment(
		target_world,
		candidate_entrance_marker.get("local_position", Vector2.ZERO) as Vector2,
		candidate_rotation,
		candidate_tile_size
	)


static func _direction_cell_offset(direction: String) -> Vector2i:
	match direction:
		"north":
			return Vector2i(0, -1)
		"south":
			return Vector2i(0, 1)
		"east":
			return Vector2i(1, 0)
		"west":
			return Vector2i(-1, 0)
		_:
			return Vector2i.ZERO


static func world_occupied_lookup(room_data, center_cell: Vector2i, rotation_deg: int) -> Dictionary:
	var lookup := {}
	for cell in room_data.occupied_cells:
		var world_cell := RoomTransformUtilsScript.transform_local_cell_to_world(cell, center_cell, rotation_deg)
		lookup[_cell_key(world_cell)] = world_cell
	return lookup


static func world_walkable_cells(room_data, center_cell: Vector2i, rotation_deg: int) -> Array[Vector2i]:
	var world_cells: Array[Vector2i] = []
	for cell in room_data.walkable_cells:
		world_cells.append(RoomTransformUtilsScript.transform_local_cell_to_world(cell, center_cell, rotation_deg))
	return world_cells


static func world_blocked_cells(room_data, center_cell: Vector2i, rotation_deg: int) -> Array[Vector2i]:
	var world_cells: Array[Vector2i] = []
	for cell in room_data.blocked_cells:
		world_cells.append(RoomTransformUtilsScript.transform_local_cell_to_world(cell, center_cell, rotation_deg))
	return world_cells


static func world_connection_markers(room_data, center_cell: Vector2i, rotation_deg: int) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	for marker in room_data.connection_markers:
		var world_marker: Dictionary = marker.duplicate(true)
		world_marker["direction"] = RoomTransformUtilsScript.rotate_direction(
			String(marker.get("direction", "")),
			rotation_deg
		)
		world_marker["world_position"] = RoomTransformUtilsScript.marker_world_position(
			center_cell,
			marker.get("local_position", Vector2.ZERO) as Vector2,
			rotation_deg,
			room_data.tile_size
		)
		world_marker["world_cell"] = RoomTransformUtilsScript.marker_world_cell(
			center_cell,
			marker.get("local_cell", Vector2i.ZERO) as Vector2i,
			rotation_deg
		)
		var world_cells: Array[Vector2i] = []
		for local_cell in marker.get("local_cells", []) as Array:
			if local_cell is not Vector2i:
				continue
			world_cells.append(
				RoomTransformUtilsScript.transform_local_cell_to_world(
					local_cell as Vector2i,
					center_cell,
					rotation_deg
				)
			)
		world_marker["world_cells"] = world_cells
		markers.append(world_marker)
	return markers


static func world_zone_markers(room_data, center_cell: Vector2i, rotation_deg: int) -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	for marker in room_data.zone_markers:
		var world_marker: Dictionary = marker.duplicate(true)
		world_marker["world_position"] = RoomTransformUtilsScript.marker_world_position(
			center_cell,
			marker.get("local_position", Vector2.ZERO) as Vector2,
			rotation_deg,
			room_data.tile_size
		)
		world_marker["world_cell"] = RoomTransformUtilsScript.marker_world_cell(
			center_cell,
			marker.get("local_cell", Vector2i.ZERO) as Vector2i,
			rotation_deg
		)
		zones.append(world_marker)
	return zones


static func placement_overlaps(
	room_data,
	center_cell: Vector2i,
	rotation_deg: int,
	placed_specs: Array,
	allowed_overlap_keys: Dictionary = {}
) -> bool:
	return not placement_fits(room_data, center_cell, rotation_deg, placed_specs, allowed_overlap_keys).get("ok", false)


static func placement_fits(
	room_data,
	center_cell: Vector2i,
	rotation_deg: int,
	placed_specs: Array,
	allowed_overlap_keys: Dictionary = {}
) -> Dictionary:
	var candidate_lookup := world_occupied_lookup(room_data, center_cell, rotation_deg)
	for placed in placed_specs:
		if placed is not Dictionary:
			continue
		var placed_lookup: Dictionary = placed.get("occupied_lookup", {})
		if placed_lookup.is_empty():
			var placed_room_data = placed.get("room_data")
			var placed_center := placed.get("center_cell", Vector2i.ZERO) as Vector2i
			var placed_rotation := int(placed.get("rotation_deg", 0))
			placed_lookup = world_occupied_lookup(placed_room_data, placed_center, placed_rotation)
		for key in candidate_lookup.keys():
			if allowed_overlap_keys.has(key):
				continue
			if placed_lookup.has(key):
				return {
					"ok": false,
					"reason": "overlap",
					"overlap_cell": candidate_lookup[key],
					"occupied_lookup": candidate_lookup,
				}
	return {"ok": true, "reason": "", "occupied_lookup": candidate_lookup}


static func _cell_key(cell: Vector2i) -> String:
	return "%s,%s" % [cell.x, cell.y]


static func allowed_overlap_lookup(
	anchor_center_cell: Vector2i,
	anchor_marker: Dictionary,
	anchor_rotation: int,
	candidate_center_cell: Vector2i,
	candidate_marker: Dictionary,
	candidate_rotation: int
) -> Dictionary:
	var allowed := {}
	var anchor_world_cells := _marker_world_cells(anchor_center_cell, anchor_marker, anchor_rotation)
	var candidate_world_cells := _marker_world_cells(candidate_center_cell, candidate_marker, candidate_rotation)
	var anchor_lookup := {}
	for world_cell in anchor_world_cells:
		anchor_lookup[_cell_key(world_cell)] = true
	for world_cell in candidate_world_cells:
		var key := _cell_key(world_cell)
		if anchor_lookup.has(key):
			allowed[key] = true
	return allowed


static func _marker_world_cells(center_cell: Vector2i, marker: Dictionary, rotation_deg: int) -> Array[Vector2i]:
	var world_cells: Array[Vector2i] = []
	for local_cell in marker.get("local_cells", []) as Array:
		if local_cell is not Vector2i:
			continue
		world_cells.append(
			RoomTransformUtilsScript.transform_local_cell_to_world(
				local_cell as Vector2i,
				center_cell,
				rotation_deg
			)
		)
	return world_cells


static func _opposite_direction(direction: String) -> String:
	match direction:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		"west":
			return "east"
		_:
			return ""
