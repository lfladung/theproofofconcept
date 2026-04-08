class_name WardenMob
extends EnemyBase
## Mass / deep: slow nav, heavy telegraphed slam; on death spawns three Shieldwalls.

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const WardenDamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const SHIELDWALL_SCENE := preload("res://scenes/entities/shieldwall.tscn")

enum Phase { CHASE, SLAM_WINDUP, SLAM_HIT, RECOVER }

@export var move_speed := 3.0
@export var stop_distance := 3.4375
@export var repath_interval := 0.28
@export var target_refresh_interval := 0.4
@export var slam_windup_sec := 1.5
@export var slam_radius := 2.8125
@export var slam_damage := 45
@export var slam_knockback := 18.0
@export var slam_hitbox_duration := 0.16
@export var slam_recover_sec := 0.55
@export var slam_cooldown_min := 6.0
@export var slam_cooldown_max := 8.0
@export var mesh_ground_y := 0.21875
@export var mesh_scale := Vector3(2.625, 2.625, 2.625)
@export var warden_clip_scale := 2.0
@export var telegraph_ground_y := 0.04375

var _visual: Node3D
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _speed_multiplier := 1.0
var _aggro_enabled := true
var _planar_facing := Vector2(0.0, -1.0)
var _phase := Phase.CHASE
var _phase_elapsed := 0.0
var _slam_cooldown_rem := 0.0
var _slam_anchor := Vector2.ZERO
var _warden_splits_done := false

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _slam_hitbox: Hitbox2D = $SlamHitbox
@onready var _slam_shape_node: CollisionShape2D = $SlamHitbox/CollisionShape2D


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func surge_infusion_bump_action_delay(seconds: float) -> void:
	if seconds <= 0.0 or not is_damage_authority():
		return
	_slam_cooldown_rem += seconds


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		_target_player = null
		velocity = Vector2.ZERO
		_phase = Phase.CHASE
		_phase_elapsed = 0.0


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func squash() -> void:
	if _warden_splits_done:
		super.squash()
		return
	_warden_splits_done = true
	if is_damage_authority():
		_request_spawn_shieldwall_splits()
	super.squash()


func _request_spawn_shieldwall_splits() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null or not scene_root.has_method(&"server_enqueue_enemy_spawn"):
		return
	var encounter_id := get_meta(&"encounter_id", &"") as StringName
	var target := _pick_nearest_player_target()
	var tpos := target.global_position if target != null else global_position
	var offsets: Array[Vector2] = [
		Vector2(-0.6875, 0.0),
		Vector2(0.6875, 0.0),
		Vector2(0.0, 0.75),
	]
	for off in offsets:
		scene_root.call(
			&"server_enqueue_enemy_spawn",
			encounter_id,
			global_position + off,
			tpos,
			_speed_multiplier,
			SHIELDWALL_SCENE
		)


func _ready() -> void:
	super._ready()
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"WardenVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_create_telegraph_mesh(vw)
	_sync_visual()
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.53125
		_nav_agent.target_desired_distance = stop_distance * 0.92
		_nav_agent.avoidance_enabled = false
	_refresh_slam_hitbox_shape()
	_roll_slam_cooldown()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func _roll_slam_cooldown() -> void:
	_slam_cooldown_rem = randf_range(slam_cooldown_min, slam_cooldown_max)


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Warden.glb")
	var scale_v: Variant = warden_clip_scale
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


func _refresh_slam_hitbox_shape() -> void:
	if _slam_shape_node != null and _slam_shape_node.shape is CircleShape2D:
		(_slam_shape_node.shape as CircleShape2D).radius = slam_radius


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_slam_telegraph_visual()
		_sync_visual()
		return
	surge_infusion_tick_server_field_decay()
	_slam_cooldown_rem = maxf(0.0, _slam_cooldown_rem - delta * surge_infusion_field_cooldown_tick_factor())
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		_enemy_network_server_broadcast(delta)
		_update_slam_telegraph_visual()
		_sync_visual()
		return
	_refresh_target_player(delta, _phase == Phase.CHASE)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()
	match _phase:
		Phase.CHASE:
			_tick_chase_slam(delta)
		Phase.SLAM_WINDUP:
			_tick_slam_windup(delta)
		Phase.SLAM_HIT:
			_tick_slam_hit()
		Phase.RECOVER:
			_tick_slam_recover(delta)
	apply_hit_knockback_to_body_velocity()
	move_and_slide()
	mass_server_post_slide()
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_update_slam_telegraph_visual()
	_sync_visual()


func _tick_chase_slam(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	_update_chase_velocity(delta)
	if _slam_cooldown_rem <= 0.0:
		var to_p := _target_player.global_position - global_position
		if to_p.length_squared() <= (stop_distance + slam_radius * 0.55) * (stop_distance + slam_radius * 0.55):
			_phase = Phase.SLAM_WINDUP
			_phase_elapsed = 0.0
			_slam_anchor = global_position
			velocity = Vector2.ZERO
			if to_p.length_squared() > 0.0001:
				_planar_facing = to_p.normalized()


func _update_chase_velocity(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent != null and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	var desired := Vector2.ZERO
	if _nav_agent != null and _nav_agent.get_navigation_map() != RID():
		var next_pos := _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		if to_next.length_squared() > 0.001:
			desired = to_next.normalized()
	var to_target := _target_player.global_position - global_position
	if desired.length_squared() <= 0.0001 and to_target.length_squared() > 0.001:
		desired = to_target.normalized()
	if to_target.length_squared() <= stop_distance * stop_distance:
		velocity = Vector2.ZERO
	else:
		velocity = (
			desired
			* move_speed
			* _speed_multiplier
			* surge_infusion_field_move_speed_factor()
		)
	if velocity.length_squared() > 0.01:
		_planar_facing = velocity.normalized()
	elif to_target.length_squared() > 0.0001:
		_planar_facing = to_target.normalized()


func _tick_slam_windup(delta: float) -> void:
	global_position = _slam_anchor
	velocity = Vector2.ZERO
	if _target_player != null and is_instance_valid(_target_player):
		var to_p := _target_player.global_position - global_position
		if to_p.length_squared() > 0.0001:
			_planar_facing = to_p.normalized()
	_phase_elapsed += delta
	if _phase_elapsed >= slam_windup_sec:
		_phase = Phase.SLAM_HIT
		_phase_elapsed = 0.0


func _tick_slam_hit() -> void:
	_activate_slam_hitbox()
	_phase = Phase.RECOVER
	_phase_elapsed = 0.0
	_roll_slam_cooldown()
	velocity = Vector2.ZERO


func _tick_slam_recover(delta: float) -> void:
	global_position = _slam_anchor
	velocity = Vector2.ZERO
	_phase_elapsed += delta
	if _phase_elapsed >= slam_recover_sec:
		_phase = Phase.CHASE
		_phase_elapsed = 0.0


func _activate_slam_hitbox() -> void:
	if _slam_hitbox == null or not is_damage_authority():
		return
	var packet := WardenDamagePacketScript.new() as DamagePacket
	packet.amount = slam_damage
	packet.kind = &"stomp"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = global_position
	packet.direction = _planar_facing
	packet.knockback = slam_knockback
	packet.apply_iframes = true
	packet.blockable = false
	packet.debug_label = &"warden_slam"
	_slam_hitbox.activate(packet, slam_hitbox_duration)


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ph": _phase,
		"pe": _phase_elapsed,
		"pf": _planar_facing,
		"sa": _slam_anchor,
		"cd": _slam_cooldown_rem,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_phase = int(state.get("ph", _phase)) as Phase
	_phase_elapsed = maxf(0.0, float(state.get("pe", 0.0)))
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()
	var sa_v: Variant = state.get("sa", _slam_anchor)
	if sa_v is Vector2:
		_slam_anchor = sa_v as Vector2
	_slam_cooldown_rem = maxf(0.0, float(state.get("cd", 0.0)))


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	var moving := _phase == Phase.CHASE and velocity.length_squared() > 0.04
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _planar_facing)


func _should_use_high_detail_visuals() -> bool:
	if _phase != Phase.CHASE:
		return true
	if _target_player != null and is_instance_valid(_target_player):
		return global_position.distance_squared_to(_target_player.global_position) <= 36.0 * 36.0
	return true


func _refresh_target_player(delta: float, allow_retarget: bool = true) -> void:
	_target_refresh_time_remaining = maxf(0.0, _target_refresh_time_remaining - delta)
	if (
		_target_player == null
		or not is_instance_valid(_target_player)
		or (allow_retarget and _target_refresh_time_remaining <= 0.0)
	):
		_target_player = _pick_nearest_player_target()
		_target_refresh_time_remaining = maxf(0.05, target_refresh_interval)


func _create_telegraph_mesh(parent: Node3D) -> void:
	_telegraph_mesh = MeshInstance3D.new()
	_telegraph_mesh.name = &"WardenTelegraph"
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color(0.02, 0.02, 0.02, 1.0)
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.albedo_color = Color(0.35, 0.22, 0.55, 0.62)
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_mesh.visible = false
	parent.add_child(_telegraph_mesh)


func _slam_telegraph_progress() -> float:
	if _phase != Phase.SLAM_WINDUP:
		return 0.0
	return clampf(_phase_elapsed / maxf(0.01, slam_windup_sec), 0.0, 1.0)


func _update_slam_telegraph_visual() -> void:
	if _telegraph_mesh == null:
		return
	var active := _phase == Phase.SLAM_WINDUP
	if not active:
		_telegraph_mesh.visible = false
		return
	var p := _slam_telegraph_progress()
	_telegraph_mesh.visible = true
	_telegraph_mesh.global_position = Vector3(_slam_anchor.x, telegraph_ground_y, _slam_anchor.y)
	_telegraph_mesh.rotation = Vector3.ZERO
	var imm := ImmediateMesh.new()
	var radius := slam_radius * p
	var outer_radius := maxf(slam_radius, 0.1)
	var segments := 28
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
	for segment_index in range(segments):
		var t0 := float(segment_index) / float(segments)
		var t1 := float(segment_index + 1) / float(segments)
		var a0 := lerpf(0.0, TAU, t0)
		var a1 := lerpf(0.0, TAU, t1)
		var p0 := Vector3(sin(a0) * outer_radius, 0.0, cos(a0) * outer_radius)
		var p1 := Vector3(sin(a1) * outer_radius, 0.0, cos(a1) * outer_radius)
		imm.surface_add_vertex(p0)
		imm.surface_add_vertex(p1)
	imm.surface_end()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
	for segment_index in range(segments):
		var t0 := float(segment_index) / float(segments)
		var t1 := float(segment_index + 1) / float(segments)
		var a0 := lerpf(0.0, TAU, t0)
		var a1 := lerpf(0.0, TAU, t1)
		var fp0 := Vector3(sin(a0) * radius, 0.001, cos(a0) * radius)
		var fp1 := Vector3(sin(a1) * radius, 0.001, cos(a1) * radius)
		imm.surface_add_vertex(Vector3(0.0, 0.001, 0.0))
		imm.surface_add_vertex(fp0)
		imm.surface_add_vertex(fp1)
	imm.surface_end()
	_telegraph_mesh.mesh = imm
