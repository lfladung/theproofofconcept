class_name LurkerMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
enum PhaseState { PHASED_IDLE, TELEGRAPHING, ATTACK, RECOVER }

@export var idle_interval_min := 2.2
@export var idle_interval_max := 3.4
@export var telegraph_duration := 0.7
@export var attack_active_duration := 0.4
@export var recover_duration := 0.42
@export var ambush_distance_min := 3.5
@export var ambush_distance_max := 5.25
@export var ambush_anchor_repick_distance := 6.0
@export var attack_damage := 15
@export var attack_knockback := 10.0
@export var attack_hit_width := 1.35
@export var attack_reach_padding := 0.85
@export var attack_reach_min := 1.4
@export var attack_reach_max := 6.5
@export var phased_move_speed := 5.8
@export var telegraph_ready_distance := 0.9
@export var materialize_distance := 5.8
@export var mesh_ground_y := 0.12
@export var mesh_scale := Vector3.ONE
@export var edge_clip_scale := 2.4
@export var target_refresh_interval := 0.3
@export_range(0.0, 1.0, 0.05) var phased_transparency := 0.62
@export_range(0.0, 1.0, 0.05) var materialized_transparency := 0.0

var _visual: Node3D
var _vw: Node3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _phase := PhaseState.PHASED_IDLE
var _phase_time_remaining := 0.0
var _telegraph_anchor := Vector2.ZERO
var _attack_facing := Vector2(0.0, -1.0)
var _attack_reach := 1.4
var _distance_to_target := INF
var _is_materialized := false
var _has_ambush_anchor := false
var _room_queries: Node
@onready var _attack_hitbox: Hitbox2D = $DashContactHitbox


func get_shadow_visual_root() -> Node3D:
	return _visual


func get_combat_planar_facing() -> Vector2:
	if _attack_facing.length_squared() > 1e-6:
		return _attack_facing.normalized()
	return super.get_combat_planar_facing()


func _ready() -> void:
	super._ready()
	_vw = get_node_or_null("../../VisualWorld3D") as Node3D
	if _vw != null:
		var vis := EnemyStateVisualScript.new()
		vis.name = &"LurkerVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		_vw.add_child(vis)
		_visual = vis
	if _attack_hitbox != null:
		_attack_hitbox.deactivate()
	_enter_phased_idle(true)


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_visuals()
		return
	_tick_server_state(delta)
	_enemy_network_server_broadcast(delta)
	_update_visuals()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ph": _phase,
		"tr": maxf(0.0, _phase_time_remaining),
		"ta": _telegraph_anchor,
		"af": _attack_facing,
		"td": _distance_to_target,
		"mat": 1 if _is_materialized else 0,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_phase = int(state.get("ph", _phase)) as PhaseState
	_phase_time_remaining = maxf(0.0, float(state.get("tr", _phase_time_remaining)))
	var anchor_v: Variant = state.get("ta", _telegraph_anchor)
	if anchor_v is Vector2:
		_telegraph_anchor = anchor_v as Vector2
	var facing_v: Variant = state.get("af", _attack_facing)
	if facing_v is Vector2:
		var facing := facing_v as Vector2
		if facing.length_squared() > 1e-6:
			_attack_facing = facing.normalized()
	_distance_to_target = float(state.get("td", _distance_to_target))
	_is_materialized = bool(int(state.get("mat", 0)))
	_apply_phase_collision_state()


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, hurtbox_area: Area2D) -> void:
	super._on_receiver_damage_applied(packet, hp_damage, hurtbox_area)
	if hp_damage <= 0 or not is_damage_authority():
		return
	if _phase == PhaseState.RECOVER:
		_force_phase_out_and_relocate()


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Lurker.glb")
	return build_single_scene_visual_state_config(scene, edge_clip_scale)


func _tick_server_state(delta: float) -> void:
	_phase_time_remaining = maxf(0.0, _phase_time_remaining - delta)
	if apply_universal_stagger_stop(delta, true):
		if _attack_hitbox != null:
			_attack_hitbox.deactivate()
		move_and_slide_with_mob_separation()
		return
	match _phase:
		PhaseState.PHASED_IDLE:
			_tick_phased_idle(delta)
		PhaseState.TELEGRAPHING:
			velocity = Vector2.ZERO
			if _phase_time_remaining <= 0.0:
				_start_attack()
		PhaseState.ATTACK:
			velocity = Vector2.ZERO
			if _phase_time_remaining <= 0.0:
				_start_recover()
		PhaseState.RECOVER:
			_tick_recover(delta)
	move_and_slide_with_mob_separation()


func cancel_active_attack_for_stagger() -> void:
	if _attack_hitbox != null:
		_attack_hitbox.deactivate()
	if _phase == PhaseState.TELEGRAPHING or _phase == PhaseState.ATTACK:
		_phase = PhaseState.RECOVER
		_phase_time_remaining = universal_stagger_duration
		_is_materialized = true
		_apply_phase_collision_state()
	velocity = Vector2.ZERO


func _tick_phased_idle(_delta: float) -> void:
	_target_refresh_time_remaining = maxf(0.0, _target_refresh_time_remaining - _delta)
	var previous_target := _target_player
	_target_player = _refresh_phase_target()
	if previous_target != _target_player:
		_has_ambush_anchor = false
	if _target_player == null or not is_instance_valid(_target_player):
		_distance_to_target = INF
		_is_materialized = false
		_has_ambush_anchor = false
		_apply_phase_collision_state()
		velocity = Vector2.ZERO
		return
	_distance_to_target = global_position.distance_to(_target_player.global_position)
	_is_materialized = _distance_to_target <= materialize_distance
	_apply_phase_collision_state()
	if (
		not _has_ambush_anchor
		or _telegraph_anchor.distance_to(_target_player.global_position) > ambush_anchor_repick_distance
	):
		_telegraph_anchor = _pick_ambush_position(_target_player)
		_has_ambush_anchor = true
	var to_anchor := _telegraph_anchor - global_position
	if to_anchor.length_squared() > 0.0001:
		velocity = to_anchor.normalized() * phased_move_speed
		_attack_facing = velocity.normalized()
	else:
		velocity = Vector2.ZERO
	var to_target := _target_player.global_position - global_position
	if to_target.length_squared() > 0.0001:
		_attack_facing = to_target.normalized()
	if (
		_phase_time_remaining <= 0.0
		and global_position.distance_to(_telegraph_anchor) <= telegraph_ready_distance
	):
		_start_telegraph()


func _tick_recover(_delta: float) -> void:
	velocity = Vector2.ZERO
	if _phase_time_remaining <= 0.0:
		_enter_phased_idle()


func _start_telegraph() -> void:
	velocity = Vector2.ZERO
	_telegraph_anchor = global_position
	_has_ambush_anchor = false
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - _telegraph_anchor
		if to_target.length_squared() > 1e-6:
			_attack_facing = to_target.normalized()
	_phase = PhaseState.TELEGRAPHING
	_phase_time_remaining = telegraph_duration
	_is_materialized = true
	_apply_phase_collision_state()


func _start_attack() -> void:
	_refresh_attack_hitbox_geometry()
	var packet := _build_damage_packet(
		attack_damage,
		&"lurker_swipe",
		global_position,
		_attack_facing,
		attack_knockback,
		true
	)
	if _attack_hitbox != null:
		_attack_hitbox.activate(packet, attack_active_duration)
	_phase = PhaseState.ATTACK
	_phase_time_remaining = attack_active_duration
	_is_materialized = true
	_apply_phase_collision_state()


func _refresh_attack_hitbox_geometry() -> void:
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 1e-6:
			_attack_facing = to_target.normalized()
			_distance_to_target = to_target.length()
	var dir := _attack_facing.normalized() if _attack_facing.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	_attack_reach = clampf(
		_distance_to_target + attack_reach_padding,
		attack_reach_min,
		attack_reach_max
	)
	if _attack_hitbox == null:
		return
	_attack_hitbox.position = dir * (_attack_reach * 0.5)
	_attack_hitbox.rotation = dir.angle() + PI * 0.5
	_attack_hitbox.repeat_mode = Hitbox2D.RepeatMode.NONE
	var shape_node := _attack_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return
	if shape_node.shape is RectangleShape2D:
		var rect := shape_node.shape as RectangleShape2D
		rect.size = Vector2(maxf(0.2, attack_hit_width), _attack_reach)


func _start_recover() -> void:
	if _attack_hitbox != null:
		_attack_hitbox.deactivate()
	_phase = PhaseState.RECOVER
	_phase_time_remaining = recover_duration
	_is_materialized = true
	_apply_phase_collision_state()
	velocity = Vector2.ZERO


func _enter_phased_idle(initial: bool = false) -> void:
	if _attack_hitbox != null:
		_attack_hitbox.deactivate()
	_phase = PhaseState.PHASED_IDLE
	_has_ambush_anchor = false
	_phase_time_remaining = randf_range(idle_interval_min, idle_interval_max)
	if initial:
		_phase_time_remaining = randf_range(idle_interval_min * 0.4, idle_interval_max)
	_is_materialized = false
	_apply_phase_collision_state()


func _force_phase_out_and_relocate() -> void:
	if _attack_hitbox != null:
		_attack_hitbox.deactivate()
	_phase = PhaseState.PHASED_IDLE
	_has_ambush_anchor = false
	_phase_time_remaining = randf_range(idle_interval_min * 0.5, idle_interval_min)
	_is_materialized = false
	_apply_phase_collision_state()
	return


func _refresh_phase_target() -> Node2D:
	var refresh: Dictionary = refresh_enemy_target_player(
		0.0,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		false
	)
	_target_player = refresh.get("target", null) as Node2D
	_target_refresh_time_remaining = float(refresh.get("refresh_time_remaining", 0.0))
	return _target_player


func _pick_ambush_position(player: Node2D) -> Vector2:
	if player == null:
		return global_position
	var facing := Vector2(0.0, -1.0)
	if player.has_method(&"get_combat_planar_facing"):
		var facing_v: Variant = player.call(&"get_combat_planar_facing")
		if facing_v is Vector2 and (facing_v as Vector2).length_squared() > 1e-6:
			facing = (facing_v as Vector2).normalized()
	var side := 1.0 if randf() < 0.5 else -1.0
	var lateral := Vector2(-facing.y, facing.x) * side
	var offset := (
		(-facing * randf_range(ambush_distance_min, ambush_distance_max))
		+ lateral * randf_range(0.9, 1.6)
	)
	var anchor := player.global_position + offset
	var away := anchor - player.global_position
	if away.length_squared() > 0.0001 and away.normalized().dot(facing) > 0.45:
		anchor = player.global_position - facing * randf_range(ambush_distance_min, ambush_distance_max)
	return _clamp_point_to_current_room(anchor)


func _clamp_point_to_current_room(point: Vector2) -> Vector2:
	var room_queries := _resolve_room_queries()
	if room_queries == null:
		return point
	var room_name := ""
	if _target_player != null and is_instance_valid(_target_player):
		room_name = String(room_queries.call("room_name_at", _target_player.global_position, 0.5))
	if room_name.is_empty():
		room_name = String(room_queries.call("room_name_at", global_position, 0.5))
	if room_name.is_empty():
		return point
	var room: Variant = room_queries.call("room_by_name", StringName(room_name))
	if room == null:
		return point
	var rect_v: Variant = room_queries.call("room_bounds_rect", room)
	if rect_v is not Rect2:
		return point
	var rect := (rect_v as Rect2).grow(-1.2)
	if rect.size.x <= 0.5 or rect.size.y <= 0.5:
		rect = rect_v as Rect2
	return Vector2(
		clampf(point.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(point.y, rect.position.y, rect.position.y + rect.size.y)
	)


func _resolve_room_queries() -> Node:
	if _room_queries != null and is_instance_valid(_room_queries):
		return _room_queries
	var cursor: Node = self
	while cursor != null:
		var found := cursor.get_node_or_null("RoomQueryService")
		if found != null:
			_room_queries = found
			return _room_queries
		cursor = cursor.get_parent()
	return null


func _apply_phase_collision_state() -> void:
	if _hurtbox != null:
		_hurtbox.set_active(not _is_phased_out() and is_damage_authority())


func _update_visuals() -> void:
	if _visual == null:
		return
	_visual.visible = true
	_visual.set_mesh_transparency(_resolve_visual_transparency())
	_visual.set_state(&"idle")
	_visual.set_attack_shake_progress(_resolve_attack_shake_progress())
	_visual.sync_from_2d(global_position, _attack_facing)


func _resolve_visual_transparency() -> float:
	if _is_phased_out():
		return phased_transparency
	return materialized_transparency


func _resolve_attack_shake_progress() -> float:
	if _phase != PhaseState.TELEGRAPHING:
		return 0.0
	return 1.0 - (_phase_time_remaining / maxf(0.01, telegraph_duration))


func _is_phased_out() -> bool:
	if _phase == PhaseState.PHASED_IDLE:
		return not _is_materialized
	return false
