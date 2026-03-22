extends CharacterBody3D

signal hit

## How fast the player moves in meters per second.
@export var speed := 14.0
## Vertical impulse applied to the character upon jumping in meters per second.
@export var jump_impulse := 20.0
## Vertical impulse applied when bouncing off a mob.
@export var bounce_impulse := 16.0
## Downward acceleration when in the air, in meters per second squared.
@export var fall_acceleration := 75.0


func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	if Input.is_action_pressed(&"move_right"):
		direction.x += 1.0
	if Input.is_action_pressed(&"move_left"):
		direction.x -= 1.0
	if Input.is_action_pressed(&"move_back"):
		direction.z += 1.0
	if Input.is_action_pressed(&"move_forward"):
		direction.z -= 1.0

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		basis = Basis.looking_at(direction)
		$AnimationPlayer.speed_scale = 4.0
	else:
		$AnimationPlayer.speed_scale = 1.0

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if is_on_floor() and Input.is_action_just_pressed(&"jump"):
		velocity.y += jump_impulse

	velocity.y -= fall_acceleration * delta
	move_and_slide()

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider == null or not collider.is_in_group(&"mob"):
			continue
		if Vector3.UP.dot(collision.get_normal()) > 0.1:
			collider.squash()
			velocity.y = bounce_impulse
			break

	rotation.x = PI / 6.0 * velocity.y / jump_impulse


func die() -> void:
	hit.emit()
	queue_free()


func _on_mob_detector_body_entered(_body: Node3D) -> void:
	die()
