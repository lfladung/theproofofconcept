extends "res://scripts/entities/edge_family_base.gd"
class_name SkewerMob

enum AttackState { APPROACH, WINDUP, LUNGE, RECOVER, STUN }

@export var move_speed := 7.0
@export var attack_trigger_distance := 3.2
@export_range(-1.0, 1.0, 0.05) var attack_alignment_dot := 0.72
@export var approach_turn_deg_per_sec := 120.0
@export var windup_duration := 0.8
@export var lunge_distance := 3.0
@export var lunge_speed := 16.0
@export var lunge_recovery_duration := 0.9
@export var body_half_width := 0.34
@export var body_damage := 8
@export var tip_half_width := 0.24
@export var tip_damage := 18
@export var tip_length := 0.9

var _attack_state := AttackState.APPROACH
var _state_time := 0.0
var _attack_dir := Vector2(0.0, -1.0)
var _lunge_attack_instance_id := -1
var _lunge_duration := 0.2


func _edge_character_scene() -> PackedScene:
	return preload("res://art/characters/enemies/Skewer.glb")


func _ready() -> void:
	super._ready()
	facing_yaw_offset_deg = 180.0
	if _visual != null:
		_visual.facing_yaw_offset_deg = facing_yaw_offset_deg
	_lunge_duration = lunge_distance / maxf(0.01, lunge_speed)


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_telegraph_visual()
		_sync_visual_from_body()
		return
	_refresh_target_player(delta, _attack_state == AttackState.APPROACH)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_target_player()
	ignore_player_body_collisions()
	var prev_position := global_position
	match _attack_state:
		AttackState.APPROACH:
			_tick_approach(delta)
		AttackState.WINDUP:
			_tick_windup(delta)
		AttackState.LUNGE:
			_tick_lunge_pre(delta)
		AttackState.RECOVER:
			_tick_recover(delta)
		AttackState.STUN:
			_tick_stun(delta)
	if is_hit_knockback_active():
		apply_hit_knockback_to_body_velocity()
	move_and_slide_with_mob_separation()
	if _attack_state == AttackState.LUNGE:
		_tick_lunge_post(delta, prev_position)
	mass_server_post_slide()
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_update_telegraph_visual()
	_sync_visual_from_body()


func _edge_network_write_state(state: Dictionary) -> void:
	state["st"] = _attack_state
	state["tm"] = _state_time
	state["ad"] = _attack_dir
	state["ld"] = _lunge_duration


func _edge_network_read_state(state: Dictionary) -> void:
	_attack_state = int(state.get("st", _attack_state)) as AttackState
	_state_time = maxf(0.0, float(state.get("tm", _state_time)))
	var dir_v: Variant = state.get("ad", _attack_dir)
	if dir_v is Vector2:
		var dir := dir_v as Vector2
		if dir.length_squared() > 0.0001:
			_attack_dir = dir.normalized()
	_lunge_duration = maxf(0.01, float(state.get("ld", _lunge_duration)))


func _resolve_visual_state_name() -> StringName:
	if _attack_state == AttackState.LUNGE or velocity.length_squared() > 0.01:
		return &"walk"
	return &"idle"


func _resolve_visual_facing_direction() -> Vector2:
	if _attack_state == AttackState.WINDUP or _attack_state == AttackState.LUNGE:
		return _attack_dir
	return super._resolve_visual_facing_direction()


func _current_attack_shake_progress() -> float:
	if _attack_state != AttackState.WINDUP:
		return 0.0
	return clampf(_state_time / maxf(0.01, windup_duration), 0.0, 1.0)


func _tick_approach(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	var to_target := _target_player.global_position - global_position
	if to_target.length_squared() <= 0.0001:
		velocity = Vector2.ZERO
		return
	_steer_planar_facing_toward(to_target.normalized(), delta, approach_turn_deg_per_sec)
	velocity = _planar_facing * move_speed * surge_infusion_field_move_speed_factor()
	var facing_dot := _planar_facing.dot(to_target.normalized())
	if to_target.length() <= attack_trigger_distance and facing_dot >= attack_alignment_dot:
		_start_windup(to_target.normalized())


func _tick_windup(delta: float) -> void:
	_state_time += delta
	velocity = Vector2.ZERO
	if _state_time >= windup_duration:
		_start_lunge()


func _tick_lunge_pre(delta: float) -> void:
	_state_time += delta
	velocity = _attack_dir * lunge_speed
	if _state_time >= _lunge_duration + 0.02:
		_begin_recover()


func _tick_lunge_post(_delta: float, previous_position: Vector2) -> void:
	var current_position := global_position
	var did_hit := _edge_apply_precision_line_damage(
		previous_position,
		current_position,
		body_half_width,
		body_damage,
		body_half_width,
		body_damage,
		&"skewer_body",
		_lunge_attack_instance_id,
		true,
		0.5,
		0.0,
		false
	)
	var tip_start := current_position + _attack_dir * maxf(0.0, tip_length * 0.2)
	var tip_end := current_position + _attack_dir * tip_length
	if _edge_apply_precision_line_damage(
		tip_start,
		tip_end,
		tip_half_width,
		tip_damage,
		tip_half_width,
		tip_damage,
		&"skewer_tip",
		_lunge_attack_instance_id,
		true,
		0.5,
		0.0,
		false
	):
		did_hit = true
	if _hit_non_player_wall_this_frame() or current_position.distance_to(previous_position) < 0.02:
		_begin_recover()
		return
	if _state_time >= _lunge_duration:
		_begin_recover()


func _tick_recover(delta: float) -> void:
	_state_time += delta
	velocity = Vector2.ZERO
	if _state_time >= lunge_recovery_duration:
		_attack_state = AttackState.APPROACH
		_state_time = 0.0


func _tick_stun(delta: float) -> void:
	_state_time += delta
	velocity = Vector2.ZERO
	if _state_time >= universal_stagger_duration and not is_hit_knockback_active():
		_attack_state = AttackState.APPROACH
		_state_time = 0.0


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	super._on_nonlethal_hit(knockback_dir, knockback_strength)
	cancel_active_attack_for_stagger()


func cancel_active_attack_for_stagger() -> void:
	_attack_state = AttackState.STUN
	_state_time = 0.0
	velocity = Vector2.ZERO


func _start_windup(direction: Vector2) -> void:
	_attack_state = AttackState.WINDUP
	_state_time = 0.0
	_attack_dir = direction if direction.length_squared() > 0.0001 else _planar_facing
	if _attack_dir.length_squared() <= 0.0001:
		_attack_dir = Vector2(0.0, -1.0)
	_planar_facing = _attack_dir
	velocity = Vector2.ZERO


func _start_lunge() -> void:
	_attack_state = AttackState.LUNGE
	_state_time = 0.0
	_lunge_attack_instance_id = _consume_edge_attack_instance_id()
	velocity = _attack_dir * lunge_speed


func _begin_recover() -> void:
	_attack_state = AttackState.RECOVER
	_state_time = 0.0
	velocity = Vector2.ZERO


func _update_telegraph_visual() -> void:
	if _attack_state != AttackState.WINDUP:
		_set_single_line_telegraph(false, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
		return
	_set_single_line_telegraph(
		true,
		global_position,
		_attack_dir,
		lunge_distance + tip_length,
		clampf(_state_time / maxf(0.01, windup_duration), 0.0, 1.0),
		body_half_width
	)
