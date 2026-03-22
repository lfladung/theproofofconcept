class_name CreepMob
extends CharacterBody2D

signal squashed

@export var min_speed := 10.0
@export var max_speed := 18.0
## Feet-to-ground mob; stomp when player.height exceeds this while falling.
@export var stomp_top_height := 1.02

var _squash_applied: bool = false
var _visual: Node3D
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn: bool = false


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func _ready() -> void:
	# Stay off collision layers until positioned — packed scene used to spawn at (0,0) with
	# layer 2 for one tick, overlapping the player and tripping MobDetector instantly.
	if _has_spawn:
		_apply_spawn(_spawn_start, _spawn_target)
	var vw := get_node_or_null("../../VisualWorld3D")
	if vw:
		var vis: Node = preload("res://mob_visual.tscn").instantiate()
		vw.add_child(vis)
		_visual = vis as Node3D
		_sync_visual_from_body()
		vis.screen_exited_visual.connect(_on_visible_on_screen_notifier_screen_exited)
	_sync_visual_anim_speed()
	if _has_spawn:
		set_deferred(&"collision_layer", 2)
	else:
		push_warning("Mob entered tree without configure_spawn; removing.")
		queue_free()


func _exit_tree() -> void:
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()


func _physics_process(_delta: float) -> void:
	move_and_slide()
	_sync_visual_from_body()


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, 0.0, global_position.y)
	# Match PlayerVisual: 2D (x, y) plane maps to 3D XZ; Godot2D Node2D.rotation ≠ this heading.
	if velocity.length_squared() > 0.0001:
		_visual.rotation.y = atan2(velocity.x, velocity.y) + PI


func _apply_spawn(start_position: Vector2, player_position: Vector2) -> void:
	global_position = start_position
	look_at(player_position)
	rotate(randf_range(-PI / 4.0, PI / 4.0))
	var random_speed := randf_range(min_speed, max_speed)
	velocity = Vector2.RIGHT.rotated(rotation) * random_speed
	_sync_visual_anim_speed(random_speed)


func _sync_visual_anim_speed(for_speed: float = -1.0) -> void:
	if _visual == null:
		return
	var ap: AnimationPlayer = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		var s := for_speed if for_speed > 0.0 else velocity.length()
		ap.speed_scale = s / min_speed


func squash() -> void:
	if _squash_applied:
		return
	_squash_applied = true
	squashed.emit()
	queue_free()


func _on_visible_on_screen_notifier_screen_exited() -> void:
	queue_free()
