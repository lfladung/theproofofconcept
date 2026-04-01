@tool
extends Node2D
class_name RoomBase

const _GENERATED_BY_ROOM_EDITOR := ^"GeneratedByRoomEditor"

@export var room_id := "room_base_template"
@export_enum("small", "medium", "large", "arena")
var size_class := "medium"
@export_enum("arena", "corridor", "puzzle", "treasure", "safe", "boss", "connector", "trap")
var room_type := "arena"
@export_enum("center", "top_left")
var origin_mode := "center"

@export var tile_size := Vector2i(32, 32)
@export var room_size_tiles := Vector2i(24, 24)
@export var allowed_rotations: PackedInt32Array = [0, 90, 180, 270]
@export var standard_room_sizes: PackedInt32Array = [10, 16, 24, 32]
@export var room_tags: PackedStringArray = ["arena"]
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
@export var authored_layout: Resource

@onready var _layout: Node2D = $Layout
@onready var _sockets: Node2D = $Sockets
@onready var _zones: Node2D = $Zones
@onready var _gameplay: Node2D = $Gameplay
@onready var _visual_3d_proxy: Node3D = $Visual3DProxy


func _ready() -> void:
	add_to_group(&"room")
	_apply_layer_z_index()
	# These are authoring-time contract checks; keep runtime logs clean.
	if Engine.is_editor_hint() and _should_run_editor_validation():
		_validate_room_rules()


func get_connection_markers() -> Array[ConnectorMarker2D]:
	var markers: Array[ConnectorMarker2D] = []
	var generated_only := _generated_connection_marker_children()
	if not generated_only.is_empty():
		return generated_only
	for child in _sockets.get_children():
		if child is ConnectorMarker2D:
			markers.append(child)
	return markers


func get_connection_markers_by_direction(direction: String) -> Array[ConnectorMarker2D]:
	var matches: Array[ConnectorMarker2D] = []
	for marker in get_connection_markers():
		if marker.direction == direction:
			matches.append(marker)
	return matches


func get_connection_markers_by_kind(marker_kind: String) -> Array[ConnectorMarker2D]:
	var matches: Array[ConnectorMarker2D] = []
	for marker in get_connection_markers():
		if marker.marker_kind == marker_kind:
			matches.append(marker)
	return matches


func get_all_sockets() -> Array[ConnectorMarker2D]:
	return get_connection_markers()


func get_socket_by_direction(direction: String) -> Array[ConnectorMarker2D]:
	return get_connection_markers_by_direction(direction)


func get_zone_markers() -> Array[ZoneMarker2D]:
	var markers: Array[ZoneMarker2D] = []
	var generated_only := _generated_zone_children()
	if not generated_only.is_empty():
		return generated_only
	for child in _zones.get_children():
		if child is ZoneMarker2D:
			markers.append(child)
	return markers


func get_generated_sockets_root() -> Node2D:
	return _sockets.get_node_or_null(_GENERATED_BY_ROOM_EDITOR) as Node2D


func get_generated_zones_root() -> Node2D:
	return _zones.get_node_or_null(_GENERATED_BY_ROOM_EDITOR) as Node2D


func get_generated_gameplay_root() -> Node2D:
	return _gameplay.get_node_or_null(_GENERATED_BY_ROOM_EDITOR) as Node2D


func get_generated_visual_root() -> Node3D:
	return _visual_3d_proxy.get_node_or_null(_GENERATED_BY_ROOM_EDITOR) as Node3D


func get_room_rect_tiles() -> Rect2i:
	if origin_mode == "top_left":
		return Rect2i(Vector2i.ZERO, room_size_tiles)
	var half_size := Vector2i(
		floori(float(room_size_tiles.x) * 0.5),
		floori(float(room_size_tiles.y) * 0.5)
	)
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


func _validate_connection_marker_grid_alignment() -> void:
	for marker in get_connection_markers():
		var tile_x_ok := is_equal_approx(fposmod(marker.position.x, float(tile_size.x)), 0.0)
		var tile_y_ok := is_equal_approx(fposmod(marker.position.y, float(tile_size.y)), 0.0)
		if not tile_x_ok or not tile_y_ok:
			push_warning(
				"Connection marker '%s' in room '%s' is not aligned to the %sx%s tile grid." % [
					marker.name,
					room_id,
					tile_size.x,
					tile_size.y,
				]
			)


func _validate_room_rules() -> void:
	_validate_grid_compliance()
	_validate_closed_boundary_contract()
	_validate_connection_marker_standardization()
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
	if _is_room_editor_authoring_context():
		_validate_connection_marker_grid_alignment()
		return
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
	_validate_connection_marker_grid_alignment()


func _validate_closed_boundary_contract() -> void:
	if _is_blank_authoring_room() or _uses_authored_layout_workflow():
		return
	var walls_layer := _layout.get_node_or_null(^"TileWalls") as TileMapLayer
	if walls_layer == null:
		push_warning("Room '%s' is missing Layout/TileWalls." % room_id)
		return
	if walls_layer.get_used_cells().is_empty():
		push_warning(
			"Room '%s' has no wall tiles painted yet. Rooms must be fully enclosed except at sockets." % room_id
		)


func _validate_connection_marker_standardization() -> void:
	var markers: Array[ConnectorMarker2D] = []
	if _is_room_editor_authoring_context():
		markers = _generated_connection_marker_children()
		if markers.is_empty():
			return
	else:
		markers = get_connection_markers()
	if markers.is_empty():
		push_warning("Room '%s' has no connection markers." % room_id)
		return
	var allowed_directions := PackedStringArray(["north", "south", "east", "west", "up", "down"])
	var world_rect := get_room_rect_world()
	var entrances := 0
	var exits := 0
	for marker in markers:
		if marker.marker_kind == "entrance":
			entrances += 1
		elif marker.marker_kind == "exit":
			exits += 1
		else:
			push_warning(
				"Room '%s' marker '%s' uses invalid marker_kind '%s'." % [room_id, marker.name, marker.marker_kind]
			)
		if not allowed_directions.has(marker.direction):
			push_warning(
				"Room '%s' marker '%s' uses invalid direction '%s'." % [room_id, marker.name, marker.direction]
			)
		if marker.direction in ["north", "south", "east", "west"]:
			if not _connection_marker_is_on_boundary(marker, world_rect):
				push_warning(
					"Room '%s' marker '%s' is not aligned to the room boundary." % [room_id, marker.name]
				)
			if marker.width_tiles != 3:
				push_warning(
					"Room '%s' marker '%s' should use the 3-tile hallway opening width." % [room_id, marker.name]
				)
	var expected := _expected_marker_counts()
	if entrances != int(expected.get("entrance", 0)) or exits != int(expected.get("exit", 0)):
		push_warning(
			"Room '%s' has entrance/exit marker count %s/%s, expected %s/%s." % [
				room_id,
				entrances,
				exits,
				int(expected.get("entrance", 0)),
				int(expected.get("exit", 0)),
			]
		)
	if entrances == 1 and exits == 1:
		var entrance_marker := get_connection_markers_by_kind("entrance").front() as ConnectorMarker2D
		var exit_marker := get_connection_markers_by_kind("exit").front() as ConnectorMarker2D
		if entrance_marker != null and exit_marker != null:
			if entrance_marker.direction == exit_marker.direction:
				push_warning("Room '%s' entrance and exit cannot share the same wall." % room_id)
			elif not _markers_are_on_opposite_halves(entrance_marker, exit_marker):
				push_warning(
					"Room '%s' entrance and exit must be on different walls and opposite room halves." % room_id
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
	if _is_blank_authoring_room():
		return
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
	if _is_room_editor_authoring_context():
		return
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


func _connection_marker_is_on_boundary(marker: ConnectorMarker2D, world_rect: Rect2) -> bool:
	var half_tile_x := tile_size.x * 0.5
	var half_tile_y := tile_size.y * 0.5
	var left := world_rect.position.x
	var right := world_rect.position.x + world_rect.size.x
	var top := world_rect.position.y
	var bottom := world_rect.position.y + world_rect.size.y
	return (
		absf(marker.position.x - left) <= half_tile_x
		or absf(marker.position.x - right) <= half_tile_x
		or absf(marker.position.y - top) <= half_tile_y
		or absf(marker.position.y - bottom) <= half_tile_y
	)


func _generated_connection_marker_children() -> Array[ConnectorMarker2D]:
	var root := get_generated_sockets_root()
	var out: Array[ConnectorMarker2D] = []
	if root == null:
		return out
	for child in root.get_children():
		if child is ConnectorMarker2D:
			out.append(child)
	return out


func _generated_zone_children() -> Array[ZoneMarker2D]:
	var root := get_generated_zones_root()
	var out: Array[ZoneMarker2D] = []
	if root == null:
		return out
	for child in root.get_children():
		if child is ZoneMarker2D:
			out.append(child)
	return out


func _should_run_editor_validation() -> bool:
	if _is_base_template_scene():
		return false
	return true


func _is_base_template_scene() -> bool:
	return scene_file_path == "res://dungeon/rooms/base/room_base.tscn"


func _is_blank_authoring_room() -> bool:
	var walls_layer := _layout.get_node_or_null(^"TileWalls") as TileMapLayer
	var has_wall_tiles := walls_layer != null and not walls_layer.get_used_cells().is_empty()
	return not has_wall_tiles and not _uses_authored_layout_workflow()


func _uses_authored_layout_workflow() -> bool:
	if authored_layout == null:
		return false
	var items = authored_layout.get("items")
	return items is Array and not (items as Array).is_empty()


func _is_room_editor_authoring_context() -> bool:
	return Engine.is_editor_hint() and authored_layout != null


func _expected_marker_counts() -> Dictionary:
	match room_type:
		"treasure", "boss":
			return {"entrance": 1, "exit": 0}
		"safe":
			return {"entrance": 0, "exit": 1}
		_:
			return {"entrance": 1, "exit": 1}


func _markers_are_on_opposite_halves(entrance_marker: ConnectorMarker2D, exit_marker: ConnectorMarker2D) -> bool:
	if entrance_marker == null or exit_marker == null:
		return false
	var entrance_local := to_room_grid(entrance_marker.position)
	var exit_local := to_room_grid(exit_marker.position)
	var half_x := room_size_tiles.x * 0.5
	var half_y := room_size_tiles.y * 0.5
	match entrance_marker.direction:
		"north", "south":
			return absf(float(entrance_local.x) - float(exit_local.x)) >= maxf(2.0, half_x * 0.25)
		"east", "west":
			return absf(float(entrance_local.y) - float(exit_local.y)) >= maxf(2.0, half_y * 0.25)
		_:
			return true
