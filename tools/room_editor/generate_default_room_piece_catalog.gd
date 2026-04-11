extends SceneTree

const CatalogScript = preload("res://addons/dungeon_room_editor/resources/room_piece_catalog.gd")
const PieceDefinitionScript = preload("res://addons/dungeon_room_editor/resources/room_piece_definition.gd")

const OUTPUT_PATH := "res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres"
const FLOOR_DIR := "res://assets/structure/floors"
const WALL_DIR := "res://assets/structure/walls"
const PROP_DIR := "res://assets/props"

const SKIP_GENERATED_ASSET_PATHS := {
	"res://assets/structure/floors/floor_dirt_small_A.gltf": true,
	"res://assets/structure/walls/wall.gltf": true,
}


func _init() -> void:
	var catalog = CatalogScript.new()
	var pieces: Array[Resource] = []
	var used_piece_ids: Dictionary = {}

	_add_manual_pieces(pieces, used_piece_ids)
	_add_generated_visual_pieces(
		pieces,
		used_piece_ids,
		FLOOR_DIR,
		&"floor",
		&"ground",
		true,
		false,
		false
	)
	_add_generated_visual_pieces(
		pieces,
		used_piece_ids,
		WALL_DIR,
		&"wall",
		&"overlay",
		false,
		true,
		true
	)
	_add_generated_visual_pieces(
		pieces,
		used_piece_ids,
		PROP_DIR,
		&"prop",
		&"overlay",
		false,
		false,
		false
	)

	catalog.pieces = pieces
	var save_error := ResourceSaver.save(catalog, OUTPUT_PATH)
	if save_error != OK:
		push_error("Failed to save room piece catalog to %s (error %d)." % [OUTPUT_PATH, save_error])
		quit(1)
		return

	print(
		"Generated room piece catalog at %s with %d pieces (%d floors, %d walls, %d props, %d gameplay markers)." % [
			OUTPUT_PATH,
			pieces.size(),
			_count_category(pieces, &"floor"),
			_count_category(pieces, &"wall"),
			_count_category(pieces, &"prop"),
			pieces.size() - _count_category(pieces, &"floor") - _count_category(pieces, &"wall") - _count_category(pieces, &"prop")
		]
	)
	quit(0)


func _add_manual_pieces(pieces: Array[Resource], used_piece_ids: Dictionary) -> void:
	var floor_piece = _make_piece(
		&"floor_dirt_small_a",
		"Floor Dirt Small A",
		&"floor",
		"res://assets/structure/floors/floor_dirt_small_A.gltf",
		"",
		&"visual_only",
		true,
		&"ground",
		false,
		false,
		PackedStringArray(["floor"])
	)
	_register_piece(pieces, used_piece_ids, floor_piece)

	var wall_piece = _make_piece(
		&"wall_straight",
		"Wall Straight",
		&"wall",
		"res://assets/structure/walls/wall.gltf",
		"",
		&"visual_only",
		false,
		&"overlay",
		true,
		true,
		PackedStringArray(["wall"])
	)
	_register_piece(pieces, used_piece_ids, wall_piece)

	var door_piece = _make_piece(
		&"door_socket_standard",
		"Door Socket Standard",
		&"door",
		"res://assets/structure/walls/wall_doorway.gltf",
		"",
		&"door_socket",
		false,
		&"overlay",
		false,
		false,
		PackedStringArray(["door"])
	)
	door_piece.connector_type = &"standard"
	_register_piece(pieces, used_piece_ids, door_piece)

	var entrance_piece = _make_piece(
		&"entrance_marker",
		"Entrance Marker",
		&"entrance",
		"",
		"",
		&"connection_marker",
		true,
		&"overlay",
		false,
		false,
		PackedStringArray(["entrance"])
	)
	entrance_piece.connector_type = &"standard"
	entrance_piece.marker_kind = "entrance"
	entrance_piece.marker_width_tiles = 3
	_register_piece(pieces, used_piece_ids, entrance_piece)

	var exit_piece = _make_piece(
		&"exit_marker",
		"Exit Marker",
		&"exit",
		"",
		"",
		&"connection_marker",
		true,
		&"overlay",
		false,
		false,
		PackedStringArray(["exit"])
	)
	exit_piece.connector_type = &"standard"
	exit_piece.marker_kind = "exit"
	exit_piece.marker_width_tiles = 3
	_register_piece(pieces, used_piece_ids, exit_piece)

	var spawn_player_piece = _make_zone_marker_piece(
		&"spawn_player_marker",
		"Spawn Player Marker",
		&"spawn",
		"spawn_player",
		&"player",
		PackedStringArray(["spawn", "player"])
	)
	_register_piece(pieces, used_piece_ids, spawn_player_piece)

	var spawn_piece = _make_piece(
		&"spawn_melee_marker",
		"Spawn Melee Marker",
		&"spawn",
		"",
		"",
		&"zone_marker",
		true,
		&"overlay",
		false,
		false,
		PackedStringArray(["spawn"])
	)
	spawn_piece.zone_type = "enemy_spawn"
	spawn_piece.zone_role = &"melee"
	_register_piece(pieces, used_piece_ids, spawn_piece)

	var spawn_exit_piece = _make_zone_marker_piece(
		&"spawn_exit_marker",
		"Spawn Exit Marker",
		&"marker",
		"spawn_exit",
		&"spawn_exit",
		PackedStringArray(["marker", "spawn", "spawn_exit"])
	)
	_register_piece(pieces, used_piece_ids, spawn_exit_piece)

	var encounter_entry_piece = _make_zone_marker_piece(
		&"encounter_entry_marker",
		"Encounter Entry Marker",
		&"marker",
		"encounter_trigger",
		&"entry",
		PackedStringArray(["marker", "encounter", "entry"])
	)
	_register_piece(pieces, used_piece_ids, encounter_entry_piece)

	var prop_placement_piece = _make_zone_marker_piece(
		&"prop_placement_marker",
		"Prop Placement Marker",
		&"marker",
		"prop_placement",
		&"default",
		PackedStringArray(["marker", "prop"])
	)
	_register_piece(pieces, used_piece_ids, prop_placement_piece)

	var nav_boundary_piece = _make_zone_marker_piece(
		&"nav_boundary_marker",
		"Nav Boundary Marker",
		&"marker",
		"nav_boundary",
		&"default",
		PackedStringArray(["marker", "nav"])
	)
	_register_piece(pieces, used_piece_ids, nav_boundary_piece)

	var floor_exit_piece = _make_zone_marker_piece(
		&"floor_exit_marker",
		"Floor Exit Marker",
		&"marker",
		"floor_exit",
		&"default",
		PackedStringArray(["marker", "floor_exit"])
	)
	floor_exit_piece.footprint = Vector2i(3, 3)
	_register_piece(pieces, used_piece_ids, floor_exit_piece)

	var loot_piece = _make_zone_marker_piece(
		&"loot_marker",
		"Loot Marker",
		&"marker",
		"loot",
		&"default",
		PackedStringArray(["marker", "loot"])
	)
	_register_piece(pieces, used_piece_ids, loot_piece)

	var blocker_piece = _make_piece(
		&"barrel_blocker",
		"Barrel Blocker",
		&"prop",
		"res://assets/props/barrel_large.gltf",
		"",
		&"visual_only",
		false,
		&"overlay",
		true,
		false,
		PackedStringArray(["prop", "blocker"])
	)
	_register_piece(pieces, used_piece_ids, blocker_piece)

	var trap_piece = _make_piece(
		&"trap_spike_tile",
		"Trap Spike Tile",
		&"trap",
		"res://assets/structure/floors/floor_tile_big_spikes.gltf",
		"res://dungeon/modules/gameplay/trap_tile_2d.tscn",
		&"runtime_scene",
		true,
		&"overlay",
		false,
		false,
		PackedStringArray(["trap"])
	)
	_register_piece(pieces, used_piece_ids, trap_piece)

	var treasure_piece = _make_piece(
		&"treasure_chest",
		"Treasure Chest",
		&"treasure",
		"res://assets/props/chest.gltf",
		"res://dungeon/modules/gameplay/treasure_chest_2d.tscn",
		&"runtime_scene",
		true,
		&"overlay",
		false,
		false,
		PackedStringArray(["treasure"])
	)
	_register_piece(pieces, used_piece_ids, treasure_piece)

	var mission_interface_piece = _make_piece(
		&"hub_mission_interface",
		"Mission Interface",
		&"Hub",
		"res://assets/props/banner_shield_blue.gltf",
		"",
		&"visual_only",
		false,
		&"overlay",
		false,
		false,
		PackedStringArray(["hub", "mission_interface"])
	)
	_register_piece(pieces, used_piece_ids, mission_interface_piece)

	var upgrade_area_piece = _make_piece(
		&"hub_upgrade_area",
		"Upgrade Area",
		&"Hub",
		"res://assets/props/table_long_decorated_A.gltf",
		"",
		&"visual_only",
		false,
		&"overlay",
		false,
		false,
		PackedStringArray(["hub", "upgrade_area"])
	)
	_register_piece(pieces, used_piece_ids, upgrade_area_piece)

	var infusion_pillar_piece = _make_piece(
		&"infusion_pillar_marker",
		"Infusion Pillar Marker",
		&"marker",
		"res://assets/structure/walls/wall_pillar.gltf",
		"res://dungeon/modules/gameplay/infusion_pillar_2d.tscn",
		&"runtime_scene",
		true,
		&"overlay",
		false,
		false,
		PackedStringArray(["marker", "infusion", "pillar"])
	)
	_register_piece(pieces, used_piece_ids, infusion_pillar_piece)


func _make_zone_marker_piece(
	piece_id: StringName,
	display_name: String,
	category: StringName,
	zone_type: String,
	zone_role: StringName,
	default_tags: PackedStringArray
):
	var piece = _make_piece(
		piece_id,
		display_name,
		category,
		"",
		"",
		&"zone_marker",
		true,
		&"overlay",
		false,
		false,
		default_tags
	)
	piece.zone_type = zone_type
	piece.zone_role = zone_role
	return piece


func _add_generated_visual_pieces(
	pieces: Array[Resource],
	used_piece_ids: Dictionary,
	directory_path: String,
	category: StringName,
	placement_layer: StringName,
	allow_overlap: bool,
	blocks_movement: bool,
	blocks_projectiles: bool
) -> void:
	for scene_path in _sorted_gltf_paths(directory_path):
		if SKIP_GENERATED_ASSET_PATHS.has(scene_path):
			continue
		var piece_id := StringName(_resource_name_to_piece_id(scene_path))
		if used_piece_ids.has(piece_id):
			continue
		var piece = _make_piece(
			piece_id,
			_display_name_from_path(scene_path),
			category,
			scene_path,
			"",
			&"visual_only",
			allow_overlap,
			placement_layer,
			blocks_movement,
			blocks_projectiles,
			PackedStringArray([String(category)])
		)
		_register_piece(pieces, used_piece_ids, piece)


func _make_piece(
	piece_id: StringName,
	display_name: String,
	category: StringName,
	preview_scene_path: String,
	runtime_scene_path: String,
	mapping_kind: StringName,
	allow_overlap: bool,
	placement_layer: StringName,
	blocks_movement: bool,
	blocks_projectiles: bool,
	default_tags: PackedStringArray
):
	var piece = PieceDefinitionScript.new()
	piece.piece_id = piece_id
	piece.display_name = display_name
	piece.category = category
	piece.mapping_kind = mapping_kind
	piece.allow_cell_overlap = allow_overlap
	piece.placement_layer = placement_layer
	piece.blocks_movement = blocks_movement
	piece.blocks_projectiles = blocks_projectiles
	piece.default_tags = default_tags
	if preview_scene_path != "":
		piece.preview_scene = load(preview_scene_path) as PackedScene
	if runtime_scene_path != "":
		piece.runtime_scene = load(runtime_scene_path) as PackedScene
	return piece


func _register_piece(pieces: Array[Resource], used_piece_ids: Dictionary, piece) -> void:
	if piece == null:
		return
	if used_piece_ids.has(piece.piece_id):
		push_error("Duplicate piece id '%s' while generating room piece catalog." % [String(piece.piece_id)])
		return
	used_piece_ids[piece.piece_id] = true
	pieces.append(piece)


func _sorted_gltf_paths(directory_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(directory_path)
	if dir == null:
		push_error("Unable to open asset directory: %s" % directory_path)
		return out
	for file_name in dir.get_files():
		if not file_name.to_lower().ends_with(".gltf"):
			continue
		out.append("%s/%s" % [directory_path, file_name])
	out.sort()
	return out


func _resource_name_to_piece_id(resource_path: String) -> String:
	return resource_path.get_file().get_basename().to_lower()


func _display_name_from_path(resource_path: String) -> String:
	return resource_path.get_file().get_basename().replace("_", " ").capitalize()


func _count_category(pieces: Array[Resource], category: StringName) -> int:
	var count := 0
	for piece in pieces:
		if piece != null and piece.category == category:
			count += 1
	return count
