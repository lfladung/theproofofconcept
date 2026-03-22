extends Node2D
class_name RoomBase

@export var room_id := "room_base_template"
@export_enum("small", "medium", "large", "arena")
var size_class := "medium"

@export var tile_size := Vector2i(32, 32)
@export var room_size_tiles := Vector2i(24, 24)
@export var allowed_rotations: PackedInt32Array = [0, 90, 180, 270]
@export var room_tags: PackedStringArray = []
@export var safe_room := false
@export var secret_room := false
@export var difficulty_tier := 1
@export var loot_tier := 1
@export var encounter_budget := 100
@export var vertical_layer := 0

@onready var _layout: Node2D = $Layout
@onready var _sockets: Node2D = $Sockets
@onready var _zones: Node2D = $Zones


func _ready() -> void:
	add_to_group(&"room")
	_apply_layer_z_index()
	_validate_socket_grid_alignment()


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
