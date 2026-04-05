class_name DasherMob
extends EnemyBase

const LEGACY_MOB_VISUAL_SCENE := preload("res://scenes/visuals/mob_visual.tscn")
const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const SHARDLING_IDLE_SCENE := preload("res://art/characters/enemies/shardling_texture.glb")
const SHARDLING_WALK_SCENE := preload("res://art/characters/enemies/shardling_walk.glb")
const _TELEGRAPH_PROGRESS_STEPS := 12

@export var min_speed := 10.0
@export var max_speed := 18.0
## Feet-to-ground mob; stomp when player.height exceeds this while falling.
@export var stomp_top_height := 1.02
@export var stop_distance := 1.2
@export var repath_interval := 0.2
@export var speed_scale := 0.75
@export var attack_trigger_distance_multiplier := 1.0
@export var telegraph_duration := 1.0
@export var dash_distance := 5.0
@export var dash_duration := 0.25
@export var dash_hit_width := 1.8
@export var dash_damage := 25
@export var arrow_ground_y := 0.06
@export var arrow_length := 7.8
@export var arrow_head_length := 0.8
@export var arrow_half_width := 0.32
@export var hit_stun_duration := 1.0
@export var hit_knockback_duration := 0.22
@export var target_refresh_interval := 0.3
@export var mesh_ground_y := 0.24
@export var mesh_scale := Vector3(2.0, 2.0, 2.0)
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
var _is_telegraphing := false
var _is_dashing := false
var _telegraph_time := 0.0
var _dash_time := 0.0
var _dash_start := Vector2.ZERO
var _dash_end := Vector2.ZERO
var _dash_dir := Vector2.ZERO
var _dash_hit_applied := false
var _stun_time_remaining := 0.0
var _knockback_time_remaining := 0.0
var _knockback_velocity := Vector2.ZERO
var _aggro_enabled := true
var _telegraph_progress_step := -1
var _planar_facing := Vector2(0.0, -1.0)
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _dash_contact_hitbox: Hitbox2D = $DashContactHitbox


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
		_is_telegraphing = false
		_is_dashing = false
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
		_outline_mat = StandardMaterial3D.new()
		_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fill_mat.albedo_color = Color(0.9, 0.08, 0.08, 0.75)
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_mesh.visible = false
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
		set_deferred(&"collision_mask", 7)
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
	_update_attack_state(delta)
	move_and_slide()
	_update_planar_facing(delta)
	_enemy_network_server_broadcast(delta)
	_sync_visual_from_body()
	_update_telegraph_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"tg": _is_telegraphing,
		"tt": _telegraph_time,
		"td": telegraph_duration,
		"dd": _dash_dir,
		"ds": _is_dashing,
		"pf": _planar_facing,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_is_telegraphing = bool(state.get("tg", false))
	_is_dashing = bool(state.get("ds", false))
	telegraph_duration = maxf(0.01, float(state.get("td", telegraph_duration)))
	_telegraph_time = clampf(float(state.get("tt", 0.0)), 0.0, telegraph_duration)
	var dash_dir_v: Variant = state.get("dd", _dash_dir)
	if dash_dir_v is Vector2:
		var dash_dir := dash_dir_v as Vector2
		if dash_dir.length_squared() > 0.0001:
			_dash_dir = dash_dir.normalized()
	if not _is_telegraphing:
		_telegraph_time = 0.0
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	_visual.set_state(_resolve_visual_state_name())
	_visual.sync_from_2d(global_position, _resolve_visual_facing_direction())


func _apply_spawn(start_position: Vector2, player_position: Vector2) -> void:
	global_position = start_position
	var random_speed := randf_range(min_speed, max_speed)
	_move_speed = random_speed * speed_scale * _speed_multiplier
	var to_player := player_position - start_position
	velocity = to_player.normalized() * _move_speed if to_player.length_squared() > 0.01 else Vector2.ZERO
	if velocity.length_squared() > 1e-6:
		_planar_facing = velocity.normalized()
	elif to_player.length_squared() > 1e-6:
		_planar_facing = to_player.normalized()
	_sync_visual_anim_speed(_move_speed)


func _update_attack_state(delta: float) -> void:
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		_is_telegraphing = false
		_is_dashing = false
		_sync_visual_anim_speed(0.0)
		return
	_refresh_target_player(delta, not _is_telegraphing and not _is_dashing)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_target_player()
		_is_telegraphing = false
		_is_dashing = false
		_telegraph_time = 0.0
		_dash_time = 0.0
		_dash_hit_applied = false
		velocity = Vector2.ZERO
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		_is_telegraphing = false
		_is_dashing = false
		return
	if _stun_time_remaining > 0.0:
		_update_stun(delta)
		return
	if _is_dashing:
		_update_dash(delta)
		return
	if _is_telegraphing:
		_update_telegraph(delta)
		return
	_update_chase_velocity(delta)
	var to_player := _target_player.global_position - global_position
	var trigger_distance := arrow_length * attack_trigger_distance_multiplier
	if to_player.length() <= trigger_distance:
		_start_telegraph(to_player.normalized())


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
		velocity = desired * _move_speed
	_sync_visual_anim_speed()


func _start_telegraph(dir_to_player: Vector2) -> void:
	_is_telegraphing = true
	_telegraph_time = 0.0
	_dash_dir = dir_to_player if dir_to_player.length_squared() > 0.0001 else Vector2(1.0, 0.0)
	velocity = Vector2.ZERO
	_sync_visual_anim_speed(0.0)


func _update_telegraph(delta: float) -> void:
	telegraph_duration = maxf(0.01, telegraph_duration)
	_telegraph_time += delta
	velocity = Vector2.ZERO
	if _telegraph_time >= telegraph_duration:
		_start_dash()


func _start_dash() -> void:
	_is_telegraphing = false
	_is_dashing = true
	_dash_time = 0.0
	_dash_start = global_position
	_dash_end = _dash_start + _dash_dir.normalized() * dash_distance
	_dash_hit_applied = false
	velocity = _dash_dir.normalized() * (dash_distance / maxf(0.01, dash_duration))
	_refresh_dash_contact_hitbox()


func _update_dash(delta: float) -> void:
	_dash_time += delta
	var u := clampf(_dash_time / maxf(0.01, dash_duration), 0.0, 1.0)
	var target_pos := _dash_start.lerp(_dash_end, u)
	var to_target := target_pos - global_position
	if to_target.length_squared() > 0.0001:
		velocity = to_target / maxf(delta, 0.0001)
	else:
		velocity = Vector2.ZERO
	_refresh_dash_contact_hitbox()
	if u >= 1.0:
		_is_dashing = false
		velocity = Vector2.ZERO
		if _dash_contact_hitbox != null:
			_dash_contact_hitbox.deactivate()
		_sync_visual_anim_speed(0.0)


func _update_telegraph_visual() -> void:
	if _telegraph_mesh == null:
		return
	if not _is_telegraphing:
		_telegraph_mesh.visible = false
		_telegraph_progress_step = -1
		return
	_telegraph_mesh.visible = true
	var progress := clampf(_telegraph_time / maxf(0.01, telegraph_duration), 0.0, 1.0)
	var dir := _dash_dir.normalized()
	_telegraph_mesh.global_position = Vector3(global_position.x, arrow_ground_y, global_position.y)
	_telegraph_mesh.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
	var progress_step := int(round(progress * float(_TELEGRAPH_PROGRESS_STEPS)))
	if progress_step == _telegraph_progress_step:
		return
	_telegraph_progress_step = progress_step
	var fill_ratio := float(progress_step) / float(_TELEGRAPH_PROGRESS_STEPS)
	var shaft_end_z := maxf(0.1, arrow_length - arrow_head_length)
	var tip_z := arrow_length
	var half_width := arrow_half_width
	var head_half_width := arrow_half_width * 1.8
	var fill_tip_z := arrow_length * fill_ratio
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
	for pair in [
		[Vector3(half_width, 0.0, 0.0), Vector3(half_width, 0.0, shaft_end_z)],
		[Vector3(half_width, 0.0, shaft_end_z), Vector3(head_half_width, 0.0, shaft_end_z)],
		[Vector3(head_half_width, 0.0, shaft_end_z), Vector3(0.0, 0.0, tip_z)],
		[Vector3(0.0, 0.0, tip_z), Vector3(-head_half_width, 0.0, shaft_end_z)],
		[Vector3(-head_half_width, 0.0, shaft_end_z), Vector3(-half_width, 0.0, shaft_end_z)],
		[Vector3(-half_width, 0.0, shaft_end_z), Vector3(-half_width, 0.0, 0.0)],
		[Vector3(-half_width, 0.0, 0.0), Vector3(half_width, 0.0, 0.0)],
	]:
		imm.surface_add_vertex(pair[0] as Vector3)
		imm.surface_add_vertex(pair[1] as Vector3)
	imm.surface_end()

	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
	for v in [
		Vector3(half_width * 0.55, 0.001, 0.0),
		Vector3(-half_width * 0.55, 0.001, 0.0),
		Vector3(0.0, 0.001, fill_tip_z),
	]:
		imm.surface_add_vertex(v as Vector3)
	imm.surface_end()
	_telegraph_mesh.mesh = imm


func _sync_visual_anim_speed(for_speed: float = -1.0) -> void:
	if _visual == null:
		return
	var s := for_speed if for_speed > 0.0 else velocity.length()
	var playback_scale := clampf(s / maxf(min_speed, 0.01), 0.35, 2.5) if s > 0.05 else 1.0
	_visual.set_playback_speed_scale(playback_scale)


func _should_use_high_detail_visuals() -> bool:
	if _is_telegraphing or _is_dashing or _stun_time_remaining > 0.0:
		return true
	if _target_player != null and is_instance_valid(_target_player):
		var detail_range := maxf(stop_distance + dash_distance, 18.0)
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
	_is_telegraphing = false
	_is_dashing = false
	_telegraph_time = 0.0
	_dash_time = 0.0
	_dash_hit_applied = false
	if _dash_contact_hitbox != null:
		_dash_contact_hitbox.deactivate()
	var dir := knockback_dir.normalized() if knockback_dir.length_squared() > 0.0001 else Vector2.ZERO
	_knockback_velocity = dir * maxf(0.0, knockback_strength) * 1.3
	_knockback_time_remaining = hit_knockback_duration
	_stun_time_remaining = hit_stun_duration
	_sync_visual_anim_speed(0.0)


func _update_stun(delta: float) -> void:
	_stun_time_remaining = maxf(0.0, _stun_time_remaining - delta)
	if _knockback_time_remaining > 0.0:
		_knockback_time_remaining = maxf(0.0, _knockback_time_remaining - delta)
		velocity = _knockback_velocity
	else:
		velocity = Vector2.ZERO
	if _stun_time_remaining <= 0.0:
		velocity = Vector2.ZERO
		_knockback_velocity = Vector2.ZERO
		_sync_visual_anim_speed(0.0)


func can_contact_damage() -> bool:
	return false


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
	if not _is_dashing or not is_damage_authority():
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
	packet.debug_label = &"dash_contact"
	if _dash_contact_hitbox.is_active():
		_dash_contact_hitbox.update_packet_template(packet)
	else:
		_dash_contact_hitbox.activate(packet, dash_duration)


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
	_target_refresh_time_remaining = maxf(0.0, _target_refresh_time_remaining - delta)
	if (
		_target_player == null
		or not is_instance_valid(_target_player)
		or (allow_retarget and _target_refresh_time_remaining <= 0.0)
	):
		_target_player = _pick_target_player()
		_target_refresh_time_remaining = maxf(0.05, target_refresh_interval)


func _resolve_visual_state_name() -> StringName:
	if _is_telegraphing or _stun_time_remaining > 0.0:
		return &"idle"
	if _is_dashing or velocity.length_squared() > 0.01:
		return &"walk"
	return &"idle"


func _desired_facing_for_orient() -> Vector2:
	if (_is_telegraphing or _is_dashing) and _dash_dir.length_squared() > 0.0001:
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
	if (_is_telegraphing or _is_dashing) and _dash_dir.length_squared() > 0.0001:
		_planar_facing = _dash_dir.normalized()
		return
	var max_step := deg_to_rad(turn_toward_facing_deg_per_sec) * delta
	_planar_facing = EnemyBase.step_planar_facing_toward(_planar_facing, desired, max_step)


func _resolve_visual_facing_direction() -> Vector2:
	if _planar_facing.length_squared() > 0.0001:
		return _planar_facing.normalized()
	return _desired_facing_for_orient()


func _build_visual_state_config() -> Dictionary:
	var idle_scene := SHARDLING_IDLE_SCENE
	var walk_scene := SHARDLING_WALK_SCENE
	if idle_scene == null and walk_scene == null:
		return {
			&"idle": {
				"scene": LEGACY_MOB_VISUAL_SCENE,
				"keywords": ["float"],
			},
			&"walk": {
				"scene": LEGACY_MOB_VISUAL_SCENE,
				"keywords": ["float"],
			},
		}
	if idle_scene == null:
		idle_scene = walk_scene
	if walk_scene == null:
		walk_scene = idle_scene
	return {
		&"idle": {
			"scene": idle_scene,
			"keywords": ["idle", "stand", "reset"],
		},
		&"walk": {
			"scene": walk_scene,
			"scene_scale": 114.0,
			"keywords": ["walk", "run", "moving"],
		},
	}
