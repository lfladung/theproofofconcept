@tool
extends SceneTree

const OUTLINES_ROOT := "res://dungeon/rooms/authored/outlines"
const MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES := 3

var _versions: PackedInt32Array = PackedInt32Array([3])
var _rooms_filter: PackedStringArray = PackedStringArray()


func _get_cmd_arg_value(key: String) -> String:
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		var a: String = args[i]
		if a == key and i + 1 < args.size():
			return String(args[i + 1])
		var prefix := key + "="
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _init() -> void:
	var versions_arg := _get_cmd_arg_value("--versions")
	if not versions_arg.is_empty():
		var parsed: PackedInt32Array = PackedInt32Array()
		for token in versions_arg.split(","):
			var n := int(String(token).strip_edges())
			if n > 0:
				parsed.append(n)
		if not parsed.is_empty():
			_versions = parsed
	var rooms_arg := _get_cmd_arg_value("--rooms")
	if not rooms_arg.is_empty():
		_rooms_filter = PackedStringArray(rooms_arg.split(","))
	_validate_all()


func _room_matches_filter(room_path: String) -> bool:
	if _rooms_filter.is_empty():
		return true
	var id := room_path.get_file().trim_suffix(".tscn").to_lower()
	for token in _rooms_filter:
		var t := String(token).to_lower()
		if t == "skirmish" and id.contains("skirmish"):
			return true
		if t == "tactical" and id.contains("tactical"):
			return true
		if t == "chokepoint" and id.contains("chokepoint"):
			return true
		if t == "connector" and id.contains("room_connector_"):
			return true
		if id.contains(t):
			return true
	return false


func _collect_room_paths() -> Array[String]:
	var out: Array[String] = []
	for v in _versions:
		var version_dir := "%s/v%d" % [OUTLINES_ROOT, v]
		var dir := DirAccess.open(version_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		while true:
			var name := dir.get_next()
			if name.is_empty():
				break
			if dir.current_is_dir():
				continue
			if not name.ends_with(".tscn"):
				continue
			if not name.begins_with("room_"):
				continue
			var full_path := "%s/%s" % [version_dir, name]
			if _room_matches_filter(full_path):
				out.append(full_path)
		dir.list_dir_end()
	out.sort()
	return out


func _count_layout_structural_markers(room: RoomBase) -> int:
	var layout = room.authored_layout
	if layout == null:
		return 0
	var n := 0
	for item in layout.items:
		if item == null:
			continue
		match item.piece_id:
			&"encounter_entry_marker", &"prop_placement_marker", &"nav_boundary_marker":
				n += 1
			_:
				pass
	return n


func _normalized_rotation(item) -> int:
	if item != null and item.has_method("normalized_rotation_steps"):
		return int(item.normalized_rotation_steps())
	return posmod(int(item.get("rotation_steps", 0)), 4)


func _opening_cells_from_sockets(layout_items: Array) -> Dictionary:
	var cells: Dictionary = {}
	for item in layout_items:
		if item == null:
			continue
		if item.piece_id != &"hall_socket_double":
			continue
		var gp: Vector2i = item.grid_position
		var rot := _normalized_rotation(item)
		cells[gp] = true
		if rot % 2 == 0:
			cells[gp + Vector2i.RIGHT] = true
		else:
			cells[gp + Vector2i.DOWN] = true
	return cells


func _build_floor_lookup(layout_items: Array) -> Dictionary:
	var out: Dictionary = {}
	for item in layout_items:
		if item == null:
			continue
		if item.category == &"floor":
			out[item.grid_position] = true
	return out


func _build_blocked_lookup(layout_items: Array) -> Dictionary:
	var out: Dictionary = {}
	for item in layout_items:
		if item == null:
			continue
		if item.piece_id == &"barrel_blocker":
			out[item.grid_position] = true
	return out


func _build_wall_items_by_pos(layout_items: Array) -> Dictionary:
	var out: Dictionary = {}
	for item in layout_items:
		if item == null:
			continue
		var id := String(item.piece_id)
		if id.begins_with("wall_"):
			out[item.grid_position] = item
	return out


func _count_layout_sockets(room: RoomBase) -> int:
	if room.authored_layout == null:
		return 0
	var n := 0
	for item in room.authored_layout.items:
		if item == null:
			continue
		if item.piece_id == &"hall_socket_double" or item.piece_id == &"door_socket_standard":
			n += 1
	return n


func _room_rect(size: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(-size.x / 2, -size.y / 2), size)


func _is_solid_floor_cell(floor_lookup: Dictionary, opening_cells: Dictionary, cell: Vector2i) -> bool:
	return floor_lookup.has(cell) and not opening_cells.has(cell)


func _is_spacing_exempt_by_corner_sharing(a: Vector2i, b: Vector2i, corner_wall_cells: Dictionary) -> bool:
	for off_a in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var ca: Vector2i = a + off_a
		if not corner_wall_cells.has(ca):
			continue
		for off_b in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if b + off_b == ca:
				return true
	return false


func _validate_parallel_wall_spacing(floor_lookup: Dictionary, opening_cells: Dictionary) -> String:
	var wall_lookup: Dictionary = {}
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell in floor_lookup.keys():
		var should_wall := false
		for direction in directions:
			if not _is_solid_floor_cell(floor_lookup, opening_cells, cell + direction):
				should_wall = true
				break
		if should_wall and not opening_cells.has(cell):
			wall_lookup[cell] = true

	var corner_wall_cells: Dictionary = {}
	var north_walls: Dictionary = {}
	var south_walls: Dictionary = {}
	var west_walls: Dictionary = {}
	var east_walls: Dictionary = {}

	for cell in wall_lookup.keys():
		var has_left := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.LEFT)
		var has_right := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.RIGHT)
		var has_up := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.UP)
		var has_down := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.DOWN)
		var missing_left := not has_left
		var missing_right := not has_right
		var missing_up := not has_up
		var missing_down := not has_down
		var missing_count := int(missing_left) + int(missing_right) + int(missing_up) + int(missing_down)
		if missing_count == 2:
			corner_wall_cells[cell] = true
			continue
		if missing_count != 1:
			continue
		if missing_up:
			north_walls[cell] = true
		elif missing_down:
			south_walls[cell] = true
		elif missing_left:
			west_walls[cell] = true
		elif missing_right:
			east_walls[cell] = true

	for n in north_walls.keys():
		var x: int = n.x
		var y: int = n.y + 1
		while floor_lookup.has(Vector2i(x, y)):
			var cur: Vector2i = Vector2i(x, y)
			if south_walls.has(cur):
				var floor_gap: int = cur.y - n.y - 1
				var inner_face_gap: int = floor_gap + 1
				var exempt := _is_spacing_exempt_by_corner_sharing(n, cur, corner_wall_cells)
				if inner_face_gap < MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES and not exempt:
					return "Parallel wall spacing violation: gap=%s between %s and %s" % [inner_face_gap, n, cur]
				break
			y += 1

	for w in west_walls.keys():
		var y: int = w.y
		var x: int = w.x + 1
		while floor_lookup.has(Vector2i(x, y)):
			var cur: Vector2i = Vector2i(x, y)
			if east_walls.has(cur):
				var floor_gap: int = cur.x - w.x - 1
				var inner_face_gap: int = floor_gap + 1
				var exempt := _is_spacing_exempt_by_corner_sharing(w, cur, corner_wall_cells)
				if inner_face_gap < MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES and not exempt:
					return "Parallel wall spacing violation: gap=%s between %s and %s" % [inner_face_gap, w, cur]
				break
			x += 1
	return ""


func _validate_accessibility(floor_lookup: Dictionary, opening_cells: Dictionary, blocked_lookup: Dictionary) -> String:
	var walkable_count := 0
	for c in floor_lookup.keys():
		if not blocked_lookup.has(c):
			walkable_count += 1
	if walkable_count == 0:
		return "No walkable floor tiles."

	var start: Variant = null
	for oc in opening_cells.keys():
		if floor_lookup.has(oc) and not blocked_lookup.has(oc):
			start = oc
			break
	if start == null:
		for c in floor_lookup.keys():
			if not blocked_lookup.has(c):
				start = c
				break
	if start == null:
		return "No valid flood-fill start tile."

	var q: Array[Vector2i] = [start as Vector2i]
	var visited: Dictionary = {start: true}
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		for d in dirs:
			var nxt: Vector2i = cur + d
			if visited.has(nxt):
				continue
			if not floor_lookup.has(nxt):
				continue
			if blocked_lookup.has(nxt):
				continue
			visited[nxt] = true
			q.append(nxt)
	if visited.size() != walkable_count:
		return "Disconnected floor regions detected."
	return ""


func _missing_solid_neighbor_count(cell: Vector2i, floor_lookup: Dictionary, opening_cells: Dictionary) -> int:
	var n := 0
	for off in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _is_solid_floor_cell(floor_lookup, opening_cells, cell + off):
			n += 1
	return n


func _validate_inner_corners(
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	wall_items_by_pos: Dictionary,
) -> String:
	# 1) Any perimeter wall with exactly two orthogonal missing neighbors should be wall_corner.
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var wall_lookup: Dictionary = {}
	for cell in floor_lookup.keys():
		var should_wall := false
		for direction in directions:
			if not _is_solid_floor_cell(floor_lookup, opening_cells, cell + direction):
				should_wall = true
				break
		if should_wall and not opening_cells.has(cell):
			wall_lookup[cell] = true
	for cell in wall_lookup.keys():
		var has_left := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.LEFT)
		var has_right := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.RIGHT)
		var has_up := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.UP)
		var has_down := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.DOWN)
		var missing_left := not has_left
		var missing_right := not has_right
		var missing_up := not has_up
		var missing_down := not has_down
		var missing_count := int(missing_left) + int(missing_right) + int(missing_up) + int(missing_down)
		if missing_count != 2:
			continue
		var expected_rot := -1
		if missing_up and missing_right:
			expected_rot = 0
		elif missing_down and missing_right:
			expected_rot = 1
		elif missing_down and missing_left:
			expected_rot = 2
		elif missing_up and missing_left:
			expected_rot = 3
		if expected_rot < 0:
			continue
		if not wall_items_by_pos.has(cell):
			return "Missing wall piece at required corner cell %s" % [cell]
		var wi = wall_items_by_pos[cell]
		if wi.piece_id != &"wall_corner" or _normalized_rotation(wi) != expected_rot:
			return "Perimeter corner mismatch at %s (expected corner rot=%s)." % [cell, expected_rot]

	# 2) Interior concave notch fillers that generator requires.
	if floor_lookup.is_empty():
		return ""
	var min_x := 0
	var max_x := 0
	var min_y := 0
	var max_y := 0
	var first := true
	for c in floor_lookup.keys():
		if first:
			min_x = c.x
			max_x = c.x
			min_y = c.y
			max_y = c.y
			first = false
		else:
			min_x = mini(min_x, c.x)
			max_x = maxi(max_x, c.x)
			min_y = mini(min_y, c.y)
			max_y = maxi(max_y, c.y)
	for vx in range(min_x - 1, max_x + 2):
		for vy in range(min_y - 1, max_y + 2):
			var void_cell := Vector2i(vx, vy)
			if _is_solid_floor_cell(floor_lookup, opening_cells, void_cell):
				continue
			var tests := [
				{"corner": Vector2i(vx - 1, vy - 1), "a": Vector2i(vx - 1, vy), "b": Vector2i(vx, vy - 1), "rot": 1},
				{"corner": Vector2i(vx + 1, vy - 1), "a": Vector2i(vx + 1, vy), "b": Vector2i(vx, vy - 1), "rot": 2},
				{"corner": Vector2i(vx + 1, vy + 1), "a": Vector2i(vx + 1, vy), "b": Vector2i(vx, vy + 1), "rot": 3},
				{"corner": Vector2i(vx - 1, vy + 1), "a": Vector2i(vx - 1, vy), "b": Vector2i(vx, vy + 1), "rot": 0},
			]
			for t in tests:
				var corner: Vector2i = t["corner"] as Vector2i
				var a: Vector2i = t["a"] as Vector2i
				var b: Vector2i = t["b"] as Vector2i
				if not _is_solid_floor_cell(floor_lookup, opening_cells, corner):
					continue
				if opening_cells.has(corner):
					continue
				if wall_lookup.has(corner):
					continue
				if _missing_solid_neighbor_count(corner, floor_lookup, opening_cells) != 0:
					continue
				if not wall_lookup.has(a) or not wall_lookup.has(b):
					continue
				if not wall_items_by_pos.has(corner):
					return "Missing interior concave wall_corner at %s" % [corner]
				var wi = wall_items_by_pos[corner]
				if wi.piece_id != &"wall_corner" or _normalized_rotation(wi) != int(t["rot"]):
					return "Interior concave wall_corner rotation mismatch at %s" % [corner]
	return ""


func _validate_socket_alignment(room: RoomBase, floor_lookup: Dictionary, layout_items: Array) -> String:
	var rect := _room_rect(room.room_size_tiles)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	for item in layout_items:
		if item == null or item.piece_id != &"hall_socket_double":
			continue
		var rot := _normalized_rotation(item)
		var gp: Vector2i = item.grid_position
		var cells: Array[Vector2i] = [gp]
		if rot % 2 == 0:
			cells.append(gp + Vector2i.RIGHT)
		else:
			cells.append(gp + Vector2i.DOWN)
		for c in cells:
			if not floor_lookup.has(c):
				return "Socket at %s uses non-floor opening cell %s" % [gp, c]
		match rot:
			0:
				if not (cells[0].y == top and cells[1].y == top):
					return "North-facing socket at %s is not on north wall." % [gp]
			1:
				if not (cells[0].x == right and cells[1].x == right):
					return "East-facing socket at %s is not on east wall." % [gp]
			2:
				if not (cells[0].y == bottom and cells[1].y == bottom):
					return "South-facing socket at %s is not on south wall." % [gp]
			3:
				if not (cells[0].x == left and cells[1].x == left):
					return "West-facing socket at %s is not on west wall." % [gp]
			_:
				return "Invalid socket rotation at %s" % [gp]
	return ""


func _validate_room_requirements(room: RoomBase, room_path: String) -> String:
	if room.authored_layout == null:
		return "Room %s is missing authored_layout" % room_path
	var layout_items = room.authored_layout.get("items")
	if not (layout_items is Array) or (layout_items as Array).is_empty():
		return "Room %s has empty authored layout items" % room_path
	var items: Array = layout_items as Array
	var floor_lookup := _build_floor_lookup(items)
	var opening_cells := _opening_cells_from_sockets(items)
	var blocked_lookup := _build_blocked_lookup(items)
	var wall_items_by_pos := _build_wall_items_by_pos(items)

	if floor_lookup.is_empty():
		return "Room %s has no floor cells in authored layout." % room_path
	var socket_err := _validate_socket_alignment(room, floor_lookup, items)
	if socket_err != "":
		return socket_err
	var spacing_err := _validate_parallel_wall_spacing(floor_lookup, opening_cells)
	if spacing_err != "":
		return "Room %s: %s" % [room_path, spacing_err]
	var access_err := _validate_accessibility(floor_lookup, opening_cells, blocked_lookup)
	if access_err != "":
		return "Room %s: %s" % [room_path, access_err]
	var corner_err := _validate_inner_corners(floor_lookup, opening_cells, wall_items_by_pos)
	if corner_err != "":
		return "Room %s: %s" % [room_path, corner_err]
	return ""


func _validate_all() -> void:
	var room_paths := _collect_room_paths()
	if room_paths.is_empty():
		push_error("No room scenes found for validator run.")
		quit(1)
		return

	var root := Node.new()
	get_root().add_child(root)
	for room_path in room_paths:
		var scene := load(room_path) as PackedScene
		if scene == null:
			push_error("Failed to load %s" % room_path)
			quit(1)
			return
		var room = scene.instantiate()
		if room == null or not (room is RoomBase):
			push_error("Scene %s did not instantiate as RoomBase" % room_path)
			quit(1)
			return
		root.add_child(room)

		var requirement_err := _validate_room_requirements(room as RoomBase, room_path)
		if requirement_err != "":
			push_error(requirement_err)
			quit(1)
			return

		var zone_nodes := 0
		var layout_zone_markers := _count_layout_structural_markers(room)
		if layout_zone_markers < 3:
			push_error(
				"Room %s is missing structural zone markers (need 3+ in layout)" % room_path
			)
			quit(1)
			return
		var socket_count := _count_layout_sockets(room)
		if socket_count <= 0:
			push_error("Room %s is missing layout sockets." % room_path)
			quit(1)
			return
		print(
			"Validated %s | items=%s | sockets=%s | zones=%s | layout_structural=%s" % [
				room_path,
				(room.authored_layout.items as Array).size(),
				socket_count,
				zone_nodes,
				layout_zone_markers,
			]
		)
		room.queue_free()
	print("VALIDATED_OUTLINE_ROOMS_OK")
	quit()
