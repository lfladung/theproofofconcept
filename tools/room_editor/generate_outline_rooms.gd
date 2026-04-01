extends SceneTree

const BASE_ROOM_SCENE := preload("res://dungeon/rooms/base/room_base.tscn")
const CATALOG_PATH := "res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres"
const LAYOUT_SCRIPT := preload("res://addons/dungeon_room_editor/resources/room_layout_data.gd")
const ITEM_SCRIPT := preload("res://addons/dungeon_room_editor/resources/room_placed_item_data.gd")
const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")

const DEFAULT_OUTPUT_VERSION := 2
const DEFAULT_GRID_SIZE := Vector2i(3, 3)
const HALLWAY_WIDTH := 3
const HALLWAY_DEPTH := 2
const MIN_PARALLEL_WALL_FLOOR_GAP_TILES := 3
const BORDER_CLEARANCE_TILES := 3
const DEFAULT_SIZE_BUMP_TILES := 6
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


func _jitter_rect_with_size_variation(
	rect: Rect2i,
	rng: RandomNumberGenerator,
	max_jitter: int = 2,
	max_size_delta: int = 2,
	min_size: int = 2
) -> Rect2i:
	var dx := rng.randi_range(-max_jitter, max_jitter)
	var dy := rng.randi_range(-max_jitter, max_jitter)
	var dw := rng.randi_range(-max_size_delta, max_size_delta)
	var dh := rng.randi_range(-max_size_delta, max_size_delta)
	var size := Vector2i(
		maxi(min_size, rect.size.x + dw),
		maxi(min_size, rect.size.y + dh)
	)
	return Rect2i(rect.position + Vector2i(dx, dy), size)


func _pick_random_floor_cells(
	floor_cells: Array[Vector2i],
	opening_cells: Dictionary,
	count: int,
	rng: RandomNumberGenerator,
	excluded_cells: Dictionary = {}
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for c in floor_cells:
		if opening_cells.has(c):
			continue
		if excluded_cells.has(c):
			continue
		candidates.append(c)
	candidates.shuffle()
	var out: Array[Vector2i] = []
	var n := mini(count, candidates.size())
	for i in range(n):
		out.append(candidates[i])
	return out


func _nearest_valid_interior_floor_cell(
	preferred: Vector2i,
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	excluded_cells: Dictionary = {}
) -> Vector2i:
	var best := preferred
	var best_dist := INF
	for candidate in floor_lookup.keys():
		var c := candidate as Vector2i
		if opening_cells.has(c):
			continue
		if excluded_cells.has(c):
			continue
		var dist := preferred.distance_squared_to(c)
		if dist < best_dist:
			best_dist = dist
			best = c
	if best_dist < INF:
		return best
	for candidate in floor_lookup.keys():
		var c := candidate as Vector2i
		if opening_cells.has(c):
			continue
		var dist := preferred.distance_squared_to(c)
		if dist < best_dist:
			best_dist = dist
			best = c
	return best


func _normalize_centered_room_size(size: Vector2i) -> Vector2i:
	var normalized := Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	if normalized.x % 2 == 0:
		normalized.x += 1
	if normalized.y % 2 == 0:
		normalized.y += 1
	return normalized


func _border_distance(cell: Vector2i, room_rect: Rect2i) -> int:
	return mini(
		mini(cell.x - room_rect.position.x, room_rect.end.x - 1 - cell.x),
		mini(cell.y - room_rect.position.y, room_rect.end.y - 1 - cell.y)
	)


func _interior_excluded_cells(
	size: Vector2i,
	hallway_cells: Dictionary,
	extra_excluded: Dictionary = {}
) -> Dictionary:
	var excluded := hallway_cells.duplicate(true)
	var room_rect := _room_rect(size)
	for x in range(room_rect.position.x, room_rect.end.x):
		for y in range(room_rect.position.y, room_rect.end.y):
			var cell := Vector2i(x, y)
			if _border_distance(cell, room_rect) < BORDER_CLEARANCE_TILES:
				excluded[cell] = true
	for cell in extra_excluded.keys():
		excluded[cell] = true
	return excluded


func _ensure_floor_contract_cells(floor_cells: Array[Vector2i], floor_lookup: Dictionary, required_cells: Dictionary) -> Array[Vector2i]:
	for cell in required_cells.keys():
		var c := cell as Vector2i
		if floor_lookup.has(c):
			continue
		floor_lookup[c] = true
		floor_cells.append(c)
	return floor_cells


func _build_variant_spec(base_spec: Dictionary, variant_suffix: String, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = base_spec.duplicate(true)
	spec["scene_name"] = _with_suffix(String(spec["scene_name"]), variant_suffix)
	spec["room_id"] = _with_suffix(String(spec["room_id"]), variant_suffix)

	# Slightly larger rooms (tile dimensions).
	var size: Vector2i = spec.get("size", Vector2i.ZERO)
	if _size_bump_tiles > 0:
		size += Vector2i(_size_bump_tiles, _size_bump_tiles)
	spec["size"] = _normalize_centered_room_size(size)

	# Randomize carve rects slightly to produce variations.
	var allow_shape_rect_jitter := String(spec.get("base_shape", "full")) != "empty"
	if spec.has("remove_rects"):
		var rr: Array = spec.get("remove_rects", [])
		var out_rr: Array[Rect2i] = []
		for r in rr:
			out_rr.append(_jitter_rect_with_size_variation(r, rng, 2, 2, 2) if allow_shape_rect_jitter else (r as Rect2i))
		spec["remove_rects"] = out_rr
	if spec.has("add_rects"):
		var ar: Array = spec.get("add_rects", [])
		var out_ar: Array[Rect2i] = []
		for r in ar:
			out_ar.append(_jitter_rect(r, rng, 2) if allow_shape_rect_jitter else (r as Rect2i))
		spec["add_rects"] = out_ar
	if String(spec.get("base_shape", "full")) == "empty":
		spec["_opening_center_span"] = 3
	else:
		spec["_opening_center_span"] = -1

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
			"size": Vector2i(19, 19),
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
			"size": Vector2i(28, 28),
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
			"openings": [&"west", &"north"],
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
			"size": Vector2i(40, 40),
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
			"size": Vector2i(14, 20),
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
			"size": Vector2i(28, 28),
			"size_class": "medium",
			"room_type": "connector",
			"room_tags": PackedStringArray(["connector", "turn", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector"]),
			"recommended_enemy_groups": PackedStringArray([]),
			"base_shape": "empty",
			"add_rects": [Rect2i(-5, -5, 10, 22), Rect2i(-5, -5, 22, 10)],
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
			"size": Vector2i(28, 28),
			"size_class": "medium",
			"room_type": "connector",
			"room_tags": PackedStringArray(["connector", "junction", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector"]),
			"recommended_enemy_groups": PackedStringArray([]),
			"base_shape": "empty",
			"add_rects": [Rect2i(-14, -5, 28, 10), Rect2i(-5, -5, 10, 22), Rect2i(-8, -10, 16, 10)],
			"openings": [&"west", &"south"],
			"entry_marker": Vector2i(0, 4),
			"prop_marker": Vector2i(0, -3),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-4, 1), Vector2i(4, 1)],
			"spawns": [{"piece_id": &"spawn_melee_marker", "position": Vector2i(0, 1)}],
		},
		{
			"scene_name": "room_treasure_reward_small_b",
			"room_id": "room_treasure_reward_small_b",
			"size": Vector2i(14, 14),
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
			"size": Vector2i(28, 19),
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
			"size": Vector2i(28, 40),
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

	var marker_plan := _build_marker_plan(spec["room_type"], spec["openings"])
	var active_openings: Array = []
	for marker_info in marker_plan:
		var side := StringName(String(marker_info.get("side", "")))
		if not active_openings.has(side):
			active_openings.append(side)
	var floor_cells := _build_floor_cells(spec)
	var opening_center_span := int(spec.get("_opening_center_span", -1))
	var hallway := _build_hallway_geometry(size, active_openings, rng, opening_center_span)
	var opening_cells: Dictionary = hallway["opening_cells"]
	var passage_cells: Dictionary = hallway["passage_cells"]
	var support_floor_cells: Dictionary = hallway["support_floor_cells"]
	var apron_cells: Dictionary = hallway["apron_cells"]
	var hallway_all_cells: Dictionary = hallway["all_cells"]
	var hallway_carve_void_cells: Dictionary = hallway["carve_void_cells"]
	var center_positions: Dictionary = hallway["center_positions"]
	var required_hallway_floor_cells := opening_cells.duplicate(true)
	for cell in passage_cells.keys():
		required_hallway_floor_cells[cell] = true
	for cell in support_floor_cells.keys():
		required_hallway_floor_cells[cell] = true
	for cell in apron_cells.keys():
		required_hallway_floor_cells[cell] = true

	var floor_lookup: Dictionary = {}
	for cell in floor_cells:
		floor_lookup[cell] = true
	# Merge hallway floor tiles (flanks + passage + boundary) into the floor.
	for cell in hallway_all_cells.keys():
		if not floor_lookup.has(cell):
			floor_lookup[cell] = true
			floor_cells.append(cell)
	for cell in hallway_carve_void_cells.keys():
		if hallway_all_cells.has(cell):
			continue
		if floor_lookup.has(cell):
			floor_lookup.erase(cell)
	var carved_floor_cells: Array[Vector2i] = []
	for cell in floor_cells:
		if floor_lookup.has(cell):
			carved_floor_cells.append(cell)
	floor_cells = carved_floor_cells
	# Bridge the 3-wide passage at the room boundary inward so that "empty"
	# base-shape rooms (whose add_rects may not reach the boundary) stay connected.
	var hall_rect := _room_rect(size)
	for raw_side in active_openings:
		var hside := String(raw_side)
		var hcenter: int = center_positions[hside]
		var boundary_cells: Array[Vector2i] = []
		match hside:
			"west":
				for dy in range(-1, 2):
					boundary_cells.append(Vector2i(hall_rect.position.x, hcenter + dy))
			"east":
				for dy in range(-1, 2):
					boundary_cells.append(Vector2i(hall_rect.position.x + hall_rect.size.x - 1, hcenter + dy))
			"north":
				for dx in range(-1, 2):
					boundary_cells.append(Vector2i(hcenter + dx, hall_rect.position.y))
			"south":
				for dx in range(-1, 2):
					boundary_cells.append(Vector2i(hcenter + dx, hall_rect.position.y + hall_rect.size.y - 1))
		for bc in boundary_cells:
			var inward := _inward_direction_for_cell(bc, size)
			# Start bridging beyond the full protected mouth footprint
			# (opening -> passage -> support -> apron), so the main room body grows
			# inward from the connector instead of chewing into it.
			var step := bc + (inward * 4)
			var bridge_limit := maxi(size.x, size.y)
			var steps_taken := 0
			while not floor_lookup.has(step) and steps_taken < bridge_limit:
				floor_lookup[step] = true
				floor_cells.append(step)
				hallway_all_cells[step] = true
				step = step + inward
				steps_taken += 1

	floor_cells = _fill_enclosed_void_pockets(floor_cells, floor_lookup, size)

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
	floor_cells = _fill_enclosed_void_pockets(floor_cells, floor_lookup, size)

	# Erode thin floor peninsulas: iteratively remove any non-opening floor tile
	# that forms a 1-tile-wide strip (no floor on both sides of at least one axis).
	# This prevents walls from forming thin protrusions around carved notches.
	var erode_changed := true
	while erode_changed:
		erode_changed = false
		var erode_remove: Array[Vector2i] = []
		for cell in floor_cells:
			if opening_cells.has(cell):
				continue
			if hallway_all_cells.has(cell):
				continue
			var has_left := floor_lookup.has(cell + Vector2i.LEFT)
			var has_right := floor_lookup.has(cell + Vector2i.RIGHT)
			var has_up := floor_lookup.has(cell + Vector2i.UP)
			var has_down := floor_lookup.has(cell + Vector2i.DOWN)
			if (not has_left and not has_right) or (not has_up and not has_down):
				erode_remove.append(cell)
		if not erode_remove.is_empty():
			erode_changed = true
			for cell in erode_remove:
				floor_lookup.erase(cell)
			var new_floor: Array[Vector2i] = []
			for cell in floor_cells:
				if floor_lookup.has(cell):
					new_floor.append(cell)
			floor_cells = new_floor

	# Re-prune to reachable region after erosion in case erosion disconnected
	# any floor pockets from the main area.
	reachable_floor = _reachable_floor_region_from_center(floor_lookup, opening_cells)
	pruned_floor_cells = []
	for cell in floor_cells:
		if reachable_floor.has(cell):
			pruned_floor_cells.append(cell)
	floor_cells = pruned_floor_cells
	floor_lookup.clear()
	for cell in floor_cells:
		floor_lookup[cell] = true
	floor_cells = _fill_enclosed_void_pockets(floor_cells, floor_lookup, size)

	var narrow_prune_changed := true
	while narrow_prune_changed:
		narrow_prune_changed = false
		var narrow_remove: Array[Vector2i] = []
		for cell in floor_cells:
			if opening_cells.has(cell):
				continue
			if passage_cells.has(cell):
				continue
			if hallway_all_cells.has(cell):
				continue
			var horizontal_gap := _parallel_floor_gap_for_axis(cell, floor_lookup, opening_cells, true)
			var vertical_gap := _parallel_floor_gap_for_axis(cell, floor_lookup, opening_cells, false)
			if (
				(horizontal_gap >= 0 and horizontal_gap < MIN_PARALLEL_WALL_FLOOR_GAP_TILES)
				or (vertical_gap >= 0 and vertical_gap < MIN_PARALLEL_WALL_FLOOR_GAP_TILES)
			):
				narrow_remove.append(cell)
		if not narrow_remove.is_empty():
			narrow_prune_changed = true
			for cell in narrow_remove:
				floor_lookup.erase(cell)
			var narrowed_floor: Array[Vector2i] = []
			for cell in floor_cells:
				if floor_lookup.has(cell):
					narrowed_floor.append(cell)
			floor_cells = narrowed_floor
			reachable_floor = _reachable_floor_region_from_center(floor_lookup, opening_cells)
			pruned_floor_cells = []
			for cell in floor_cells:
				if reachable_floor.has(cell):
					pruned_floor_cells.append(cell)
			floor_cells = pruned_floor_cells
			floor_lookup.clear()
			for cell in floor_cells:
				floor_lookup[cell] = true

	floor_cells = _fill_enclosed_void_pockets(floor_cells, floor_lookup, size)

	var allowed_border_walls := _opening_contract_boundary_wall_positions(size, active_openings, center_positions)
	floor_cells = _strip_non_hallway_border_band_floor_cells(
		floor_cells,
		floor_lookup,
		size,
		required_hallway_floor_cells,
		BORDER_CLEARANCE_TILES
	)
	reachable_floor = _reachable_floor_region_from_center(floor_lookup, opening_cells)
	pruned_floor_cells = []
	for cell in floor_cells:
		if reachable_floor.has(cell):
			pruned_floor_cells.append(cell)
	floor_cells = pruned_floor_cells
	floor_lookup.clear()
	for cell in floor_cells:
		floor_lookup[cell] = true

	floor_cells = _ensure_floor_contract_cells(floor_cells, floor_lookup, required_hallway_floor_cells)

	floor_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	var spacing_spacing_exempt: Dictionary = hallway_all_cells.duplicate(true)
	for cell in allowed_border_walls.keys():
		spacing_spacing_exempt[cell] = true
	var spacing_err := _validate_parallel_wall_spacing(floor_lookup, opening_cells, spacing_spacing_exempt)
	if spacing_err != "":
		_last_generate_error = spacing_err
		if report_errors:
			push_error(spacing_err)
		room.free()
		return false
	var wall_items := _build_perimeter_wall_items_for_current_floor(
		floor_cells,
		floor_lookup,
		opening_cells,
		hallway_all_cells
	)

	# Randomize blockers/spawns positions after floor exists (optional per spec).
	if bool(spec.get("_randomize_positions", false)):
		var spawn_randomize_excluded := _interior_excluded_cells(size, hallway_all_cells)
		if spec.has("blockers"):
			var blockers: Array = spec.get("blockers", [])
			var new_blockers := _pick_random_floor_cells(
				floor_cells,
				opening_cells,
				blockers.size(),
				rng,
				spawn_randomize_excluded
			)
			spec["blockers"] = new_blockers
		if spec.has("spawns"):
			var spawns: Array = spec.get("spawns", [])
			var new_positions := _pick_random_floor_cells(
				floor_cells,
				opening_cells,
				spawns.size(),
				rng,
				spawn_randomize_excluded
			)
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
	var blocker_used: Dictionary = {}
	for b in blockers:
		if b is not Vector2i:
			continue
		var blocker_position := b as Vector2i
		if not reachable_floor.has(blocker_position) or hallway_all_cells.has(blocker_position):
			blocker_position = _nearest_valid_interior_floor_cell(
				blocker_position,
				floor_lookup,
				opening_cells,
				hallway_all_cells.merged(blocker_used, true)
			)
		if reachable_floor.has(blocker_position) and not hallway_all_cells.has(blocker_position) and not blocker_used.has(blocker_position):
			pruned_blockers.append(blocker_position)
			blocker_used[blocker_position] = true
	spec["blockers"] = pruned_blockers

	var blocked_lookup := _blocked_cells_lookup(spec.get("blockers", []))
	var accessibility_err := _validate_room_accessibility(floor_lookup, opening_cells, blocked_lookup)
	if accessibility_err != "":
		_last_generate_error = accessibility_err
		if report_errors:
			push_error(accessibility_err)
		room.free()
		return false

	_item_sequence = 0
	for cell in floor_cells:
		_add_item(layout, &"floor_dirt_small_a", cell)
	var forced_opening_walls := _opening_contract_wall_items(size, active_openings, center_positions)
	for forced_wall in forced_opening_walls:
		wall_items.append(forced_wall)
	wall_items = _normalize_wall_items(wall_items, opening_cells, allowed_border_walls, size)
	var wall_items_by_pos: Dictionary = {}
	for wall_item in wall_items:
		var pos: Vector2i = wall_item.get("position", Vector2i.ZERO) as Vector2i
		wall_items_by_pos[pos] = wall_item
	for fill in _build_void_corner_fillers(_room_rect(size), floor_lookup, opening_cells, wall_items_by_pos):
		var pos: Vector2i = fill.get("position", Vector2i.ZERO) as Vector2i
		if wall_items_by_pos.has(pos):
			continue
		wall_items_by_pos[pos] = fill
	wall_items.clear()
	for pos in wall_items_by_pos.keys():
		wall_items.append(wall_items_by_pos[pos])
	wall_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap := a.get("position", Vector2i.ZERO) as Vector2i
		var bp := b.get("position", Vector2i.ZERO) as Vector2i
		return ap.y < bp.y if ap.y != bp.y else ap.x < bp.x
	)
	wall_items = _normalize_wall_items(wall_items, opening_cells, allowed_border_walls, size)
	wall_items_by_pos.clear()
	for wall_item in wall_items:
		var pos: Vector2i = wall_item.get("position", Vector2i.ZERO) as Vector2i
		wall_items_by_pos[pos] = wall_item

	var prop_excluded_cells := _interior_excluded_cells(size, hallway_all_cells, wall_items_by_pos)
	var adjusted_blockers: Array[Vector2i] = []
	var adjusted_blocker_used: Dictionary = {}
	for blocker_position in spec.get("blockers", []):
		if blocker_position is not Vector2i:
			continue
		var next_blocker := _nearest_valid_interior_floor_cell(
			blocker_position,
			floor_lookup,
			opening_cells,
			prop_excluded_cells.merged(adjusted_blocker_used, true)
		)
		if adjusted_blocker_used.has(next_blocker):
			continue
		adjusted_blockers.append(next_blocker)
		adjusted_blocker_used[next_blocker] = true
	spec["blockers"] = adjusted_blockers

	var prop_marker_position := _nearest_valid_interior_floor_cell(
		spec["prop_marker"],
		floor_lookup,
		opening_cells,
		prop_excluded_cells
	)
	spec["prop_marker"] = prop_marker_position
	if spec.has("treasure"):
		var treasure_position := _nearest_valid_interior_floor_cell(
			spec["treasure"],
			floor_lookup,
			opening_cells,
			prop_excluded_cells.merged(adjusted_blocker_used, true)
		)
		spec["treasure"] = treasure_position
	var spawn_excluded_cells := _interior_excluded_cells(size, hallway_all_cells, wall_items_by_pos)
	for wall_item in wall_items:
		_add_item(
			layout,
			wall_item.get("piece_id", &"wall_straight"),
			wall_item.get("position", Vector2i.ZERO) as Vector2i,
			int(wall_item.get("rotation_steps", 0))
		)
	for marker_info in marker_plan:
		_add_marker_for_opening(
			layout,
			size,
			StringName(String(marker_info.get("side", ""))),
			String(marker_info.get("kind", "entrance")),
			center_positions[String(marker_info.get("side", ""))]
		)

	_add_item(layout, &"encounter_entry_marker", spec["entry_marker"])
	_add_item(layout, &"prop_placement_marker", prop_marker_position)
	_add_item(layout, &"nav_boundary_marker", spec["nav_marker"])

	if spec.has("loot_marker"):
		_add_item(layout, &"loot_marker", spec["loot_marker"])
	if spec.has("treasure"):
		_add_item(layout, &"treasure_chest", spec["treasure"])

	for blocker_position in spec.get("blockers", []):
		_add_item(layout, &"barrel_blocker", blocker_position)
	var exit_side := String(marker_plan.back().get("side", "")) if not marker_plan.is_empty() else ""
	for spawn_data in spec.get("spawns", []):
		var spawn_position := _nearest_valid_interior_floor_cell(
			spawn_data.get("position", Vector2i.ZERO) as Vector2i,
			floor_lookup,
			opening_cells,
			spawn_excluded_cells
		)
		if exit_side != "":
			spawn_position = _bias_spawn_cell_toward_side(
				spawn_position,
				floor_lookup,
				opening_cells,
				size,
				exit_side,
				spawn_excluded_cells
			)
		_add_item(
			layout,
			spawn_data.get("piece_id", &"spawn_melee_marker"),
			spawn_position,
			int(spawn_data.get("rotation_steps", 0)),
			StringName(String(spawn_data.get("encounter_group_id", "combat_main")))
		)

	var layout_path := "%s/layouts/%s.layout.tres" % [_output_dir, spec["scene_name"]]
	if ResourceSaver.save(layout, layout_path) != OK:
		push_error("Failed to save layout at %s" % layout_path)
		room.free()
		return false
	var scene_path := "%s/%s.tscn" % [_output_dir, spec["scene_name"]]
	if not _write_minimal_room_scene(scene_path, layout_path, spec, layout, room):
		push_error("Failed to write scene at %s" % scene_path)
		room.free()
		return false
	room.free()
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


func _find_enclosed_void_cells(floor_lookup: Dictionary, size: Vector2i) -> Dictionary:
	var room_rect := _room_rect(size)
	var outer_rect := Rect2i(room_rect.position - Vector2i.ONE, room_rect.size + Vector2i.ONE * 2)
	var outside_air: Dictionary = {}
	var queue: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

	for x in range(outer_rect.position.x, outer_rect.end.x):
		for y in [outer_rect.position.y, outer_rect.end.y - 1]:
			var edge := Vector2i(x, y)
			if floor_lookup.has(edge) or outside_air.has(edge):
				continue
			outside_air[edge] = true
			queue.append(edge)
	for y in range(outer_rect.position.y, outer_rect.end.y):
		for x in [outer_rect.position.x, outer_rect.end.x - 1]:
			var edge := Vector2i(x, y)
			if floor_lookup.has(edge) or outside_air.has(edge):
				continue
			outside_air[edge] = true
			queue.append(edge)

	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in dirs:
			var nxt := cur + d
			if not outer_rect.has_point(nxt):
				continue
			if floor_lookup.has(nxt):
				continue
			if outside_air.has(nxt):
				continue
			outside_air[nxt] = true
			queue.append(nxt)

	var enclosed: Dictionary = {}
	for x in range(room_rect.position.x, room_rect.end.x):
		for y in range(room_rect.position.y, room_rect.end.y):
			var cell := Vector2i(x, y)
			if floor_lookup.has(cell):
				continue
			if outside_air.has(cell):
				continue
			enclosed[cell] = true
	return enclosed


func _fill_enclosed_void_pockets(
	floor_cells: Array[Vector2i],
	floor_lookup: Dictionary,
	size: Vector2i
) -> Array[Vector2i]:
	var enclosed := _find_enclosed_void_cells(floor_lookup, size)
	if enclosed.is_empty():
		return floor_cells
	for cell in enclosed.keys():
		if floor_lookup.has(cell):
			continue
		floor_lookup[cell] = true
		floor_cells.append(cell)
	return floor_cells


func _opening_contract_boundary_wall_positions(size: Vector2i, openings: Array, center_positions: Dictionary) -> Dictionary:
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	var out: Dictionary = {}
	for raw_side in openings:
		var side := String(raw_side)
		var center: int = int(center_positions.get(side, 0))
		match side:
			"north":
				out[Vector2i(center - 2, top)] = true
				out[Vector2i(center + 2, top)] = true
			"south":
				out[Vector2i(center - 2, bottom)] = true
				out[Vector2i(center + 2, bottom)] = true
			"east":
				out[Vector2i(right, center - 2)] = true
				out[Vector2i(right, center + 2)] = true
			"west":
				out[Vector2i(left, center - 2)] = true
				out[Vector2i(left, center + 2)] = true
	return out


func _strip_non_hallway_border_band_floor_cells(
	floor_cells: Array[Vector2i],
	floor_lookup: Dictionary,
	size: Vector2i,
	allowed_hallway_cells: Dictionary,
	clearance_tiles: int = BORDER_CLEARANCE_TILES
) -> Array[Vector2i]:
	var rect := _room_rect(size)
	var out: Array[Vector2i] = []
	for cell in floor_cells:
		var c := cell as Vector2i
		var border_distance := mini(
			mini(c.x - rect.position.x, rect.end.x - 1 - c.x),
			mini(c.y - rect.position.y, rect.end.y - 1 - c.y)
		)
		if border_distance < clearance_tiles and not allowed_hallway_cells.has(c):
			floor_lookup.erase(c)
			continue
		out.append(c)
	return out


func _normalized_wall_item_for_neighbors(pos: Vector2i, structure_lookup: Dictionary, existing: Dictionary) -> Dictionary:
	if bool(existing.get("_forced_contract", false)):
		return existing.duplicate(true)
	var has_left := structure_lookup.has(pos + Vector2i.LEFT)
	var has_right := structure_lookup.has(pos + Vector2i.RIGHT)
	var has_up := structure_lookup.has(pos + Vector2i.UP)
	var has_down := structure_lookup.has(pos + Vector2i.DOWN)
	var neighbor_count := int(has_left) + int(has_right) + int(has_up) + int(has_down)
	var item := existing.duplicate(true)
	item["position"] = pos

	var horizontal := int(has_left) + int(has_right)
	var vertical := int(has_up) + int(has_down)
	if neighbor_count == 2 and horizontal == 1 and vertical == 1:
		item["piece_id"] = &"wall_corner"
		item["rotation_steps"] = _corner_rotation_for_walls(has_left, has_right, has_up, has_down)
		return item
	if horizontal > 0 and vertical == 0:
		item["piece_id"] = &"wall_straight"
		item["rotation_steps"] = 0
		return item
	if vertical > 0 and horizontal == 0:
		item["piece_id"] = &"wall_straight"
		item["rotation_steps"] = 1
		return item
	if existing.get("piece_id", &"") == &"wall_corner":
		item["rotation_steps"] = _corner_rotation_for_walls(has_left, has_right, has_up, has_down)
		return item
	item["piece_id"] = &"wall_straight"
	item["rotation_steps"] = 1 if vertical >= horizontal else 0
	return item


func _normalize_wall_items(
	wall_items: Array[Dictionary],
	opening_cells: Dictionary,
	allowed_border_walls: Dictionary,
	size: Vector2i
) -> Array[Dictionary]:
	var rect := _room_rect(size)
	var items_by_pos: Dictionary = {}
	for item in wall_items:
		var pos: Vector2i = item.get("position", Vector2i.ZERO) as Vector2i
		var on_border := (
			pos.x == rect.position.x
			or pos.x == rect.end.x - 1
			or pos.y == rect.position.y
			or pos.y == rect.end.y - 1
		)
		if on_border and not allowed_border_walls.has(pos):
			continue
		if items_by_pos.has(pos):
			var existing: Dictionary = items_by_pos[pos]
			var existing_forced := bool(existing.get("_forced_contract", false))
			var next_forced := bool(item.get("_forced_contract", false))
			if existing_forced and not next_forced:
				continue
			if existing_forced and next_forced:
				var existing_piece: StringName = existing.get("piece_id", &"")
				var next_piece: StringName = item.get("piece_id", &"")
				if existing_piece == &"wall_corner" and next_piece != &"wall_corner":
					continue
		items_by_pos[pos] = item.duplicate(true)

	var structure_lookup: Dictionary = opening_cells.duplicate(true)
	for pos in items_by_pos.keys():
		structure_lookup[pos] = true

	var out: Array[Dictionary] = []
	for pos in items_by_pos.keys():
		out.append(_normalized_wall_item_for_neighbors(pos, structure_lookup, items_by_pos[pos]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap: Vector2i = a.get("position", Vector2i.ZERO) as Vector2i
		var bp: Vector2i = b.get("position", Vector2i.ZERO) as Vector2i
		return ap.y < bp.y if ap.y != bp.y else ap.x < bp.x
	)
	return out


func _build_perimeter_wall_items_for_current_floor(
	floor_cells: Array[Vector2i],
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	excluded_cells: Dictionary = {}
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell in floor_cells:
		var c := cell as Vector2i
		if opening_cells.has(c) or excluded_cells.has(c):
			continue
		var should_wall := false
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not _is_solid_floor_cell(floor_lookup, opening_cells, c + direction):
				should_wall = true
				break
		if not should_wall:
			continue
		out.append(_wall_item_for_cell(c, floor_lookup, opening_cells))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap: Vector2i = a.get("position", Vector2i.ZERO) as Vector2i
		var bp: Vector2i = b.get("position", Vector2i.ZERO) as Vector2i
		return ap.y < bp.y if ap.y != bp.y else ap.x < bp.x
	)
	return out


func _rect_from_cells(cells: Array[Vector2i]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var min_x := cells[0].x
	var max_x := cells[0].x
	var min_y := cells[0].y
	var max_y := cells[0].y
	for c in cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_y = mini(min_y, c.y)
		max_y = maxi(max_y, c.y)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))


func _build_wall_items(
	floor_cells: Array[Vector2i],
	opening_cells: Dictionary,
	passage_cells: Dictionary = {},
	protected_cells: Dictionary = {}
) -> Array[Dictionary]:
	var floor_lookup: Dictionary = {}
	for cell in floor_cells:
		floor_lookup[cell] = true

	var wall_lookup: Dictionary = {}
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var reachable_floor := _reachable_floor_region_from_center(floor_lookup, opening_cells)

	for cell in floor_cells:
		if not reachable_floor.has(cell):
			continue
		if opening_cells.has(cell) or passage_cells.has(cell) or protected_cells.has(cell):
			continue
		var should_wall := false
		for direction in directions:
			if not _is_solid_floor_cell(floor_lookup, opening_cells, cell + direction):
				should_wall = true
				break
		if should_wall:
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
		var wall_n := int(has_left) + int(has_right) + int(has_up) + int(has_down)
		if wall_n != 2:
			continue
		var rot := _corner_rotation_for_walls(has_left, has_right, has_up, has_down)
		item["rotation_steps"] = rot
		items_by_pos[p] = item

	for fill in _build_void_corner_fillers(_rect_from_cells(floor_cells), floor_lookup, opening_cells, items_by_pos):
		var pos: Vector2i = fill.get("position", Vector2i.ZERO) as Vector2i
		if items_by_pos.has(pos):
			continue
		items_by_pos[pos] = fill

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


func _apply_opening_wall_contract(
	wall_items: Array[Dictionary],
	size: Vector2i,
	openings: Array,
	center_positions: Dictionary
) -> Array[Dictionary]:
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	var items_by_pos: Dictionary = {}
	for item in wall_items:
		if item == null:
			continue
		var pos: Vector2i = item.get("position", Vector2i.ZERO) as Vector2i
		items_by_pos[pos] = item
	for raw_side in openings:
		var side := String(raw_side)
		var center: int = int(center_positions.get(side, 0))
		match side:
			"north":
				items_by_pos[Vector2i(center - 2, top)] = {"piece_id": &"wall_straight", "position": Vector2i(center - 2, top), "rotation_steps": 0}
				items_by_pos[Vector2i(center + 2, top)] = {"piece_id": &"wall_straight", "position": Vector2i(center + 2, top), "rotation_steps": 0}
				items_by_pos[Vector2i(center - 2, top + 1)] = {"piece_id": &"wall_straight", "position": Vector2i(center - 2, top + 1), "rotation_steps": 1}
				items_by_pos[Vector2i(center + 2, top + 1)] = {"piece_id": &"wall_straight", "position": Vector2i(center + 2, top + 1), "rotation_steps": 1}
			"south":
				items_by_pos[Vector2i(center - 2, bottom)] = {"piece_id": &"wall_straight", "position": Vector2i(center - 2, bottom), "rotation_steps": 0}
				items_by_pos[Vector2i(center + 2, bottom)] = {"piece_id": &"wall_straight", "position": Vector2i(center + 2, bottom), "rotation_steps": 0}
				items_by_pos[Vector2i(center - 2, bottom - 1)] = {"piece_id": &"wall_straight", "position": Vector2i(center - 2, bottom - 1), "rotation_steps": 1}
				items_by_pos[Vector2i(center + 2, bottom - 1)] = {"piece_id": &"wall_straight", "position": Vector2i(center + 2, bottom - 1), "rotation_steps": 1}
			"east":
				items_by_pos[Vector2i(right, center - 2)] = {"piece_id": &"wall_straight", "position": Vector2i(right, center - 2), "rotation_steps": 1}
				items_by_pos[Vector2i(right, center + 2)] = {"piece_id": &"wall_straight", "position": Vector2i(right, center + 2), "rotation_steps": 1}
				items_by_pos[Vector2i(right - 1, center - 2)] = {"piece_id": &"wall_straight", "position": Vector2i(right - 1, center - 2), "rotation_steps": 0}
				items_by_pos[Vector2i(right - 1, center + 2)] = {"piece_id": &"wall_straight", "position": Vector2i(right - 1, center + 2), "rotation_steps": 0}
			"west":
				items_by_pos[Vector2i(left, center - 2)] = {"piece_id": &"wall_straight", "position": Vector2i(left, center - 2), "rotation_steps": 1}
				items_by_pos[Vector2i(left, center + 2)] = {"piece_id": &"wall_straight", "position": Vector2i(left, center + 2), "rotation_steps": 1}
				items_by_pos[Vector2i(left + 1, center - 2)] = {"piece_id": &"wall_straight", "position": Vector2i(left + 1, center - 2), "rotation_steps": 0}
				items_by_pos[Vector2i(left + 1, center + 2)] = {"piece_id": &"wall_straight", "position": Vector2i(left + 1, center + 2), "rotation_steps": 0}
	var out: Array[Dictionary] = []
	for item in items_by_pos.values():
		out.append(item)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap := a.get("position", Vector2i.ZERO) as Vector2i
		var bp := b.get("position", Vector2i.ZERO) as Vector2i
		return ap.y < bp.y if ap.y != bp.y else ap.x < bp.x
	)
	return out


func _opening_contract_wall_items(size: Vector2i, openings: Array, center_positions: Dictionary) -> Array[Dictionary]:
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	var out: Array[Dictionary] = []
	for raw_side in openings:
		var side := String(raw_side)
		var center: int = int(center_positions.get(side, 0))
		match side:
			"north":
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 2, top), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 2, top), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 2, top + 1), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 2, top + 1), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 2, top + 2), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 2, top + 2), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(center - 2, top + 3), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(center + 2, top + 3), "rotation_steps": 2, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 3, top + 3), "rotation_steps": 0})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 3, top + 3), "rotation_steps": 0})
			"south":
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 2, bottom), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 2, bottom), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 2, bottom - 1), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 2, bottom - 1), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 2, bottom - 2), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 2, bottom - 2), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(center - 2, bottom - 3), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(center + 2, bottom - 3), "rotation_steps": 3, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center - 3, bottom - 3), "rotation_steps": 0})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(center + 3, bottom - 3), "rotation_steps": 0})
			"east":
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right, center - 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right, center + 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right - 1, center - 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right - 1, center + 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right - 2, center - 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right - 2, center + 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(right - 3, center - 2), "rotation_steps": 2, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(right - 3, center + 2), "rotation_steps": 3, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right - 3, center - 3), "rotation_steps": 1})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(right - 3, center + 3), "rotation_steps": 1})
			"west":
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left, center - 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left, center + 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left + 1, center - 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left + 1, center + 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left + 2, center - 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left + 2, center + 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(left + 3, center - 2), "rotation_steps": 1, "_forced_contract": true})
				out.append({"piece_id": &"wall_corner", "position": Vector2i(left + 3, center + 2), "rotation_steps": 0, "_forced_contract": true})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left + 3, center - 3), "rotation_steps": 1})
				out.append({"piece_id": &"wall_straight", "position": Vector2i(left + 3, center + 3), "rotation_steps": 1})
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


func _build_void_corner_fillers(
	room_rect: Rect2i,
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	wall_items_by_pos: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for y in range(room_rect.position.y, room_rect.end.y):
		for x in range(room_rect.position.x, room_rect.end.x):
			var cell := Vector2i(x, y)
			var border_distance := mini(
				mini(cell.x - room_rect.position.x, room_rect.end.x - 1 - cell.x),
				mini(cell.y - room_rect.position.y, room_rect.end.y - 1 - cell.y)
			)
			if border_distance < BORDER_CLEARANCE_TILES:
				continue
			if floor_lookup.has(cell) or opening_cells.has(cell) or wall_items_by_pos.has(cell):
				continue
			var has_left := wall_items_by_pos.has(cell + Vector2i.LEFT)
			var has_right := wall_items_by_pos.has(cell + Vector2i.RIGHT)
			var has_up := wall_items_by_pos.has(cell + Vector2i.UP)
			var has_down := wall_items_by_pos.has(cell + Vector2i.DOWN)
			var neighbor_count := int(has_left) + int(has_right) + int(has_up) + int(has_down)
			var horizontal := int(has_left) + int(has_right)
			var vertical := int(has_up) + int(has_down)
			if neighbor_count != 2 or horizontal != 1 or vertical != 1:
				continue
			var inside_floor := Vector2i.ZERO
			if has_left and has_up:
				inside_floor = cell + Vector2i(-1, -1)
			elif has_right and has_up:
				inside_floor = cell + Vector2i(1, -1)
			elif has_right and has_down:
				inside_floor = cell + Vector2i(1, 1)
			elif has_left and has_down:
				inside_floor = cell + Vector2i(-1, 1)
			else:
				continue
			if not _is_solid_floor_cell(floor_lookup, opening_cells, inside_floor):
				continue
			out.append({
				"piece_id": &"wall_corner",
				"position": cell,
				"rotation_steps": _corner_rotation_for_walls(has_left, has_right, has_up, has_down),
			})
	return out


func _missing_solid_neighbor_count(cell: Vector2i, floor_lookup: Dictionary, opening_cells: Dictionary) -> int:
	var count := 0
	for off in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not _is_solid_floor_cell(floor_lookup, opening_cells, cell + off):
			count += 1
	return count


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


func _validate_parallel_wall_spacing(
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	exempt_cells: Dictionary = {}
) -> String:
	for cell in floor_lookup.keys():
		var c := cell as Vector2i
		if opening_cells.has(c) or exempt_cells.has(c):
			continue
		var horizontal_gap := _parallel_floor_gap_for_axis(c, floor_lookup, opening_cells, true)
		if horizontal_gap >= 0 and horizontal_gap < MIN_PARALLEL_WALL_FLOOR_GAP_TILES:
			return "Parallel wall spacing violation (horizontal floor gap=%s) at %s" % [horizontal_gap, c]
		var vertical_gap := _parallel_floor_gap_for_axis(c, floor_lookup, opening_cells, false)
		if vertical_gap >= 0 and vertical_gap < MIN_PARALLEL_WALL_FLOOR_GAP_TILES:
			return "Parallel wall spacing violation (vertical floor gap=%s) at %s" % [vertical_gap, c]
	return ""


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
				cells[Vector2i(left, 1)] = true
			&"east":
				cells[Vector2i(right, -1)] = true
				cells[Vector2i(right, 0)] = true
				cells[Vector2i(right, 1)] = true
			&"north":
				cells[Vector2i(-1, top)] = true
				cells[Vector2i(0, top)] = true
				cells[Vector2i(1, top)] = true
			&"south":
				cells[Vector2i(-1, bottom)] = true
				cells[Vector2i(0, bottom)] = true
				cells[Vector2i(1, bottom)] = true
	return cells


func _build_hallway_geometry(size: Vector2i, openings: Array, rng: RandomNumberGenerator, center_span: int = -1) -> Dictionary:
	# Build the full hallway mouth contract first so the room conforms to it:
	#   border opening row:     3 opening cells on the room edge
	#   inner passage row:      flank walls + 3 floor passage cells
	#   boundary support row:   corner walls + 3 floor cells
	#   interior apron row:     7 floor cells to guarantee usable width beyond the mouth
	#
	# The room body can then be carved/pruned around this protected footprint without
	# collapsing the exit shape or violating the minimum 3-floor-tile spacing rule.
	# Returns:
	#   all_cells       – every protected floor/wall-support tile in the hallway mouth
	#   passage_cells   – the inward row of 3 passage tiles
	#   opening_cells   – the 3 border connection cells
	#   apron_cells     – the first 7-wide interior row beyond the mouth
	#   carve_void_cells – floor cells that must be removed so the mouth keeps its notch shape
	#   center_positions – maps side name to the chosen center offset
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1

	var all_cells: Dictionary = {}
	var passage_cells: Dictionary = {}
	var opening_cells: Dictionary = {}
	var support_floor_cells: Dictionary = {}
	var apron_cells: Dictionary = {}
	var carve_void_cells: Dictionary = {}
	var center_positions: Dictionary = {}

	var orthogonal_pair_sign := -1 if rng.randi_range(0, 1) == 0 else 1
	for raw_side in openings:
		var side := String(raw_side)
		var center: int
		match side:
			"west", "east":
				center = _random_opening_center_for_side(side, left, right, top, bottom, rng, orthogonal_pair_sign, center_span)
				center_positions[side] = center
				var boundary_x: int
				var inner_x: int
				if side == "west":
					boundary_x = left
					inner_x = left + 1
				else:
					boundary_x = right
					inner_x = right - 1
				for dy in range(-1, 2):
					var opening := Vector2i(boundary_x, center + dy)
					var passage := Vector2i(inner_x, center + dy)
					opening_cells[opening] = true
					all_cells[opening] = true
					all_cells[passage] = true
					passage_cells[passage] = true
				var support_x := inner_x + 1 if side == "west" else inner_x - 1
				for dy in range(-1, 2):
					var support_floor := Vector2i(support_x, center + dy)
					all_cells[support_floor] = true
					support_floor_cells[support_floor] = true
				all_cells[Vector2i(inner_x, center - 2)] = true
				all_cells[Vector2i(inner_x, center + 2)] = true
				carve_void_cells[Vector2i(inner_x, center - 3)] = true
				carve_void_cells[Vector2i(inner_x, center + 3)] = true
				for dy in range(-3, 4):
					var apron := Vector2i(support_x + 1 if side == "west" else support_x - 1, center + dy)
					all_cells[apron] = true
					apron_cells[apron] = true
			"north", "south":
				center = _random_opening_center_for_side(side, left, right, top, bottom, rng, orthogonal_pair_sign, center_span)
				center_positions[side] = center
				var boundary_y: int
				var inner_y: int
				if side == "north":
					boundary_y = top
					inner_y = top + 1
				else:
					boundary_y = bottom
					inner_y = bottom - 1
				for dx in range(-1, 2):
					var opening := Vector2i(center + dx, boundary_y)
					var passage := Vector2i(center + dx, inner_y)
					opening_cells[opening] = true
					all_cells[opening] = true
					all_cells[passage] = true
					passage_cells[passage] = true
				var support_y := inner_y + 1 if side == "north" else inner_y - 1
				for dx in range(-1, 2):
					var support_floor := Vector2i(center + dx, support_y)
					all_cells[support_floor] = true
					support_floor_cells[support_floor] = true
				all_cells[Vector2i(center - 2, inner_y)] = true
				all_cells[Vector2i(center + 2, inner_y)] = true
				carve_void_cells[Vector2i(center - 3, inner_y)] = true
				carve_void_cells[Vector2i(center + 3, inner_y)] = true
				for dx in range(-3, 4):
					var apron := Vector2i(center + dx, support_y + 1 if side == "north" else support_y - 1)
					all_cells[apron] = true
					apron_cells[apron] = true

	return {
		"all_cells": all_cells,
		"passage_cells": passage_cells,
		"opening_cells": opening_cells,
		"support_floor_cells": support_floor_cells,
		"apron_cells": apron_cells,
		"carve_void_cells": carve_void_cells,
		"center_positions": center_positions,
	}


func _build_marker_plan(room_type: String, openings: Array) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if openings.is_empty():
		return plan
	var first_side := StringName(openings.front())
	var last_side := StringName(openings.back())
	match room_type:
		"treasure", "boss":
			plan.append({"kind": "entrance", "side": first_side})
		"safe":
			plan.append({"kind": "exit", "side": first_side})
		_:
			plan.append({"kind": "entrance", "side": first_side})
			plan.append({"kind": "exit", "side": last_side})
	return plan


func _random_opening_center_for_side(
	side: String,
	left: int,
	right: int,
	top: int,
	bottom: int,
	rng: RandomNumberGenerator,
	orthogonal_pair_sign: int,
	center_span: int = -1
) -> int:
	var vertical_min := top + 5
	var vertical_max := bottom - 5
	if vertical_min > vertical_max:
		vertical_min = top + 3
		vertical_max = bottom - 3
	var horizontal_min := left + 5
	var horizontal_max := right - 5
	if horizontal_min > horizontal_max:
		horizontal_min = left + 3
		horizontal_max = right - 3
	if center_span >= 0:
		vertical_min = maxi(vertical_min, -center_span)
		vertical_max = mini(vertical_max, center_span)
		horizontal_min = maxi(horizontal_min, -center_span)
		horizontal_max = mini(horizontal_max, center_span)
		if vertical_min > vertical_max:
			vertical_min = clampi(0, top + 3, bottom - 3)
			vertical_max = vertical_min
		if horizontal_min > horizontal_max:
			horizontal_min = clampi(0, left + 3, right - 3)
			horizontal_max = horizontal_min
	match side:
		"west":
			return _random_center_in_range(vertical_min, vertical_max, rng, orthogonal_pair_sign)
		"east":
			return _random_center_in_range(vertical_min, vertical_max, rng, -orthogonal_pair_sign)
		"north":
			return _random_center_in_range(horizontal_min, horizontal_max, rng, orthogonal_pair_sign)
		"south":
			return _random_center_in_range(horizontal_min, horizontal_max, rng, -orthogonal_pair_sign)
		_:
			return 0


func _random_center_in_range(min_value: int, max_value: int, rng: RandomNumberGenerator, preferred_sign: int) -> int:
	if min_value >= max_value:
		return min_value
	var values: Array[int] = []
	for v in range(min_value, max_value + 1):
		values.append(v)
	var preferred: Array[int] = []
	var fallback: Array[int] = []
	for v in values:
		if preferred_sign < 0 and v < 0:
			preferred.append(v)
		elif preferred_sign > 0 and v > 0:
			preferred.append(v)
		else:
			fallback.append(v)
	if not preferred.is_empty():
		return preferred[rng.randi_range(0, preferred.size() - 1)]
	return fallback[rng.randi_range(0, fallback.size() - 1)]


func _add_marker_for_opening(
	layout, size: Vector2i, side: StringName, marker_kind: String, hallway_center: int = 0
) -> void:
	var rect := _room_rect(size)
	var left := rect.position.x
	var right := rect.position.x + rect.size.x - 1
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y - 1
	var rotation_steps := _marker_rotation_for_opening_side(side)
	var piece_id: StringName = &"entrance_marker" if marker_kind == "entrance" else &"exit_marker"
	match side:
		&"west":
			_add_item(layout, piece_id, Vector2i(left, hallway_center - 1), rotation_steps)
		&"east":
			_add_item(layout, piece_id, Vector2i(right, hallway_center - 1), rotation_steps)
		&"north":
			_add_item(layout, piece_id, Vector2i(hallway_center - 1, top), rotation_steps)
		&"south":
			_add_item(layout, piece_id, Vector2i(hallway_center - 1, bottom), rotation_steps)


func _marker_rotation_for_opening_side(side: StringName) -> int:
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


func _bias_spawn_cell_toward_side(
	cell: Vector2i,
	floor_lookup: Dictionary,
	opening_cells: Dictionary,
	size: Vector2i,
	side: String,
	excluded_cells: Dictionary = {}
) -> Vector2i:
	if _is_cell_in_side_half(cell, size, side) and not excluded_cells.has(cell):
		return cell
	var best := cell
	var best_dist := 1_000_000.0
	for candidate in floor_lookup.keys():
		var c := candidate as Vector2i
		if opening_cells.has(c):
			continue
		if excluded_cells.has(c):
			continue
		if not _is_cell_in_side_half(c, size, side):
			continue
		var dist := cell.distance_squared_to(c)
		if dist < best_dist:
			best_dist = dist
			best = c
	return best


func _is_cell_in_side_half(cell: Vector2i, size: Vector2i, side: String) -> bool:
	match side:
		"east":
			return float(cell.x) >= 0.0
		"west":
			return float(cell.x) <= 0.0
		"north":
			return float(cell.y) <= 0.0
		"south":
			return float(cell.y) >= 0.0
		_:
			return true


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
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://dungeon/modules/connectivity/entrance_marker_2d.tscn\" id=\"3_entrance\"]")
	lines.append("[ext_resource type=\"PackedScene\" path=\"res://dungeon/modules/connectivity/exit_marker_2d.tscn\" id=\"5_exit\"]")
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
	var entrance_piece = _catalog.find_piece(&"entrance_marker")
	var exit_piece = _catalog.find_piece(&"exit_marker")
	for item in layout.items:
		if item == null or (item.piece_id != &"entrance_marker" and item.piece_id != &"exit_marker"):
			continue
		var direction := _direction_name(item.rotation_steps)
		var is_entrance: bool = item.piece_id == &"entrance_marker"
		var piece = entrance_piece if is_entrance else exit_piece
		var resource_id := "3_entrance" if is_entrance else "5_exit"
		lines.append(
			"[node name=\"%s_%s\" parent=\"Sockets/GeneratedByRoomEditor\" instance=ExtResource(\"%s\")]"
			% [String(item.piece_id), item.item_id, resource_id]
		)
		var marker_pos := _connection_marker_center_world(item.grid_position, direction)
		lines.append("position = Vector2(%s, %s)" % [marker_pos.x, marker_pos.y])
		lines.append("rotation = %s" % (float(item.rotation_steps) * PI * 0.5))
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


func _connection_marker_center_world(grid_position: Vector2i, direction: String) -> Vector2:
	match direction:
		"north":
			return _grid_to_world(grid_position + Vector2i(1, 0))
		"south":
			return _grid_to_world(grid_position + Vector2i(1, 0))
		"east":
			return _grid_to_world(grid_position + Vector2i(0, 1))
		"west":
			return _grid_to_world(grid_position + Vector2i(0, 1))
		_:
			return _grid_to_world(grid_position)


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
