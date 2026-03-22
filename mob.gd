class_name CreepMob
extends CharacterBody2D

signal squashed

@export var min_speed := 10.0
@export var max_speed := 18.0
## Feet-to-ground mob; stomp when player.height exceeds this while falling.
@export var stomp_top_height := 1.02
@export var stop_distance := 1.2
@export var repath_interval := 0.2

var _squash_applied: bool = false
var _visual: Node3D
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn: bool = false
var _move_speed := 12.0
var _repath_time_remaining := 0.0
var _target_player: Node2D
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


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
	_target_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _nav_agent:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = stop_distance
		_nav_agent.avoidance_enabled = false
	if _has_spawn:
		set_deferred(&"collision_layer", 2)
	else:
		push_warning("Mob entered tree without configure_spawn; removing.")
		queue_free()


func _exit_tree() -> void:
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()


func _physics_process(delta: float) -> void:
	_update_chase_velocity(delta)
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
	var random_speed := randf_range(min_speed, max_speed)
	_move_speed = random_speed
	var to_player := player_position - start_position
	velocity = to_player.normalized() * _move_speed if to_player.length_squared() > 0.01 else Vector2.ZERO
	_sync_visual_anim_speed(random_speed)


func _update_chase_velocity(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group(&"player") as Node2D
		if _target_player == null:
			velocity = Vector2.ZERO
			return
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	var desired := Vector2.ZERO
	if _nav_agent and _nav_agent.get_navigation_map() != RID():
		var next_pos := _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		if to_next.length_squared() > 0.001:
			desired = to_next.normalized()
		else:
			# Navigation can return current position when no path is baked; fall back to direct chase.
			var to_player_fallback := _target_player.global_position - global_position
			desired = to_player_fallback.normalized() if to_player_fallback.length_squared() > 0.001 else Vector2.ZERO
	else:
		var to_player := _target_player.global_position - global_position
		desired = to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.ZERO
	var distance_to_player := global_position.distance_to(_target_player.global_position)
	if distance_to_player <= stop_distance:
		velocity = Vector2.ZERO
	else:
		velocity = desired * _move_speed
	_sync_visual_anim_speed()


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
