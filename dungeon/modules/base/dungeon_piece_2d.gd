@tool
extends Node2D
class_name DungeonPiece2D

@export var piece_id: StringName = &"piece"
@export var piece_category: StringName = &"structure"
@export var tile_size := Vector2i(3, 3)
@export var footprint_tiles := Vector2i(1, 1)
@export var display_color := Color(1.0, 1.0, 1.0, 1.0)
@export var walkable := true
@export var blocks_movement := false
@export var tags: PackedStringArray = []

@onready var _visual: Polygon2D = $Visual
@onready var _body: StaticBody2D = $BlockingBody
@onready var _collision: CollisionShape2D = $BlockingBody/CollisionShape2D


func _ready() -> void:
	_rebuild_piece_geometry()
	_update_blocking_state()
	if Engine.is_editor_hint():
		set_process(true)
	else:
		add_to_group(&"dungeon_piece")
		add_to_group(piece_category)


func get_world_size() -> Vector2:
	return Vector2(footprint_tiles.x * tile_size.x, footprint_tiles.y * tile_size.y)


func set_blocks_movement(value: bool) -> void:
	blocks_movement = value
	_update_blocking_state()


func _validate_properties() -> void:
	footprint_tiles.x = maxi(1, footprint_tiles.x)
	footprint_tiles.y = maxi(1, footprint_tiles.y)
	tile_size.x = maxi(1, tile_size.x)
	tile_size.y = maxi(1, tile_size.y)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild_piece_geometry()
		_update_blocking_state()


func _rebuild_piece_geometry() -> void:
	_validate_properties()
	if _visual == null:
		return
	var size := get_world_size()
	var half := size * 0.5
	_visual.color = display_color
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	if _collision and _collision.shape is RectangleShape2D:
		var rect := _collision.shape as RectangleShape2D
		if not rect.resource_local_to_scene:
			rect = rect.duplicate()
			rect.resource_local_to_scene = true
			_collision.shape = rect
		rect.size = size


func _update_blocking_state() -> void:
	if _body == null or _collision == null:
		return
	# Toggle shape only; disabling StaticBody2D.process_mode can desync 2D physics queries/collision.
	_collision.disabled = not blocks_movement
