class_name ShieldwallMob
extends EnemyBase
## Mass / mid: directional shield toward player, bash knockback, back-hit exposed window.

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const ShieldwallDamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const GroundAoeTelegraphMeshScript = preload("res://scripts/visuals/ground_aoe_telegraph_mesh.gd")
const FlowTelegraphArrowMeshScript = preload("res://scripts/entities/flow_telegraph_arrow_mesh.gd")

enum BashPhase { IDLE, WINDUP, LUNGE, RECOVER }

@export var move_speed := 6.0
@export var stop_distance := 2.5
@export var repath_interval := 0.22
@export var target_refresh_interval := 0.35
@export var shield_turn_deg_per_sec := 80.0
@export var block_arc_degrees := 180.0
@export var bash_interval_sec := 2.0
@export var bash_trigger_distance := 9.5
@export var bash_windup_sec := 0.5
@export var bash_lunge_sec := 0.2
@export var bash_lunge_distance := 4.0
@export var bash_recover_sec := 0.4
@export var bash_knockback := 22.0
@export var bash_telegraph_ground_y := 0.05
@export var bash_arrow_length := 2.8
@export var bash_arrow_head_length := 0.7
@export var bash_arrow_half_width := 0.24
@export var bash_circle_radius := 5.0
## Forward hitbox placement: same convention as player melee (rect `size.y` = depth along bash after `rotation = dir.angle() + PI/2`).
@export var bash_hit_start_beyond_body := 0.06
@export var exposed_duration_sec := 2.0
@export var back_hits_to_expose := 3
@export var back_hit_window_sec := 5.0
@export var mesh_ground_y := 0.28
@export var mesh_scale := Vector3(1.95, 1.95, 1.95)
@export var shieldwall_clip_scale := 1.8375

var _visual: Node3D
var _vw: Node3D
var _telegraph_arrow_mesh: MeshInstance3D
var _telegraph_circle_mesh: MeshInstance3D
var _telegraph_outline_mat: StandardMaterial3D
var _telegraph_fill_mat: StandardMaterial3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _speed_multiplier := 1.0
var _aggro_enabled := true
var _shield_facing := Vector2(0.0, -1.0)
var _bash_phase := BashPhase.IDLE
var _bash_elapsed := 0.0
var _bash_cooldown_rem := 0.0
var _bash_dir := Vector2(0.0, -1.0)
var _exposed_until_msec := 0
var _back_hit_times: Array[float] = []
var _remote_exposed := false
var _exposed_indicator_mesh: MeshInstance3D

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _bash_hitbox: Hitbox2D = $BashHitbox
@onready var _bash_shape_node: CollisionShape2D = $BashHitbox/CollisionShape2D


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func surge_infusion_bump_action_delay(seconds: float) -> void:
	if seconds <= 0.0 or not is_damage_authority():
		return
	_bash_cooldown_rem += seconds


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		_target_player = null
		velocity = Vector2.ZERO
		_bash_phase = BashPhase.IDLE
		_bash_elapsed = 0.0


func get_combat_planar_facing() -> Vector2:
	if _shield_facing.length_squared() > 1e-6:
		return _shield_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func is_directional_guard_active() -> bool:
	if not is_damage_authority():
		return _aggro_enabled and _bash_phase == BashPhase.IDLE and not _remote_exposed
	return (
		_aggro_enabled
		and _bash_phase == BashPhase.IDLE
		and Time.get_ticks_msec() >= _exposed_until_msec
	)


func get_directional_guard_facing() -> Vector2:
	return _shield_facing.normalized() if _shield_facing.length_squared() > 1e-6 else Vector2(0.0, -1.0)


func directional_guard_incoming_damage_scale(packet: DamagePacket) -> float:
	if Time.get_ticks_msec() < _exposed_until_msec:
		return 2.0
	var origin_dir := packet.origin - global_position
	if origin_dir.length_squared() <= 1e-6 and packet.direction.length_squared() > 1e-6:
		origin_dir = -packet.direction
	if origin_dir.length_squared() <= 1e-6:
		return 1.0
	origin_dir = origin_dir.normalized()
	if _shield_facing.dot(origin_dir) < -0.35:
		return 1.5
	return 1.0


func _ready() -> void:
	super._ready()
	var dr := $DamageReceiver as DirectionalGuardDamageReceiverComponent
	if dr != null:
		dr.block_arc_degrees = block_arc_degrees
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"ShieldwallVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_create_exposed_indicator(vw)
		_create_bash_telegraph_meshes(vw)
	_sync_visual()
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.5625
		_nav_agent.target_desired_distance = stop_distance
		_nav_agent.avoidance_enabled = false
	_refresh_bash_hitbox_layout()
	_bash_cooldown_rem = bash_interval_sec * 0.35


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _exposed_indicator_mesh != null and is_instance_valid(_exposed_indicator_mesh):
		_exposed_indicator_mesh.queue_free()
	if _telegraph_arrow_mesh != null and is_instance_valid(_telegraph_arrow_mesh):
		_telegraph_arrow_mesh.queue_free()
	if _telegraph_circle_mesh != null and is_instance_valid(_telegraph_circle_mesh):
		_telegraph_circle_mesh.queue_free()


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, hurtbox: Area2D) -> void:
	super._on_receiver_damage_applied(packet, hp_damage, hurtbox)
	if hp_damage <= 0 or not is_damage_authority():
		return
	var origin_dir := packet.origin - global_position
	if origin_dir.length_squared() <= 1e-6:
		return
	origin_dir = origin_dir.normalized()
	if _shield_facing.dot(origin_dir) < -0.28:
		_register_back_hit()


func _register_back_hit() -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	_back_hit_times.append(now)
	while _back_hit_times.size() > 0 and now - _back_hit_times[0] > back_hit_window_sec:
		_back_hit_times.pop_front()
	if _back_hit_times.size() >= back_hits_to_expose:
		_exposed_until_msec = Time.get_ticks_msec() + int(exposed_duration_sec * 1000.0)
		_back_hit_times.clear()


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Shieldwall.glb")
	return build_single_scene_visual_state_config(scene, shieldwall_clip_scale)


func _refresh_bash_hitbox_layout() -> void:
	var depth_along_bash := 1.35
	if _bash_shape_node != null and _bash_shape_node.shape is RectangleShape2D:
		var rect := _bash_shape_node.shape as RectangleShape2D
		rect.size = Vector2(1.8, 1.35)
		depth_along_bash = rect.size.y
	var inner := _body_footprint_radius() + bash_hit_start_beyond_body
	_bash_hitbox.position = _bash_dir * (inner + depth_along_bash * 0.5)
	_bash_hitbox.rotation = _bash_dir.angle() + PI * 0.5


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual()
		return
	surge_infusion_tick_server_field_decay()
	var cd_tick := surge_infusion_field_cooldown_tick_factor()
	_bash_cooldown_rem = maxf(0.0, _bash_cooldown_rem - delta * cd_tick)
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	_refresh_target_player(delta, _bash_phase == BashPhase.IDLE)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()
	_update_shield_facing(delta)
	match _bash_phase:
		BashPhase.IDLE:
			_update_chase_velocity(delta)
			_try_start_bash()
		BashPhase.WINDUP:
			velocity = Vector2.ZERO
			_tick_bash_windup(delta)
		BashPhase.LUNGE:
			_tick_bash_lunge(delta)
		BashPhase.RECOVER:
			velocity = Vector2.ZERO
			_tick_bash_recover(delta)
	apply_hit_knockback_to_body_velocity()
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _update_shield_facing(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		return
	var to_p := _target_player.global_position - global_position
	if to_p.length_squared() <= 1e-6:
		return
	var want := to_p.normalized()
	var max_step := deg_to_rad(shield_turn_deg_per_sec) * delta
	_shield_facing = EnemyBase.step_planar_facing_toward(_shield_facing, want, max_step)


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


func _try_start_bash() -> void:
	if _bash_cooldown_rem > 0.0 or _target_player == null or not is_instance_valid(_target_player):
		return
	var to_t := _target_player.global_position - global_position
	if to_t.length_squared() > bash_trigger_distance * bash_trigger_distance:
		return
	_bash_phase = BashPhase.WINDUP
	_bash_elapsed = 0.0
	_bash_dir = _shield_facing.normalized() if _shield_facing.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	_refresh_bash_hitbox_layout()
	velocity = Vector2.ZERO


func _tick_bash_windup(delta: float) -> void:
	_bash_elapsed += delta
	if _bash_elapsed >= bash_windup_sec:
		_bash_phase = BashPhase.LUNGE
		_bash_elapsed = 0.0
		_activate_bash_hitbox()
		var speed := bash_lunge_distance / maxf(0.04, bash_lunge_sec)
		velocity = _bash_dir * speed


func _tick_bash_lunge(delta: float) -> void:
	_bash_elapsed += delta
	if _bash_elapsed >= bash_lunge_sec:
		_bash_phase = BashPhase.RECOVER
		_bash_elapsed = 0.0
		velocity = Vector2.ZERO
		if _bash_hitbox != null:
			_bash_hitbox.deactivate()


func _tick_bash_recover(delta: float) -> void:
	_bash_elapsed += delta
	if _bash_elapsed >= bash_recover_sec:
		_bash_phase = BashPhase.IDLE
		_bash_elapsed = 0.0
		_bash_cooldown_rem = bash_interval_sec


func _activate_bash_hitbox() -> void:
	if _bash_hitbox == null or not is_damage_authority():
		return
	var packet := ShieldwallDamagePacketScript.new() as DamagePacket
	packet.amount = 1
	packet.kind = &"bash"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = (
		_bash_hitbox.global_position
		if _bash_hitbox != null
		else global_position + _bash_dir * (_body_footprint_radius() + bash_hit_start_beyond_body)
	)
	packet.direction = _bash_dir
	packet.knockback = bash_knockback
	packet.apply_iframes = false
	packet.blockable = true
	packet.debug_label = &"shieldwall_bash"
	_refresh_bash_hitbox_layout()
	_bash_hitbox.activate(packet, bash_lunge_sec + 0.05)


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"bp": _bash_phase,
		"be": _bash_elapsed,
		"sf": _shield_facing,
		"bd": _bash_dir,
		"cd": _bash_cooldown_rem,
		"ex": Time.get_ticks_msec() < _exposed_until_msec,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_bash_phase = int(state.get("bp", _bash_phase)) as BashPhase
	_bash_elapsed = maxf(0.0, float(state.get("be", 0.0)))
	var sf_v: Variant = state.get("sf", _shield_facing)
	if sf_v is Vector2:
		var sf := sf_v as Vector2
		if sf.length_squared() > 0.0001:
			_shield_facing = sf.normalized()
	var bd_v: Variant = state.get("bd", _bash_dir)
	if bd_v is Vector2:
		var bd := bd_v as Vector2
		if bd.length_squared() > 0.0001:
			_bash_dir = bd.normalized()
	_bash_cooldown_rem = maxf(0.0, float(state.get("cd", 0.0)))
	_remote_exposed = bool(state.get("ex", false))


func _refresh_target_player(delta: float, allow_retarget: bool = true) -> void:
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		allow_retarget
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(
		refresh.get("refresh_time_remaining", _target_refresh_time_remaining)
	)


func _sync_visual() -> void:
	if _visual == null:
		return
	var shake_progress := (
		clampf(_bash_elapsed / maxf(0.01, bash_windup_sec), 0.0, 1.0)
		if _bash_phase == BashPhase.WINDUP
		else 0.0
	)
	_visual.set_attack_shake_progress(shake_progress)
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	var moving := velocity.length_squared() > 0.04
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _shield_facing)
	_update_exposed_indicator()
	_update_bash_telegraph_visual()


func _should_use_high_detail_visuals() -> bool:
	if _bash_phase != BashPhase.IDLE:
		return true
	if _target_player != null and is_instance_valid(_target_player):
		return global_position.distance_squared_to(_target_player.global_position) <= 20.0 * 20.0
	return velocity.length_squared() > 0.04


func _create_exposed_indicator(parent: Node3D) -> void:
	_exposed_indicator_mesh = MeshInstance3D.new()
	_exposed_indicator_mesh.name = &"ShieldwallExposedIndicator"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.42
	mesh.outer_radius = 0.62
	_exposed_indicator_mesh.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.82, 0.24, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.9, 0.3, 1.0)
	material.emission_energy_multiplier = 1.8
	_exposed_indicator_mesh.material_override = material
	_exposed_indicator_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_exposed_indicator_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_exposed_indicator_mesh.visible = false
	parent.add_child(_exposed_indicator_mesh)


func _create_bash_telegraph_meshes(parent: Node3D) -> void:
	_telegraph_outline_mat = FlowTelegraphArrowMeshScript.create_outline_material(Color(0.02, 0.02, 0.02, 1.0))
	_telegraph_fill_mat = FlowTelegraphArrowMeshScript.create_fill_material(Color(0.75, 0.62, 0.2, 0.72))
	_telegraph_arrow_mesh = MeshInstance3D.new()
	_telegraph_arrow_mesh.name = &"ShieldwallBashArrow"
	_telegraph_arrow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_arrow_mesh.visible = false
	parent.add_child(_telegraph_arrow_mesh)

	_telegraph_circle_mesh = MeshInstance3D.new()
	_telegraph_circle_mesh.name = &"ShieldwallBashCircle"
	_telegraph_circle_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_circle_mesh.visible = false
	parent.add_child(_telegraph_circle_mesh)


func _update_bash_telegraph_visual() -> void:
	var active := _bash_phase == BashPhase.WINDUP
	if _telegraph_arrow_mesh != null and is_instance_valid(_telegraph_arrow_mesh):
		_telegraph_arrow_mesh.visible = active
	if _telegraph_circle_mesh != null and is_instance_valid(_telegraph_circle_mesh):
		_telegraph_circle_mesh.visible = active
	if not active:
		return
	var progress := clampf(_bash_elapsed / maxf(0.01, bash_windup_sec), 0.0, 1.0)
	var dir := _bash_dir.normalized() if _bash_dir.length_squared() > 0.0001 else _shield_facing.normalized()
	if dir.length_squared() <= 0.0001:
		dir = Vector2(0.0, -1.0)
	if _telegraph_arrow_mesh != null and is_instance_valid(_telegraph_arrow_mesh):
		_telegraph_arrow_mesh.global_position = Vector3(global_position.x, bash_telegraph_ground_y, global_position.y)
		_telegraph_arrow_mesh.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
		var arrow_step := int(round(progress * 12.0))
		_telegraph_arrow_mesh.mesh = FlowTelegraphArrowMeshScript.build_mesh_for_step(
			arrow_step,
			12,
			bash_arrow_length,
			bash_arrow_head_length,
			bash_arrow_half_width,
			_telegraph_outline_mat,
			_telegraph_fill_mat
		)
	if _telegraph_circle_mesh != null and is_instance_valid(_telegraph_circle_mesh):
		var impact_center := global_position + dir * bash_lunge_distance
		_telegraph_circle_mesh.global_position = Vector3(impact_center.x, bash_telegraph_ground_y, impact_center.y)
		_telegraph_circle_mesh.rotation = Vector3.ZERO
		_telegraph_circle_mesh.mesh = GroundAoeTelegraphMeshScript.build_expanding_circle_mesh(
			progress,
			bash_circle_radius,
			20,
			_telegraph_outline_mat,
			_telegraph_fill_mat
		)


func _is_exposed_active() -> bool:
	if not is_damage_authority():
		return _remote_exposed
	return Time.get_ticks_msec() < _exposed_until_msec


func _update_exposed_indicator() -> void:
	if _exposed_indicator_mesh == null or not is_instance_valid(_exposed_indicator_mesh):
		return
	var active := _is_exposed_active()
	_exposed_indicator_mesh.visible = active
	if not active:
		return
	_exposed_indicator_mesh.global_position = Vector3(global_position.x, mesh_ground_y + 2.4, global_position.y)
	var t := float(Time.get_ticks_msec()) * 0.001
	_exposed_indicator_mesh.scale = Vector3.ONE * (0.9 + sin(t * 5.2) * 0.08)
