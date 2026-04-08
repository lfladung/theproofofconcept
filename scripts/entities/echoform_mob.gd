class_name EchoformMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const EchoSamplerScript = preload("res://scripts/entities/echo_behavior_sampler.gd")
const EchoReflectionHelperScript = preload("res://scripts/entities/echo_reflection_helper.gd")
const ArrowProjectilePoolScript = preload("res://scripts/entities/arrow_projectile_pool.gd")
const MODEL_SCENE := preload("res://art/characters/enemies/Spawner.glb")

enum EchoformState {
	OBSERVE = 0,
	RUSH = 1,
	RUSH_TELEGRAPH = 2,
	RUSH_RECOVERY = 3,
	RANGED = 4,
	RANGED_CHARGE = 5,
}

@export var observation_duration := 3.0
@export var observation_retreat_speed := 5.5
@export var observation_desired_distance := 7.5
@export var target_refresh_interval := 0.28
@export var repath_interval := 0.18
@export var rush_move_speed := 9.2
@export var rush_trigger_distance := 6.0
@export var rush_dash_speed := 17.5
@export var rush_dash_duration := 0.2
@export var rush_telegraph_duration := 0.5
@export var rush_recovery_duration := 0.28
@export var rush_contact_damage := 18
@export var ranged_move_speed := 5.4
@export var ranged_preferred_distance := 8.0
@export var ranged_backoff_distance := 5.2
@export var ranged_charge_duration := 0.7
@export var ranged_projectile_damage := 10
@export var ranged_projectile_speed := 17.0
@export var ranged_projectile_max_distance := 10.0
@export var ranged_projectile_count := 3
@export var ranged_projectile_spread_degrees := 22.0
@export var ranged_projectile_spawn_distance := 1.0
@export var ranged_attack_cooldown := 1.45
@export var reflection_ratio := 0.3
@export var reflection_melee_range := 2.4
@export var reflection_projectile_speed := 18.0
@export var reflection_projectile_distance := 10.0
@export var mesh_ground_y := 0.13
@export var mesh_scale := Vector3(1.05, 1.05, 1.05)
@export var echoform_scene_scale := 2.5
@export var turn_toward_target_deg_per_sec := 320.0

var _visual: EnemyStateVisual
var _vw: Node3D
var _target_player: Node2D
var _mirrored_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _state := EchoformState.OBSERVE
var _observation_time_remaining := 0.0
var _cooldown_remaining := 0.0
var _state_time_remaining := 0.0
var _aggro_enabled := true
var _spawn_start := Vector2.ZERO
var _spawn_target := Vector2.ZERO
var _has_spawn := false
var _planar_facing := Vector2(0.0, -1.0)
var _sampler = EchoSamplerScript.new()
var _adapted_style := 1

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Echoform entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	_planar_facing = (_spawn_target - _spawn_start).normalized() if _spawn_target.distance_squared_to(_spawn_start) > 0.0001 else Vector2(0.0, -1.0)
	_vw = _resolve_visual_world_3d()
	if _vw != null:
		_visual = EnemyStateVisualScript.new()
		_visual.name = &"EchoformVisual"
		_visual.mesh_ground_y = mesh_ground_y
		_visual.mesh_scale = mesh_scale
		_visual.facing_yaw_offset_deg = 0.0
		_visual.configure_states(build_single_scene_visual_state_config(MODEL_SCENE, echoform_scene_scale))
		_vw.add_child(_visual)
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = ranged_backoff_distance
		_nav_agent.avoidance_enabled = false
	_target_player = _pick_nearest_player_target()
	_mirrored_player = _target_player
	_observation_time_remaining = observation_duration
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
	ignore_player_body_collisions()
	match _state:
		EchoformState.OBSERVE:
			_update_observation(delta)
		EchoformState.RUSH:
			_update_rush(delta)
		EchoformState.RUSH_TELEGRAPH:
			_update_rush_telegraph(delta)
		EchoformState.RUSH_RECOVERY:
			_update_rush_recovery(delta)
		EchoformState.RANGED:
			_update_ranged(delta)
		EchoformState.RANGED_CHARGE:
			_update_ranged_charge(delta)
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"st": int(_state),
		"pf": _planar_facing,
		"ot": _observation_time_remaining,
		"cd": _cooldown_remaining,
		"sr": _state_time_remaining,
		"as": _adapted_style,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_state = int(state.get("st", int(_state))) as EchoformState
	_observation_time_remaining = maxf(0.0, float(state.get("ot", _observation_time_remaining)))
	_cooldown_remaining = maxf(0.0, float(state.get("cd", _cooldown_remaining)))
	_state_time_remaining = maxf(0.0, float(state.get("sr", _state_time_remaining)))
	_adapted_style = int(state.get("as", _adapted_style))
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()


func _refresh_target_player(delta: float) -> void:
	var picker := Callable(self, "_pick_behavior_target")
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		true,
		picker
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(refresh.get("refresh_time_remaining", _target_refresh_time_remaining))


func _pick_behavior_target() -> Node2D:
	if _mirrored_player != null and is_instance_valid(_mirrored_player) and not _is_player_downed_node(_mirrored_player):
		return _mirrored_player
	return _pick_nearest_player_target()


func _update_observation(delta: float) -> void:
	_observation_time_remaining = maxf(0.0, _observation_time_remaining - delta)
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
	else:
		var to_target := _target_player.global_position - global_position
		if to_target.length() < observation_desired_distance:
			velocity = -to_target.normalized() * observation_retreat_speed
			if velocity.length_squared() > 0.0001:
				_planar_facing = (-velocity).normalized()
		else:
			velocity = Vector2.ZERO
	if _observation_time_remaining <= 0.0:
		_lock_adaptation()


func _lock_adaptation() -> void:
	_adapted_style = _sampler.dominant_style(EchoSamplerScript.EchoStyle.RANGED)
	_mirrored_player = _sampler.highest_damage_player()
	_target_player = _pick_behavior_target()
	_state = EchoformState.RUSH if _adapted_style == EchoSamplerScript.EchoStyle.MELEE else EchoformState.RANGED
	_cooldown_remaining = 0.0
	_state_time_remaining = 0.0


func _update_rush(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	var to_target := _target_player.global_position - global_position
	var dir := to_target.normalized() if to_target.length_squared() > 0.0001 else _planar_facing
	var max_step := deg_to_rad(turn_toward_target_deg_per_sec) * delta
	_planar_facing = step_planar_facing_toward(_planar_facing, dir, max_step)
	if to_target.length() <= rush_trigger_distance:
		_state = EchoformState.RUSH_TELEGRAPH
		_state_time_remaining = rush_telegraph_duration
		velocity = Vector2.ZERO
		return
	velocity = _planar_facing * rush_move_speed * surge_infusion_field_move_speed_factor()


func _update_rush_telegraph(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_time_remaining = maxf(0.0, _state_time_remaining - delta)
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 0.0001:
			var max_step := deg_to_rad(turn_toward_target_deg_per_sec) * delta
			_planar_facing = step_planar_facing_toward(_planar_facing, to_target.normalized(), max_step)
	if _state_time_remaining <= 0.0:
		var pkt := DamagePacketScript.new() as DamagePacket
		pkt.amount = rush_contact_damage
		pkt.kind = &"contact"
		pkt.source_node = self
		pkt.source_uid = get_instance_id()
		pkt.origin = global_position
		pkt.direction = _planar_facing
		pkt.knockback = 0.0
		pkt.apply_iframes = true
		pkt.blockable = true
		pkt.debug_label = &"echoform_rush"
		var hit_target := _target_player
		if hit_target != null and is_instance_valid(hit_target):
			var to_target := hit_target.global_position - global_position
			if to_target.length() <= rush_trigger_distance + 1.0 and hit_target.has_method(&"take_attack_damage"):
				hit_target.call(&"take_attack_damage", rush_contact_damage, global_position, _planar_facing)
		velocity = _planar_facing * rush_dash_speed
		_state = EchoformState.RUSH_RECOVERY
		_state_time_remaining = rush_dash_duration + rush_recovery_duration


func _update_rush_recovery(delta: float) -> void:
	_state_time_remaining = maxf(0.0, _state_time_remaining - delta)
	if _state_time_remaining <= rush_recovery_duration:
		velocity = Vector2.ZERO
	if _state_time_remaining <= 0.0:
		_state = EchoformState.RUSH


func _update_ranged(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	var to_target := _target_player.global_position - global_position
	var distance := to_target.length()
	var dir := to_target.normalized() if to_target.length_squared() > 0.0001 else _planar_facing
	var desired := Vector2.ZERO
	if distance > ranged_preferred_distance:
		desired = dir
	elif distance < ranged_backoff_distance:
		desired = -dir
	velocity = desired * ranged_move_speed * surge_infusion_field_move_speed_factor()
	var max_step := deg_to_rad(turn_toward_target_deg_per_sec) * delta
	_planar_facing = step_planar_facing_toward(_planar_facing, dir, max_step)
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta * surge_infusion_field_cooldown_tick_factor())
	if _cooldown_remaining <= 0.0 and distance <= ranged_projectile_max_distance:
		_state = EchoformState.RANGED_CHARGE
		_state_time_remaining = ranged_charge_duration
		velocity = Vector2.ZERO


func _update_ranged_charge(delta: float) -> void:
	velocity = Vector2.ZERO
	_state_time_remaining = maxf(0.0, _state_time_remaining - delta)
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 0.0001:
			var max_step := deg_to_rad(turn_toward_target_deg_per_sec) * delta
			_planar_facing = step_planar_facing_toward(_planar_facing, to_target.normalized(), max_step)
	if _state_time_remaining <= 0.0:
		_fire_ranged_volley(_planar_facing)
		_cooldown_remaining = ranged_attack_cooldown
		_state = EchoformState.RANGED


func _fire_ranged_volley(direction: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spawn_position := global_position + direction.normalized() * ranged_projectile_spawn_distance
	for projectile_index in range(ranged_projectile_count):
		var dir := _volley_direction_for(direction, projectile_index, ranged_projectile_count, ranged_projectile_spread_degrees)
		var projectile := ArrowProjectilePoolScript.acquire_projectile(parent)
		if projectile == null:
			continue
		projectile.speed = ranged_projectile_speed
		projectile.max_distance = ranged_projectile_max_distance
		projectile.damage = ranged_projectile_damage
		projectile.mesh_scale = Vector3(1.0, 1.0, 1.0) * 0.78
		if projectile.has_method(&"set_authoritative_damage"):
			projectile.call(&"set_authoritative_damage", is_damage_authority())
		projectile.configure(spawn_position, dir, _vw, false, &"purple")


func _volley_direction_for(base_direction: Vector2, projectile_index: int, count: int, total_spread_degrees: float) -> Vector2:
	var dir := base_direction.normalized() if base_direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	if count <= 1:
		return dir
	var start_deg := -total_spread_degrees * 0.5
	var step_deg := total_spread_degrees / float(maxi(1, count - 1))
	return dir.rotated(deg_to_rad(start_deg + step_deg * float(projectile_index))).normalized()


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, hurtbox_area: Area2D) -> void:
	if hp_damage > 0 and packet != null and is_damage_authority():
		if _state == EchoformState.OBSERVE:
			_sampler.record_packet(packet, hp_damage)
		var attacker = EchoSamplerScript.resolve_attacker_node(packet)
		if attacker != null and is_instance_valid(attacker):
			_mirrored_player = attacker
		if EchoReflectionHelperScript.is_reflectable(packet):
			EchoReflectionHelperScript.reflect_to_attacker(
				self,
				packet,
				reflection_ratio,
				2 if _health <= maxi(1, int(roundf(float(max_health) * 0.5))) else 1,
				_vw,
				maxi(1, int(roundf(float(maxi(1, packet.amount)) * reflection_ratio))),
				reflection_projectile_speed,
				reflection_projectile_distance,
				reflection_melee_range
			)
	super._on_receiver_damage_applied(packet, hp_damage, hurtbox_area)


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(true)
	var moving := velocity.length_squared() > 0.04
	_visual.set_attack_shake_progress(1.0 - (_state_time_remaining / maxf(0.01, rush_telegraph_duration)) if _state == EchoformState.RUSH_TELEGRAPH else 0.0)
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _planar_facing)
