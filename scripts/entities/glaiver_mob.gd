extends "res://scripts/entities/edge_family_base.gd"
class_name GlaiverMob

enum AttackState { POSITION, TELEGRAPH, DASH_SLASH, CHAIN_CHECK, RECOVER, STUN }

@export var move_speed := 9.0
@export var maintain_distance := 5.0
@export var maintain_distance_tolerance := 1.15
@export var repath_interval := 0.2
@export var attack_trigger_distance := 8.0
@export var minimum_attack_distance := 2.5
@export var telegraph_duration := 0.7
@export var chain_telegraph_duration := 0.35
@export var slash_distance := 7.0
@export var slash_speed := 28.0
@export var slash_half_width := 0.34
@export var slash_damage := 28
@export var slash_peripheral_half_width := 0.6
@export var slash_peripheral_damage := 16
@export var recover_duration := 0.3
@export var interrupt_stun_duration := 0.6
@export var chain_angle_degrees := 30.0
@export_range(-1.0, 1.0, 0.05) var attack_alignment_dot := 0.72

var _attack_state := AttackState.POSITION
var _state_time := 0.0
var _attack_dir := Vector2(0.0, -1.0)
var _dash_attack_instance_id := -1
var _current_telegraph_duration := 0.7
var _dash_duration := 0.25
var _repath_time_remaining := 0.0
var _is_chain_attack := false
var _slash_hit_registered := false

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func _edge_character_scene() -> PackedScene:
	return preload("res://art/characters/enemies/Glavier.glb")


func _ready() -> void:
	super._ready()
	facing_yaw_offset_deg = 90.0
	if _visual != null:
		_visual.facing_yaw_offset_deg = facing_yaw_offset_deg
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = maintain_distance
		_nav_agent.avoidance_enabled = false
	_dash_duration = slash_distance / maxf(0.01, slash_speed)


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_telegraph_visual()
		_sync_visual_from_body()
		return
	_refresh_target_player(delta, _attack_state == AttackState.POSITION)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_target_player()
	ignore_player_body_collisions()
	var prev_position := global_position
	match _attack_state:
		AttackState.POSITION:
			_tick_position(delta)
		AttackState.TELEGRAPH:
			_tick_telegraph(delta)
		AttackState.DASH_SLASH:
			_tick_dash_pre(delta)
		AttackState.CHAIN_CHECK:
			_tick_chain_check()
		AttackState.RECOVER:
			_tick_recover(delta)
		AttackState.STUN:
			_tick_stun(delta)
	if is_hit_knockback_active():
		apply_hit_knockback_to_body_velocity()
	move_and_slide_with_mob_separation()
	if _attack_state == AttackState.DASH_SLASH:
		_tick_dash_post(prev_position)
	mass_server_post_slide()
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_update_telegraph_visual()
	_sync_visual_from_body()


func _edge_network_write_state(state: Dictionary) -> void:
	state["st"] = _attack_state
	state["tm"] = _state_time
	state["ad"] = _attack_dir
	state["td"] = _current_telegraph_duration
	state["da"] = _dash_duration
	state["ca"] = _is_chain_attack
	state["sh"] = _slash_hit_registered


func _edge_network_read_state(state: Dictionary) -> void:
	_attack_state = int(state.get("st", _attack_state)) as AttackState
	_state_time = maxf(0.0, float(state.get("tm", _state_time)))
	var dir_v: Variant = state.get("ad", _attack_dir)
	if dir_v is Vector2:
		var dir := dir_v as Vector2
		if dir.length_squared() > 0.0001:
			_attack_dir = dir.normalized()
	_current_telegraph_duration = maxf(0.05, float(state.get("td", _current_telegraph_duration)))
	_dash_duration = maxf(0.05, float(state.get("da", _dash_duration)))
	_is_chain_attack = bool(state.get("ca", _is_chain_attack))
	_slash_hit_registered = bool(state.get("sh", _slash_hit_registered))


func _resolve_visual_state_name() -> StringName:
	if _attack_state == AttackState.DASH_SLASH or velocity.length_squared() > 0.01:
		return &"walk"
	return &"idle"


func _resolve_visual_facing_direction() -> Vector2:
	if _attack_state == AttackState.TELEGRAPH or _attack_state == AttackState.DASH_SLASH:
		return _attack_dir
	return super._resolve_visual_facing_direction()


func _current_attack_shake_progress() -> float:
	if _attack_state != AttackState.TELEGRAPH:
		return 0.0
	return clampf(_state_time / maxf(0.01, _current_telegraph_duration), 0.0, 1.0)


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	super._on_nonlethal_hit(knockback_dir, knockback_strength)
	if _attack_state == AttackState.TELEGRAPH and not _is_chain_attack:
		_attack_state = AttackState.STUN
		_state_time = 0.0
		velocity = Vector2.ZERO


func _tick_position(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	var to_target := _target_player.global_position - global_position
	var distance := to_target.length()
	if distance > 0.001:
		_steer_planar_facing_toward(to_target.normalized(), delta)
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent != null and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	var desired := Vector2.ZERO
	if distance > maintain_distance + maintain_distance_tolerance:
		desired = _glaiver_navigation_direction(to_target)
	elif distance < maintain_distance - maintain_distance_tolerance and distance > 0.001:
		desired = -to_target.normalized()
	if desired.length_squared() > 0.0001:
		velocity = desired * move_speed * surge_infusion_field_move_speed_factor()
	else:
		velocity = Vector2.ZERO
	if _can_start_primary_attack(distance, to_target):
		_start_telegraph(to_target.normalized(), false)


func _tick_telegraph(delta: float) -> void:
	_state_time += delta
	velocity = Vector2.ZERO
	_planar_facing = _attack_dir
	if _state_time >= _current_telegraph_duration:
		_start_dash()


func _tick_dash_pre(delta: float) -> void:
	_state_time += delta
	velocity = _attack_dir * slash_speed


func _tick_dash_post(previous_position: Vector2) -> void:
	var current_position := global_position
	if _edge_apply_precision_line_damage(
		previous_position,
		current_position,
		slash_half_width,
		slash_damage,
		slash_peripheral_half_width,
		slash_peripheral_damage,
		&"glaiver_slash",
		_dash_attack_instance_id,
		true,
		0.5,
		0.0,
		false
	):
		_slash_hit_registered = true
	if _hit_non_player_wall_this_frame() or current_position.distance_to(previous_position) < 0.02:
		_begin_chain_check()
		return
	if _state_time >= _dash_duration:
		_begin_chain_check()


func _tick_chain_check() -> void:
	if (
		not _is_chain_attack
		and not _slash_hit_registered
		and _target_player != null
		and is_instance_valid(_target_player)
	):
		var follow_dir := _choose_chain_follow_dir()
		if follow_dir.length_squared() > 0.0001:
			_start_telegraph(follow_dir, true)
			return
	_attack_state = AttackState.RECOVER
	_state_time = 0.0
	velocity = Vector2.ZERO


func _tick_recover(delta: float) -> void:
	_state_time += delta
	velocity = Vector2.ZERO
	if _state_time >= recover_duration:
		_attack_state = AttackState.POSITION
		_state_time = 0.0


func _tick_stun(delta: float) -> void:
	_state_time += delta
	velocity = Vector2.ZERO
	if _state_time >= interrupt_stun_duration and not is_hit_knockback_active():
		_attack_state = AttackState.POSITION
		_state_time = 0.0


func _can_start_primary_attack(distance: float, to_target: Vector2) -> bool:
	if distance > attack_trigger_distance or distance < minimum_attack_distance:
		return false
	if to_target.length_squared() <= 0.0001:
		return false
	return _planar_facing.dot(to_target.normalized()) >= attack_alignment_dot


func _glaiver_navigation_direction(to_target: Vector2) -> Vector2:
	if _nav_agent != null and _nav_agent.get_navigation_map() != RID():
		var next_pos := _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		if to_next.length_squared() > 0.001:
			return to_next.normalized()
	return to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.ZERO


func _start_telegraph(direction: Vector2, is_chain: bool) -> void:
	_attack_state = AttackState.TELEGRAPH
	_state_time = 0.0
	_is_chain_attack = is_chain
	_current_telegraph_duration = chain_telegraph_duration if is_chain else telegraph_duration
	_attack_dir = direction if direction.length_squared() > 0.0001 else _planar_facing
	if _attack_dir.length_squared() <= 0.0001:
		_attack_dir = Vector2(0.0, -1.0)
	_planar_facing = _attack_dir
	velocity = Vector2.ZERO


func _start_dash() -> void:
	_attack_state = AttackState.DASH_SLASH
	_state_time = 0.0
	_dash_attack_instance_id = _consume_edge_attack_instance_id()
	_dash_duration = slash_distance / maxf(0.01, slash_speed)
	_slash_hit_registered = false
	velocity = _attack_dir * slash_speed


func _begin_chain_check() -> void:
	_attack_state = AttackState.CHAIN_CHECK
	_state_time = 0.0
	velocity = Vector2.ZERO


func _choose_chain_follow_dir() -> Vector2:
	if _target_player == null or not is_instance_valid(_target_player):
		return Vector2.ZERO
	var to_target := _target_player.global_position - global_position
	if to_target.length_squared() <= 0.0001:
		return Vector2.ZERO
	var cross := _attack_dir.cross(to_target.normalized())
	if absf(cross) < 0.08:
		return Vector2.ZERO
	var sign_value := 1.0 if cross > 0.0 else -1.0
	return _attack_dir.rotated(deg_to_rad(chain_angle_degrees) * sign_value).normalized()


func _update_telegraph_visual() -> void:
	if _attack_state != AttackState.TELEGRAPH:
		_set_single_line_telegraph(false, Vector2.ZERO, Vector2.ZERO, 0.0, 0.0)
		return
	_set_single_line_telegraph(
		true,
		global_position,
		_attack_dir,
		slash_distance,
		clampf(_state_time / maxf(0.01, _current_telegraph_duration), 0.0, 1.0),
		telegraph_line_half_width
	)
