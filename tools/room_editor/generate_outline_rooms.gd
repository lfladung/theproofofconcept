extends SceneTree

const BASE_ROOM_SCENE := preload("res://dungeon/rooms/base/room_base.tscn")
const CATALOG_PATH := "res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres"
const LAYOUT_SCRIPT := preload("res://addons/dungeon_room_editor/resources/room_layout_data.gd")
const ITEM_SCRIPT := preload("res://addons/dungeon_room_editor/resources/room_placed_item_data.gd")
const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")

const DEFAULT_OUTPUT_VERSION := 2
const DEFAULT_GRID_SIZE := Vector2i(3, 3)
const HALLWAY_WIDTH := 2
const MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES := 3
const DEFAULT_SIZE_BUMP_TILES := 2
const DEFAULT_VARIANT_COUNT := 1
const DEFAULT_VARIANT_ATTEMPTS := 25

var _catalog
var _item_sequence: int = 0
var _output_version: int = DEFAULT_OUTPUT_VERSION
var _output_dir: String = ""
var _suffix: String = "b"
var _rooms_filter: PackedStringArray = PackedStringArray()
var _size_bump_tiles: int = DEFAULT_SIZE_BUMP_TILES
var _variant_count: int = DEFAULT_VARIANT_COUNT
var _variant_attempts: int = DEFAULT_VARIANT_ATTEMPTS
var _seed: int = 0
var _last_generate_error: String = ""


func _get_cmd_arg_value(key: String) -> String:
	# Supports: --key=value and --key value
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		var a: String = args[i]
		if a == key and i + 1 < args.size():
			return String(args[i + 1])
		var prefix := key + "="
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _with_suffix(scene_name: String, suffix: String) -> String:
	# Scene names look like: room_connector_turn_medium_b -> replace trailing token.
	var parts := scene_name.split("_")
	if parts.is_empty():
		return scene_name
	parts[parts.size() - 1] = suffix
	return "_".join(parts)


func _spec_matches_filter(spec: Dictionary) -> bool:
	if _rooms_filter.is_empty():
		return true
	var id := String(spec.get("room_id", ""))
	# Normalize tokens to lower-case for matching.
	var wants := _rooms_filter
	for token in wants:
		var t := String(token).to_lower()
		if t == "skirmish" and id.contains("skirmish"):
			return true
		if t == "tactical" and id.contains("tactical"):
			return true
		if t == "chokepoint" and id.contains("chokepoint"):
			return true
		if t == "connector" and id.contains("room_connector_"):
			return true
	return false


func _hash32(s: String) -> int:
	# Stable-ish hash for deterministic seeding.
	var h := 2166136261
	for i in range(s.length()):
		h = int(posmod(h ^ s.unicode_at(i), 0x7fffffff))
		h = int(posmod(h * 16777619, 0x7fffffff))
	return h


func _rng_for(room_id: String, variant_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var base := _seed
	if base == 0:
		# Deterministic default seed if not provided.
		base = 1337
	rng.seed = int(base + _hash32(room_id) + variant_index * 1013)
	return rng


func _jitter_rect(rect: Rect2i, rng: RandomNumberGenerator, max_jitter: int = 1) -> Rect2i:
	var dx := rng.randi_range(-max_jitter, max_jitter)
	var dy := rng.randi_range(-max_jitter, max_jitter)
	return Rect2i(rect.position + Vector2i(dx, dy), rect.size)


func _pick_random_floor_cells(
	floor_cells: Array[Vector2i],
	opening_cells: Dictionary,
	count: int,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for c in floor_cells:
		if opening_cells.has(c):
			continue
		candidates.append(c)
	candidates.shuffle()
	var out: Array[Vector2i] = []
	var n := mini(count, candidates.size())
	for i in range(n):
		out.append(candidates[i])
	return out


func _build_variant_spec(base_spec: Dictionary, variant_suffix: String, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = base_spec.duplicate(true)
	spec["scene_name"] = _with_suffix(String(spec["scene_name"]), variant_suffix)
	spec["room_id"] = _with_suffix(String(spec["room_id"]), variant_suffix)

	# Slightly larger rooms (tile dimensions).
	var size: Vector2i = spec.get("size", Vector2i.ZERO)
	if _size_bump_tiles > 0:
		size += Vector2i(_size_bump_tiles, _size_bump_tiles)
	spec["size"] = size

	# Randomize carve rects slightly to produce variations.
	if spec.has("remove_rects"):
		var rr: Array = spec.get("remove_rects", [])
		var out_rr: Array[Rect2i] = []
		for r in rr:
			out_rr.append(_jitter_rect(r, rng, 1))
		spec["remove_rects"] = out_rr
	if spec.has("add_rects"):
		var ar: Array = spec.get("add_rects", [])
		var out_ar: Array[Rect2i] = []
		for r in ar:
			out_ar.append(_jitter_rect(r, rng, 1))
		spec["add_rects"] = out_ar

	# Randomize blockers/spawns a bit (keep same counts).
	# We do this later after floor_cells are built, because we need valid cells.
	spec["_randomize_positions"] = true
	return spec


func _init() -> void:
	var output_version_str := _get_cmd_arg_value("--output_version")
	if not output_version_str.is_empty():
		_output_version = int(output_version_str)

	var suffix_arg := _get_cmd_arg_value("--suffix")
	if not suffix_arg.is_empty():
		_suffix = suffix_arg
	else:
		# Default suffix mapping to match existing naming convention: v1 -> _a, v2 -> _b, v3 -> _c.
		match _output_version:
			1:
				_suffix = "a"
			2:
				_suffix = "b"
			3:
				_suffix = "c"
			_:
				_suffix = "b"

	var rooms_arg := _get_cmd_arg_value("--rooms")
	if not rooms_arg.is_empty():
		_rooms_filter = PackedStringArray(rooms_arg.split(","))

	var bump_arg := _get_cmd_arg_value("--size_bump")
	if not bump_arg.is_empty():
		_size_bump_tiles = maxi(0, int(bump_arg))

	var seed_arg := _get_cmd_arg_value("--seed")
	if not seed_arg.is_empty():
		_seed = int(seed_arg)

	var variants_arg := _get_cmd_arg_value("--variant_count")
	if not variants_arg.is_empty():
		_variant_count = maxi(1, int(variants_arg))

	var attempts_arg := _get_cmd_arg_value("--variant_attempts")
	if not attempts_arg.is_empty():
		_variant_attempts = maxi(1, int(attempts_arg))

	_output_dir = "res://dungeon/rooms/authored/outlines/v%d" % _output_version

	_catalog = load(CATALOG_PATH)
	if _catalog == null:
		push_error("Failed to load room piece catalog at %s" % CATALOG_PATH)
		quit(1)
		return
	var make_dir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	if make_dir_result != OK:
		push_error("Failed to create output directory %s" % _output_dir)
		quit(1)
		return
	var layouts_dir := "%s/layouts" % _output_dir
	make_dir_result = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(layouts_dir))
	if make_dir_result != OK:
		push_error("Failed to create layouts directory %s" % layouts_dir)
		quit(1)
		return

	var base_specs := _build_room_specs()
	for base_spec in base_specs:
		# Allow individual specs to opt out of specific output versions.
		if _output_version == 3 and bool(base_spec.get("skip_in_v3", false)):
			continue
		if not _spec_matches_filter(base_spec):
			continue
		for vi in range(_variant_count):
			var variant_suffix := _suffix if _variant_count == 1 else ("%s%02d" % [_suffix, vi + 1])
			var rng := _rng_for(String(base_spec.get("room_id", "")), vi)
			var ok := false
			var last_err := ""
			for attempt in range(_variant_attempts):
				var spec := _build_variant_spec(base_spec, variant_suffix, rng)
				if _generate_room(spec, rng, false):
					ok = true
					break
				last_err = _last_generate_error
			if not ok:
				if last_err.is_empty():
					last_err = "Unknown generation failure."
				push_error("Failed to generate variant %s after %s attempts. Last error: %s" % [variant_suffix, _variant_attempts, last_err])
				quit(1)
				return

	print("GENERATED_OUTLINE_ROOMS_OK")
	quit()


func _build_room_specs() -> Array[Dictionary]:
	# v2 batch: distinct room_id/scene_name (_b). Combat + chokepoint + boss use 1.5x linear
	# footprint vs v1; connectors + treasure keep v1 tile sizes.
	var specs: Array[Dictionary] = [
		{
			"scene_name": "room_combat_skirmish_small_b",
			"room_id": "room_combat_skirmish_small_b",
			"size": Vector2i(15, 15),
			"size_class": "small",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "small"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["melee_pack"]),
			"base_shape": "full",
			# Trim the upper-left ledge more aggressively and remove the
			# inaccessible 3x3 pocket near the east wall.
			"remove_rects": [
				Rect2i(-8, -8, 4, 4),   # widen top-left carve to avoid hanging walls
				Rect2i(5, 3, 3, 3),     # existing central notch
				Rect2i(7, 4, 3, 3),     # remove isolated 3x3 pocket centered at (8,5)
			],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-3, 0),
			"prop_marker": Vector2i(3, -3),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-2, -2), Vector2i(2, 2)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(3, -2)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(3, 3)},
			],
		},
		{
			"scene_name": "room_combat_tactical_medium_b",
			"room_id": "room_combat_tactical_medium_b",
			"size": Vector2i(24, 24),
			"size_class": "medium",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["mixed_patrol"]),
			"base_shape": "full",
			# Carve out the upper-left ledge to avoid a reachable but undesirable
			# hanging platform and its top wall run. First rect removes the tall
			# notch; second rect trims a matching band along the very top edge.
			"remove_rects": [
				Rect2i(-12, -12, 5, 6),
				Rect2i(8, 6, 5, 6),
				Rect2i(-12, -12, 5, 1),
			],
			"openings": [&"west", &"east", &"north"],
			"entry_marker": Vector2i(-8, 0),
			"prop_marker": Vector2i(6, 5),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-3, 3), Vector2i(3, -3)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(-5, -6)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(6, 5)},
				{"piece_id": &"spawn_arrow_tower_marker", "position": Vector2i(2, 8)},
			],
		},
		{
			"scene_name": "room_arena_wave_large_b",
			"room_id": "room_arena_wave_large_b",
			"size": Vector2i(36, 36),
			"size_class": "arena",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "large"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["wave_swarm"]),
			"base_shape": "full",
			"remove_rects": [
				Rect2i(-18, -18, 3, 3),
				Rect2i(15, -18, 3, 3),
				Rect2i(-18, 15, 3, 3),
				Rect2i(15, 15, 3, 3),
			],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-12, 0),
			"prop_marker": Vector2i(12, -5),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-6, 0), Vector2i(6, 0)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(-9, -8)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(9, -6)},
				{"piece_id": &"spawn_iron_sentinel_marker", "position": Vector2i(0, 9)},
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(-8, 8)},
				{"piece_id": &"spawn_arrow_tower_marker", "position": Vector2i(9, 8)},
			],
			# The v3-sized variant of this large arena currently violates the strict
			# MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES rule in one corner pocket; skip it
			# for output_version 3 until the shape is redesigned.
			"skip_in_v3": true,
		},
		{
			"scene_name": "room_connector_narrow_medium_b",
			"room_id": "room_connector_narrow_medium_b",
			"size": Vector2i(10, 16),
			"size_class": "medium",
			"room_type": "corridor",
			"room_tags": PackedStringArray(["corridor", "connector", "narrow"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector"]),
			"recommended_enemy_groups": PackedStringArray([]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-5, -8, 3, 5), Rect2i(2, 3, 3, 5)],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-3, 0),
			"prop_marker": Vector2i(2, -3),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-1, 3), Vector2i(1, -3)],
			"spawns": [{"piece_id": &"spawn_melee_marker", "position": Vector2i(0, 0)}],
		},
		{
			"scene_name": "room_connector_turn_medium_b",
			"room_id": "room_connector_turn_medium_b",
			"size": Vector2i(16, 16),
			"size_class": "medium",
			"room_type": "connector",
			"room_tags": PackedStringArray(["connector", "turn", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector"]),
			"recommended_enemy_groups": PackedStringArray([]),
			"base_shape": "empty",
			"add_rects": [Rect2i(-2, -2, 4, 10), Rect2i(-2, -2, 10, 4)],
			"openings": [&"south", &"east"],
			"entry_marker": Vector2i(0, 4),
			"prop_marker": Vector2i(3, -1),
			"nav_marker": Vector2i(1, 1),
			"blockers": [Vector2i(1, 1)],
			"spawns": [{"piece_id": &"spawn_melee_marker", "position": Vector2i(3, 1)}],
		},
		{
			"scene_name": "room_connector_junction_medium_b",
			"room_id": "room_connector_junction_medium_b",
			"size": Vector2i(16, 16),
			"size_class": "medium",
			"room_type": "connector",
			"room_tags": PackedStringArray(["connector", "junction", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector"]),
			"recommended_enemy_groups": PackedStringArray([]),
			"base_shape": "empty",
			"add_rects": [Rect2i(-8, -2, 16, 4), Rect2i(-2, -2, 4, 10), Rect2i(-4, -4, 8, 4)],
			"openings": [&"west", &"east", &"south"],
			"entry_marker": Vector2i(0, 4),
			"prop_marker": Vector2i(0, -3),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-4, 1), Vector2i(4, 1)],
			"spawns": [{"piece_id": &"spawn_melee_marker", "position": Vector2i(0, 1)}],
		},
		{
			"scene_name": "room_treasure_reward_small_b",
			"room_id": "room_treasure_reward_small_b",
			"size": Vector2i(10, 10),
			"size_class": "small",
			"room_type": "treasure",
			"room_tags": PackedStringArray(["treasure", "reward", "small"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector"]),
			"recommended_enemy_groups": PackedStringArray([]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-5, -5, 2, 2), Rect2i(-5, 3, 2, 2)],
			"openings": [&"west"],
			"entry_marker": Vector2i(-3, 0),
			"prop_marker": Vector2i(0, 2),
			"nav_marker": Vector2i(0, 0),
			"loot_marker": Vector2i(3, 0),
			"treasure": Vector2i(3, 0),
			"blockers": [Vector2i(1, -2)],
			"spawns": [{"piece_id": &"spawn_melee_marker", "position": Vector2i(1, 0)}],
		},
		{
			"scene_name": "room_chokepoint_gate_medium_b",
			"room_id": "room_chokepoint_gate_medium_b",
			"size": Vector2i(24, 15),
			"size_class": "medium",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "chokepoint", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["pressure_lane"]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-12, -8, 6, 5), Rect2i(6, 3, 6, 5)],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-8, 0),
			"prop_marker": Vector2i(5, -3),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(0, -2), Vector2i(0, 2), Vector2i(3, 0)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(6, -2)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(5, 3)},
				{"piece_id": &"spawn_arrow_tower_marker", "position": Vector2i(8, 0)},
			],
		},
		{
			"scene_name": "room_boss_approach_large_b",
			"room_id": "room_boss_approach_large_b",
			"size": Vector2i(24, 36),
			"size_class": "large",
			"room_type": "boss",
			"room_tags": PackedStringArray(["boss", "boss_approach", "connector", "large"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["elite_guard"]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-12, -18, 6, 8), Rect2i(6, 11, 6, 8)],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-9, 0),
			"prop_marker": Vector2i(8, -6),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-5, 0), Vector2i(5, 0)],
			"spawns": [
				{"piece_id": &"spawn_iron_sentinel_marker", "position": Vector2i(6, -3)},
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(8, 5)},
			],
		},
	]

	# Return base specs; suffix/variants are applied in `_init()`.
	return specs


func _generate_room(spec: Dictionary, rng: RandomNumberGenerator, report_errors: bool = true) -> bool:
	_last_generate_error = ""
	var room := BASE_ROOM_SCENE.instantiate()
	if room == null:
		_last_generate_error = "Failed to instantiate base room scene."
		if report_errors:
			push_error(_last_generate_error)
		return false

	var size: Vector2i = spec["size"]
	var layout = LAYOUT_SCRIPT.new()
	layout.room_id = spec["room_id"]
	layout.room_tags = spec["room_tags"]
	layout.recommended_enemy_groups = spec["recommended_enemy_groups"]
	layout.grid_size = DEFAULT_GRID_SIZE

	room.room_id = spec["room_id"]
	room.size_class = spec["size_class"]
	room.room_type = spec["room_type"]
	room.origin_mode = "center"
	room.tile_size = DEFAULT_GRID_SIZE
	room.room_size_tiles = size
	room.room_tags = spec["room_tags"]
	room.allowed_connection_types = spec["allowed_connection_types"]
	room.authored_layout = layout
	room.encounter_budget = _encounter_budget_for_size(size)
	room.max_tile_budget = maxi(1024, size.x * size.y * 2)

	var floor_cells := _build_floor_cells(spec)
	var opening_cells := _opening_cells(size, spec["openings"])
	var floor_lookup: Dictionary = {}
	for cell in floor_cells:
		floor_lookup[cell] = true
	# Openings must remain walkable floor anchors for socket alignment and connectivity.
	# For "empty" base-shape rooms with jittered add_rects, the floor may not extend
	# to the boundary where openings sit. Bridge inward from each opening cell until
	# we connect to existing floor so the opening is never isolated.
	for oc in opening_cells.keys():
		var open_cell := oc as Vector2i
		if not floor_lookup.has(open_cell):
			floor_lookup[open_cell] = true
			floor_cells.append(open_cell)
		var inward := _inward_direction_for_cell(open_cell, size)
		var step := open_cell + inward
		var bridge_limit := maxi(size.x, size.y)
		var steps_taken := 0
		while not floor_lookup.has(step) and steps_taken < bridge_limit:
			floor_lookup[step] = true
			floor_cells.append(step)
			step = step + inward
			steps_taken += 1

	# Prune the room down to the main reachable region from the logical center
	# before we place floors, walls, blockers, and spawns. This avoids hanging
	# ledges and pocket floors that are not actually part of the playable space.
	var reachable_floor := _reachable_floor_region_from_center(floor_lookup, opening_cells)
	var pruned_floor_cells: Array[Vector2i] = []
	for cell in floor_cells:
		if reachable_floor.has(cell):
			pruned_floor_cells.append(cell)
	floor_cells = pruned_floor_cells
	floor_lookup.clear()
	for cell in floor_cells:
		floor_lookup[cell] = true
	floor_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	var spacing_err := _validate_parallel_wall_spacing(floor_lookup, opening_cells)
	if spacing_err != "":
		_last_generate_error = spacing_err
		if report_errors:
			push_error(spacing_err)
		return false
	var wall_items := _build_wall_items(floor_cells, opening_cells)

	# Randomize blockers/spawns positions after floor exists (optional per spec).
	if bool(spec.get("_randomize_positions", false)):
		if spec.has("blockers"):
			var blockers: Array = spec.get("blockers", [])
			var new_blockers := _pick_random_floor_cells(floor_cells, opening_cells, blockers.size(), rng)
			spec["blockers"] = new_blockers
		if spec.has("spawns"):
			var spawns: Array = spec.get("spawns", [])
			var new_positions := _pick_random_floor_cells(floor_cells, opening_cells, spawns.size(), rng)
			var out_spawns: Array[Dictionary] = []
			for i in range(spawns.size()):
				var s: Dictionary = (spawns[i] as Dictionary).duplicate(true)
				if i < new_positions.size():
					s["position"] = new_positions[i]
				out_spawns.append(s)
			spec["spawns"] = out_spawns

	# Blockers that land outside the reachable region are dropped to avoid
	# creating unreachable clutter.
	var blockers: Array = spec.get("blockers", [])
	var pruned_blockers: Array[Vector2i] = []
	for b in blockers:
		if b is Vector2i and reachable_floor.has(b):
			pruned_blockers.append(b)
	spec["blockers"] = pruned_blockers

	var blocked_lookup := _blocked_cells_lookup(spec.get("blockers", []))
	var accessibility_err := _validate_room_accessibility(floor_lookup, opening_cells, blocked_lookup)
	if accessibility_err != "":
		_last_generate_error = accessibility_err
		if report_errors:
			push_error(accessibility_err)
		return false

	_item_sequence = 0
	for cell in floor_cells:
		_add_item(layout, &"floor_dirt_small_a", cell)
	for wall_item in wall_items:
		_add_item(
			layout,
			wall_item.get("piece_id", &"wall_straight"),
			wall_item.get("position", Vector2i.ZERO),
			int(wall_item.get("rotation_steps", 0))
		)
	for side in spec["openings"]:
		_add_socket_for_opening(layout, size, side)

	_add_item(layout, &"encounter_entry_marker", spec["entry_marker"])
	_add_item(layout, &"prop_placement_marker", spec["prop_marker"])
	_add_item(layout, &"nav_boundary_marker", spec["nav_marker"])

	if spec.has("loot_marker"):
		_add_item(layout, &"loot_marker", spec["loot_marker"])
	if spec.has("treasure"):
		_add_item(layout, &"treasure_chest", spec["treasure"])

	for blocker_position in spec.get("blockers", []):
		_add_item(layout, &"barrel_blocker", blocker_position)
	for spawn_data in spec.get("spawns", []):
		_add_item(
			layout,
			spawn_data.get("piece_id", &"spawn_melee_marker"),
			spawn_data.get("position", Vector2i.ZERO),
			int(spawn_data.get("rotation_steps", 0)),
			StringName(String(spawn_data.get("encounter_group_id", "combat_main")))
		)

	var layout_path := "%s/layouts/%s.layout.tres" % [_output_dir, spec["scene_name"]]
	if ResourceSaver.save(layout, layout_path) != OK:
		push_error("Failed to save layout at %s" % layout_path)
		return false
	var scene_path := "%s/%s.tscn" % [_output_dir, spec["scene_name"]]
	if not _write_minimal_room_scene(scene_path, layout_path, spec, layout, room):
		push_error("Failed to write scene at %s" % scene_path)
		return false
	print("Generated %s" % scene_path)
	return true


func _build_floor_cells(spec: Dictionary) -> Array[Vector2i]:
	var size: Vector2i = spec["size"]
	var cells: Dictionary = {}
	if String(spec.get("base_shape", "full")) == "full":
		for cell in _rect_cells(_room_rect(size)):
			cells[cell] = true
	for rect in spec.get("add_rects", []):
		for cell in _rect_cells(rect):
			cells[cell] = true
	for rect in spec.get("remove_rects", []):
		for cell in _rect_cells(rect):
			cells.erase(cell)

	var out: Array[Vector2i] = []
	for cell in cells.keys():
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return out


func _blocked_cells_lookup(blockers: Array) -> Dictionary:
	var out: Dictionary = {}
	for b in blockers:
		if b is Vector2i:
			out[b] = true
	return out


func _validate_room_accessibility(
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	blocked_lookup: Dictionary
) -> String:
	# All walkable floor tiles (including doorway/opening tiles) must be connected.
	# Blockers are treated as non-walkable for this check.
	var walkable_count := 0
	for cell in floor_lookup.keys():
		if not blocked_lookup.has(cell):
			walkable_count += 1
	if walkable_count == 0:
		return "Room accessibility violation: no walkable floor tiles remain."

	var start: Variant = null
	var has_walkable_opening := false
	for oc in opening_cells.keys():
		if floor_lookup.has(oc) and not blocked_lookup.has(oc):
			has_walkable_opening = true
			start = oc
			break
	# Fall back to any walkable tile if no opening tile survives.
	if start == null:
		for cell in floor_lookup.keys():
			if not blocked_lookup.has(cell):
				start = cell
				break
	# Require at least one walkable opening when openings are authored.
	if opening_cells.size() > 0 and not has_walkable_opening:
		return "Room accessibility violation: all opening tiles are blocked or removed."

	var queue: Array[Vector2i] = [start as Vector2i]
	var visited: Dictionary = {start: true}
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
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
			queue.append(nxt)

	if visited.size() != walkable_count:
		for cell in floor_lookup.keys():
			if blocked_lookup.has(cell):
				continue
			if not visited.has(cell):
				return "Room accessibility violation: unreachable floor tile at %s" % [cell]
		return "Room accessibility violation: disconnected walkable regions."
	return ""


func _reachable_floor_region_from_center(
	floor_lookup: Dictionary,
	opening_cells: Dictionary
) -> Dictionary:
	# Identify the main playable region: start from the floor cell closest to the
	# logical room center (0,0) and flood-fill over floor tiles. Hanging platforms
	# or pockets disconnected from this region are treated as unreachable.
	var reachable: Dictionary = {}
	if floor_lookup.is_empty():
		return reachable

	var start: Variant = null
	var best_score: int = 1_000_000_000
	for cell in floor_lookup.keys():
		# Prefer cells near the origin; ignore opening-only cells since they are
		# primarily exterior anchors.
		if opening_cells.has(cell):
			continue
		var c: Vector2i = cell
		var score: int = abs(c.x) + abs(c.y)
		if score < best_score:
			best_score = score
			start = c
	if start == null:
		# Fallback: any floor tile.
		for cell in floor_lookup.keys():
			start = cell
			break
	if start == null:
		return reachable

	var queue: Array[Vector2i] = [start as Vector2i]
	reachable[start] = true
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in dirs:
			var nxt: Vector2i = cur + d
			if reachable.has(nxt):
				continue
			if not floor_lookup.has(nxt):
				continue
			reachable[nxt] = true
			queue.append(nxt)
	return reachable


func _build_wall_items(floor_cells: Array[Vector2i], opening_cells: Dictionary) -> Array[Dictionary]:
	var floor_lookup: Dictionary = {}
	for cell in floor_cells:
		floor_lookup[cell] = true

	var wall_lookup: Dictionary = {}
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var reachable_floor := _reachable_floor_region_from_center(floor_lookup, opening_cells)
	for cell in floor_cells:
		# Avoid "hanging" perimeter walls around unreachable floor pockets: only
		# consider walls anchored on the main reachable floor region.
		if not reachable_floor.has(cell):
			continue
		var should_wall := false
		for direction in directions:
			if not _is_solid_floor_cell(floor_lookup, opening_cells, cell + direction):
				should_wall = true
				break
		if should_wall and not opening_cells.has(cell):
			wall_lookup[cell] = true

	var wall_cells: Array[Vector2i] = []
	for cell in wall_lookup.keys():
		wall_cells.append(cell)
	wall_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	var out: Array[Dictionary] = []
	var items_by_pos: Dictionary = {}
	for cell in wall_cells:
		var item := _wall_item_for_cell(cell, floor_lookup, opening_cells)
		if item.get("piece_id", &"") == &"wall_straight":
			var inner_corner_rotation := _inner_corner_rotation_for_cell(cell, floor_lookup, opening_cells, wall_lookup)
			if inner_corner_rotation >= 0:
				item["piece_id"] = &"wall_corner"
				item["rotation_steps"] = inner_corner_rotation
		items_by_pos[cell] = item

	# Add only strictly interior concave-corner fillers:
	# these are non-wall floor cells diagonally touching a void notch, with both orthogonal
	# neighbors already on the perimeter wall ring. This restores missing inner corners without
	# adding broad corner spam. Only consider reachable floor cells to avoid hanging fillers.
	var reachable_floor_cells: Array[Vector2i] = []
	for cell in floor_cells:
		if reachable_floor.has(cell):
			reachable_floor_cells.append(cell)
	for fill in _build_concave_interior_corner_fillers(reachable_floor_cells, floor_lookup, opening_cells, wall_lookup):
		var pos: Vector2i = fill.get("position", Vector2i.ZERO) as Vector2i
		if items_by_pos.has(pos):
			continue
		items_by_pos[pos] = fill

	# Prune walls that do not sit on a reachable floor tile; this removes "hanging"
	# perimeter runs that float over pure void or unreachable floor pockets.
	for pos in items_by_pos.keys():
		var item: Dictionary = items_by_pos[pos]
		var pid: StringName = item.get("piece_id", &"")
		if pid != &"wall_corner" and pid != &"wall_straight":
			continue
		var p: Vector2i = item.get("position", pos) as Vector2i
		if not reachable_floor.has(p):
			items_by_pos.erase(pos)

	# Second pass: adjust boundary wall_corner rotations so they visually connect
	# to neighboring wall pieces (corners and straights). Interior concave corners
	# already have their rotation set by void-cell direction and must not be overridden.
	for pos in items_by_pos.keys():
		var item: Dictionary = items_by_pos[pos]
		if item.get("piece_id", &"") != &"wall_corner":
			continue
		if bool(item.get("_concave_interior", false)):
			continue
		var p: Vector2i = item.get("position", pos) as Vector2i
		var has_left := false
		var has_right := false
		var has_up := false
		var has_down := false
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var npos: Vector2i = p + dir
			if not items_by_pos.has(npos):
				continue
			var nitem: Dictionary = items_by_pos[npos]
			var pid: StringName = nitem.get("piece_id", &"")
			if pid != &"wall_corner" and pid != &"wall_straight":
				continue
			if dir == Vector2i.LEFT:
				has_left = true
			elif dir == Vector2i.RIGHT:
				has_right = true
			elif dir == Vector2i.UP:
				has_up = true
			elif dir == Vector2i.DOWN:
				has_down = true
		var rot := _corner_rotation_for_walls(has_left, has_right, has_up, has_down)
		item["rotation_steps"] = rot
		items_by_pos[p] = item

	out.clear()
	for cell in items_by_pos.keys():
		out.append(items_by_pos[cell])
	# Keep stable ordering for deterministic exports.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap := a.get("position", Vector2i.ZERO) as Vector2i
		var bp := b.get("position", Vector2i.ZERO) as Vector2i
		return ap.y < bp.y if ap.y != bp.y else ap.x < bp.x
	)
	return out


func _inner_corner_rotation_for_cell(
	cell: Vector2i,
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	wall_lookup: Dictionary
) -> int:
	# Convert a straight wall into a corner only when the cell borders a concave pocket:
	# - diagonal is void/opening
	# - both orthogonal neighbors toward that diagonal are solid floor and perimeter wall cells
	# This prevents broad corner over-placement while restoring missing inner turns.
	var tests := [
		{"diag": Vector2i(1, -1), "a": Vector2i.RIGHT, "b": Vector2i.UP, "rot": 0},
		{"diag": Vector2i(1, 1), "a": Vector2i.RIGHT, "b": Vector2i.DOWN, "rot": 1},
		{"diag": Vector2i(-1, 1), "a": Vector2i.LEFT, "b": Vector2i.DOWN, "rot": 2},
		{"diag": Vector2i(-1, -1), "a": Vector2i.LEFT, "b": Vector2i.UP, "rot": 3},
	]
	for t in tests:
		var diag: Vector2i = cell + (t["diag"] as Vector2i)
		if _is_solid_floor_cell(floor_lookup, opening_cells, diag):
			continue
		var a_cell: Vector2i = cell + (t["a"] as Vector2i)
		var b_cell: Vector2i = cell + (t["b"] as Vector2i)
		if not _is_solid_floor_cell(floor_lookup, opening_cells, a_cell):
			continue
		if not _is_solid_floor_cell(floor_lookup, opening_cells, b_cell):
			continue
		if not wall_lookup.has(a_cell) or not wall_lookup.has(b_cell):
			continue
		var has_left := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.LEFT)
		var has_right := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.RIGHT)
		var has_up := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.UP)
		var has_down := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.DOWN)
		return _corner_rotation_for_walls(has_left, has_right, has_up, has_down)
	return -1


func _build_concave_interior_corner_fillers(
	floor_cells: Array[Vector2i],
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	wall_lookup: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if floor_cells.is_empty():
		return out
	var min_x := floor_cells[0].x
	var max_x := floor_cells[0].x
	var min_y := floor_cells[0].y
	var max_y := floor_cells[0].y
	for c in floor_cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)

	for vx in range(min_x - 1, max_x + 2):
		for vy in range(min_y - 1, max_y + 2):
			var void_cell := Vector2i(vx, vy)
			if _is_solid_floor_cell(floor_lookup, opening_cells, void_cell):
				continue
			# Rotation convention matches the validator: rotation is determined by
			# where the void cell sits relative to the corner cell.
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
				# Only add filler corners on interior floor cells (not already boundary walls).
				if wall_lookup.has(corner):
					continue
				if _missing_solid_neighbor_count(corner, floor_lookup, opening_cells) != 0:
					continue
				# Must be a true notch bounded by existing perimeter wall cells.
				if not wall_lookup.has(a) or not wall_lookup.has(b):
					continue
				out.append({
					"piece_id": &"wall_corner",
					"position": corner,
					"rotation_steps": int(t["rot"]),
					"_concave_interior": true,
				})
	return out


func _missing_solid_neighbor_count(cell: Vector2i, floor_lookup: Dictionary, opening_cells: Dictionary) -> int:
	var count := 0
	for off in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _is_solid_floor_cell(floor_lookup, opening_cells, cell + off):
			count += 1
	return count


func _validate_parallel_wall_spacing(
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
) -> String:
	# Enforce minimum corridor width between facing parallel straight walls.
	# Measure: from inner face to inner face, in grid tiles.
	# Exemption:
	# - only when both walls share the same corner cell (true corner-sharing turn)

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

		var missing_count := 0
		missing_count += int(missing_left)
		missing_count += int(missing_right)
		missing_count += int(missing_up)
		missing_count += int(missing_down)

		# Only straight walls participate in the “parallel facing” scan.
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

	# Vertical facing scans: north wall faces south wall along +Y.
	for n in north_walls.keys():
		var x: int = n.x
		var y: int = n.y + 1
		while floor_lookup.has(Vector2i(x, y)):
			var cur: Vector2i = Vector2i(x, y)
			if south_walls.has(cur):
				# floor_gap is the count of floor cells strictly between the two facing wall rings.
				# The requested measurement is inner-face-to-inner-face, which is offset by one cell.
				var floor_gap: int = cur.y - n.y - 1
				var inner_face_gap: int = floor_gap + 1
				var exempt := _is_spacing_exempt_by_corner_sharing(n, cur, corner_wall_cells)
				if inner_face_gap == 1 and not exempt:
					return (
						"Parallel wall spacing violation (adjacent) in generator: "
						+ "gap=%s between north=%s and south=%s"
						% [inner_face_gap, n, cur]
					)

				if inner_face_gap < MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES and not exempt:
					return (
						"Parallel wall spacing violation (vertical) in generator: "
						+ "gap=%s < %s between north=%s and south=%s"
						% [inner_face_gap, MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES, n, cur]
					)
				break
			y += 1

	# Horizontal facing scans: west wall faces east wall along +X.
	for w in west_walls.keys():
		var y: int = w.y
		var x: int = w.x + 1
		while floor_lookup.has(Vector2i(x, y)):
			var cur: Vector2i = Vector2i(x, y)
			if east_walls.has(cur):
				var floor_gap: int = cur.x - w.x - 1
				var inner_face_gap: int = floor_gap + 1
				var exempt := _is_spacing_exempt_by_corner_sharing(w, cur, corner_wall_cells)
				if inner_face_gap == 1 and not exempt:
					return (
						"Parallel wall spacing violation (adjacent) in generator: "
						+ "gap=%s between west=%s and east=%s"
						% [inner_face_gap, w, cur]
					)

				if inner_face_gap < MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES and not exempt:
					return (
						"Parallel wall spacing violation (horizontal) in generator: "
						+ "gap=%s < %s between west=%s and east=%s"
						% [inner_face_gap, MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES, w, cur]
					)
				break
			x += 1

	return ""


func _is_spacing_exempt_by_corner_sharing(a: Vector2i, b: Vector2i, corner_wall_cells: Dictionary) -> bool:
	# Exempt only if BOTH walls touch the same corner wall cell, i.e. a true 90° turn
	# sharing a single corner tile. This preserves narrow wall adjacency exactly at the
	# bend while still enforcing MIN_PARALLEL_WALL_INNER_FACE_GAP_TILES for all
	# straight corridor spans.
	for off_a in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var ca: Vector2i = a + off_a
		if not corner_wall_cells.has(ca):
			continue
		for off_b in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if b + off_b == ca:
				return true
	return false


func _is_solid_floor_cell(floor_lookup: Dictionary, opening_cells: Dictionary, cell: Vector2i) -> bool:
	# Opening tiles are still authored as floor for nav/socket anchoring, but they are exterior holes
	# for wall perimeter logic (corner rotation must see them as "missing" neighbors).
	return floor_lookup.has(cell) and not opening_cells.has(cell)


## Orthogonal neighbors only see "two voids" for both outside (convex) and inside (concave) 90° bends.
## Convex outer corners have few floor cells in the 8-ring; re-entrant corners sit in a denser floor pocket.
func _is_concave_wall_corner_cell(cell: Vector2i, floor_lookup: Dictionary) -> bool:
	var floor_in_8 := 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if floor_lookup.has(cell + Vector2i(dx, dy)):
				floor_in_8 += 1
	return floor_in_8 >= 4


func _corner_rotation_for_walls(has_left: bool, has_right: bool, has_up: bool, has_down: bool) -> int:
	# Rotation convention for wall corners (connects to adjacent WALLS),
	# then flipped 180° to match the current mesh orientation:
	# base:
	#   0 -> right + above
	#   1 -> right + below
	#   2 -> left  + below
	#   3 -> left  + above
	if has_right and has_up:
		return 2
	if has_right and has_down:
		return 3
	if has_left and has_down:
		return 0
	if has_left and has_up:
		return 1
	return 0


func _flip_corner_rotation(rot: int) -> int:
	# Invert rotation direction for corner pieces so that layout `rotation_steps`
	# better matches the mesh's visual facing (PreviewBuilder applies a negated yaw).
	# 0 -> 0, 1 -> 3, 2 -> 2, 3 -> 1
	return posmod(4 - rot, 4)


func _wall_item_for_cell(cell: Vector2i, floor_lookup: Dictionary, opening_cells: Dictionary) -> Dictionary:
	var has_left := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.LEFT)
	var has_right := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.RIGHT)
	var has_up := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.UP)
	var has_down := _is_solid_floor_cell(floor_lookup, opening_cells, cell + Vector2i.DOWN)

	var missing_left := not has_left
	var missing_right := not has_right
	var missing_up := not has_up
	var missing_down := not has_down

	var missing_count := int(missing_left) + int(missing_right) + int(missing_up) + int(missing_down)

	var use_outer_corner := not _is_concave_wall_corner_cell(cell, floor_lookup)

	# Corner support:
	# If exactly two orthogonal neighbors are missing, this is an L-corner perimeter cell.
	# Use the rotation convention in terms of the *present* wall neighbors so it matches
	# the design doc:
	# 0 deg  -> right + above
	# 90 deg -> right + below
	# 180 deg-> left  + below
	# 270 deg-> left  + above
	if missing_count == 2:
		var rot := _corner_rotation_for_walls(has_left, has_right, has_up, has_down)
		return {"piece_id": &"wall_corner", "position": cell, "rotation_steps": rot}

	# Fallback straight-wall handling if we didn't early-return as a corner.
	if missing_left or missing_right:
		return {"piece_id": &"wall_straight", "position": cell, "rotation_steps": 1}
	return {"piece_id": &"wall_straight", "position": cell, "rotation_steps": 0}


func _inward_direction_for_cell(cell: Vector2i, size: Vector2i) -> Vector2i:
	# Return the direction pointing inward from a boundary cell toward the room center.
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	if cell.x == left:
		return Vector2i.RIGHT
	if cell.x == right:
		return Vector2i.LEFT
	if cell.y == top:
		return Vector2i.DOWN
	if cell.y == bottom:
		return Vector2i.UP
	# Fallback: step toward origin.
	if absi(cell.x) >= absi(cell.y):
		return Vector2i(-signi(cell.x), 0) if cell.x != 0 else Vector2i.RIGHT
	return Vector2i(0, -signi(cell.y)) if cell.y != 0 else Vector2i.DOWN


func _opening_cells(size: Vector2i, openings: Array) -> Dictionary:
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	var cells: Dictionary = {}
	for raw_side in openings:
		var side := StringName(raw_side)
		match side:
			&"west":
				cells[Vector2i(left, -1)] = true
				cells[Vector2i(left, 0)] = true
			&"east":
				cells[Vector2i(right, -1)] = true
				cells[Vector2i(right, 0)] = true
			&"north":
				cells[Vector2i(-1, top)] = true
				cells[Vector2i(0, top)] = true
			&"south":
				cells[Vector2i(-1, bottom)] = true
				cells[Vector2i(0, bottom)] = true
	return cells


func _add_socket_for_opening(layout, size: Vector2i, side: StringName) -> void:
	# Anchor on the same floor columns/rows as _opening_cells (not one tile past east/south).
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	# grid_position = min tile of the 2-wide opening (matches anchor_rect tile AABB).
	var rotation_steps := _socket_rotation_for_opening_side(side)
	match side:
		&"west":
			_add_item(layout, &"hall_socket_double", Vector2i(left, -1), rotation_steps)
		&"east":
			_add_item(layout, &"hall_socket_double", Vector2i(right, -1), rotation_steps)
		&"north":
			_add_item(layout, &"hall_socket_double", Vector2i(-1, top), rotation_steps)
		&"south":
			_add_item(layout, &"hall_socket_double", Vector2i(-1, bottom), rotation_steps)


func _socket_rotation_for_opening_side(side: StringName) -> int:
	match side:
		&"north":
			return 0
		&"east":
			return 1
		&"south":
			return 2
		&"west":
			return 3
		_:
			return 0


func _add_item(
	layout,
	piece_id: StringName,
	grid_position: Vector2i,
	rotation_steps: int = 0,
	encounter_group_id: StringName = &""
):
	var piece = _catalog.find_piece(piece_id)
	if piece == null:
		push_error("Catalog piece '%s' not found." % String(piece_id))
		return null
	var item = ITEM_SCRIPT.new()
	_item_sequence += 1
	item.item_id = "%s_%03d" % [String(piece_id), _item_sequence]
	item.piece_id = piece_id
	item.category = piece.category
	item.grid_position = grid_position
	item.rotation_steps = posmod(rotation_steps, 4)
	item.tags = piece.default_tags.duplicate()
	item.encounter_group_id = encounter_group_id
	item.placement_layer = piece.default_placement_layer()
	item.blocks_movement = piece.blocks_movement
	item.blocks_projectiles = piece.blocks_projectiles
	layout.items.append(item)
	return item


func _room_rect(size: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(-size.x / 2, -size.y / 2), size)


func _rect_cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			out.append(Vector2i(x, y))
	return out


func _encounter_budget_for_size(size: Vector2i) -> int:
	var area := size.x * size.y
	if area <= 100:
		return 80
	if area <= 256:
		return 120
	return 180


func _write_minimal_room_scene(
	scene_path: String, layout_path: String, spec: Dictionary, layout, room: RoomBase
) -> bool:
	var absolute_scene_path := ProjectSettings.globalize_path(scene_path)
	var file := FileAccess.open(absolute_scene_path, FileAccess.WRITE)
	if file == null:
		return false
	var lines: Array[String] = []
	lines.append("[gd_scene format=3]")
	lines.append("")
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://dungeon/rooms/base/room_base.tscn\" id=\"1_room_base\"]")
	lines.append("[ext_resource type=\"Resource\" path=\"%s\" id=\"2_layout\"]" % layout_path)
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://dungeon/rooms/base/door_socket_2d.tscn\" id=\"3_socket\"]")
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://dungeon/metadata/zone_marker_2d.tscn\" id=\"4_zone\"]")
	lines.append("")
	lines.append("[node name=\"RoomRoot\" instance=ExtResource(\"1_room_base\")]")
	lines.append("room_id = \"%s\"" % spec["room_id"])
	lines.append("size_class = \"%s\"" % spec["size_class"])
	lines.append("room_type = \"%s\"" % spec["room_type"])
	lines.append("origin_mode = \"%s\"" % "center")
	lines.append("tile_size = Vector2i(%s, %s)" % [DEFAULT_GRID_SIZE.x, DEFAULT_GRID_SIZE.y])
	var size: Vector2i = spec["size"]
	lines.append("room_size_tiles = Vector2i(%s, %s)" % [size.x, size.y])
	lines.append("room_tags = %s" % _packed_string_array_literal(spec["room_tags"]))
	lines.append(
		"allowed_connection_types = %s" % _packed_string_array_literal(spec["allowed_connection_types"])
	)
	lines.append("encounter_budget = %s" % _encounter_budget_for_size(size))
	lines.append("max_tile_budget = %s" % maxi(1024, size.x * size.y * 2))
	lines.append("authored_layout = ExtResource(\"2_layout\")")
	lines.append("")
	lines.append("[node name=\"GeneratedByRoomEditor\" type=\"Node2D\" parent=\"Sockets\"]")
	var socket_piece = _catalog.find_piece(&"hall_socket_double")
	for item in layout.items:
		if item == null or item.piece_id != &"hall_socket_double":
			continue
		var direction := _direction_name(item.rotation_steps)
		lines.append(
			"[node name=\"%s_%s\" parent=\"Sockets/GeneratedByRoomEditor\" instance=ExtResource(\"3_socket\")]"
			% [String(item.piece_id), item.item_id]
		)
		var sock_pos := _grid_to_world(item.grid_position)
		if socket_piece != null:
			sock_pos = GridMath.item_rect(item, socket_piece, layout, room).get_center()
		lines.append("position = Vector2(%s, %s)" % [sock_pos.x, sock_pos.y])
		lines.append("direction = \"%s\"" % direction)
		lines.append("width_tiles = %s" % HALLWAY_WIDTH)
		lines.append("")
	lines.append("[node name=\"GeneratedByRoomEditor\" type=\"Node2D\" parent=\"Zones\"]")
	for item in layout.items:
		var piece = _catalog.find_piece(item.piece_id)
		if piece == null or String(piece.mapping_kind) != "zone_marker":
			continue
		lines.append(
			"[node name=\"%s_%s\" parent=\"Zones/GeneratedByRoomEditor\" instance=ExtResource(\"4_zone\")]"
			% [String(item.piece_id), item.item_id]
		)
		lines.append("position = Vector2(%s, %s)" % [_grid_to_world(item.grid_position).x, _grid_to_world(item.grid_position).y])
		lines.append("zone_type = \"%s\"" % piece.zone_type)
		lines.append("zone_role = &\"%s\"" % String(piece.zone_role))
		if String(item.resolved_enemy_id(piece)) != "":
			lines.append("enemy_id = &\"%s\"" % String(item.resolved_enemy_id(piece)))
		if not item.tags.is_empty():
			lines.append("tags = %s" % _packed_string_array_literal(item.tags))
		lines.append("")
	file.store_string("\n".join(lines) + "\n")
	return true


func _packed_string_array_literal(values: PackedStringArray) -> String:
	if values.is_empty():
		return "PackedStringArray()"
	var escaped: Array[String] = []
	for value in values:
		escaped.append("\"%s\"" % String(value).replace("\\", "\\\\").replace("\"", "\\\""))
	return "PackedStringArray(%s)" % ", ".join(escaped)


func _grid_to_world(grid_position: Vector2i) -> Vector2:
	return Vector2(grid_position.x * DEFAULT_GRID_SIZE.x, grid_position.y * DEFAULT_GRID_SIZE.y)


func _direction_name(rotation_steps: int) -> String:
	match posmod(rotation_steps, 4):
		0:
			return "north"
		1:
			return "east"
		2:
			return "south"
		_:
			return "west"
