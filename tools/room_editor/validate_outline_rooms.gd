@tool
extends SceneTree

const OUTLINES_ROOT := "res://dungeon/rooms/authored/outlines"
const MIN_PARALLEL_WALL_FLOOR_GAP_TILES := 3

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


func _connection_marker_cells(item) -> Array[Vector2i]:
	var gp: Vector2i = item.grid_position
	var rot := _normalized_rotation(item)
	if item.piece_id == &"entrance_marker" or item.piece_id == &"exit_marker":
		match rot:
			0:
				return [gp, gp + Vector2i.RIGHT, gp + Vector2i(2, 0)]
			1:
				return [gp, gp + Vector2i.DOWN, gp + Vector2i(0, 2)]
			2:
				return [gp, gp + Vector2i.RIGHT, gp + Vector2i(2, 0)]
			_:
				return [gp, gp + Vector2i(0, 1), gp + Vector2i(0, 2)]
	if item.piece_id == &"hall_socket_triple":
		if rot % 2 == 0:
			return [gp, gp + Vector2i.RIGHT, gp + Vector2i(2, 0)]
		return [gp, gp + Vector2i.DOWN, gp + Vector2i(0, 2)]
	if item.piece_id == &"hall_socket_double":
		if rot % 2 == 0:
			return [gp, gp + Vector2i.RIGHT]
		return [gp, gp + Vector2i.DOWN]
	return []


func _hallway_mouth_geometry(item) -> Dictionary:
	if item == null:
		return {}
	if item.piece_id != &"entrance_marker" and item.piece_id != &"exit_marker":
		return {}
	var gp: Vector2i = item.grid_position
	var rot := _normalized_rotation(item)
	var opening: Array[Vector2i] = []
	var passage: Array[Vector2i] = []
	var support_floor: Array[Vector2i] = []
	var flank_walls: Array[Vector2i] = []
	var boundary_walls: Array[Vector2i] = []
	var support_corners: Array[Vector2i] = []
	var apron: Array[Vector2i] = []
	match rot:
		0:
			for dx in range(0, 3):
				opening.append(gp + Vector2i(dx, 0))
				passage.append(gp + Vector2i(dx, 1))
				support_floor.append(gp + Vector2i(dx, 2))
			boundary_walls = [gp + Vector2i(-1, 0), gp + Vector2i(3, 0)]
			flank_walls = [gp + Vector2i(-1, 1), gp + Vector2i(3, 1)]
			support_corners = [gp + Vector2i(-1, 2), gp + Vector2i(3, 2)]
			for dx in range(-2, 5):
				apron.append(gp + Vector2i(dx, 3))
		1:
			for dy in range(0, 3):
				opening.append(gp + Vector2i(0, dy))
				passage.append(gp + Vector2i(-1, dy))
				support_floor.append(gp + Vector2i(-2, dy))
			boundary_walls = [gp + Vector2i(0, -1), gp + Vector2i(0, 3)]
			flank_walls = [gp + Vector2i(-1, -1), gp + Vector2i(-1, 3)]
			support_corners = [gp + Vector2i(-2, -1), gp + Vector2i(-2, 3)]
			for dy in range(-2, 5):
				apron.append(gp + Vector2i(-3, dy))
		2:
			for dx in range(0, 3):
				opening.append(gp + Vector2i(dx, 0))
				passage.append(gp + Vector2i(dx, -1))
				support_floor.append(gp + Vector2i(dx, -2))
			boundary_walls = [gp + Vector2i(-1, 0), gp + Vector2i(3, 0)]
			flank_walls = [gp + Vector2i(-1, -1), gp + Vector2i(3, -1)]
			support_corners = [gp + Vector2i(-1, -2), gp + Vector2i(3, -2)]
			for dx in range(-2, 5):
				apron.append(gp + Vector2i(dx, -3))
		_:
			for dy in range(0, 3):
				opening.append(gp + Vector2i(0, dy))
				passage.append(gp + Vector2i(1, dy))
				support_floor.append(gp + Vector2i(2, dy))
			boundary_walls = [gp + Vector2i(0, -1), gp + Vector2i(0, 3)]
			flank_walls = [gp + Vector2i(1, -1), gp + Vector2i(1, 3)]
			support_corners = [gp + Vector2i(2, -1), gp + Vector2i(2, 3)]
			for dy in range(-2, 5):
				apron.append(gp + Vector2i(3, dy))
	return {
		"opening": opening,
		"passage": passage,
		"support_floor": support_floor,
		"boundary_walls": boundary_walls,
		"flank_walls": flank_walls,
		"support_corners": support_corners,
		"apron": apron,
	}


func _opening_cells_from_markers(layout_items: Array) -> Dictionary:
	var cells: Dictionary = {}
	for item in layout_items:
		if item == null:
			continue
		for c in _connection_marker_cells(item):
			cells[c] = true
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


func _count_layout_markers(room: RoomBase) -> int:
	if room.authored_layout == null:
		return 0
	var n := 0
	for item in room.authored_layout.items:
		if item == null:
			continue
		if item.piece_id == &"hall_socket_triple" or item.piece_id == &"hall_socket_double" or item.piece_id == &"door_socket_standard" or item.piece_id == &"entrance_marker" or item.piece_id == &"exit_marker":
			n += 1
	return n


func _room_rect(size: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(-size.x / 2, -size.y / 2), size)


func _is_solid_floor_cell(floor_lookup: Dictionary, opening_cells: Dictionary, cell: Vector2i) -> bool:
	return floor_lookup.has(cell) and not opening_cells.has(cell)


func _validate_parallel_wall_spacing(floor_lookup: Dictionary, opening_cells: Dictionary) -> String:
	for cell in floor_lookup.keys():
		var c := cell as Vector2i
		if opening_cells.has(c):
			continue
		var horizontal_gap := _parallel_floor_gap_for_axis(c, floor_lookup, opening_cells, true)
		if horizontal_gap >= 0 and horizontal_gap < MIN_PARALLEL_WALL_FLOOR_GAP_TILES:
			return "Parallel wall spacing violation (horizontal floor gap=%s) at %s" % [horizontal_gap, c]
		var vertical_gap := _parallel_floor_gap_for_axis(c, floor_lookup, opening_cells, false)
		if vertical_gap >= 0 and vertical_gap < MIN_PARALLEL_WALL_FLOOR_GAP_TILES:
			return "Parallel wall spacing violation (vertical floor gap=%s) at %s" % [vertical_gap, c]
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


func _parallel_floor_gap_for_axis(
	cell: Vector2i,
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	horizontal_scan: bool
) -> int:
	if not _is_solid_floor_cell(floor_lookup, opening_cells, cell):
		return -1
	var neg := Vector2i.LEFT if horizontal_scan else Vector2i.UP
	var pos := Vector2i.RIGHT if horizontal_scan else Vector2i.DOWN
	var span := 1
	var cur := cell + neg
	while _is_solid_floor_cell(floor_lookup, opening_cells, cur):
		span += 1
		cur += neg
	var neg_wall := not _is_solid_floor_cell(floor_lookup, opening_cells, cur)
	cur = cell + pos
	while _is_solid_floor_cell(floor_lookup, opening_cells, cur):
		span += 1
		cur += pos
	var pos_wall := not _is_solid_floor_cell(floor_lookup, opening_cells, cur)
	if neg_wall and pos_wall:
		return span
	return -1


func _validate_inner_corners(
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	wall_items_by_pos: Dictionary,
	exempt_cells: Dictionary = {},
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
		if exempt_cells.has(cell):
			continue
		if not wall_items_by_pos.has(cell):
			continue
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
				if exempt_cells.has(corner):
					continue
				if wall_lookup.has(corner):
					continue
				if _missing_solid_neighbor_count(corner, floor_lookup, opening_cells) != 0:
					continue
				if not wall_lookup.has(a) or not wall_lookup.has(b):
					continue
				if not wall_items_by_pos.has(corner):
					continue
				var wi = wall_items_by_pos[corner]
				if wi.piece_id != &"wall_corner" or _normalized_rotation(wi) != int(t["rot"]):
					return "Interior concave wall_corner rotation mismatch at %s" % [corner]
	return ""


func _validate_marker_alignment(
	room: RoomBase,
	floor_lookup: Dictionary,
	layout_items: Array,
	wall_items_by_pos: Dictionary
) -> String:
	for item in layout_items:
		if item == null:
			continue
		var gp: Vector2i = item.grid_position
		var rot := _normalized_rotation(item)
		var geometry := _hallway_mouth_geometry(item)
		var opening_cells: Array = geometry.get("opening", [])
		if opening_cells.is_empty():
			continue
		for c in opening_cells:
			if not floor_lookup.has(c):
				return "Connection marker at %s uses non-floor opening cell %s" % [gp, c]
		for c in geometry.get("passage", []):
			if not floor_lookup.has(c):
				return "Connection marker at %s is missing passage floor cell %s" % [gp, c]
		for c in geometry.get("support_floor", []):
			if not floor_lookup.has(c):
				return "Connection marker at %s is missing support floor cell %s" % [gp, c]
		for c in geometry.get("apron", []):
			if not floor_lookup.has(c):
				return "Connection marker at %s is missing interior apron floor cell %s" % [gp, c]
		for c in geometry.get("boundary_walls", []):
			if not wall_items_by_pos.has(c):
				return "Connection marker at %s is missing outer straight wall cell %s" % [gp, c]
			var boundary_wall = wall_items_by_pos[c]
			if boundary_wall.piece_id != &"wall_straight":
				return "Connection marker at %s requires wall_straight at outer wall cell %s" % [gp, c]
		for c in geometry.get("flank_walls", []):
			if not wall_items_by_pos.has(c):
				return "Connection marker at %s is missing flank wall cell %s" % [gp, c]
		for c in geometry.get("support_corners", []):
			if not wall_items_by_pos.has(c):
				return "Connection marker at %s is missing support corner cell %s" % [gp, c]
			var wall_item = wall_items_by_pos[c]
			if wall_item.piece_id != &"wall_corner":
				return "Connection marker at %s requires wall_corner at %s" % [gp, c]
		if rot < 0 or rot > 3:
			return "Invalid connection marker rotation at %s" % [gp]
	return ""


func _validate_marker_counts(room: RoomBase, layout_items: Array) -> String:
	var entrances := 0
	var exits := 0
	for item in layout_items:
		if item == null:
			continue
		if item.piece_id == &"entrance_marker":
			entrances += 1
		elif item.piece_id == &"exit_marker":
			exits += 1
	match String(room.room_type):
		"treasure", "boss":
			if entrances != 1 or exits != 0:
				return "Expected treasure/boss room to have exactly one entrance marker."
		"safe":
			if entrances != 0 or exits != 1:
				return "Expected safe room to have exactly one exit marker."
		_:
			if entrances != 1 or exits != 1:
				return "Expected room to have exactly one entrance marker and one exit marker."
	return ""


func _validate_no_hanging_walls(
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	wall_items_by_pos: Dictionary,
	exempt_cells: Dictionary = {}
) -> String:
	# Flood-fill from center to find the main reachable floor region, then check
	# that every wall piece sits on a reachable floor tile.
	if floor_lookup.is_empty():
		return ""
	var start: Variant = null
	var best_score: int = 1_000_000_000
	for cell in floor_lookup.keys():
		if opening_cells.has(cell):
			continue
		var c: Vector2i = cell
		var score: int = abs(c.x) + abs(c.y)
		if score < best_score:
			best_score = score
			start = c
	if start == null:
		for cell in floor_lookup.keys():
			start = cell
			break
	if start == null:
		return ""
	var q: Array[Vector2i] = [start as Vector2i]
	var reachable: Dictionary = {start: true}
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		for d in dirs:
			var nxt: Vector2i = cur + d
			if reachable.has(nxt):
				continue
			if not floor_lookup.has(nxt):
				continue
			reachable[nxt] = true
			q.append(nxt)
	for pos in wall_items_by_pos.keys():
		if exempt_cells.has(pos):
			continue
		if not reachable.has(pos):
			return "Hanging wall at %s: wall piece on unreachable floor tile." % [pos]
	return ""


func _validate_room_requirements(room: RoomBase, room_path: String) -> String:
	if room.authored_layout == null:
		return "Room %s is missing authored_layout" % room_path
	var layout_items = room.authored_layout.get("items")
	if not (layout_items is Array) or (layout_items as Array).is_empty():
		return "Room %s has empty authored layout items" % room_path
	var items: Array = layout_items as Array
	var floor_lookup := _build_floor_lookup(items)
	var opening_cells := _opening_cells_from_markers(items)
	var blocked_lookup := _build_blocked_lookup(items)
	var wall_items_by_pos := _build_wall_items_by_pos(items)
	var mouth_exempt_cells: Dictionary = {}
	for item in items:
		if item == null:
			continue
		var geometry := _hallway_mouth_geometry(item)
		for c in geometry.get("boundary_walls", []):
			mouth_exempt_cells[c] = true
		for c in geometry.get("flank_walls", []):
			mouth_exempt_cells[c] = true
		for c in geometry.get("support_corners", []):
			mouth_exempt_cells[c] = true

	if floor_lookup.is_empty():
		return "Room %s has no floor cells in authored layout." % room_path
	var marker_err := _validate_marker_alignment(room, floor_lookup, items, wall_items_by_pos)
	if marker_err != "":
		return marker_err
	var marker_count_err := _validate_marker_counts(room, items)
	if marker_count_err != "":
		return "Room %s: %s" % [room_path, marker_count_err]
	var spacing_err := _validate_parallel_wall_spacing(floor_lookup, opening_cells)
	if spacing_err != "":
		return "Room %s: %s" % [room_path, spacing_err]
	var access_err := _validate_accessibility(floor_lookup, opening_cells, blocked_lookup)
	if access_err != "":
		return "Room %s: %s" % [room_path, access_err]
	var corner_err := _validate_inner_corners(floor_lookup, opening_cells, wall_items_by_pos, mouth_exempt_cells)
	if corner_err != "":
		return "Room %s: %s" % [room_path, corner_err]
	var hanging_err := _validate_no_hanging_walls(floor_lookup, opening_cells, wall_items_by_pos, mouth_exempt_cells)
	if hanging_err != "":
		return "Room %s: %s" % [room_path, hanging_err]
	return ""


func _validate_all() -> void:
	var room_paths := _collect_room_paths()
	if room_paths.is_empty():
		push_error("No room scenes found for validator run.")
		quit(1)
		return

	for room_path in room_paths:
		var scene := ResourceLoader.load(
			room_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		) as PackedScene
		if scene == null:
			push_error("Failed to load %s" % room_path)
			quit(1)
			return
		var room = scene.instantiate()
		if room == null or not (room is RoomBase):
			if room is Node:
				(room as Node).free()
			push_error("Scene %s did not instantiate as RoomBase" % room_path)
			quit(1)
			return

		var requirement_err := _validate_room_requirements(room as RoomBase, room_path)
		if requirement_err != "":
			room.free()
			push_error(requirement_err)
			quit(1)
			return

		var zone_nodes := 0
		var layout_zone_markers := _count_layout_structural_markers(room)
		if layout_zone_markers < 3:
			room.free()
			push_error(
				"Room %s is missing structural zone markers (need 3+ in layout)" % room_path
			)
			quit(1)
			return
		var marker_count := _count_layout_markers(room)
		if marker_count <= 0:
			room.free()
			push_error("Room %s is missing layout connection markers." % room_path)
			quit(1)
			return
		print(
			"Validated %s | items=%s | markers=%s | zones=%s | layout_structural=%s" % [
				room_path,
				(room.authored_layout.items as Array).size(),
				marker_count,
				zone_nodes,
				layout_zone_markers,
			]
		)
		room.free()
	print("VALIDATED_OUTLINE_ROOMS_OK")
	quit()
