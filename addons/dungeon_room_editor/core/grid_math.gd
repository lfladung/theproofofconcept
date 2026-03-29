@tool
extends RefCounted
class_name DungeonRoomGridMath


static func grid_step(layout, room: RoomBase) -> Vector2:
	if layout != null and layout.grid_size.x > 0 and layout.grid_size.y > 0:
		return Vector2(layout.grid_size)
	if room != null and room.tile_size.x > 0 and room.tile_size.y > 0:
		return Vector2(room.tile_size)
	return Vector2(3.0, 3.0)


static func room_local_rect(room: RoomBase) -> Rect2:
	if room == null:
		return Rect2()
	var tile_size_value = room.get(&"tile_size")
	var room_size_tiles_value = room.get(&"room_size_tiles")
	var origin_mode = String(room.get(&"origin_mode"))
	var tile_size := tile_size_value as Vector2i
	var room_size_tiles := room_size_tiles_value as Vector2i
	if tile_size == null or room_size_tiles == null:
		return Rect2()
	var size = Vector2(
		float(tile_size.x * maxi(room_size_tiles.x, 1)),
		float(tile_size.y * maxi(room_size_tiles.y, 1))
	)
	var position = Vector2.ZERO
	if origin_mode != "top_left":
		position = -size * 0.5
	return Rect2(position, size)


static func grid_to_local(grid_position: Vector2i, layout, room: RoomBase) -> Vector2:
	var step := grid_step(layout, room)
	var origin_mode = String(room.get(&"origin_mode")) if room != null else "center"
	var local = Vector2(float(grid_position.x) * step.x, float(grid_position.y) * step.y)
	if origin_mode == "top_left":
		return room_local_rect(room).position + local
	return local


static func local_to_grid(local_position: Vector2, layout, room: RoomBase) -> Vector2i:
	var step := grid_step(layout, room)
	if is_zero_approx(step.x) or is_zero_approx(step.y):
		return Vector2i.ZERO
	var origin_mode = String(room.get(&"origin_mode")) if room != null else "center"
	var relative = local_position
	if origin_mode == "top_left":
		relative -= room_local_rect(room).position
	return Vector2i(roundi(relative.x / step.x), roundi(relative.y / step.y))


static func grid_is_inside_room(grid_position: Vector2i, layout, room: RoomBase) -> bool:
	return is_inside_room(grid_to_local(grid_position, layout, room), room, layout)


static func is_defined_grid(grid_position: Vector2i) -> bool:
	return absi(grid_position.x) < 1_000_000 and absi(grid_position.y) < 1_000_000


static func rotated_footprint(footprint: Vector2i, rotation_steps: int) -> Vector2i:
	var normalized := posmod(rotation_steps, 4)
	if normalized % 2 == 0:
		return Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))
	return Vector2i(maxi(1, footprint.y), maxi(1, footprint.x))


static func anchor_rect(
	grid_position: Vector2i,
	footprint: Vector2i,
	rotation_steps: int,
	layout,
	room: RoomBase
) -> Rect2:
	var size_tiles := rotated_footprint(footprint, rotation_steps)
	var step := grid_step(layout, room)
	var world_size := Vector2(float(size_tiles.x) * step.x, float(size_tiles.y) * step.y)
	var local_center := grid_to_local(grid_position, layout, room)
	return Rect2(local_center - world_size * 0.5, world_size)


static func item_rect(item, piece, layout, room: RoomBase) -> Rect2:
	if item == null or piece == null:
		return Rect2()
	return anchor_rect(item.grid_position, piece.footprint, item.rotation_steps, layout, room)


static func room_half_extents(room: RoomBase) -> Vector2:
	if room == null:
		return Vector2.ZERO
	return room_world_size(room) * 0.5


static func room_world_size(room: RoomBase) -> Vector2:
	return room_local_rect(room).size


static func is_inside_room(local_position: Vector2, room: RoomBase, layout) -> bool:
	var room_rect := room_local_rect(room)
	var step := grid_step(layout, room) * 0.5
	return (
		local_position.x >= room_rect.position.x - step.x - 0.001
		and local_position.y >= room_rect.position.y - step.y - 0.001
		and local_position.x <= room_rect.end.x + step.x + 0.001
		and local_position.y <= room_rect.end.y + step.y + 0.001
	)


static func direction_from_rotation(rotation_steps: int) -> String:
	match posmod(rotation_steps, 4):
		0:
			return "north"
		1:
			return "east"
		2:
			return "south"
		_:
			return "west"


static func direction_matches_boundary(room: RoomBase, layout, local_position: Vector2, direction: String) -> bool:
	var room_rect := room_local_rect(room)
	var tolerance := maxf(grid_step(layout, room).x, grid_step(layout, room).y) * 0.35
	match direction:
		"north":
			return is_equal_approx(local_position.y, room_rect.position.y) and local_position.x >= room_rect.position.x - tolerance and local_position.x <= room_rect.end.x + tolerance
		"south":
			return is_equal_approx(local_position.y, room_rect.end.y) and local_position.x >= room_rect.position.x - tolerance and local_position.x <= room_rect.end.x + tolerance
		"east":
			return is_equal_approx(local_position.x, room_rect.end.x) and local_position.y >= room_rect.position.y - tolerance and local_position.y <= room_rect.end.y + tolerance
		"west":
			return is_equal_approx(local_position.x, room_rect.position.x) and local_position.y >= room_rect.position.y - tolerance and local_position.y <= room_rect.end.y + tolerance
		_:
			return false


static func local_to_canvas(room: RoomBase, local_position: Vector2) -> Vector2:
	if room == null:
		return local_position
	return room.get_global_transform_with_canvas() * local_position


static func canvas_to_local(room: RoomBase, canvas_position: Vector2) -> Vector2:
	if room == null:
		return canvas_position
	return room.make_canvas_position_local(canvas_position)
