class_name DasherMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const FlowTelegraphArrowMeshScript = preload("res://scripts/entities/flow_telegraph_arrow_mesh.gd")
const DASHER_VISUAL_SCENE := preload("res://art/characters/enemies/Dasher.glb")
const _TELEGRAPH_PROGRESS_STEPS := 12

enum AttackPhase { CHASE, TELEGRAPH, DASH, RECOVERY, STUN }

@export var min_speed := 10.0
@export var max_speed := 18.0
## Feet-to-ground mob; stomp when player.height exceeds this while falling.
@export var stomp_top_height := 1.02
@export var stop_distance := 1.2
@export var repath_interval := 0.2
@export var speed_scale := 0.75
@export var attack_trigger_distance_multiplier := 1.0
@export var telegraph_duration := 1.0
@export var dash_range := 7.0
@export var dash_speed := 28.0
@export var dash_pass_through_distance := 1.25
@export var dash_hit_width := 1.8
@export var dash_damage := 25
@export var dash_recovery_duration := 0.3
@export_range(0.0, 1.0, 0.05) var guard_stamina_split_ratio := 0.5
@export var arrow_ground_y := 0.06
@export var arrow_length := 7.8
@export var arrow_head_length := 0.8
@export var arrow_half_width := 0.32
@export var hit_stun_duration := 0.3
@export var target_refresh_interval := 0.3
@export var mesh_ground_y := 0.24
@export var mesh_scale := Vector3(2.0, 2.0, 2.0)
## Root scale for imported `Dasher.glb` inside `EnemyStateVisual` (idle + walk use the same mesh).
@export var dasher_clip_scale: float = 2.5
## Max rotation rate when aligning to chase direction / player (lets players slip behind).
@export var turn_toward_facing_deg_per_sec := 420.0

var _squash_applied: bool = false
var _visual
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn: bool = false
var _move_speed := 12.0
var _speed_multiplier := 1.0
var _repath_time_remaining := 0.0
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _attack_phase := AttackPhase.CHASE
var _telegraph_time := 0.0
var _dash_time := 0.0
var _dash_start := Vector2.ZERO
var _dash_end := Vector2.ZERO
var _dash_target_point := Vector2.ZERO
var _dash_dir := Vector2.ZERO
var _dash_hit_applied := false
var _recovery_time_remaining := 0.0
var _stun_time_remaining := 0.0
var _aggro_enabled := true
var _telegraph_progress_step := -1
var _planar_facing := Vector2(0.0, -1.0)
var _telegraph_meshes: Array[Mesh] = []
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _dash_contact_hitbox: Hitbox2D = $DashContactHitbox


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func surge_infusion_bump_action_delay(seconds: float) -> void:
	mass_infusion_add_bonus_stun(seconds)


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		_set_attack_phase(AttackPhase.CHASE)
		_telegraph_time = 0.0
		_dash_time = 0.0
		_recovery_time_remaining = 0.0
		_stun_time_remaining = 0.0
		if _dash_contact_hitbox != null:
			_dash_contact_hitbox.deactivate()
		_sync_visual_anim_speed(0.0)


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func _ready() -> void:
	super._ready()
	# Stay off collision layers until positioned — packed scene used to spawn at (0,0) with
	# layer 2 for one tick, overlapping the player and tripping MobDetector instantly.
	if _has_spawn:
		_apply_spawn(_spawn_start, _spawn_target)
	var vw := get_node_or_null("../../VisualWorld3D")
	_vw = vw as Node3D
	if vw:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"DasherVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_sync_visual_from_body()
		_telegraph_mesh = MeshInstance3D.new()
		_telegraph_mesh.name = &"MobTelegraphArrow"
		_outline_mat = FlowTelegraphArrowMeshScript.create_outline_material()
		_fill_mat = FlowTelegraphArrowMeshScript.create_fill_material(Color(0.9, 0.08, 0.08, 0.75))
		_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_mesh.visible = false
		_telegraph_meshes.clear()
		for step in range(_TELEGRAPH_PROGRESS_STEPS + 1):
			_telegraph_meshes.append(_build_telegraph_mesh_for_step(step))
		vw.add_child(_telegraph_mesh)
	_sync_visual_anim_speed()
	_target_player = _pick_target_player()
	_target_refresh_time_remaining = 0.0
	if _nav_agent:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = stop_distance
		_nav_agent.avoidance_enabled = false
	if _has_spawn:
		set_deferred(&"collision_layer", 2)
		set_deferred(&"collision_mask", _body_collision_mask_on_spawn())
		ignore_player_body_collisions()
	else:
		push_warning("Mob entered tree without configure_spawn; removing.")
		queue_free()
	_refresh_dash_contact_hitbox()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual_from_body()
		_update_telegraph_visual()
		return
	surge_infusion_tick_server_field_decay()
	_update_attack_state(delta)
	move_and_slide_with_mob_separation()
	_handle_flow_wall_reset()
	mass_server_post_slide()
	_update_planar_facing(delta)
	_enemy_network_server_broadcast(delta)
	_sync_visual_from_body()
	_update_telegraph_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ph": _attack_phase,
		"tt": _telegraph_time,
		"td": telegraph_duration,
		"dd": _dash_dir,
		"dt": _dash_target_point,
		"de": _dash_end,
		"da": _dash_start,
		"rt": _recovery_time_remaining,
		"st": _stun_time_remaining,
		"pf": _planar_facing,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_attack_phase = int(state.get("ph", _attack_phase)) as AttackPhase
	telegraph_duration = maxf(0.01, float(state.get("td", telegraph_duration)))
	_telegraph_time = clampf(float(state.get("tt", 0.0)), 0.0, telegraph_duration)
	_recovery_time_remaining = maxf(0.0, float(state.get("rt", _recovery_time_remaining)))
	_stun_time_remaining = maxf(0.0, float(state.get("st", _stun_time_remaining)))
	var dash_dir_v: Variant = state.get("dd", _dash_dir)
	if dash_dir_v is Vector2:
		var dash_dir := dash_dir_v as Vector2
		if dash_dir.length_squared() > 0.0001:
			_dash_dir = dash_dir.normalized()
	var dash_target_v: Variant = state.get("dt", _dash_target_point)
	if dash_target_v is Vector2:
		_dash_target_point = dash_target_v as Vector2
	var dash_end_v: Variant = state.get("de", _dash_end)
	if dash_end_v is Vector2:
		_dash_end = dash_end_v as Vector2
	var dash_start_v: Variant = state.get("da", _dash_start)
	if dash_start_v is Vector2:
		_dash_start = dash_start_v as Vector2
	if not _is_telegraphing():
		_telegraph_time = 0.0
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	var shake_progress := 0.0
	if _is_telegraphing():
		shake_progress = clampf(_telegraph_time / maxf(0.01, telegraph_duration), 0.0, 1.0)
	_visual.set_attack_shake_progress(shake_progress)
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	_visual.set_state(_resolve_visual_state_name())
	_visual.sync_from_2d(global_position, _resolve_visual_facing_direction())


func _apply_spawn(start_position: Vector2, player_position: Vector2) -> void:
	global_position = start_position
	var random_speed := randf_range(min_speed, max_speed)
	_move_speed = random_speed * speed_scale
	var to_player := player_position - start_position
	var sp := (
		_move_speed * _speed_multiplier * surge_infusion_field_move_speed_factor()
	)
	velocity = to_player.normalized() * sp if to_player.length_squared() > 0.01 else Vector2.ZERO
	if velocity.length_squared() > 1e-6:
		_planar_facing = velocity.normalized()
	elif to_player.length_squared() > 1e-6:
		_planar_facing = to_player.normalized()
	_sync_visual_anim_speed(sp)


func _update_attack_state(delta: float) -> void:
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		_set_attack_phase(AttackPhase.CHASE)
		_sync_visual_anim_speed(0.0)
		return
	_refresh_target_player(delta, _attack_phase == AttackPhase.CHASE)
	ignore_player_body_collisions()
	if _is_player_downed_node(_target_player):
		_target_player = _pick_target_player()
		_set_attack_phase(AttackPhase.CHASE)
		_telegraph_time = 0.0
		_dash_time = 0.0
		_dash_hit_applied = false
		_recovery_time_remaining = 0.0
		velocity = Vector2.ZERO
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		_set_attack_phase(AttackPhase.CHASE)
		return
	if _attack_phase == AttackPhase.STUN:
		_update_stun(delta)
		return
	if _attack_phase == AttackPhase.DASH:
		_update_dash(delta)
		return
	if _attack_phase == AttackPhase.TELEGRAPH:
		_update_telegraph(delta)
		return
	if _attack_phase == AttackPhase.RECOVERY:
		_update_recovery(delta)
		return
	_update_chase_velocity(delta)
	var to_player := _target_player.global_position - global_position
	var trigger_distance := _attack_trigger_distance()
	if to_player.length() <= trigger_distance:
		_start_telegraph(_target_player.global_position)


func _attack_trigger_distance() -> float:
	return dash_range * attack_trigger_distance_multiplier


func _update_chase_velocity(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		if _target_player == null:
			velocity = Vector2.ZERO
			return
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	var desired := Vector2.ZERO
	if _nav_agent and _nav_agent.get_navigation_map() != RID():
		var next_pos := _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		if to_next.length_squared() > 0.001:
			desired = to_next.normalized()
		else:
			# Navigation can return current position when no path is baked; fall back to direct chase.
			var to_player_fallback := _target_player.global_position - global_position
			desired = to_player_fallback.normalized() if to_player_fallback.length_squared() > 0.001 else Vector2.ZERO
	else:
		var to_player := _target_player.global_position - global_position
		desired = to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.ZERO
	var distance_to_player := global_position.distance_to(_target_player.global_position)
	if distance_to_player <= stop_distance:
		velocity = Vector2.ZERO
	else:
		velocity = (
			desired
			* _move_speed
			* _speed_multiplier
			* surge_infusion_field_move_speed_factor()
		)
	_sync_visual_anim_speed()


func _start_telegraph(target_point: Vector2) -> void:
	_set_attack_phase(AttackPhase.TELEGRAPH)
	_telegraph_time = 0.0
	_dash_target_point = target_point
	var dir_to_target := _dash_target_point - global_position
	_dash_dir = dir_to_target.normalized() if dir_to_target.length_squared() > 0.0001 else _planar_facing
	if _dash_dir.length_squared() <= 0.0001:
		_dash_dir = Vector2(0.0, -1.0)
	velocity = Vector2.ZERO
	_sync_visual_anim_speed(0.0)


func _update_telegraph(delta: float) -> void:
	telegraph_duration = maxf(0.01, telegraph_duration)
	_telegraph_time += delta
	velocity = Vector2.ZERO
	var dir_to_target := _dash_target_point - global_position
	if dir_to_target.length_squared() > 0.0001:
		_dash_dir = dir_to_target.normalized()
	if _telegraph_time >= telegraph_duration:
		_start_dash()


func _start_dash() -> void:
	_set_attack_phase(AttackPhase.DASH)
	_dash_time = 0.0
	_dash_start = global_position
	var dash_dir := _dash_dir.normalized() if _dash_dir.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	var to_target := _dash_target_point - _dash_start
	var dash_distance := maxf(to_target.dot(dash_dir), dash_range)
	dash_distance += dash_pass_through_distance
	_dash_end = _dash_start + dash_dir * dash_distance
	_dash_hit_applied = false
	velocity = dash_dir * dash_speed
	_refresh_dash_contact_hitbox()


func _update_dash(delta: float) -> void:
	_dash_time += delta
	var dash_duration := _current_dash_duration()
	var u := clampf(_dash_time / maxf(0.01, dash_duration), 0.0, 1.0)
	var target_pos := _dash_start.lerp(_dash_end, u)
	var to_target := target_pos - global_position
	if to_target.length_squared() > 0.0001:
		velocity = to_target / maxf(delta, 0.0001)
	else:
		velocity = Vector2.ZERO
	_refresh_dash_contact_hitbox()
	if u >= 1.0:
		_set_attack_phase(AttackPhase.RECOVERY)
		_recovery_time_remaining = dash_recovery_duration
		velocity = Vector2.ZERO
		if _dash_contact_hitbox != null:
			_dash_contact_hitbox.deactivate()
		_sync_visual_anim_speed(0.0)


func _update_recovery(delta: float) -> void:
	_recovery_time_remaining = maxf(0.0, _recovery_time_remaining - delta)
	velocity = Vector2.ZERO
	if _recovery_time_remaining <= 0.0:
		_set_attack_phase(AttackPhase.CHASE)


func _update_telegraph_visual() -> void:
	if _telegraph_mesh == null:
		return
	if not _is_telegraphing():
		_telegraph_mesh.visible = false
		_telegraph_progress_step = -1
		return
	_telegraph_mesh.visible = true
	var progress := clampf(_telegraph_time / maxf(0.01, telegraph_duration), 0.0, 1.0)
	var dir := _dash_dir.normalized() if _dash_dir.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	_telegraph_mesh.global_position = Vector3(global_position.x, arrow_ground_y, global_position.y)
	_telegraph_mesh.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
	var progress_step := int(round(progress * float(_TELEGRAPH_PROGRESS_STEPS)))
	if progress_step == _telegraph_progress_step:
		return
	_telegraph_progress_step = progress_step
	if progress_step >= 0 and progress_step < _telegraph_meshes.size():
		_telegraph_mesh.mesh = _telegraph_meshes[progress_step]


func _sync_visual_anim_speed(for_speed: float = -1.0) -> void:
	if _visual == null:
		return
	var s := for_speed if for_speed > 0.0 else velocity.length()
	var playback_scale := clampf(s / maxf(min_speed, 0.01), 0.35, 2.5) if s > 0.05 else 1.0
	_visual.set_playback_speed_scale(playback_scale)


func _should_use_high_detail_visuals() -> bool:
	if _is_telegraphing() or _is_dashing() or _attack_phase == AttackPhase.RECOVERY or _stun_time_remaining > 0.0:
		return true
	if _target_player != null and is_instance_valid(_target_player):
		var detail_range := maxf(stop_distance + dash_range + dash_pass_through_distance, 18.0)
		return global_position.distance_squared_to(_target_player.global_position) <= detail_range * detail_range
	return velocity.length_squared() > 0.04


func take_hit(
	damage: int,
	knockback_dir: Vector2,
	knockback_strength: float,
	from_backstab: bool = false,
	is_critical: bool = false
) -> void:
	if damage <= 0 or _squash_applied:
		return
	super.take_hit(damage, knockback_dir, knockback_strength, from_backstab, is_critical)


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	_set_attack_phase(AttackPhase.STUN)
	_telegraph_time = 0.0
	_dash_time = 0.0
	_dash_hit_applied = false
	_recovery_time_remaining = 0.0
	if _dash_contact_hitbox != null:
		_dash_contact_hitbox.deactivate()
	super._on_nonlethal_hit(knockback_dir, knockback_strength)
	_stun_time_remaining = hit_stun_duration * _mass_stun_mult_this_hit
	_sync_visual_anim_speed(0.0)


func _update_stun(delta: float) -> void:
	_stun_time_remaining = maxf(0.0, _stun_time_remaining - delta)
	tick_hit_knockback_timer(delta)
	if not apply_hit_knockback_to_body_velocity() and _stun_time_remaining > 0.0:
		velocity = Vector2.ZERO
	if _stun_time_remaining <= 0.0 and not is_hit_knockback_active():
		_set_attack_phase(AttackPhase.CHASE)
		velocity = Vector2.ZERO
		_sync_visual_anim_speed(0.0)


func can_contact_damage() -> bool:
	return false


func mass_infusion_add_bonus_stun(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_stun_time_remaining = maxf(_stun_time_remaining, seconds)


func mass_infusion_knockback_size_factor() -> float:
	return 1.18


func _refresh_dash_contact_hitbox() -> void:
	if _dash_contact_hitbox == null:
		return
	var shape_node := _dash_contact_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var rect := shape_node.shape as RectangleShape2D
		rect.size = Vector2(dash_hit_width, maxf(2.4, dash_hit_width * 1.6))
	var dir := _dash_dir
	if dir.length_squared() <= 0.0001:
		dir = Vector2(0.0, -1.0)
	else:
		dir = dir.normalized()
	_dash_contact_hitbox.position = dir * 0.9
	_dash_contact_hitbox.rotation = dir.angle() + PI * 0.5
	_dash_contact_hitbox.repeat_mode = Hitbox2D.RepeatMode.INTERVAL
	_dash_contact_hitbox.repeat_interval_sec = 0.65
	if not _is_dashing() or not is_damage_authority():
		_dash_contact_hitbox.deactivate()
		return
	var packet := DamagePacketScript.new() as DamagePacket
	packet.amount = dash_damage
	packet.kind = &"contact"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = global_position
	packet.direction = dir
	packet.knockback = 0.0
	packet.apply_iframes = true
	packet.blockable = true
	packet.guard_stamina_split_ratio = guard_stamina_split_ratio
	packet.debug_label = &"dash_contact"
	if _dash_contact_hitbox.is_active():
		_dash_contact_hitbox.update_packet_template(packet)
	else:
		_dash_contact_hitbox.activate(packet, _current_dash_duration())


func _body_collision_mask_on_spawn() -> int:
	return 7


func _handle_flow_wall_reset() -> void:
	if not _hit_non_player_wall_this_frame():
		return
	velocity = Vector2.ZERO
	if _is_dashing():
		if _dash_contact_hitbox != null:
			_dash_contact_hitbox.deactivate()
		_set_attack_phase(AttackPhase.RECOVERY)
		_recovery_time_remaining = dash_recovery_duration
		_dash_time = 0.0
		return
	if _attack_phase == AttackPhase.TELEGRAPH:
		_set_attack_phase(AttackPhase.CHASE)
		_telegraph_time = 0.0
		return
	_set_attack_phase(AttackPhase.CHASE)
	_repath_time_remaining = 0.0


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
		return true
	return false


func squash() -> void:
	if _squash_applied:
		return
	_squash_applied = true
	super.squash()


func get_shadow_visual_root() -> Node3D:
	return _visual


func _pick_target_player() -> Node2D:
	return _pick_nearest_player_target()


func _refresh_target_player(delta: float, allow_retarget: bool = true) -> void:
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		allow_retarget,
		Callable(self, "_pick_target_player")
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(
		refresh.get("refresh_time_remaining", _target_refresh_time_remaining)
	)


func _set_attack_phase(next_phase: AttackPhase) -> void:
	_attack_phase = next_phase


func _is_telegraphing() -> bool:
	return _attack_phase == AttackPhase.TELEGRAPH


func _is_dashing() -> bool:
	return _attack_phase == AttackPhase.DASH


func _current_dash_duration() -> float:
	return _dash_start.distance_to(_dash_end) / maxf(0.01, dash_speed)


func _build_telegraph_mesh_for_step(progress_step: int) -> Mesh:
	return FlowTelegraphArrowMeshScript.build_mesh_for_step(
		progress_step,
		_TELEGRAPH_PROGRESS_STEPS,
		arrow_length,
		arrow_head_length,
		arrow_half_width,
		_outline_mat,
		_fill_mat
	)


func _resolve_visual_state_name() -> StringName:
	if _is_telegraphing() or _attack_phase == AttackPhase.STUN:
		return &"idle"
	if _is_dashing() or _attack_phase == AttackPhase.RECOVERY or velocity.length_squared() > 0.01:
		return &"walk"
	return &"idle"


func _desired_facing_for_orient() -> Vector2:
	if (_is_telegraphing() or _is_dashing()) and _dash_dir.length_squared() > 0.0001:
		return _dash_dir.normalized()
	if velocity.length_squared() > 0.0001:
		return velocity.normalized()
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 0.0001:
			return to_target.normalized()
	if _dash_dir.length_squared() > 0.0001:
		return _dash_dir.normalized()
	return Vector2(0.0, -1.0)


func _update_planar_facing(delta: float) -> void:
	var desired := _desired_facing_for_orient()
	if (_is_telegraphing() or _is_dashing()) and _dash_dir.length_squared() > 0.0001:
		_planar_facing = _dash_dir.normalized()
		return
	var max_step := deg_to_rad(turn_toward_facing_deg_per_sec) * delta
	_planar_facing = EnemyBase.step_planar_facing_toward(_planar_facing, desired, max_step)


func _resolve_visual_facing_direction() -> Vector2:
	if _planar_facing.length_squared() > 0.0001:
		return _planar_facing.normalized()
	return _desired_facing_for_orient()


func _build_visual_state_config() -> Dictionary:
	return build_single_scene_visual_state_config(DASHER_VISUAL_SCENE, dasher_clip_scale)
