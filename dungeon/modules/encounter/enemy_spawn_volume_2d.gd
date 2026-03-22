@tool
extends Area2D
class_name EnemySpawnVolume2D

@export var encounter_id: StringName = &"combat"
@export var size := Vector2(24.0, 24.0)
@export var marker_color := Color(1.0, 0.89, 0.10, 0.18)

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	_rebuild_shape()
	if Engine.is_editor_hint():
		set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild_shape()


func sample_spawn_position() -> Vector2:
	var half := size * 0.5
	return global_position + Vector2(
		randf_range(-half.x, half.x),
		randf_range(-half.y, half.y)
	)


func _rebuild_shape() -> void:
	size.x = maxf(1.0, size.x)
	size.y = maxf(1.0, size.y)
	if _shape and _shape.shape is RectangleShape2D:
		(_shape.shape as RectangleShape2D).size = size
	if _visual:
		var half := size * 0.5
		_visual.color = marker_color
		_visual.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
