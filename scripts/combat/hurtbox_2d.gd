extends Area2D
class_name Hurtbox2D

@export var receiver_path: NodePath
@export var owner_path: NodePath
@export var faction: StringName = &"neutral"
@export var active := true
@export var debug_draw_enabled := false
@export var debug_label: StringName = &""


func _ready() -> void:
	monitoring = false
	monitorable = active
	if debug_draw_enabled:
		queue_redraw()


func set_active(enabled: bool) -> void:
	active = enabled
	monitorable = enabled
	if debug_draw_enabled:
		queue_redraw()


func is_active() -> bool:
	return active


func get_receiver_component() -> DamageReceiverComponent:
	if receiver_path != NodePath():
		return get_node_or_null(receiver_path) as DamageReceiverComponent
	var owner_node := get_target_node()
	if owner_node == null:
		return null
	for child in owner_node.get_children():
		if child is DamageReceiverComponent:
			return child as DamageReceiverComponent
	return null


func get_target_node() -> Node:
	if owner_path != NodePath():
		return get_node_or_null(owner_path)
	return get_parent()


func get_target_uid() -> int:
	var owner_node := get_target_node()
	if owner_node != null and is_instance_valid(owner_node):
		return owner_node.get_instance_id()
	return get_instance_id()


func _draw() -> void:
	if not debug_draw_enabled:
		return
	var color := Color(0.15, 0.95, 0.45, 0.7) if active else Color(0.45, 0.45, 0.45, 0.4)
	for shape_node in _shape_nodes():
		_draw_shape_outline(shape_node, color)


func _shape_nodes() -> Array[CollisionShape2D]:
	var nodes: Array[CollisionShape2D] = []
	for child in get_children():
		if child is CollisionShape2D:
			nodes.append(child as CollisionShape2D)
	return nodes


func _draw_shape_outline(shape_node: CollisionShape2D, color: Color) -> void:
	if shape_node.shape is CircleShape2D:
		var circle := shape_node.shape as CircleShape2D
		draw_arc(shape_node.position, circle.radius, 0.0, TAU, 32, color, 2.0)
	elif shape_node.shape is RectangleShape2D:
		var rect := shape_node.shape as RectangleShape2D
		var half := rect.size * 0.5
		var transform_2d := shape_node.transform
		var points := PackedVector2Array([
			transform_2d * Vector2(-half.x, -half.y),
			transform_2d * Vector2(half.x, -half.y),
			transform_2d * Vector2(half.x, half.y),
			transform_2d * Vector2(-half.x, half.y),
		])
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, color, 2.0)
