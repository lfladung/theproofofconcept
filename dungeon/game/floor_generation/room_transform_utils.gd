extends RefCounted
class_name RoomTransformUtils


static func normalize_rotation_deg(rotation_deg: int) -> int:
	var normalized := posmod(rotation_deg, 360)
	return int(roundf(float(normalized) / 90.0)) * 90 % 360


static func rotate_cell(cell: Vector2i, rotation_deg: int) -> Vector2i:
	match normalize_rotation_deg(rotation_deg):
		90:
			return Vector2i(-cell.y, cell.x)
		180:
			return Vector2i(-cell.x, -cell.y)
		270:
			return Vector2i(cell.y, -cell.x)
		_:
			return cell


static func rotate_direction(direction: String, rotation_deg: int) -> String:
	var dirs := ["north", "east", "south", "west"]
	var idx := dirs.find(direction)
	if idx < 0:
		return direction
	var steps := posmod(normalize_rotation_deg(rotation_deg) / 90, 4)
	return dirs[(idx + steps) % 4]


static func rotate_cells(cells: Array[Vector2i], rotation_deg: int) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	rotated.resize(cells.size())
	for i in range(cells.size()):
		rotated[i] = rotate_cell(cells[i], rotation_deg)
	return rotated


static func transform_local_cell_to_world(
	local_cell: Vector2i,
	center_cell: Vector2i,
	rotation_deg: int
) -> Vector2i:
	return center_cell + rotate_cell(local_cell, rotation_deg)


static func transform_local_position(local_position: Vector2, rotation_deg: int) -> Vector2:
	return local_position.rotated(deg_to_rad(float(normalize_rotation_deg(rotation_deg))))


static func marker_world_cell(
	center_cell: Vector2i,
	marker_local_cell: Vector2i,
	rotation_deg: int
) -> Vector2i:
	return transform_local_cell_to_world(marker_local_cell, center_cell, rotation_deg)


static func marker_world_position(
	center_cell: Vector2i,
	marker_local_position: Vector2,
	rotation_deg: int,
	tile_size: Vector2i
) -> Vector2:
	return Vector2(center_cell * tile_size) + transform_local_position(marker_local_position, rotation_deg)


static func solve_center_cell_from_marker_alignment(
	anchor_world_position: Vector2,
	candidate_marker_local_position: Vector2,
	rotation_deg: int,
	tile_size: Vector2i
) -> Vector2i:
	var center_world := anchor_world_position - transform_local_position(candidate_marker_local_position, rotation_deg)
	if tile_size.x == 0 or tile_size.y == 0:
		return Vector2i.ZERO
	return Vector2i(
		roundi(center_world.x / float(tile_size.x)),
		roundi(center_world.y / float(tile_size.y))
	)
