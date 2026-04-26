extends "res://scripts/entities/edge_family_base.gd"
class_name RazorformMob

const EdgeCutLineHazardScript = preload("res://scripts/entities/edge_cut_line_hazard.gd")

enum SequenceState { SEQUENCE_SELECT, PLACE_CUTS, EXECUTE_CUTS, COOLDOWN }

@export var move_speed := 4.0
@export var maintain_distance_min := 6.0
@export var maintain_distance_max := 10.0
@export var sequence_cooldown_duration := 3.2
@export var sequence_telegraph_duration := 1.5
@export var sequence_spawn_interval := 1.0
@export var max_sequence_cuts := 3
@export var cut_line_half_length := 7.25
@export var cut_full_half_width := 0.75
@export var cut_damage := 30
@export var death_burst_full_half_width := 0.95
@export var death_burst_cut_count := 8
@export var death_burst_radius := 10
@export var death_burst_telegraph_duration := 1.9
@export var death_burst_outline_color := Color(1.0, 0.98, 0.92, 1.0)
@export var death_burst_fill_color := Color(1.0, 0.26, 0.12, 0.95)

var _sequence_state := SequenceState.SEQUENCE_SELECT
var _state_time := 0.0
var _cooldown_remaining := 0.0
var _next_hazard_id := 1
var _cut_hazards_by_id: Dictionary = {}
var _death_burst_started := false
var _pending_sequence_cut_indices: Array[int] = []
var _sequence_spawn_timer := 0.0


func _edge_character_scene() -> PackedScene:
	return preload("res://art/characters/enemies/Razorform.glb")


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_remote_cut_visuals()
		_sync_visual_from_body()
		return
	_refresh_target_player(delta, _sequence_state == SequenceState.SEQUENCE_SELECT)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_target_player()
	ignore_player_body_collisions()
	_tick_cut_hazards(delta)
	if apply_universal_stagger_stop(delta, true):
		move_and_slide_with_mob_separation()
		mass_server_post_slide()
		_enemy_network_server_broadcast(delta)
		_sync_visual_from_body()
		return
	if is_death_deferred():
		velocity = Vector2.ZERO
		if _cut_hazards_by_id.is_empty():
			squash()
	else:
		_tick_sequence_state(delta)
	if is_hit_knockback_active():
		apply_hit_knockback_to_body_velocity()
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_sync_visual_from_body()


func _exit_tree() -> void:
	_release_all_cut_visuals()
	super._exit_tree()


func _edge_network_write_state(state: Dictionary) -> void:
	state["st"] = _sequence_state
	state["tm"] = _state_time
	state["cd"] = _cooldown_remaining
	state["db"] = _death_burst_started
	state["ps"] = _sequence_spawn_timer
	var cut_snapshots: Array = []
	for hazard in _cut_hazards_by_id.values():
		if hazard != null:
			cut_snapshots.append(hazard.to_snapshot())
	state["ct"] = cut_snapshots


func _edge_network_read_state(state: Dictionary) -> void:
	_sequence_state = int(state.get("st", _sequence_state)) as SequenceState
	_state_time = maxf(0.0, float(state.get("tm", _state_time)))
	_cooldown_remaining = maxf(0.0, float(state.get("cd", _cooldown_remaining)))
	_death_burst_started = bool(state.get("db", _death_burst_started))
	_sequence_spawn_timer = maxf(0.0, float(state.get("ps", _sequence_spawn_timer)))
	var snapshots_v: Variant = state.get("ct", [])
	if snapshots_v is Array:
		_apply_remote_cut_snapshots(snapshots_v)


func _should_defer_death(_packet: DamagePacket) -> bool:
	return not _death_burst_started


func _begin_deferred_death(_packet: DamagePacket) -> void:
	_death_burst_started = true
	velocity = Vector2.ZERO
	if _hurtbox != null:
		_hurtbox.set_active(false)
	collision_layer = 0
	collision_mask = 0
	_release_all_cut_visuals()
	_cut_hazards_by_id.clear()
	_pending_sequence_cut_indices.clear()
	_sequence_spawn_timer = 0.0
	_spawn_death_burst_cuts()


func _tick_sequence_state(delta: float) -> void:
	_state_time += delta
	match _sequence_state:
		SequenceState.SEQUENCE_SELECT:
			_tick_body_reposition(delta)
			if _target_player != null and is_instance_valid(_target_player):
				_sequence_state = SequenceState.PLACE_CUTS
				_state_time = 0.0
				_begin_sequence_cut_spawns()
		SequenceState.PLACE_CUTS:
			velocity = Vector2.ZERO
			_tick_sequence_cut_spawns(delta)
		SequenceState.EXECUTE_CUTS:
			velocity = Vector2.ZERO
			if _cut_hazards_by_id.is_empty():
				_sequence_state = SequenceState.COOLDOWN
				_state_time = 0.0
				_cooldown_remaining = sequence_cooldown_duration
		SequenceState.COOLDOWN:
			_tick_body_reposition(delta * 0.5)
			_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
			if _cooldown_remaining <= 0.0 and _cut_hazards_by_id.is_empty():
				_sequence_state = SequenceState.SEQUENCE_SELECT
				_state_time = 0.0


func _tick_body_reposition(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	var to_target := _target_player.global_position - global_position
	var distance := to_target.length()
	if to_target.length_squared() > 0.001:
		_steer_planar_facing_toward(to_target.normalized(), delta, 240.0)
	if distance > maintain_distance_max:
		velocity = to_target.normalized() * move_speed
	elif distance < maintain_distance_min and distance > 0.001:
		velocity = -to_target.normalized() * move_speed
	else:
		velocity = Vector2.ZERO


func _tick_cut_hazards(delta: float) -> void:
	var finished_ids: Array[int] = []
	for hazard_id in _cut_hazards_by_id.keys():
		var hazard = _cut_hazards_by_id[hazard_id]
		if hazard == null:
			finished_ids.append(int(hazard_id))
			continue
		if hazard.tick_server(delta, self):
			hazard.release_visual()
			finished_ids.append(int(hazard_id))
	for hazard_id in finished_ids:
		_cut_hazards_by_id.erase(hazard_id)


func _begin_sequence_cut_spawns() -> void:
	var cut_count := _choose_sequence_cut_count()
	_pending_sequence_cut_indices.clear()
	for index in range(cut_count):
		_pending_sequence_cut_indices.append(index)
	_sequence_spawn_timer = 0.0


func cancel_active_attack_for_stagger() -> void:
	if is_death_deferred():
		return
	_release_all_cut_visuals()
	_cut_hazards_by_id.clear()
	_pending_sequence_cut_indices.clear()
	_sequence_spawn_timer = 0.0
	_sequence_state = SequenceState.COOLDOWN
	_state_time = 0.0
	_cooldown_remaining = maxf(_cooldown_remaining, universal_stagger_duration)
	velocity = Vector2.ZERO


func _tick_sequence_cut_spawns(delta: float) -> void:
	if _pending_sequence_cut_indices.is_empty():
		_sequence_state = SequenceState.EXECUTE_CUTS
		_state_time = 0.0
		return
	_sequence_spawn_timer = maxf(0.0, _sequence_spawn_timer - delta)
	if _sequence_spawn_timer > 0.0:
		return
	var cut_index := int(_pending_sequence_cut_indices.pop_front())
	var config := _build_sequence_cut_config(cut_index)
	if config.is_empty():
		_sequence_state = SequenceState.EXECUTE_CUTS
		_state_time = 0.0
		return
	_add_cut_hazard(config)
	_sequence_spawn_timer = sequence_spawn_interval
	if _pending_sequence_cut_indices.is_empty():
		_sequence_state = SequenceState.EXECUTE_CUTS
		_state_time = 0.0


func _spawn_death_burst_cuts() -> void:
	var step := TAU / float(maxi(1, death_burst_cut_count))
	for index in range(death_burst_cut_count):
		var angle := step * float(index)
		var direction := Vector2(sin(angle), cos(angle))
		var config := {
			"id": _consume_hazard_id(),
			"s": global_position,
			"e": global_position + direction * death_burst_radius,
			"fw": death_burst_full_half_width,
			"rw": death_burst_full_half_width,
			"tw": maxf(telegraph_line_half_width, death_burst_full_half_width * 0.8),
			"td": death_burst_telegraph_duration,
			"el": 0.0,
			"fd": cut_damage,
			"rd": cut_damage,
			"dl": "razorform_death_cut",
			"gy": telegraph_ground_y,
			"bl": true,
			"gs": 0.5,
			"ai": _consume_edge_attack_instance_id(),
			"oc": death_burst_outline_color,
			"fc": death_burst_fill_color,
		}
		_add_cut_hazard(config)


func _choose_sequence_cut_count() -> int:
	if _target_player == null or not is_instance_valid(_target_player):
		return 1
	var player_velocity := _player_velocity(_target_player)
	var count := 2
	if player_velocity.length() > 5.0:
		count += 1
	return clampi(count, 1, max_sequence_cuts)


func _build_sequence_cut_config(index: int) -> Dictionary:
	if _target_player == null or not is_instance_valid(_target_player):
		return {}
	var player_velocity := _player_velocity(_target_player)
	var anchor := _target_player.global_position
	if player_velocity.length_squared() > 0.001:
		anchor += player_velocity.normalized() * minf(player_velocity.length() * 0.18, 1.8)
	var base_dir := player_velocity.normalized() if player_velocity.length_squared() > 0.001 else _planar_facing
	if base_dir.length_squared() <= 0.0001:
		base_dir = Vector2(0.0, -1.0)
	var angle_offsets := [0.0, 55.0, -55.0]
	var center_offsets := [0.0, -1.35, 1.35]
	var slot := clampi(index, 0, angle_offsets.size() - 1)
	var direction := base_dir.rotated(deg_to_rad(float(angle_offsets[slot])))
	var perpendicular := Vector2(-direction.y, direction.x)
	var center := anchor + perpendicular * float(center_offsets[slot])
	return {
		"id": _consume_hazard_id(),
		"s": center - direction * cut_line_half_length,
		"e": center + direction * cut_line_half_length,
		"fw": cut_full_half_width,
		"rw": cut_full_half_width,
		"tw": telegraph_line_half_width,
		"td": sequence_telegraph_duration,
		"el": 0.0,
		"fd": cut_damage,
		"rd": cut_damage,
		"dl": "razorform_cut",
		"gy": telegraph_ground_y,
		"bl": true,
		"gs": 0.5,
		"ai": _consume_edge_attack_instance_id(),
	}


func _add_cut_hazard(config: Dictionary) -> void:
	var hazard = EdgeCutLineHazardScript.new()
	hazard.bind_visual(_vw, telegraph_outline_color, telegraph_fill_color, telegraph_progress_steps)
	hazard.configure_from_dict(config)
	hazard.update_visual()
	_cut_hazards_by_id[hazard.hazard_id] = hazard


func _apply_remote_cut_snapshots(snapshots: Array) -> void:
	var seen_ids: Dictionary = {}
	for snapshot_v in snapshots:
		if snapshot_v is not Dictionary:
			continue
		var snapshot: Dictionary = snapshot_v
		var hazard_id := int(snapshot.get("id", 0))
		if hazard_id <= 0:
			continue
		seen_ids[hazard_id] = true
		var hazard = _cut_hazards_by_id.get(hazard_id, null)
		if hazard == null:
			hazard = EdgeCutLineHazardScript.new()
			hazard.bind_visual(_vw, telegraph_outline_color, telegraph_fill_color, telegraph_progress_steps)
			_cut_hazards_by_id[hazard_id] = hazard
		hazard.configure_from_dict(snapshot)
		hazard.update_visual()
	var stale_ids: Array[int] = []
	for hazard_id in _cut_hazards_by_id.keys():
		if not seen_ids.has(hazard_id):
			var hazard = _cut_hazards_by_id[hazard_id]
			if hazard != null:
				hazard.release_visual()
			stale_ids.append(int(hazard_id))
	for hazard_id in stale_ids:
		_cut_hazards_by_id.erase(hazard_id)


func _update_remote_cut_visuals() -> void:
	for hazard in _cut_hazards_by_id.values():
		if hazard != null:
			hazard.update_visual()


func _release_all_cut_visuals() -> void:
	for hazard in _cut_hazards_by_id.values():
		if hazard != null:
			hazard.release_visual()


func _consume_hazard_id() -> int:
	var next_id := _next_hazard_id
	_next_hazard_id += 1
	return next_id


func _player_velocity(player: Node2D) -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	if player is CharacterBody2D:
		return (player as CharacterBody2D).velocity
	var velocity_v: Variant = player.get("velocity")
	if velocity_v is Vector2:
		return velocity_v as Vector2
	return Vector2.ZERO
