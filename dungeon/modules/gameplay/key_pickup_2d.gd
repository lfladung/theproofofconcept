extends Area2D
class_name KeyPickup2D

@export var key_id: StringName = &"generic"
@export var pickup_color := Color(0.95, 0.82, 0.22, 1.0)

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	if _visual:
		_visual.color = pickup_color


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	var host := get_tree().get_first_node_in_group(&"dungeon_gameplay_host")
	if host == null or not host.has_method(&"register_player_key"):
		return
	host.register_player_key(key_id)
	queue_free()
