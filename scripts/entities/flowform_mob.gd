class_name FlowformMob
extends FlowModelDasherMob

const FLOWFORM_MODEL := preload("res://art/characters/enemies/Flowform.glb")
const HOTSPOT_SCENE := preload("res://dungeon/modules/gameplay/flowform_dash_hotspot_2d.tscn")

enum TrailMode { NONE, DASH, DEATH_SKID }

@export var trail_spawn_interval := 0.09
@export var trail_damage_per_tick := 1
@export var trail_tick_interval_sec := 0.2
@export var trail_lifetime_sec := 3.0
@export var dash_distance_multiplier := 3.0
## Telegraph/dash when within this fraction of nominal dash length: (dash_range + pass_through) * dash_distance_multiplier.
@export var attack_trigger_dash_length_fraction := 0.5
@export var death_skid_distance := 2.4
@export var death_skid_speed := 12.0

var _trail_timer: Timer
var _trail_mode := TrailMode.NONE
var _death_skid_active := false
var _death_skid_dir := Vector2.ZERO
var _death_skid_start := Vector2.ZERO
var _death_skid_end := Vector2.ZERO
var _death_skid_time := 0.0


func _flow_character_scene() -> PackedScene:
	return FLOWFORM_MODEL


func _attack_trigger_distance() -> float:
	var nominal_dash := (dash_range + dash_pass_through_distance) * dash_distance_multiplier
	return (
		nominal_dash
		* attack_trigger_dash_length_fraction
		* attack_trigger_distance_multiplier
	)


func _ready() -> void:
	super._ready()
	if _visual != null:
		_visual.facing_yaw_offset_deg = 90.0
	_trail_timer = Timer.new()
	_trail_timer.wait_time = maxf(0.04, trail_spawn_interval)
	_trail_timer.one_shot = false
	_trail_timer.timeout.connect(_on_trail_timer_timeout)
	add_child(_trail_timer)


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		super._physics_process(delta)
		return
	if _death_skid_active:
		_update_death_skid(delta)
		move_and_slide_with_mob_separation()
		mass_server_post_slide()
		_enemy_network_server_broadcast(delta)
		_sync_visual_from_body()
		_update_telegraph_visual()
		return
	super._physics_process(delta)


func _enemy_network_compact_state() -> Dictionary:
	var state := super._enemy_network_compact_state()
	state["dk"] = _death_skid_active
	state["ddr"] = _death_skid_dir
	state["dks"] = _death_skid_start
	state["dke"] = _death_skid_end
	state["dkt"] = _death_skid_time
	return state


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	super._enemy_network_apply_remote_state(state)
	_death_skid_active = bool(state.get("dk", _death_skid_active))
	var death_dir_v: Variant = state.get("ddr", _death_skid_dir)
	if death_dir_v is Vector2:
		var death_dir := death_dir_v as Vector2
		if death_dir.length_squared() > 0.0001:
			_death_skid_dir = death_dir.normalized()
	var death_start_v: Variant = state.get("dks", _death_skid_start)
	if death_start_v is Vector2:
		_death_skid_start = death_start_v as Vector2
	var death_end_v: Variant = state.get("dke", _death_skid_end)
	if death_end_v is Vector2:
		_death_skid_end = death_end_v as Vector2
	_death_skid_time = maxf(0.0, float(state.get("dkt", _death_skid_time)))


func _should_defer_death(_packet: DamagePacket) -> bool:
	return true


func _begin_deferred_death(_packet: DamagePacket) -> void:
	_begin_death_skid()


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	if _death_skid_active:
		return
	if _is_dashing():
		return
	super._on_nonlethal_hit(knockback_dir, knockback_strength)


func _begin_death_skid() -> void:
	_death_skid_active = true
	_aggro_enabled = false
	_set_attack_phase(AttackPhase.CHASE)
	_telegraph_time = 0.0
	_dash_time = 0.0
	_recovery_time_remaining = 0.0
	_stun_time_remaining = 0.0
	_dash_hit_applied = false
	if _damage_receiver != null:
		_damage_receiver.set_active(false)
	if _hurtbox != null:
		_hurtbox.set_active(false)
	if _dash_contact_hitbox != null:
		_dash_contact_hitbox.deactivate()
	var death_dir := _dash_dir
	if death_dir.length_squared() <= 0.0001:
		death_dir = _planar_facing
	if death_dir.length_squared() <= 0.0001:
		death_dir = velocity
	_death_skid_dir = death_dir.normalized() if death_dir.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	_death_skid_start = global_position
	_death_skid_end = _death_skid_start + _death_skid_dir * death_skid_distance
	_death_skid_time = 0.0
	_planar_facing = _death_skid_dir
	velocity = _death_skid_dir * death_skid_speed
	_start_trail_mode(TrailMode.DEATH_SKID, true)
	_sync_visual_anim_speed(death_skid_speed)


func _update_death_skid(delta: float) -> void:
	_death_skid_time += delta
	var duration := _current_death_skid_duration()
	var u := clampf(_death_skid_time / maxf(0.01, duration), 0.0, 1.0)
	var target_pos := _death_skid_start.lerp(_death_skid_end, u)
	var to_target := target_pos - global_position
	if to_target.length_squared() > 0.0001:
		velocity = to_target / maxf(delta, 0.0001)
	else:
		velocity = Vector2.ZERO
	if u >= 1.0:
		_finish_death_skid()


func _finish_death_skid() -> void:
	_death_skid_active = false
	_stop_trail_mode()
	velocity = Vector2.ZERO
	_sync_visual_anim_speed(0.0)
	super.squash()


func _current_death_skid_duration() -> float:
	return _death_skid_start.distance_to(_death_skid_end) / maxf(0.01, death_skid_speed)


func _start_dash() -> void:
	super._start_dash()
	var dash_vec := _dash_end - _dash_start
	if dash_vec.length_squared() > 0.0001 and dash_distance_multiplier != 1.0:
		_dash_end = _dash_start + dash_vec * dash_distance_multiplier
		_refresh_dash_contact_hitbox()
	_start_trail_mode(TrailMode.DASH, true)


func _update_dash(delta: float) -> void:
	super._update_dash(delta)
	if not _is_dashing() and _trail_mode == TrailMode.DASH:
		_stop_trail_mode()


func _start_trail_mode(next_mode: TrailMode, spawn_immediate: bool) -> void:
	_trail_mode = next_mode
	if _trail_timer == null:
		return
	_trail_timer.wait_time = maxf(0.04, trail_spawn_interval)
	if spawn_immediate:
		_spawn_trail_segment(global_position, true)
	_trail_timer.start()


func _stop_trail_mode() -> void:
	_trail_mode = TrailMode.NONE
	if _trail_timer != null:
		_trail_timer.stop()


func _on_trail_timer_timeout() -> void:
	if not is_damage_authority():
		return
	if _trail_mode == TrailMode.NONE:
		return
	_spawn_trail_segment(global_position, true)


func _spawn_trail_segment(world_position: Vector2, authoritative_damage: bool) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spot := HOTSPOT_SCENE.instantiate()
	if spot is FlowformDashHotspot2D:
		var hotspot := spot as FlowformDashHotspot2D
		hotspot.damage_per_tick = trail_damage_per_tick
		hotspot.tick_interval_sec = trail_tick_interval_sec
		hotspot.lifetime_sec = trail_lifetime_sec
		hotspot.visual_only = not authoritative_damage
	parent.add_child(spot)
	spot.global_position = world_position
	if authoritative_damage and _multiplayer_active() and _is_server_peer() and _can_broadcast_world_replication():
		_rpc_spawn_trail_segment.rpc(world_position)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_trail_segment(world_position: Vector2) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	_spawn_trail_segment(world_position, false)
