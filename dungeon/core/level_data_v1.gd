extends RefCounted
class_name LevelDataV1

const SCHEMA_VERSION := "level.v1"
const COORD_SPACE_GRID_ANCHOR := "room_anchor_grid_center"
const COORD_SPACE_LOCAL := "room_local_center_world"
const UNITS_WORLD := "world"

const ROOM_TYPES := {
	"start": true,
	"exit": true,
	"combat": true,
	"puzzle": true,
	"treasure": true,
	"trap": true,
	"challenge": true,
	"lore": true,
	"safe": true,
}

const CARDINALS := {
	"north": true,
	"south": true,
	"east": true,
	"west": true,
}

const GATE_TYPES := {
	"puzzle": true,
	"combat_clear": true,
	"key_item": true,
	"timed": true,
}

const ONE_DOOR_ALLOWED_ROOM_TYPES := {
	"start": true,
	"safe": true,
	"treasure": true,
	"exit": true,
	"boss": true,
}


static func from_layout(layout: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	var rooms: Array[Dictionary] = []
	for spec_variant in layout.get("room_specs", []) as Array:
		if spec_variant is not Dictionary:
			continue
		var spec := spec_variant as Dictionary
		var size := spec.get("size", Vector2i(9, 9)) as Vector2i
		var grid := spec.get("grid", Vector2i.ZERO) as Vector2i
		rooms.append({
			"id": String(spec.get("name", "")),
			"type": String(spec.get("kind", "combat")),
			"templateId": "room_%s_default" % [String(spec.get("kind", "combat"))],
			"gridPosition": {"x": grid.x, "y": grid.y},
			"sizeTiles": {"w": size.x, "h": size.y},
		})

	var doors: Array[Dictionary] = []
	for i in range((layout.get("links", []) as Array).size()):
		var link := (layout.get("links", []) as Array)[i] as Dictionary
		doors.append({
			"id": "D_%03d" % i,
			"fromRoomId": String(link.get("from", "")),
			"toRoomId": String(link.get("to", "")),
			"fromDir": String(link.get("from_dir", "")),
			"toDir": String(link.get("to_dir", "")),
			"widthTiles": 4,
		})

	var pathing := {
		"startRoomId": String(layout.get("start_room", "")),
		"exitRoomId": String(layout.get("exit_room", "")),
		"criticalPathRoomIds": layout.get("critical_path", []),
		"sideBranches": _to_side_branch_objects(layout.get("side_branches", []) as Array),
	}

	var out := {
		"schemaVersion": SCHEMA_VERSION,
		"level": {
			"levelId": String(metadata.get("levelId", "procedural_level")),
			"seed": int(metadata.get("seed", 0)),
			"difficulty": int(metadata.get("difficulty", 1)),
			"theme": String(metadata.get("theme", "default")),
			"coordinateSystem": {
				"gridPosition": {
					"meaning": COORD_SPACE_GRID_ANCHOR,
					"units": "grid_cells",
				},
				"localPosition": {
					"meaning": COORD_SPACE_LOCAL,
					"units": UNITS_WORLD,
				},
			},
		},
		"pathing": pathing,
		"rooms": rooms,
		"doors": doors,
		"encounters": [],
		"rewards": [],
		"hazards": [],
		"puzzles": [],
	}

	return out


static func validate(level_data: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if String(level_data.get("schemaVersion", "")) != SCHEMA_VERSION:
		errors.append("schemaVersion must be '%s'." % SCHEMA_VERSION)

	var rooms := level_data.get("rooms", []) as Array
	var doors := level_data.get("doors", []) as Array
	var pathing := level_data.get("pathing", {}) as Dictionary
	var encounters := level_data.get("encounters", []) as Array
	var rewards := level_data.get("rewards", []) as Array
	var hazards := level_data.get("hazards", []) as Array
	var puzzles := level_data.get("puzzles", []) as Array

	if rooms.is_empty():
		errors.append("rooms must not be empty.")
		return {"ok": false, "errors": errors}

	var room_ids: Dictionary = {}
	var room_types_by_id: Dictionary = {}
	for room_variant in rooms:
		if room_variant is not Dictionary:
			errors.append("rooms entries must be objects.")
			continue
		var room := room_variant as Dictionary
		var rid := String(room.get("id", ""))
		if rid.is_empty():
			errors.append("each room must have a non-empty id.")
			continue
		if room_ids.has(rid):
			errors.append("duplicate room id '%s'." % rid)
			continue
		room_ids[rid] = true
		var rtype := String(room.get("type", ""))
		room_types_by_id[rid] = rtype
		if not ROOM_TYPES.has(rtype):
			errors.append("room '%s' has invalid type '%s'." % [rid, rtype])

	var door_ids: Dictionary = {}
	for door_variant in doors:
		if door_variant is not Dictionary:
			errors.append("doors entries must be objects.")
			continue
		var door := door_variant as Dictionary
		var did := String(door.get("id", ""))
		if did.is_empty():
			errors.append("each door must have a non-empty id.")
			continue
		if door_ids.has(did):
			errors.append("duplicate door id '%s'." % did)
		door_ids[did] = true
		var from_room := String(door.get("fromRoomId", ""))
		var to_room := String(door.get("toRoomId", ""))
		if not room_ids.has(from_room):
			errors.append("door '%s' references unknown fromRoomId '%s'." % [did, from_room])
		if not room_ids.has(to_room):
			errors.append("door '%s' references unknown toRoomId '%s'." % [did, to_room])
		var from_dir := String(door.get("fromDir", ""))
		var to_dir := String(door.get("toDir", ""))
		if not CARDINALS.has(from_dir):
			errors.append("door '%s' has invalid fromDir '%s'." % [did, from_dir])
		if not CARDINALS.has(to_dir):
			errors.append("door '%s' has invalid toDir '%s'." % [did, to_dir])
		if from_room == to_room:
			errors.append("door '%s' cannot connect a room to itself." % did)

		var gate := door.get("gate", {}) as Dictionary
		if not gate.is_empty():
			var gate_type := String(gate.get("type", ""))
			if not GATE_TYPES.has(gate_type):
				errors.append("door '%s' gate type '%s' is invalid." % [did, gate_type])
			if gate_type == "puzzle":
				var pid := String(gate.get("puzzleId", ""))
				if pid.is_empty():
					errors.append("door '%s' puzzle gate requires puzzleId." % did)

	var puzzle_ids: Dictionary = {}
	for puzzle_variant in puzzles:
		if puzzle_variant is not Dictionary:
			errors.append("puzzles entries must be objects.")
			continue
		var puzzle := puzzle_variant as Dictionary
		var pid := String(puzzle.get("id", ""))
		if pid.is_empty():
			errors.append("each puzzle must have a non-empty id.")
			continue
		if puzzle_ids.has(pid):
			errors.append("duplicate puzzle id '%s'." % pid)
		puzzle_ids[pid] = true
		var room_id := String(puzzle.get("roomId", ""))
		if not room_ids.has(room_id):
			errors.append("puzzle '%s' references unknown roomId '%s'." % [pid, room_id])
		var effects := puzzle.get("effects", []) as Array
		for effect_variant in effects:
			if effect_variant is not Dictionary:
				errors.append("puzzle '%s' has non-object effect." % pid)
				continue
			var effect := effect_variant as Dictionary
			var effect_type := String(effect.get("type", ""))
			if effect_type == "unlock_door":
				var target_door_id := String(effect.get("doorId", ""))
				if not door_ids.has(target_door_id):
					errors.append("puzzle '%s' effect references unknown doorId '%s'." % [pid, target_door_id])

	for door_variant in doors:
		if door_variant is not Dictionary:
			continue
		var door := door_variant as Dictionary
		var did := String(door.get("id", ""))
		var gate := door.get("gate", {}) as Dictionary
		if gate.is_empty():
			continue
		var gate_type := String(gate.get("type", ""))
		if gate_type == "puzzle":
			var gate_pid := String(gate.get("puzzleId", ""))
			if not puzzle_ids.has(gate_pid):
				errors.append("door '%s' gate references unknown puzzleId '%s'." % [did, gate_pid])

	var start_room_id := String(pathing.get("startRoomId", ""))
	var exit_room_id := String(pathing.get("exitRoomId", ""))
	if not room_ids.has(start_room_id):
		errors.append("pathing.startRoomId '%s' does not exist in rooms." % start_room_id)
	if not room_ids.has(exit_room_id):
		errors.append("pathing.exitRoomId '%s' does not exist in rooms." % exit_room_id)

	var critical_path := pathing.get("criticalPathRoomIds", []) as Array
	for rid_variant in critical_path:
		var rid := String(rid_variant)
		if not room_ids.has(rid):
			errors.append("pathing.criticalPathRoomIds contains unknown room id '%s'." % rid)

	var side_branches := pathing.get("sideBranches", []) as Array
	for br_variant in side_branches:
		if br_variant is not Dictionary:
			errors.append("pathing.sideBranches entries must be objects.")
			continue
		var br := br_variant as Dictionary
		var parent_room_id := String(br.get("parentRoomId", ""))
		if not room_ids.has(parent_room_id):
			errors.append("side branch parentRoomId '%s' does not exist." % parent_room_id)
		var room_list := br.get("roomIds", []) as Array
		for room_id_variant in room_list:
			var br_room_id := String(room_id_variant)
			if not room_ids.has(br_room_id):
				errors.append("side branch references unknown room id '%s'." % br_room_id)

	_validate_room_ref_array(encounters, room_ids, "encounters", errors)
	_validate_room_ref_array(rewards, room_ids, "rewards", errors)
	_validate_room_ref_array(hazards, room_ids, "hazards", errors)
	_validate_room_ref_array(puzzles, room_ids, "puzzles", errors)

	# Doors are the canonical source for physical adjacency.
	var adjacency := _adjacency_from_doors(doors)
	if not _is_connected_graph(room_ids.keys(), adjacency):
		errors.append("door graph is not fully connected.")
	if _count_paths(start_room_id, exit_room_id, adjacency, 2) != 1:
		errors.append("door graph must have exactly one path from startRoomId to exitRoomId.")
	for rid in room_ids.keys():
		var room_id := String(rid)
		var room_type := String(room_types_by_id.get(room_id, ""))
		var degree := (adjacency.get(room_id, []) as Array).size()
		if degree == 0:
			errors.append("room '%s' has no door connections." % room_id)
			continue
		if degree == 1 and not ONE_DOOR_ALLOWED_ROOM_TYPES.has(room_type):
			errors.append(
				"room '%s' type '%s' cannot be a dead-end (1 door). Only start/safe/treasure/exit/boss may have degree 1." % [
					room_id,
					room_type,
				]
			)

	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_room_ref_array(items: Array, room_ids: Dictionary, label: String, errors: Array[String]) -> void:
	for item_variant in items:
		if item_variant is not Dictionary:
			errors.append("%s entries must be objects." % label)
			continue
		var item := item_variant as Dictionary
		var room_id := String(item.get("roomId", ""))
		if room_id.is_empty():
			errors.append("%s entry missing roomId." % label)
			continue
		if not room_ids.has(room_id):
			errors.append("%s entry references unknown roomId '%s'." % [label, room_id])


static func _adjacency_from_doors(doors: Array) -> Dictionary:
	var out: Dictionary = {}
	for door_variant in doors:
		if door_variant is not Dictionary:
			continue
		var door := door_variant as Dictionary
		var a := String(door.get("fromRoomId", ""))
		var b := String(door.get("toRoomId", ""))
		if a.is_empty() or b.is_empty():
			continue
		if not out.has(a):
			out[a] = []
		if not out.has(b):
			out[b] = []
		(out[a] as Array).append(b)
		(out[b] as Array).append(a)
	return out


static func _is_connected_graph(room_ids: Array, adjacency: Dictionary) -> bool:
	if room_ids.is_empty():
		return false
	var start := String(room_ids[0])
	var seen: Dictionary = {}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var cur := String(queue.pop_front())
		if seen.has(cur):
			continue
		seen[cur] = true
		for next_room in adjacency.get(cur, []) as Array:
			var n := String(next_room)
			if not seen.has(n):
				queue.append(n)
	return seen.size() == room_ids.size()


static func _count_paths(start_room_id: String, exit_room_id: String, adjacency: Dictionary, cap: int) -> int:
	var seen: Dictionary = {}
	return _dfs_paths(start_room_id, exit_room_id, adjacency, seen, cap)


static func _dfs_paths(
	cur_room_id: String, target_room_id: String, adjacency: Dictionary, seen: Dictionary, cap: int
) -> int:
	if cap <= 0:
		return cap
	if cur_room_id == target_room_id:
		return 1
	seen[cur_room_id] = true
	var total := 0
	for next_room in adjacency.get(cur_room_id, []) as Array:
		var n := String(next_room)
		if seen.has(n):
			continue
		total += _dfs_paths(n, target_room_id, adjacency, seen, cap - total)
		if total >= cap:
			seen.erase(cur_room_id)
			return total
	seen.erase(cur_room_id)
	return total


static func _to_side_branch_objects(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for branch_variant in raw:
		if branch_variant is Array:
			var b := branch_variant as Array
			if b.size() >= 2:
				out.append({
					"parentRoomId": String(b[0]),
					"roomIds": [String(b[1])],
				})
	return out
