@tool
extends SceneTree

const BASE_ROOM_SCENE := preload("res://dungeon/rooms/base/room_base.tscn")
const CATALOG_PATH := "res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres"
const LAYOUT_SCRIPT := preload("res://addons/dungeon_room_editor/resources/room_layout_data.gd")
const ITEM_SCRIPT := preload("res://addons/dungeon_room_editor/resources/room_placed_item_data.gd")

const OUTPUT_DIR := "res://dungeon/rooms/authored/outlines"
const DEFAULT_GRID_SIZE := Vector2i(3, 3)
const HALLWAY_WIDTH := 2

var _catalog
var _item_sequence: int = 0


func _initialize() -> void:
	_catalog = load(CATALOG_PATH)
	if _catalog == null:
		push_error("Failed to load room piece catalog at %s" % CATALOG_PATH)
		quit(1)
		return
	var make_dir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if make_dir_result != OK:
		push_error("Failed to create output directory %s" % OUTPUT_DIR)
		quit(1)
		return

	var room_specs := _build_room_specs()
	for spec in room_specs:
		if not _generate_room(spec):
			quit(1)
			return

	print("GENERATED_OUTLINE_ROOMS_OK")
	quit()


func _build_room_specs() -> Array[Dictionary]:
	return [
		{
			"scene_name": "room_combat_skirmish_small_a",
			"room_id": "room_combat_skirmish_small_a",
			"size": Vector2i(10, 10),
			"size_class": "small",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "small"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["melee_pack"]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-5, -5, 2, 2), Rect2i(3, 2, 2, 2)],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-2, 0),
			"prop_marker": Vector2i(2, -2),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-1, -1), Vector2i(1, 1)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(2, -1)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(2, 2)},
			],
		},
		{
			"scene_name": "room_combat_tactical_medium_a",
			"room_id": "room_combat_tactical_medium_a",
			"size": Vector2i(16, 16),
			"size_class": "medium",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["mixed_patrol"]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-8, -8, 3, 4), Rect2i(5, 4, 3, 4)],
			"openings": [&"west", &"east", &"north"],
			"entry_marker": Vector2i(-5, 0),
			"prop_marker": Vector2i(4, 3),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-2, 2), Vector2i(2, -2)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(-3, -4)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(4, 3)},
				{"piece_id": &"spawn_arrow_tower_marker", "position": Vector2i(1, 5)},
			],
		},
		{
			"scene_name": "room_arena_wave_large_a",
			"room_id": "room_arena_wave_large_a",
			"size": Vector2i(24, 24),
			"size_class": "arena",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "large"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["wave_swarm"]),
			"base_shape": "full",
			"remove_rects": [
				Rect2i(-12, -12, 2, 2),
				Rect2i(10, -12, 2, 2),
				Rect2i(-12, 10, 2, 2),
				Rect2i(10, 10, 2, 2),
			],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-8, 0),
			"prop_marker": Vector2i(8, -3),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-4, 0), Vector2i(4, 0)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(-6, -5)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(6, -4)},
				{"piece_id": &"spawn_iron_sentinel_marker", "position": Vector2i(0, 6)},
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(-5, 5)},
				{"piece_id": &"spawn_arrow_tower_marker", "position": Vector2i(6, 5)},
			],
		},
		{
			"scene_name": "room_connector_narrow_medium_a",
			"room_id": "room_connector_narrow_medium_a",
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
			"scene_name": "room_connector_turn_medium_a",
			"room_id": "room_connector_turn_medium_a",
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
			"scene_name": "room_connector_junction_medium_a",
			"room_id": "room_connector_junction_medium_a",
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
			"scene_name": "room_treasure_reward_small_a",
			"room_id": "room_treasure_reward_small_a",
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
			"scene_name": "room_chokepoint_gate_medium_a",
			"room_id": "room_chokepoint_gate_medium_a",
			"size": Vector2i(16, 10),
			"size_class": "medium",
			"room_type": "arena",
			"room_tags": PackedStringArray(["arena", "combat", "chokepoint", "medium"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["pressure_lane"]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-8, -5, 4, 3), Rect2i(4, 2, 4, 3)],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-5, 0),
			"prop_marker": Vector2i(3, -2),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(0, -1), Vector2i(0, 1), Vector2i(2, 0)],
			"spawns": [
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(4, -1)},
				{"piece_id": &"spawn_dasher_marker", "position": Vector2i(3, 2)},
				{"piece_id": &"spawn_arrow_tower_marker", "position": Vector2i(5, 0)},
			],
		},
		{
			"scene_name": "room_boss_approach_large_a",
			"room_id": "room_boss_approach_large_a",
			"size": Vector2i(16, 24),
			"size_class": "large",
			"room_type": "boss",
			"room_tags": PackedStringArray(["boss", "boss_approach", "connector", "large"]),
			"allowed_connection_types": PackedStringArray(["corridor", "connector", "arena"]),
			"recommended_enemy_groups": PackedStringArray(["elite_guard"]),
			"base_shape": "full",
			"remove_rects": [Rect2i(-8, -12, 4, 5), Rect2i(4, 7, 4, 5)],
			"openings": [&"west", &"east"],
			"entry_marker": Vector2i(-6, 0),
			"prop_marker": Vector2i(5, -4),
			"nav_marker": Vector2i(0, 0),
			"blockers": [Vector2i(-3, 0), Vector2i(3, 0)],
			"spawns": [
				{"piece_id": &"spawn_iron_sentinel_marker", "position": Vector2i(4, -2)},
				{"piece_id": &"spawn_robot_mob_marker", "position": Vector2i(5, 3)},
			],
		},
	]


func _generate_room(spec: Dictionary) -> bool:
	var room := BASE_ROOM_SCENE.instantiate()
	if room == null:
		push_error("Failed to instantiate base room scene.")
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
	var wall_cells := _build_wall_cells(floor_cells, opening_cells)

	_item_sequence = 0
	for cell in floor_cells:
		_add_item(layout, &"floor_dirt_small_a", cell)
	for cell in wall_cells:
		_add_item(layout, &"wall_straight", cell)
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

	var layout_path := "%s/%s.layout.tres" % [OUTPUT_DIR, spec["scene_name"]]
	if ResourceSaver.save(layout, layout_path) != OK:
		push_error("Failed to save layout at %s" % layout_path)
		return false
	var scene_path := "%s/%s.tscn" % [OUTPUT_DIR, spec["scene_name"]]
	if not _write_minimal_room_scene(scene_path, layout_path, spec, layout):
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


func _build_wall_cells(floor_cells: Array[Vector2i], opening_cells: Dictionary) -> Array[Vector2i]:
	var floor_lookup: Dictionary = {}
	for cell in floor_cells:
		floor_lookup[cell] = true

	var wall_lookup: Dictionary = {}
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell in floor_cells:
		var should_wall := false
		for direction in directions:
			if not floor_lookup.has(cell + direction):
				should_wall = true
				break
		if should_wall and not opening_cells.has(cell):
			wall_lookup[cell] = true

	var out: Array[Vector2i] = []
	for cell in wall_lookup.keys():
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return out


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
	var rect := _room_rect(size)
	var left := rect.position.x
	var right_boundary := rect.position.x + rect.size.x
	var top := rect.position.y
	var bottom_boundary := rect.position.y + rect.size.y
	match side:
		&"west":
			_add_item(layout, &"hall_socket_double", Vector2i(left, 0), 3)
		&"east":
			_add_item(layout, &"hall_socket_double", Vector2i(right_boundary, 0), 1)
		&"north":
			_add_item(layout, &"hall_socket_double", Vector2i(0, top), 0)
		&"south":
			_add_item(layout, &"hall_socket_double", Vector2i(0, bottom_boundary), 2)


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


func _write_minimal_room_scene(scene_path: String, layout_path: String, spec: Dictionary, layout) -> bool:
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
	for item in layout.items:
		if item == null or item.piece_id != &"hall_socket_double":
			continue
		var direction := _direction_name(item.rotation_steps)
		lines.append(
			"[node name=\"%s_%s\" parent=\"Sockets/GeneratedByRoomEditor\" instance=ExtResource(\"3_socket\")]"
			% [String(item.piece_id), item.item_id]
		)
		lines.append("position = Vector2(%s, %s)" % [_grid_to_world(item.grid_position).x, _grid_to_world(item.grid_position).y])
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
