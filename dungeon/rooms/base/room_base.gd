extends Node2D
class_name RoomBase

@export var room_id := "room_base_template"
@export_enum("small", "medium", "large", "arena")
var size_class := "medium"
@export_enum("arena", "corridor", "puzzle", "treasure", "safe", "boss", "connector")
var room_type := "arena"
@export_enum("center", "top_left")
var origin_mode := "center"

@export var tile_size := Vector2i(32, 32)
@export var room_size_tiles := Vector2i(24, 24)
@export var allowed_rotations: PackedInt32Array = [0, 90, 180, 270]
@export var standard_room_sizes: PackedInt32Array = [10, 16, 24, 32]
@export var room_tags: PackedStringArray = []
@export var allowed_connection_types: PackedStringArray = ["corridor", "connector", "arena"]
@export var safe_room := false
@export var secret_room := false
@export var difficulty_tier := 1
@export var min_difficulty_tier := 1
@export var max_difficulty_tier := 3
@export var loot_tier := 1
@export var encounter_budget := 100
@export var max_tile_budget := 1024
@export var max_prop_density := 0.35
@export var vertical_layer := 0

@onready var _layout: Node2D = $Layout
@onready var _sockets: Node2D = $Sockets
@onready var _zones: Node2D = $Zones


func _ready() -> void:
	add_to_group(&"room")
	_apply_layer_z_index()
	_validate_room_rules()


func get_all_sockets() -> Array[DoorSocket2D]:
	var sockets: Array[DoorSocket2D] = []
	for child in _sockets.get_children():
		if child is DoorSocket2D:
			sockets.append(child)
	return sockets


func get_socket_by_direction(direction: String) -> Array[DoorSocket2D]:
	var matches: Array[DoorSocket2D] = []
	for socket in get_all_sockets():
		if socket.direction == direction:
			matches.append(socket)
	return matches


func get_zone_markers() -> Array[ZoneMarker2D]:
	var markers: Array[ZoneMarker2D] = []
	for child in _zones.get_children():
		if child is ZoneMarker2D:
			markers.append(child)
	return markers


func get_room_rect_tiles() -> Rect2i:
	var half_size := room_size_tiles / 2
	return Rect2i(-half_size, room_size_tiles)


func get_room_rect_world() -> Rect2:
	var tile_rect := get_room_rect_tiles()
	return Rect2(
		Vector2(tile_rect.position * tile_size),
		Vector2(tile_rect.size * tile_size)
	)


func to_room_grid(world_position: Vector2) -> Vector2i:
	return Vector2i(floor(world_position.x / tile_size.x), floor(world_position.y / tile_size.y))


func _apply_layer_z_index() -> void:
	# Keep a deterministic draw order across all room templates.
	var floor_layer := _layout.get_node_or_null(^"TileFloor") as TileMapLayer
	var wall_layer := _layout.get_node_or_null(^"TileWalls") as TileMapLayer
	var hazard_layer := _layout.get_node_or_null(^"TileHazards") as TileMapLayer
	var deco_layer := _layout.get_node_or_null(^"TileDeco") as TileMapLayer
	if floor_layer:
		floor_layer.z_index = 0
	if wall_layer:
		wall_layer.z_index = 10
	if hazard_layer:
		hazard_layer.z_index = 20
	if deco_layer:
		deco_layer.z_index = 30


func _validate_socket_grid_alignment() -> void:
	for socket in get_all_sockets():
		var tile_x_ok := is_equal_approx(fposmod(socket.position.x, float(tile_size.x)), 0.0)
		var tile_y_ok := is_equal_approx(fposmod(socket.position.y, float(tile_size.y)), 0.0)
		if not tile_x_ok or not tile_y_ok:
			push_warning(
				"Door socket '%s' in room '%s' is not aligned to the %sx%s tile grid." % [
					socket.name,
					room_id,
					tile_size.x,
					tile_size.y,
				]
			)


func _validate_room_rules() -> void:
	_validate_grid_compliance()
	_validate_closed_boundary_contract()
	_validate_door_socket_standardization()
	_validate_traversable_space_contract()
	_validate_gameplay_zoning_contract()
	_validate_origin_standard()
	_validate_room_classification()
	_validate_connection_compatibility()
	_validate_tile_budget()
	_validate_rotation_compatibility()


func _validate_grid_compliance() -> void:
	if tile_size.x <= 0 or tile_size.y <= 0:
		push_warning("Room '%s' has invalid tile size %s." % [room_id, tile_size])
	if tile_size.x != tile_size.y:
		push_warning("Room '%s' should use square tile units. Current tile size: %s." % [room_id, tile_size])
	if room_size_tiles.x <= 0 or room_size_tiles.y <= 0:
		push_warning("Room '%s' has invalid room size %s." % [room_id, room_size_tiles])
	var width_standard := standard_room_sizes.has(room_size_tiles.x)
	var height_standard := standard_room_sizes.has(room_size_tiles.y)
	if not width_standard or not height_standard:
		push_warning(
			"Room '%s' uses non-standard size %sx%s. Standard sizes are %s (or add a 'custom_size' tag)." % [
				room_id,
				room_size_tiles.x,
				room_size_tiles.y,
				standard_room_sizes,
			]
		)
	_validate_socket_grid_alignment()


func _validate_closed_boundary_contract() -> void:
	var walls_layer := _layout.get_node_or_null(^"TileWalls") as TileMapLayer
	if walls_layer == null:
		push_warning("Room '%s' is missing Layout/TileWalls." % room_id)
		return
	if walls_layer.get_used_cells().is_empty():
		push_warning(
			"Room '%s' has no wall tiles painted yet. Rooms must be fully enclosed except at sockets." % room_id
		)


func _validate_door_socket_standardization() -> void:
	var sockets := get_all_sockets()
	if sockets.is_empty():
		push_warning("Room '%s' has no door sockets." % room_id)
		return
	var allowed_directions := PackedStringArray(["north", "south", "east", "west", "up", "down"])
	var world_rect := get_room_rect_world()
	for socket in sockets:
		if not allowed_directions.has(socket.direction):
			push_warning("Room '%s' socket '%s' uses invalid direction '%s'." % [room_id, socket.name, socket.direction])
		if socket.direction in ["north", "south", "east", "west"]:
			if not _socket_is_on_boundary(socket, world_rect):
				push_warning(
					"Room '%s' socket '%s' is not aligned to room boundary walls." % [room_id, socket.name]
				)


func _validate_traversable_space_contract() -> void:
	var has_nav_boundary := false
	var has_entry_trigger := false
	for zone in get_zone_markers():
		if zone.zone_type == "nav_boundary":
			has_nav_boundary = true
		if zone.zone_type == "encounter_trigger" and String(zone.zone_role) == "entry":
			has_entry_trigger = true
	if not has_nav_boundary:
		push_warning("Room '%s' is missing a nav boundary zone marker." % room_id)
	if not has_entry_trigger:
		push_warning("Room '%s' should include at least one entry trigger marker near doors." % room_id)


func _validate_gameplay_zoning_contract() -> void:
	var seen: Dictionary = {}
	for zone in get_zone_markers():
		seen[zone.zone_type] = true
	for required_type in ["enemy_spawn", "prop_placement", "encounter_trigger"]:
		if not seen.has(required_type):
			push_warning(
				"Room '%s' is missing required gameplay zone type '%s'." % [room_id, required_type]
			)


func _validate_origin_standard() -> void:
	var x_aligned := is_equal_approx(fposmod(global_position.x, float(tile_size.x)), 0.0)
	var y_aligned := is_equal_approx(fposmod(global_position.y, float(tile_size.y)), 0.0)
	if origin_mode == "center" and (not x_aligned or not y_aligned):
		push_warning(
			"Room '%s' origin is not aligned to tile grid (%sx%s)." % [room_id, tile_size.x, tile_size.y]
		)


func _validate_room_classification() -> void:
	if not room_tags.has(room_type):
		push_warning(
			"Room '%s' room_tags should include room_type '%s' for generator filtering." % [room_id, room_type]
		)


func _validate_connection_compatibility() -> void:
	if allowed_connection_types.is_empty():
		push_warning("Room '%s' has no allowed connection types." % room_id)
	if min_difficulty_tier > max_difficulty_tier:
		push_warning(
			"Room '%s' has invalid difficulty tier range (%s > %s)." % [
				room_id,
				min_difficulty_tier,
				max_difficulty_tier,
			]
		)


func _validate_tile_budget() -> void:
	var tile_count := room_size_tiles.x * room_size_tiles.y
	if tile_count > max_tile_budget:
		push_warning(
			"Room '%s' exceeds tile budget (%s > %s)." % [room_id, tile_count, max_tile_budget]
		)
	if max_prop_density <= 0.0 or max_prop_density > 1.0:
		push_warning("Room '%s' max_prop_density should be in (0, 1]." % room_id)


func _validate_rotation_compatibility() -> void:
	for deg in allowed_rotations:
		if deg % 90 != 0:
			push_warning(
				"Room '%s' has invalid rotation '%s'. Allowed rotations must be multiples of 90." % [
					room_id,
					deg,
				]
			)


func _socket_is_on_boundary(socket: DoorSocket2D, world_rect: Rect2) -> bool:
	var half_tile_x := tile_size.x * 0.5
	var half_tile_y := tile_size.y * 0.5
	var left := world_rect.position.x
	var right := world_rect.position.x + world_rect.size.x
	var top := world_rect.position.y
	var bottom := world_rect.position.y + world_rect.size.y
	return (
		absf(socket.position.x - left) <= half_tile_x
		or absf(socket.position.x - right) <= half_tile_x
		or absf(socket.position.y - top) <= half_tile_y
		or absf(socket.position.y - bottom) <= half_tile_y
	)
