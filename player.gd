extends CharacterBody2D

signal hit

## Horizontal speed (matches former 3D XZ plane).
@export var speed := 14.0
@export var jump_impulse := 20.0
@export var bounce_impulse := 16.0
@export var fall_acceleration := 75.0
## Altitude of feet above the ground plane (jump); not CharacterBody2D.position.y.
@export var height := 0.0
## 2D radius used for stomp proximity vs mob origin.
@export var stomp_radius := 1.1
## Ignore MobDetector kills while feet are above this height.
@export var mob_detector_safe_height := 1.15
## Max planar center distance for a kill; filters spurious Area2D body_entered at large separation.
@export var mob_kill_max_planar_dist := 3.25

@onready var _visual: Node3D = get_node_or_null("../../VisualWorld3D/PlayerVisual") as Node3D

var vertical_velocity := 0.0


func _mouse_steering_active() -> bool:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return false
	# Don't steal movement when a Control is under the cursor (e.g. game-over overlay).
	return get_viewport().gui_get_hovered_control() == null


## Screen mouse → GameWorld2D plane (same coords as global_position: x, y ↔ 3D x, z).
func _mouse_planar_world() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if absf(dir.y) < 1e-5:
		return global_position
	var t := -from.y / dir.y
	if t < 0.0:
		return global_position
	var hit := from + dir * t
	return Vector2(hit.x, hit.z)


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if _mouse_steering_active():
		var target := _mouse_planar_world()
		var to_target := target - global_position
		if to_target.length_squared() > 0.01:
			direction = to_target.normalized()

	var planar_speed := 0.0
	if direction != Vector2.ZERO:
		velocity = direction * speed
		planar_speed = speed
	else:
		velocity = Vector2.ZERO

	if height <= 0.001 and Input.is_action_just_pressed(&"jump"):
		vertical_velocity = jump_impulse

	vertical_velocity -= fall_acceleration * delta
	height += vertical_velocity * delta
	if height <= 0.0:
		height = 0.0
		if vertical_velocity < 0.0:
			vertical_velocity = 0.0

	move_and_slide()

	_try_stomp_from_above()

	if _visual:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)
		if direction != Vector2.ZERO:
			_visual.rotation.y = atan2(direction.x, direction.y)
		if _visual.has_method(&"set_locomotion_from_planar_speed"):
			_visual.set_locomotion_from_planar_speed(planar_speed, speed)
		if _visual.has_method(&"set_jump_tilt"):
			_visual.set_jump_tilt(vertical_velocity, jump_impulse)

	if Input.is_action_just_pressed(&"player_attack") and _visual and _visual.has_method(&"try_play_attack"):
		_visual.try_play_attack()


func _try_stomp_from_above() -> void:
	if vertical_velocity > 0.0:
		return
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is CharacterBody2D or not node.has_method(&"squash"):
			continue
		var mob := node as CharacterBody2D
		if global_position.distance_to(mob.global_position) > stomp_radius:
			continue
		var top_h: float = 1.0
		var st: Variant = mob.get(&"stomp_top_height")
		if st != null:
			top_h = float(st)
		if height < top_h + 0.05:
			continue
		mob.squash()
		vertical_velocity = bounce_impulse
		break


func die() -> void:
	hit.emit()
	queue_free()


func _on_mob_detector_body_entered(body: Node2D) -> void:
	# Only creeps kill the player; avoids spurious Area2D overlaps (e.g. parent body quirks).
	if body == null or body == self or not body.is_in_group(&"mob"):
		return
	if height >= mob_detector_safe_height:
		return
	var planar_d := body.global_position.distance_to(global_position)
	if planar_d > mob_kill_max_planar_dist:
		return
	die()
