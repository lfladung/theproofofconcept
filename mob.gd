extends CharacterBody3D

signal squashed

## Minimum speed of the mob in meters per second.
@export var min_speed := 10.0
## Maximum speed of the mob in meters per second.
@export var max_speed := 18.0

var _squash_applied: bool = false


func _physics_process(_delta: float) -> void:
	move_and_slide()


func initialize(start_position: Vector3, player_position: Vector3) -> void:
	var target := Vector3(player_position.x, start_position.y, player_position.z)
	look_at_from_position(start_position, target, Vector3.UP)
	rotate_y(randf_range(-PI / 4.0, PI / 4.0))
	var random_speed := randf_range(min_speed, max_speed)
	velocity = Vector3.FORWARD * random_speed
	velocity = velocity.rotated(Vector3.UP, rotation.y)
	$AnimationPlayer.speed_scale = random_speed / min_speed


func squash() -> void:
	if _squash_applied:
		return
	_squash_applied = true
	squashed.emit()
	queue_free()


func _on_visible_on_screen_notifier_screen_exited() -> void:
	queue_free()
