@tool
extends Marker2D
class_name EnemySpawnPoint2D

@export var encounter_id: StringName = &"combat"
@export var enemy_id: StringName = &""
@export var spawn_weight := 1.0
@export var marker_color := Color(1.0, 0.89, 0.10, 1.0)

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	if _visual:
		_visual.color = marker_color
	if Engine.is_editor_hint():
		set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _visual:
		_visual.color = marker_color


func get_spawn_position() -> Vector2:
	return global_position
