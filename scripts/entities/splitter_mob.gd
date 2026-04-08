class_name SplitterMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const EchoSpawnManagerScript = preload("res://scripts/entities/echo_spawn_manager.gd")
const MODEL_SCENE := preload("res://art/characters/enemies/Splitter.glb")
const ECHO_SPLINTER_KIND := 23

@export var move_speed := 1.0
@export var drift_change_interval := 1.6
@export var spawn_interval := 6.0
@export var spawn_min_count := 1
@export var spawn_max_count := 2
@export var max_splinters := 5
@export var target_refresh_interval := 0.45
@export var mesh_ground_y := 0.14
@export var mesh_scale := Vector3(1.15, 1.15, 1.15)
@export var splitter_scene_scale := 2.45

var _visual: EnemyStateVisual
var _vw: Node3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _spawn_time_remaining := 0.0
var _drift_time_remaining := 0.0
var _drift_dir := Vector2.ZERO
var _spawn_start := Vector2.ZERO
var _spawn_target := Vector2.ZERO
var _has_spawn := false
var _aggro_enabled := true
var _spawn_manager = EchoSpawnManagerScript.new(self)


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Splitter entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	_vw = _resolve_visual_world_3d()
	if _vw != null:
		_visual = EnemyStateVisualScript.new()
		_visual.name = &"SplitterVisual"
		_visual.mesh_ground_y = mesh_ground_y
		_visual.mesh_scale = mesh_scale
		_visual.facing_yaw_offset_deg = 0.0
		_visual.configure_states(build_single_scene_visual_state_config(MODEL_SCENE, splitter_scene_scale))
		_vw.add_child(_visual)
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0
	_spawn_time_remaining = spawn_interval
	_choose_next_drift()
	_sync_visual()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual()
		return
	surge_infusion_tick_server_field_decay()
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		move_and_slide_with_mob_separation()
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	_refresh_target_player(delta)
	_update_drift(delta)
	_tick_spawning(delta)
	ignore_player_body_collisions()
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {"dd": _drift_dir}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	var drift_v: Variant = state.get("dd", _drift_dir)
	if drift_v is Vector2:
		_drift_dir = drift_v as Vector2


func _refresh_target_player(delta: float) -> void:
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		true,
		Callable(self, "_pick_nearest_player_target")
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(refresh.get("refresh_time_remaining", _target_refresh_time_remaining))


func _choose_next_drift() -> void:
	_drift_time_remaining = drift_change_interval
	var dir := Vector2.ZERO
	if _target_player != null and is_instance_valid(_target_player):
		var to_player := _target_player.global_position - global_position
		if to_player.length_squared() > 0.0001:
			dir = -to_player.normalized() * 0.8
			dir += Vector2(randf_range(-0.45, 0.45), randf_range(-0.45, 0.45))
	if dir.length_squared() <= 0.0001:
		dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	_drift_dir = dir.normalized()


func _update_drift(delta: float) -> void:
	_drift_time_remaining = maxf(0.0, _drift_time_remaining - delta)
	if _drift_time_remaining <= 0.0:
		_choose_next_drift()
	velocity = _drift_dir * move_speed * surge_infusion_field_move_speed_factor()


func _tick_spawning(delta: float) -> void:
	_spawn_time_remaining = maxf(0.0, _spawn_time_remaining - delta)
	if _spawn_time_remaining <= 0.0:
		_spawn_time_remaining = spawn_interval
		_spawn_splinters()
	elif _spawn_manager.should_trigger_empty_burst():
		_spawn_splinters()


func _spawn_splinters() -> void:
	var remaining_slots := maxi(0, max_splinters - _spawn_manager.active_count())
	if remaining_slots <= 0:
		return
	var spawn_count := mini(remaining_slots, randi_range(spawn_min_count, spawn_max_count))
	var orchestrator := _runtime_orchestrator()
	if orchestrator == null:
		return
	var encounter_id := StringName(get_meta(&"encounter_id", &""))
	for _i in range(spawn_count):
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		var spawn_pos := global_position + dir * randf_range(1.1, 1.8)
		var target_pos := _target_player.global_position if _target_player != null and is_instance_valid(_target_player) else global_position + dir
		var child_v: Variant = orchestrator.call(
			&"spawn_runtime_enemy_by_kind",
			encounter_id,
			ECHO_SPLINTER_KIND,
			spawn_pos,
			target_pos,
			1.0,
			_aggro_enabled
		)
		if child_v is EnemyBase and is_instance_valid(child_v):
			_spawn_manager.track(child_v as EnemyBase)


func _runtime_orchestrator() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(true)
	_visual.set_state(&"walk" if velocity.length_squared() > 0.02 else &"idle")
	var facing := velocity.normalized() if velocity.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	_visual.sync_from_2d(global_position, facing)
