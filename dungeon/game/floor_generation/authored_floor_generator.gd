extends RefCounted
class_name AuthoredFloorGenerator

const RoomPlacementValidatorScript = preload("res://dungeon/game/floor_generation/room_placement_validator.gd")
const RoomTransformUtilsScript = preload("res://dungeon/game/floor_generation/room_transform_utils.gd")


func generate_floor(catalog, rng: RandomNumberGenerator, config: Dictionary = {}) -> Dictionary:
	if catalog == null:
		return _failed_layout({}, [{"reason": "missing_catalog"}])
	var all_rooms = catalog.all_rooms()
	if all_rooms.is_empty():
		catalog.build()
		all_rooms = catalog.all_rooms()
	if all_rooms.is_empty():
		return _failed_layout({}, [{"reason": "empty_catalog"}])

	var min_rooms := int(config.get("min_rooms", 7))
	var max_rooms := int(config.get("max_rooms", 9))
	var max_attempts := int(config.get("max_floor_attempts", 20))
	var aggregate_failures := {}
	var attempt_debug: Array[Dictionary] = []

	for attempt_index in range(max_attempts):
		var total_rooms := rng.randi_range(min_rooms, max_rooms)
		var role_sequence := _build_role_sequence(total_rooms, rng)
		var attempt_result := _attempt_sequence(catalog, rng, role_sequence)
		attempt_debug.append(
			{
				"attempt": attempt_index + 1,
				"total_rooms": total_rooms,
				"roles": role_sequence,
				"ok": bool(attempt_result.get("ok", false)),
				"failure_buckets": attempt_result.get("failure_buckets", {}),
			}
		)
		_merge_failure_buckets(aggregate_failures, attempt_result.get("failure_buckets", {}) as Dictionary)
		if bool(attempt_result.get("ok", false)):
			var layout := _build_layout_from_placed(
				attempt_result.get("placed_specs", []) as Array,
				attempt_result.get("links", []) as Array,
				role_sequence,
				aggregate_failures,
				attempt_debug
			)
			layout["ok"] = true
			return layout
	return _failed_layout(aggregate_failures, attempt_debug)


func _attempt_sequence(catalog, rng: RandomNumberGenerator, role_sequence: Array[String]) -> Dictionary:
	var failure_buckets := {}
	var spawn_pool: Array = catalog.rooms_for_role("spawn")
	var boss_pool: Array = catalog.rooms_for_role("boss")
	if spawn_pool.is_empty():
		_increment_bucket(failure_buckets, "missing_spawn_pool")
		return {"ok": false, "failure_buckets": failure_buckets}
	if boss_pool.is_empty():
		_increment_bucket(failure_buckets, "missing_boss_pool")
		return {"ok": false, "failure_buckets": failure_buckets}

	var spawn_candidates := spawn_pool.duplicate()
	spawn_candidates.shuffle()
	for spawn_room_data in spawn_candidates:
		var spawn_rotations := _shuffled_rotations(spawn_room_data.allowed_rotations, rng)
		for rotation_deg in spawn_rotations:
			var spawn_spec := _make_placed_spec(spawn_room_data, 0, Vector2i.ZERO, rotation_deg)
			var placed_specs: Array = [spawn_spec]
			var used_paths := {spawn_room_data.scene_path: true}
			var links: Array[Dictionary] = []
			if _place_next_room(1, role_sequence, catalog, rng, placed_specs, links, used_paths, failure_buckets):
				return {
					"ok": true,
					"placed_specs": placed_specs,
					"links": links,
					"failure_buckets": failure_buckets,
				}
	_increment_bucket(failure_buckets, "spawn_exhausted")
	return {"ok": false, "failure_buckets": failure_buckets}


func _place_next_room(
	index: int,
	role_sequence: Array[String],
	catalog,
	rng: RandomNumberGenerator,
	placed_specs: Array,
	links: Array[Dictionary],
	used_paths: Dictionary,
	failure_buckets: Dictionary
) -> bool:
	if index >= role_sequence.size():
		return true
	var current_spec := placed_specs[placed_specs.size() - 1] as Dictionary
	var current_room_data = current_spec.get("room_data")
	var current_exit_markers = current_room_data.exit_markers()
	if current_exit_markers.is_empty():
		_increment_bucket(failure_buckets, "no_exit_marker")
		return false

	var requested_role := role_sequence[index]
	var candidate_rooms := _candidate_pool_for_role(catalog, requested_role, rng, used_paths)
	if candidate_rooms.is_empty():
		_increment_bucket(failure_buckets, "empty_pool_%s" % requested_role)
		return false

	for anchor_exit in current_exit_markers:
		for candidate_room_data in candidate_rooms:
			var entrance_markers = candidate_room_data.entrance_markers()
			if entrance_markers.is_empty():
				_increment_bucket(failure_buckets, "missing_entrance_marker")
				continue
			var rotations := _shuffled_rotations(candidate_room_data.allowed_rotations, rng)
			for candidate_rotation in rotations:
				for candidate_entrance in entrance_markers:
					if not RoomPlacementValidatorScript.markers_are_compatible(
						anchor_exit,
						int(current_spec.get("rotation_deg", 0)),
						candidate_entrance,
						candidate_rotation
					):
						_increment_bucket(failure_buckets, "no_compatible_marker")
						continue
					var candidate_center := RoomPlacementValidatorScript.solve_candidate_center_cell(
						current_spec.get("center_cell", Vector2i.ZERO) as Vector2i,
						anchor_exit,
						int(current_spec.get("rotation_deg", 0)),
						current_room_data.tile_size,
						candidate_entrance,
						candidate_rotation,
						candidate_room_data.tile_size
					)
					var allowed_overlap_keys := RoomPlacementValidatorScript.allowed_overlap_lookup(
						current_spec.get("center_cell", Vector2i.ZERO) as Vector2i,
						anchor_exit,
						int(current_spec.get("rotation_deg", 0)),
						candidate_center,
						candidate_entrance,
						candidate_rotation
					)
					var placement := RoomPlacementValidatorScript.placement_fits(
						candidate_room_data,
						candidate_center,
						candidate_rotation,
						placed_specs,
						allowed_overlap_keys
					)
					if not bool(placement.get("ok", false)):
						_increment_bucket(failure_buckets, String(placement.get("reason", "placement_failed")))
						continue
					var placed_spec := _make_placed_spec(candidate_room_data, index, candidate_center, candidate_rotation)
					placed_spec["occupied_lookup"] = placement.get("occupied_lookup", {})
					placed_spec["connected_from"] = String(current_spec.get("name", ""))
					placed_specs.append(placed_spec)
					used_paths[candidate_room_data.scene_path] = true
					var link := {
						"from": String(current_spec.get("name", "")),
						"to": String(placed_spec.get("name", "")),
						"from_dir": RoomTransformUtilsScript.rotate_direction(
							String(anchor_exit.get("direction", "")),
							int(current_spec.get("rotation_deg", 0))
						),
						"to_dir": RoomTransformUtilsScript.rotate_direction(
							String(candidate_entrance.get("direction", "")),
							candidate_rotation
						),
					}
					links.append(link)
					current_spec["connected_to"] = String(placed_spec.get("name", ""))
					placed_specs[placed_specs.size() - 2] = current_spec
					if _place_next_room(
						index + 1,
						role_sequence,
						catalog,
						rng,
						placed_specs,
						links,
						used_paths,
						failure_buckets
					):
						return true
					links.remove_at(links.size() - 1)
					placed_specs.remove_at(placed_specs.size() - 1)
	_increment_bucket(failure_buckets, "exhausted_pool_%s" % requested_role)
	return false


func _build_role_sequence(total_rooms: int, rng: RandomNumberGenerator) -> Array[String]:
	var sequence: Array[String] = ["spawn"]
	var encounter_toggle := rng.randi_range(0, 1)
	for path_index in range(1, total_rooms - 1):
		if path_index % 2 == 1:
			sequence.append("connector")
		else:
			sequence.append("chokepoint" if encounter_toggle % 2 == 0 else "combat")
			encounter_toggle += 1
	sequence.append("boss")
	return sequence


func _candidate_pool_for_role(
	catalog,
	role: String,
	rng: RandomNumberGenerator,
	used_paths: Dictionary
) -> Array:
	var fresh: Array = []
	var reused: Array = []
	var roles: Array[String] = [role]
	if role == "combat" or role == "chokepoint":
		roles = [role, "combat" if role == "chokepoint" else "chokepoint"]
	for lookup_role in roles:
		for room_data in catalog.rooms_for_role(lookup_role):
			if used_paths.has(room_data.scene_path):
				reused.append(room_data)
			else:
				fresh.append(room_data)
	fresh.shuffle()
	reused.shuffle()
	var out: Array = []
	out.append_array(fresh)
	out.append_array(reused)
	return out


func _make_placed_spec(room_data, index: int, center_cell: Vector2i, rotation_deg: int) -> Dictionary:
	var name := "%s_%02d" % [_scene_base_name(room_data.scene_path), index]
	var occupied_lookup := RoomPlacementValidatorScript.world_occupied_lookup(room_data, center_cell, rotation_deg)
	return {
		"name": name,
		"room_instance_id": name,
		"room_data": room_data,
		"center_cell": center_cell,
		"rotation_deg": rotation_deg,
		"connected_from": "",
		"connected_to": "",
		"occupied_lookup": occupied_lookup,
	}


func _build_layout_from_placed(
	placed_specs: Array,
	links: Array,
	role_sequence: Array[String],
	failure_buckets: Dictionary,
	attempt_debug: Array[Dictionary]
) -> Dictionary:
	var room_specs: Array[Dictionary] = []
	var critical_path: Array[String] = []
	var combat_room_name := ""
	var combat_entry_dir := "west"
	var combat_exit_dir := "east"
	var boss_room_name := ""
	var boss_entry_dir := "west"
	var start_room_name := ""

	for placed in placed_specs:
		var spec := placed as Dictionary
		var room_data = spec.get("room_data")
		var center_cell := spec.get("center_cell", Vector2i.ZERO) as Vector2i
		var rotation_deg := int(spec.get("rotation_deg", 0))
		var connection_markers := RoomPlacementValidatorScript.world_connection_markers(
			room_data,
			center_cell,
			rotation_deg
		)
		var zone_markers := RoomPlacementValidatorScript.world_zone_markers(room_data, center_cell, rotation_deg)
		var world_position := Vector2(center_cell * room_data.tile_size)
		var occupied_cells := []
		for cell in spec.get("occupied_lookup", {}).values():
			occupied_cells.append(cell)
		occupied_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		)
		var walkable_cells := RoomPlacementValidatorScript.world_walkable_cells(room_data, center_cell, rotation_deg)
		var blocked_cells := RoomPlacementValidatorScript.world_blocked_cells(room_data, center_cell, rotation_deg)
		var role := String(room_data.role)
		var room_name := String(spec.get("name", ""))
		critical_path.append(room_name)
		if role == "spawn":
			start_room_name = room_name
		if role == "boss":
			boss_room_name = room_name
		if combat_room_name.is_empty() and (role == "combat" or role == "chokepoint"):
			combat_room_name = room_name
		room_specs.append(
			{
				"name": room_name,
				"room_instance_id": room_name,
				"scene_path": room_data.scene_path,
				"room_id": room_data.room_id,
				"role": role,
				"room_type": _runtime_room_type_for_role(role),
				"room_tags": room_data.room_tags.duplicate(),
				"rotation_deg": rotation_deg,
				"grid": center_cell,
				"world_position": world_position,
				"tile_size": room_data.tile_size,
				"occupied_cells": occupied_cells,
				"blocked_cells": blocked_cells,
				"walkable_cells": walkable_cells,
				"connection_markers": connection_markers,
				"zone_markers": zone_markers,
				"connected_from": String(spec.get("connected_from", "")),
				"connected_to": String(spec.get("connected_to", "")),
			}
		)

	for link_value in links:
		var link := link_value as Dictionary
		if String(link.get("to", "")) == combat_room_name:
			combat_entry_dir = String(link.get("to_dir", "west"))
		if String(link.get("from", "")) == combat_room_name:
			combat_exit_dir = String(link.get("from_dir", "east"))
		if String(link.get("to", "")) == boss_room_name:
			boss_entry_dir = String(link.get("to_dir", "west"))

	return {
		"generator_mode": "authored_rooms",
		"room_specs": room_specs,
		"links": links.duplicate(true),
		"start_room": start_room_name,
		"exit_room": boss_room_name,
		"critical_path": critical_path,
		"combat_room": combat_room_name,
		"combat_entry_dir": combat_entry_dir,
		"combat_exit_dir": combat_exit_dir,
		"boss_entry_dir": boss_entry_dir,
		"puzzle_room": "",
		"treasure_room": "",
		"trap_room": "",
		"failure_buckets": failure_buckets.duplicate(true),
		"debug_failures": attempt_debug.duplicate(true),
		"stage_debug": {
			"graph": {"rooms": room_specs.size(), "links": links.size()},
			"roles": {"sequence": role_sequence, "combat_room": combat_room_name},
			"spatial": {"start_room": start_room_name, "boss_room": boss_room_name},
		},
	}


func _failed_layout(failure_buckets: Dictionary, attempt_debug: Array) -> Dictionary:
	return {
		"ok": false,
		"generator_mode": "authored_rooms",
		"room_specs": [],
		"links": [],
		"start_room": "",
		"exit_room": "",
		"critical_path": [],
		"combat_room": "",
		"combat_entry_dir": "west",
		"combat_exit_dir": "east",
		"boss_entry_dir": "west",
		"puzzle_room": "",
		"treasure_room": "",
		"trap_room": "",
		"failure_buckets": failure_buckets.duplicate(true),
		"debug_failures": attempt_debug.duplicate(true),
	}


func _runtime_room_type_for_role(role: String) -> String:
	match role:
		"spawn":
			return "safe"
		"connector":
			return "connector"
		"combat", "chokepoint":
			return "arena"
		"boss":
			return "boss"
		_:
			return "connector"


func _scene_base_name(scene_path: String) -> String:
	return scene_path.get_file().get_basename()


func _shuffled_rotations(rotations: PackedInt32Array, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	for rotation in rotations:
		out.append(int(rotation))
	if out.is_empty():
		out = [0]
	for i in range(out.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, i)
		var tmp := out[i]
		out[i] = out[swap_index]
		out[swap_index] = tmp
	return out


func _increment_bucket(buckets: Dictionary, key: String) -> void:
	buckets[key] = int(buckets.get(key, 0)) + 1


func _merge_failure_buckets(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		var bucket_key := String(key)
		target[bucket_key] = int(target.get(bucket_key, 0)) + int(source[key])
