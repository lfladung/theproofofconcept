class_name StumblerMob
extends EnemyBase
## Mass / surface: slow straight-line approach, telegraphed stomp AoE.

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const GroundAoeTelegraphMeshScript = preload("res://scripts/visuals/ground_aoe_telegraph_mesh.gd")
const StumblerDamagePacketScript = preload("res://scripts/combat/damage_packet.gd")

enum Phase { CHASE, STOMP_WINDUP, STOMP_HIT, RECOVER }

@export var move_speed := 4.0
@export var reorient_stop_distance := 2.9
@export var turn_toward_target_deg_per_sec := 110.0
@export var turn_ready_angle_deg := 14.0
@export var reorient_delay_sec := 0.28
@export var stomp_trigger_dist := 5.0
@export var stomp_windup_sec := 1.2
@export var stomp_radius := 4.5
@export var stomp_damage := 20
@export var stomp_knockback := 14.0
@export var stomp_hitbox_duration := 0.14
@export var stomp_cooldown_sec := 1.0
@export var recover_sec := 0.45
@export var stuck_speed_threshold := 0.15
@export var stuck_time_to_retarget := 0.22
@export var target_refresh_interval := 0.35
@export var mesh_ground_y := 0.3
@export var mesh_scale := Vector3(1.65, 1.65, 1.65)
@export var stumbler_clip_scale := 1.7625
@export var telegraph_ground_y := 0.045

var _visual: Node3D
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn: bool = false
var _speed_multiplier := 1.0
var _aggro_enabled := true
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _locked_dir := Vector2(0.0, -1.0)
var _planar_facing := Vector2(0.0, -1.0)
var _stuck_accum := 0.0
var _is_reorienting := false
var _reorient_delay_remaining := 0.0
var _reorient_target_dir := Vector2(0.0, -1.0)

var _phase := Phase.CHASE
var _phase_elapsed := 0.0
var _stomp_cooldown_rem := 0.0
var _stomp_anchor := Vector2.ZERO

@onready var _stomp_hitbox: Hitbox2D = $StompHitbox
@onready var _stomp_shape_node: CollisionShape2D = $StompHitbox/CollisionShape2D


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
		_phase = Phase.CHASE
		_phase_elapsed = 0.0


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Stumbler entered tree without configure_spawn; removing.")
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
		vis.name = &"StumblerVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_create_telegraph_mesh(vw)
		_sync_visual_from_body()
	if _has_spawn:
		set_deferred(&"collision_layer", 2)
		set_deferred(&"collision_mask", 7)
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0
	_refresh_stomp_hitbox_shape()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Stumbler.glb")
	var scale_v: Variant = stumbler_clip_scale
	return {
		&"idle": {
			"scene": scene,
			"scene_scale": scale_v,
			"clip_hint": "",
			"keywords": [],
		},
		&"walk": {
			"scene": scene,
			"scene_scale": scale_v,
			"clip_hint": "",
			"keywords": [],
		},
	}


func _refresh_stomp_hitbox_shape() -> void:
	if _stomp_shape_node != null and _stomp_shape_node.shape is CircleShape2D:
		(_stomp_shape_node.shape as CircleShape2D).radius = stomp_radius


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_stomp_telegraph_visual()
		_sync_visual_from_body()
		return
	surge_infusion_tick_server_field_decay()
	_stomp_cooldown_rem = maxf(0.0, _stomp_cooldown_rem - delta)
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		move_and_slide_with_mob_separation()
		_enemy_network_server_broadcast(delta)
		_update_stomp_telegraph_visual()
		_sync_visual_from_body()
		return
	_refresh_target_player(delta)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()
	match _phase:
		Phase.CHASE:
			_tick_chase(delta)
		Phase.STOMP_WINDUP:
			_tick_stomp_windup(delta)
		Phase.STOMP_HIT:
			_tick_stomp_hit()
		Phase.RECOVER:
			_tick_recover(delta)
	apply_hit_knockback_to_body_velocity()
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	if _phase == Phase.CHASE:
		var to_player := (
			_target_player.global_position - global_position
			if _target_player != null and is_instance_valid(_target_player)
			else Vector2.ZERO
		)
		if _hit_non_player_wall_this_frame():
			_reset_after_wall_hit(to_player)
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_update_stomp_telegraph_visual()
	_sync_visual_from_body()


func _tick_chase(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	var to_p := _target_player.global_position - global_position
	var dist := to_p.length()
	if (
		dist <= stomp_trigger_dist
		and _stomp_cooldown_rem <= 0.0
		and to_p.length_squared() > 0.0001
	):
		_phase = Phase.STOMP_WINDUP
		_phase_elapsed = 0.0
		_stomp_anchor = global_position
		_locked_dir = to_p.normalized()
		_planar_facing = _locked_dir
		velocity = Vector2.ZERO
		return
	if _is_reorienting:
		_update_reorientation(delta, to_p, dist)
		return
	if dist <= reorient_stop_distance:
		_begin_reorientation(to_p)
		_update_reorientation(delta, to_p, dist)
		return
	var sp := move_speed * _speed_multiplier * surge_infusion_field_move_speed_factor()
	velocity = _locked_dir * sp
	_planar_facing = _locked_dir
	var spd := velocity.length()
	if spd < stuck_speed_threshold:
		_stuck_accum += delta
		if _stuck_accum >= stuck_time_to_retarget:
			_stuck_accum = 0.0
			_begin_reorientation(to_p)
	else:
		_stuck_accum = 0.0


func _update_reorientation(delta: float, to_player: Vector2, _player_distance: float) -> void:
	velocity = Vector2.ZERO
	_reorient_delay_remaining = maxf(0.0, _reorient_delay_remaining - delta)
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
	if facing_ready and _reorient_delay_remaining <= 0.0:
		_locked_dir = _planar_facing.normalized()
		_is_reorienting = false


func _begin_reorientation(target_dir: Vector2 = Vector2.ZERO) -> void:
	_is_reorienting = true
	_reorient_delay_remaining = reorient_delay_sec
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


func _tick_stomp_windup(delta: float) -> void:
	global_position = _stomp_anchor
	velocity = Vector2.ZERO
	if _target_player != null and is_instance_valid(_target_player):
		var to_p := _target_player.global_position - global_position
		if to_p.length_squared() > 0.0001:
			_planar_facing = to_p.normalized()
	_phase_elapsed += delta
	if _phase_elapsed >= stomp_windup_sec:
		_phase = Phase.STOMP_HIT
		_phase_elapsed = 0.0


func _tick_stomp_hit() -> void:
	_activate_stomp_hitbox()
	_phase = Phase.RECOVER
	_phase_elapsed = 0.0
	_stomp_cooldown_rem = stomp_cooldown_sec
	velocity = Vector2.ZERO


func _tick_recover(delta: float) -> void:
	global_position = _stomp_anchor
	velocity = Vector2.ZERO
	_phase_elapsed += delta
	if _phase_elapsed >= recover_sec:
		_phase = Phase.CHASE
		_phase_elapsed = 0.0


func _activate_stomp_hitbox() -> void:
	if _stomp_hitbox == null or not is_damage_authority():
		return
	var packet := StumblerDamagePacketScript.new() as DamagePacket
	packet.amount = stomp_damage
	packet.kind = &"stomp"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = global_position
	packet.direction = _planar_facing
	packet.knockback = stomp_knockback
	packet.apply_iframes = true
	packet.blockable = false
	packet.debug_label = &"stumbler_stomp"
	_stomp_hitbox.activate(packet, stomp_hitbox_duration)


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ph": _phase,
		"pe": _phase_elapsed,
		"pf": _planar_facing,
		"ld": _locked_dir,
		"ro": _is_reorienting,
		"rd": _reorient_delay_remaining,
		"rt": _reorient_target_dir,
		"sa": _stomp_anchor,
		"cd": _stomp_cooldown_rem,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_phase = int(state.get("ph", _phase)) as Phase
	_phase_elapsed = maxf(0.0, float(state.get("pe", 0.0)))
	_is_reorienting = bool(state.get("ro", _is_reorienting))
	_reorient_delay_remaining = maxf(0.0, float(state.get("rd", _reorient_delay_remaining)))
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()
	var ld_v: Variant = state.get("ld", _locked_dir)
	if ld_v is Vector2:
		var ld := ld_v as Vector2
		if ld.length_squared() > 0.0001:
			_locked_dir = ld.normalized()
	var rt_v: Variant = state.get("rt", _reorient_target_dir)
	if rt_v is Vector2:
		var rt := rt_v as Vector2
		if rt.length_squared() > 0.0001:
			_reorient_target_dir = rt.normalized()
	var sa_v: Variant = state.get("sa", _stomp_anchor)
	if sa_v is Vector2:
		_stomp_anchor = sa_v as Vector2
	_stomp_cooldown_rem = maxf(0.0, float(state.get("cd", 0.0)))


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	var shake_progress := _stomp_telegraph_progress() if _phase == Phase.STOMP_WINDUP else 0.0
	_visual.set_attack_shake_progress(shake_progress)
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	var moving := _phase == Phase.CHASE and velocity.length_squared() > 0.04
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _planar_facing)


func _should_use_high_detail_visuals() -> bool:
	if _phase != Phase.CHASE:
		return true
	if _target_player != null and is_instance_valid(_target_player):
		return global_position.distance_squared_to(_target_player.global_position) <= 24.0 * 24.0
	return velocity.length_squared() > 0.04


func _refresh_target_player(delta: float) -> void:
	_target_refresh_time_remaining = maxf(0.0, _target_refresh_time_remaining - delta)
	if (
		_target_player == null
		or not is_instance_valid(_target_player)
		or _target_refresh_time_remaining <= 0.0
	):
		_target_player = _pick_nearest_player_target()
		_target_refresh_time_remaining = maxf(0.05, target_refresh_interval)


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
		if collider is Node and (collider as Node).is_in_group(&"player"):
			continue
		if collider is Node and (collider as Node).is_in_group(&"mob"):
			continue
		return true
	return false


func _reset_after_wall_hit(to_player: Vector2) -> void:
	velocity = Vector2.ZERO
	_stuck_accum = 0.0
	var reset_dir := (
		to_player.normalized()
		if to_player.length_squared() > 0.0001
		else (_planar_facing.normalized() if _planar_facing.length_squared() > 0.0001 else Vector2(0.0, -1.0))
	)
	_reorient_target_dir = reset_dir
	_begin_reorientation(reset_dir)


func _create_telegraph_mesh(parent: Node3D) -> void:
	_telegraph_mesh = MeshInstance3D.new()
	_telegraph_mesh.name = &"StumblerTelegraph"
	_outline_mat = GroundAoeTelegraphMeshScript.create_outline_material(Color(0.0, 0.0, 0.0, 1.0))
	_fill_mat = GroundAoeTelegraphMeshScript.create_fill_material(Color(0.48, 0.34, 0.18, 0.78))
	_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_mesh.visible = false
	parent.add_child(_telegraph_mesh)


func _stomp_telegraph_progress() -> float:
	if _phase != Phase.STOMP_WINDUP:
		return 0.0
	return clampf(_phase_elapsed / maxf(0.01, stomp_windup_sec), 0.0, 1.0)


func _update_stomp_telegraph_visual() -> void:
	if _telegraph_mesh == null:
		return
	var active := _phase == Phase.STOMP_WINDUP
	if not active:
		_telegraph_mesh.visible = false
		return
	var p := _stomp_telegraph_progress()
	_telegraph_mesh.visible = true
	_telegraph_mesh.global_position = Vector3(_stomp_anchor.x, telegraph_ground_y, _stomp_anchor.y)
	_telegraph_mesh.rotation = Vector3.ZERO
	_telegraph_mesh.mesh = GroundAoeTelegraphMeshScript.build_crack_ring_mesh(
		p,
		stomp_radius,
		28,
		_outline_mat,
		_fill_mat
	)
