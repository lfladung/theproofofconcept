extends Area2D
class_name TreasureChest2D

signal opened

## Key granted when the chest is opened (spawned as a pickup next to the chest).
@export var key_id: StringName = &"generic"
@export var closed_color := Color(0.55, 0.35, 0.18, 1.0)
@export var open_color := Color(0.42, 0.38, 0.32, 1.0)

const KEY_PICKUP_SCENE := preload("res://dungeon/modules/gameplay/key_pickup_2d.tscn")

@onready var _visual: Polygon2D = $Visual

var _opened := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	if _visual:
		_visual.color = closed_color


func _on_body_entered(body: Node2D) -> void:
	if _opened or body == null or not body.is_in_group(&"player"):
		return
	_opened = true
	if _visual:
		_visual.color = open_color
	opened.emit()
	var pickup := KEY_PICKUP_SCENE.instantiate() as KeyPickup2D
	if pickup:
		pickup.key_id = key_id
		pickup.global_position = global_position + Vector2(5.0, 0.0)
		get_parent().add_child(pickup)
