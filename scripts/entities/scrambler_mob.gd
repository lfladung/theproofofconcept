class_name ScramblerMob
extends EnemyBase
## Rush surface: straight-line rush, weak stuck recovery, body contact damage (no dash).

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")

@export var move_speed := 9.8
@export var stop_distance := 1.48
@export var reengage_distance := 1.8
@export var turn_toward_target_deg_per_sec := 165.0
@export var turn_ready_angle_deg := 16.0
@export var recommit_delay_sec := 0.28
@export var recommit_charge_time_sec := 0.45
@export var stuck_speed_threshold := 0.18
@export var stuck_time_to_retarget := 0.22
## Only treat wall contact as a reset when Scrambler is actively pushing into the blocker.
@export var wall_hit_reset_min_speed := 0.12
@export var wall_hit_push_into_dot := 0.12
@export var contact_damage := 8
@export var contact_repeat_sec := 0.5
@export_range(0.0, 1.0, 0.05) var guard_stamina_split_ratio := 0.5
@export var target_refresh_interval := 0.35
@export var mesh_ground_y := 0.16
@export var mesh_scale := Vector3(1.48, 1.48, 1.48)
@export var scrambler_clip_scale := 2.0

var _visual: Node3D
var _vw: Node3D
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn: bool = false
var _speed_multiplier := 1.0
var _aggro_enabled := true
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _locked_dir := Vector2(0.0, -1.0)
var _stuck_accum := 0.0
var _planar_facing := Vector2(0.0, -1.0)
var _is_reorienting := false
var _recommit_delay_remaining := 0.0
var _charge_commit_remaining := 0.0
var _reorient_target_dir := Vector2(0.0, -1.0)

@onready var _body_contact_hitbox: Hitbox2D = $BodyContactHitbox


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		if _body_contact_hitbox != null:
			_body_contact_hitbox.deactivate()


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Scrambler entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	var to_p := _spawn_target - _spawn_start
	_locked_dir = to_p.normalized() if to_p.length_squared() > 0.01 else Vector2(0.0, -1.0)
	_planar_facing = _locked_dir
	_reorient_target_dir = _locked_dir
	velocity = _locked_dir * move_speed * _speed_multiplier
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"ScramblerVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_sync_visual_from_body()
	_activate_contact_hitbox()
	if _has_spawn:
		set_deferred(&"collision_layer", 2)
		set_deferred(&"collision_mask", 4)
	ignore_player_body_collisions()
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Scrambler.glb")
	return build_single_scene_visual_state_config(scene, scrambler_clip_scale)


func _activate_contact_hitbox() -> void:
	if _body_contact_hitbox == null or not is_damage_authority():
		return
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.amount = contact_damage
	pkt.kind = &"contact"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = global_position
	pkt.direction = _locked_dir
	pkt.knockback = 0.0
	pkt.apply_iframes = true
	pkt.blockable = true
	pkt.guard_stamina_split_ratio = guard_stamina_split_ratio
	pkt.debug_label = &"scrambler_contact"
	_body_contact_hitbox.repeat_mode = Hitbox2D.RepeatMode.INTERVAL
	_body_contact_hitbox.repeat_interval_sec = contact_repeat_sec
	_body_contact_hitbox.activate(pkt, -1.0)


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual_from_body()
		return
	surge_infusion_tick_server_field_decay()
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		move_and_slide_with_mob_separation()
		_enemy_network_server_broadcast(delta)
		_sync_visual_from_body()
		return
	_refresh_target_player(delta)
	ignore_player_body_collisions()
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		move_and_slide_with_mob_separation()
		_enemy_network_server_broadcast(delta)
		_sync_visual_from_body()
		return
	var to_player := _target_player.global_position - global_position
	var player_distance := to_player.length()
	_charge_commit_remaining = maxf(0.0, _charge_commit_remaining - delta)
	if _is_reorienting:
		_update_reorientation(delta, to_player, player_distance)
	else:
		_update_direct_rush(delta, to_player, player_distance)
	var vel_before_slide := velocity
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	var hit_wall := _hit_non_player_wall_this_frame()
	var should_wall_reset := _should_reset_after_wall_hit(vel_before_slide)
	if hit_wall and should_wall_reset:
		_reset_after_wall_hit(to_player)
	elif _charge_commit_remaining <= 0.0 and not _is_reorienting:
		var slide_redirect_dir := _slide_reorientation_direction()
		if slide_redirect_dir.length_squared() > 0.0001:
			_begin_reorientation(slide_redirect_dir)
	if (
		not hit_wall
		and _charge_commit_remaining <= 0.0
		and not _is_reorienting
		and velocity.length() < stuck_speed_threshold
	):
		_stuck_accum += delta
		if _stuck_accum >= stuck_time_to_retarget:
			_stuck_accum = 0.0
			var retarget_dir := (
				to_player.normalized() if to_player.length_squared() > 0.0001 else _planar_facing
			)
			_begin_reorientation(retarget_dir)
	else:
		_stuck_accum = 0.0
	_refresh_contact_hitbox_packet()
	_enemy_network_server_broadcast(delta)
	_sync_visual_from_body()


func _update_direct_rush(delta: float, to_player: Vector2, player_distance: float) -> void:
	if _charge_commit_remaining <= 0.0 and player_distance <= stop_distance:
		_begin_nearest_target_reorientation()
		to_player = _target_player.global_position - global_position if _target_player != null and is_instance_valid(_target_player) else to_player
		player_distance = to_player.length()
		_update_reorientation(delta, to_player, player_distance)
		return
	if _charge_commit_remaining <= 0.0 and _should_reengage_after_passing_target(to_player, player_distance):
		_begin_nearest_target_reorientation()
		to_player = _target_player.global_position - global_position if _target_player != null and is_instance_valid(_target_player) else to_player
		player_distance = to_player.length()
		_update_reorientation(delta, to_player, player_distance)
		return
	var sp := move_speed * _speed_multiplier * surge_infusion_field_move_speed_factor()
	velocity = _locked_dir * sp
	_planar_facing = _locked_dir


func _update_reorientation(delta: float, to_player: Vector2, player_distance: float) -> void:
	velocity = Vector2.ZERO
	_recommit_delay_remaining = maxf(0.0, _recommit_delay_remaining - delta)
	if to_player.length_squared() > 0.0001:
		_reorient_target_dir = to_player.normalized()
	if _reorient_target_dir.length_squared() > 0.0001:
		var max_step := deg_to_rad(turn_toward_target_deg_per_sec) * delta
		_planar_facing = EnemyBase.step_planar_facing_toward(
			_planar_facing,
			_reorient_target_dir,
			max_step
		)
	var ready_cos := cos(deg_to_rad(turn_ready_angle_deg))
	var facing_ready := (
		_reorient_target_dir.length_squared() <= 0.0001
		or _planar_facing.dot(_reorient_target_dir.normalized()) >= ready_cos
	)
	if facing_ready and _recommit_delay_remaining <= 0.0:
		_locked_dir = _planar_facing.normalized()
		_is_reorienting = false
		_charge_commit_remaining = recommit_charge_time_sec


func _begin_reorientation(target_dir: Vector2 = Vector2.ZERO) -> void:
	_is_reorienting = true
	_recommit_delay_remaining = recommit_delay_sec
	_charge_commit_remaining = 0.0
	if target_dir.length_squared() > 0.0001:
		_reorient_target_dir = target_dir.normalized()
	elif _target_player != null and is_instance_valid(_target_player):
		var to_player := _target_player.global_position - global_position
		_reorient_target_dir = (
			to_player.normalized() if to_player.length_squared() > 0.0001 else _planar_facing
		)
	else:
		_reorient_target_dir = _planar_facing
	velocity = Vector2.ZERO


func _begin_nearest_target_reorientation() -> void:
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = maxf(0.05, target_refresh_interval)
	_begin_reorientation()


func _should_reengage_after_passing_target(to_player: Vector2, player_distance: float) -> bool:
	if reengage_distance <= stop_distance:
		return false
	if player_distance < reengage_distance:
		return false
	if to_player.length_squared() <= 0.0001:
		return false
	if _locked_dir.length_squared() <= 0.0001:
		return false
	var dir_to_player := to_player / player_distance
	return _locked_dir.normalized().dot(dir_to_player) < 0.0


func _slide_reorientation_direction() -> Vector2:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var collider: Variant = collision.get_collider()
		if collider == null:
			return _planar_facing
		if collider is Area2D:
			continue
		if collider is Node:
			var collider_node := collider as Node
			if collider_node.is_in_group(&"player") or collider_node.is_in_group(&"mob"):
				continue
		var wall_normal := collision.get_normal()
		if wall_normal.length_squared() > 0.0001:
			var tangent_a := Vector2(-wall_normal.y, wall_normal.x).normalized()
			var tangent_b := -tangent_a
			var to_player := Vector2.ZERO
			if _target_player != null and is_instance_valid(_target_player):
				to_player = _target_player.global_position - global_position
			if to_player.length_squared() > 0.0001:
				return tangent_a if tangent_a.dot(to_player) >= tangent_b.dot(to_player) else tangent_b
			return tangent_a
		return _planar_facing
	return Vector2.ZERO


func _hit_non_player_wall_this_frame() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var collider: Variant = collision.get_collider()
		if collider == null:
			return true
		if collider is Area2D:
			continue
		if collider is Node:
			var collider_node := collider as Node
			if collider_node.is_in_group(&"player") or collider_node.is_in_group(&"mob"):
				continue
		return true
	return false


func _is_blocking_wall_collision(collision: KinematicCollision2D) -> bool:
	if collision == null:
		return true
	var collider: Variant = collision.get_collider()
	if collider == null:
		return true
	if collider is Area2D:
		return false
	if collider is Node:
		var n := collider as Node
		if n.is_in_group(&"player") or n.is_in_group(&"mob"):
			return false
	return true


func _should_reset_after_wall_hit(pre_slide_vel: Vector2) -> bool:
	var spd_sq := pre_slide_vel.length_squared()
	var min_sp := wall_hit_reset_min_speed
	if spd_sq < min_sp * min_sp:
		return false
	var dir := pre_slide_vel / sqrt(spd_sq)
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		if not _is_blocking_wall_collision(collision):
			continue
		var n := collision.get_normal()
		if n.length_squared() <= 0.0001:
			continue
		n = n.normalized()
		if dir.dot(n) < -wall_hit_push_into_dot:
			return true
	return false


func _reset_after_wall_hit(to_player: Vector2) -> void:
	velocity = Vector2.ZERO
	_stuck_accum = 0.0
	_charge_commit_remaining = 0.0
	var slide_dir := _slide_reorientation_direction()
	var reset_dir := slide_dir
	if reset_dir.length_squared() <= 0.0001:
		reset_dir = (
			to_player.normalized()
			if to_player.length_squared() > 0.0001
			else (
				_planar_facing.normalized()
				if _planar_facing.length_squared() > 0.0001
				else Vector2(0.0, -1.0)
			)
		)
	_reorient_target_dir = reset_dir
	_begin_reorientation(reset_dir)


func _refresh_contact_hitbox_packet() -> void:
	if _body_contact_hitbox == null or not _body_contact_hitbox.is_active():
		return
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.amount = contact_damage
	pkt.kind = &"contact"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = global_position
	pkt.direction = _locked_dir
	pkt.knockback = 0.0
	pkt.apply_iframes = true
	pkt.blockable = true
	pkt.guard_stamina_split_ratio = guard_stamina_split_ratio
	pkt.debug_label = &"scrambler_contact"
	_body_contact_hitbox.update_packet_template(pkt)


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ld": _locked_dir,
		"pf": _planar_facing,
		"ro": _is_reorienting,
		"rd": _recommit_delay_remaining,
		"cc": _charge_commit_remaining,
		"rt": _reorient_target_dir,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_is_reorienting = bool(state.get("ro", _is_reorienting))
	_recommit_delay_remaining = maxf(0.0, float(state.get("rd", _recommit_delay_remaining)))
	_charge_commit_remaining = maxf(0.0, float(state.get("cc", _charge_commit_remaining)))
	var rt_v: Variant = state.get("rt", _reorient_target_dir)
	if rt_v is Vector2:
		var rt := rt_v as Vector2
		if rt.length_squared() > 0.0001:
			_reorient_target_dir = rt.normalized()
	var ld_v: Variant = state.get("ld", _locked_dir)
	if ld_v is Vector2:
		var ld := ld_v as Vector2
		if ld.length_squared() > 0.0001:
			_locked_dir = ld.normalized()
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	var moving := velocity.length_squared() > 0.04
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _planar_facing)


func _should_use_high_detail_visuals() -> bool:
	if _target_player != null and is_instance_valid(_target_player):
		return global_position.distance_squared_to(_target_player.global_position) <= 22.0 * 22.0
	return velocity.length_squared() > 0.04


func _refresh_target_player(delta: float) -> void:
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(
		refresh.get("refresh_time_remaining", _target_refresh_time_remaining)
	)


func take_hit(
	damage: int,
	knockback_dir: Vector2,
	knockback_strength: float,
	from_backstab: bool = false,
	is_critical: bool = false
) -> void:
	if damage <= 0:
		return
	super.take_hit(damage, knockback_dir, knockback_strength, from_backstab, is_critical)
