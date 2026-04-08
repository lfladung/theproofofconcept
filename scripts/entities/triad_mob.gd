class_name TriadMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const EchoSamplerScript = preload("res://scripts/entities/echo_behavior_sampler.gd")
const EchoSpawnManagerScript = preload("res://scripts/entities/echo_spawn_manager.gd")
const MODEL_SCENE := preload("res://art/characters/enemies/Triad.glb")
const ECHO_UNIT_KIND := 24

@export var move_speed := 2.0
@export var drift_change_interval := 1.2
@export var spawn_interval := 5.0
@export var max_echo_units := 3
@export var target_refresh_interval := 0.35
@export var pulse_interval := 2.6
@export var pulse_radius := 3.2
@export var pulse_damage := 4
@export var destabilize_delay_min := 1.0
@export var destabilize_delay_max := 2.0
@export var mesh_ground_y := 0.16
@export var mesh_scale := Vector3(1.2, 1.2, 1.2)
@export var triad_scene_scale := 2.55

var _visual: EnemyStateVisual
var _vw: Node3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _spawn_time_remaining := 0.0
var _pulse_time_remaining := 0.0
var _drift_time_remaining := 0.0
var _drift_dir := Vector2.ZERO
var _spawn_start := Vector2.ZERO
var _spawn_target := Vector2.ZERO
var _has_spawn := false
var _aggro_enabled := true
var _spawn_manager = EchoSpawnManagerScript.new(self)
var _sampler = EchoSamplerScript.new()


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
		push_warning("Triad entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	_vw = _resolve_visual_world_3d()
	if _vw != null:
		_visual = EnemyStateVisualScript.new()
		_visual.name = &"TriadVisual"
		_visual.mesh_ground_y = mesh_ground_y
		_visual.mesh_scale = mesh_scale
		_visual.facing_yaw_offset_deg = 0.0
		_visual.configure_states(build_single_scene_visual_state_config(MODEL_SCENE, triad_scene_scale))
		_vw.add_child(_visual)
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0
	_spawn_time_remaining = spawn_interval
	_pulse_time_remaining = pulse_interval
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
	_tick_pulse(delta)
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
	var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 0.0001:
			dir += -to_target.normalized() * 0.35
	_drift_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector2(0.0, -1.0)


func _update_drift(delta: float) -> void:
	_drift_time_remaining = maxf(0.0, _drift_time_remaining - delta)
	if _drift_time_remaining <= 0.0:
		_choose_next_drift()
	velocity = _drift_dir * move_speed * surge_infusion_field_move_speed_factor()


func _tick_spawning(delta: float) -> void:
	_spawn_time_remaining = maxf(0.0, _spawn_time_remaining - delta)
	if _spawn_time_remaining <= 0.0:
		_spawn_time_remaining = spawn_interval
		_spawn_echo_unit()
	elif _spawn_manager.should_trigger_empty_burst():
		_spawn_echo_unit()


func _spawn_echo_unit() -> void:
	if not _spawn_manager.can_spawn(max_echo_units):
		return
	var orchestrator := _runtime_orchestrator()
	if orchestrator == null:
		return
	var encounter_id := StringName(get_meta(&"encounter_id", &""))
	var target := _target_player if _target_player != null and is_instance_valid(_target_player) else _pick_nearest_player_target()
	var snapshot_style := _sampler.style_for_player(target, _sampler.dominant_style(EchoSamplerScript.EchoStyle.RANGED))
	var dir := Vector2.RIGHT.rotated(randf() * TAU)
	var spawn_pos := global_position + dir * randf_range(1.2, 2.0)
	var target_pos := target.global_position if target != null and is_instance_valid(target) else global_position + dir
	var child_v: Variant = orchestrator.call(
		&"spawn_runtime_enemy_by_kind",
		encounter_id,
		ECHO_UNIT_KIND,
		spawn_pos,
		target_pos,
		1.0,
		_aggro_enabled
	)
	if child_v is EnemyBase and is_instance_valid(child_v):
		var child := child_v as EnemyBase
		child.mode = (
			0
			if snapshot_style == EchoSamplerScript.EchoStyle.MELEE
			else 1
		)
		_spawn_manager.track(child)


func _tick_pulse(delta: float) -> void:
	_pulse_time_remaining = maxf(0.0, _pulse_time_remaining - delta)
	if _pulse_time_remaining > 0.0:
		return
	_pulse_time_remaining = pulse_interval
	for candidate in _targetable_player_candidates():
		if candidate == null or not is_instance_valid(candidate):
			continue
		if global_position.distance_squared_to(candidate.global_position) > pulse_radius * pulse_radius:
			continue
		if candidate.has_method(&"take_attack_damage"):
			var dir := (candidate.global_position - global_position).normalized()
			candidate.call(&"take_attack_damage", pulse_damage, global_position, dir)


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, hurtbox_area: Area2D) -> void:
	if hp_damage > 0 and packet != null and is_damage_authority():
		_sampler.record_packet(packet, hp_damage)
	super._on_receiver_damage_applied(packet, hp_damage, hurtbox_area)


func squash() -> void:
	_destabilize_children()
	super.squash()


func _destabilize_children() -> void:
	for child in _spawn_manager.active_children():
		if child == null or not is_instance_valid(child):
			continue
		var timer := get_tree().create_timer(randf_range(destabilize_delay_min, destabilize_delay_max))
		timer.timeout.connect(
			func() -> void:
				if is_instance_valid(child):
					child.queue_free(),
			CONNECT_ONE_SHOT
		)
	_spawn_manager.clear_without_free()


func _runtime_orchestrator() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(true)
	_visual.set_state(&"walk" if velocity.length_squared() > 0.02 else &"idle")
	var facing := Vector2(0.0, -1.0)
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 0.0001:
			facing = to_target.normalized()
	elif velocity.length_squared() > 0.0001:
		facing = velocity.normalized()
	_visual.sync_from_2d(global_position, facing)
