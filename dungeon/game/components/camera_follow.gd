extends Node
class_name CameraFollowController

var camera_pivot: Marker3D
var player: CharacterBody2D
var lerp_speed := 8.0


func tick(delta: float) -> void:
	if player == null or not is_instance_valid(player) or camera_pivot == null:
		return
	var target := Vector3(player.global_position.x, camera_pivot.global_position.y, player.global_position.y)
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		target,
		clampf(delta * lerp_speed, 0.0, 1.0)
	)
