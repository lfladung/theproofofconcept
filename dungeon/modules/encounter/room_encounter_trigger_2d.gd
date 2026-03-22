@tool
extends Area2D
class_name RoomEncounterTrigger2D

signal encounter_triggered(encounter_id: StringName)

@export var encounter_id: StringName = &"combat"
@export var one_shot := true
@export var trigger_size := Vector2(24.0, 24.0)
@export var marker_color := Color(0.62, 0.26, 0.86, 0.18)

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _visual: Polygon2D = $Visual

var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	_rebuild_shape()
	body_entered.connect(_on_body_entered)
	if Engine.is_editor_hint():
		set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild_shape()


func _on_body_entered(body: Node2D) -> void:
	if _fired and one_shot:
		return
	if body == null or not body.is_in_group(&"player"):
		return
	_fired = true
	encounter_triggered.emit(encounter_id)


func reset_trigger() -> void:
	_fired = false


func _rebuild_shape() -> void:
	trigger_size.x = maxf(1.0, trigger_size.x)
	trigger_size.y = maxf(1.0, trigger_size.y)
	if _shape and _shape.shape is RectangleShape2D:
		(_shape.shape as RectangleShape2D).size = trigger_size
	if _visual:
		var half := trigger_size * 0.5
		_visual.color = marker_color
		_visual.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
