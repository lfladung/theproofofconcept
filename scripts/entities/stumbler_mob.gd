class_name StumblerMob
extends EnemyBase
## Mass / surface: slow straight-line approach, telegraphed stomp AoE.

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const StumblerDamagePacketScript = preload("res://scripts/combat/damage_packet.gd")

enum Phase { CHASE, STOMP_WINDUP, STOMP_HIT, RECOVER }

@export var move_speed := 4.0
@export var stomp_trigger_dist := 2.1375
@export var stomp_windup_sec := 1.2
@export var stomp_radius := 1.875
@export var stomp_damage := 20
@export var stomp_knockback := 14.0
@export var stomp_hitbox_duration := 0.14
@export var stomp_cooldown_sec := 2.0
@export var recover_sec := 0.45
@export var stuck_speed_threshold := 0.15
@export var stuck_time_to_retarget := 0.22
@export var target_refresh_interval := 0.35
@export var mesh_ground_y := 0.165
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
		move_and_slide()
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
	move_and_slide()
	mass_server_post_slide()
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
	var sp := move_speed * _speed_multiplier * surge_infusion_field_move_speed_factor()
	velocity = _locked_dir * sp
	var spd := velocity.length()
	if spd < stuck_speed_threshold:
		_stuck_accum += delta
		if _stuck_accum >= stuck_time_to_retarget:
			_stuck_accum = 0.0
			var to_player := _target_player.global_position - global_position
			_locked_dir = to_player.normalized() if to_player.length_squared() > 0.01 else _locked_dir
	else:
		_stuck_accum = 0.0
	_planar_facing = _locked_dir


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
		"sa": _stomp_anchor,
		"cd": _stomp_cooldown_rem,
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
	var ld_v: Variant = state.get("ld", _locked_dir)
	if ld_v is Vector2:
		var ld := ld_v as Vector2
		if ld.length_squared() > 0.0001:
			_locked_dir = ld.normalized()
	var sa_v: Variant = state.get("sa", _stomp_anchor)
	if sa_v is Vector2:
		_stomp_anchor = sa_v as Vector2
	_stomp_cooldown_rem = maxf(0.0, float(state.get("cd", 0.0)))


func _sync_visual_from_body() -> void:
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


func _create_telegraph_mesh(parent: Node3D) -> void:
	_telegraph_mesh = MeshInstance3D.new()
	_telegraph_mesh.name = &"StumblerTelegraph"
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.albedo_color = Color(0.55, 0.42, 0.2, 0.7)
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	var imm := ImmediateMesh.new()
	var radius := stomp_radius * p
	var outer_radius := maxf(stomp_radius, 0.1)
	var segments := 24
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
