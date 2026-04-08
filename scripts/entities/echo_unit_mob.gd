extends EnemyBase
class_name EchoUnitMob

const ArrowProjectilePoolScript = preload("res://scripts/entities/arrow_projectile_pool.gd")
const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const EchoGrowthScript = preload("res://scripts/entities/echo_spawn_growth.gd")
const MODEL_SCENE := preload("res://art/characters/enemies/Triad.glb")

enum EchoUnitMode {
	RUSHER = 0,
	SHOOTER = 1,
}

@export var mode: EchoUnitMode = EchoUnitMode.RUSHER
@export var move_speed := 8.5
@export var rush_stop_distance := 1.45
@export var ranged_preferred_distance := 6.8
@export var ranged_backoff_distance := 4.6
@export var target_refresh_interval := 0.3
@export var repath_interval := 0.18
@export var contact_damage := 9
@export var contact_repeat_sec := 0.55
@export var projectile_damage := 8
@export var projectile_speed := 16.0
@export var projectile_max_distance := 8.0
@export var projectile_spawn_distance := 0.9
@export var projectile_cooldown := 1.35
@export var projectile_count := 2
@export var projectile_total_spread_degrees := 18.0
@export var mesh_ground_y := .8
@export var mesh_scale := Vector3(1.0, 1.0, 1.0)
@export var visual_scene_scale := 1.25
@export var spawn_growth_duration := 0.65
@export var spawn_final_visual_scale := 0.5
@export var turn_toward_target_deg_per_sec := 240.0

var _visual: EnemyStateVisual
var _vw: Node3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _cooldown_remaining := 0.0
var _aggro_enabled := true
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn := false
var _planar_facing := Vector2(0.0, -1.0)
var _growth = EchoGrowthScript.new()
var _growth_scale := 0.5

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _body_contact_hitbox: Hitbox2D = $BodyContactHitbox


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		if _body_contact_hitbox != null:
			_body_contact_hitbox.deactivate()


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Echo unit entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	var to_target := _spawn_target - _spawn_start
	_planar_facing = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	_vw = _resolve_visual_world_3d()
	if _vw != null:
		_visual = EnemyStateVisualScript.new()
		_visual.name = &"EchoUnitVisual"
		_visual.mesh_ground_y = mesh_ground_y
		_visual.mesh_scale = mesh_scale * spawn_final_visual_scale
		_visual.facing_yaw_offset_deg = 0.0
		_visual.configure_states(build_single_scene_visual_state_config(MODEL_SCENE, visual_scene_scale))
		_vw.add_child(_visual)
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.65
		_nav_agent.target_desired_distance = rush_stop_distance
		_nav_agent.avoidance_enabled = false
	_growth.begin(spawn_growth_duration, spawn_final_visual_scale)
	_growth_scale = _growth.start_scale
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0
	_activate_or_deactivate_contact_hitbox(false)
	_sync_visual()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual()
		return
	surge_infusion_tick_server_field_decay()
	_growth_scale = _growth.tick(delta)
	var can_act := bool(_growth.is_complete()) and _aggro_enabled
	_activate_or_deactivate_contact_hitbox(can_act and mode == EchoUnitMode.RUSHER)
	if not can_act:
		velocity = Vector2.ZERO
		move_and_slide_with_mob_separation()
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	_refresh_target_player(delta)
	ignore_player_body_collisions()
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
	else:
		match mode:
			EchoUnitMode.RUSHER:
				_update_rusher(delta)
			EchoUnitMode.SHOOTER:
				_update_shooter(delta)
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"md": int(mode),
		"pf": _planar_facing,
		"gr": _growth_scale,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	mode = int(state.get("md", int(mode))) as EchoUnitMode
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()
	_growth_scale = clampf(float(state.get("gr", _growth_scale)), 0.05, spawn_final_visual_scale)


func _activate_or_deactivate_contact_hitbox(active: bool) -> void:
	if _body_contact_hitbox == null:
		return
	if not active or not is_damage_authority():
		_body_contact_hitbox.deactivate()
		return
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.amount = contact_damage
	pkt.kind = &"contact"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = global_position
	pkt.direction = _planar_facing
	pkt.knockback = 0.0
	pkt.apply_iframes = true
	pkt.blockable = true
	pkt.debug_label = &"echo_unit_contact"
	_body_contact_hitbox.repeat_mode = Hitbox2D.RepeatMode.INTERVAL
	_body_contact_hitbox.repeat_interval_sec = contact_repeat_sec
	_body_contact_hitbox.activate(pkt, -1.0)


func _refresh_target_player(delta: float) -> void:
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		true,
		Callable(self, "_pick_nearest_player_target")
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(refresh.get("refresh_time_remaining", _target_refresh_time_remaining))


func _update_rusher(_delta: float) -> void:
	var to_target := _target_player.global_position - global_position
	if to_target.length_squared() <= rush_stop_distance * rush_stop_distance:
		velocity = Vector2.ZERO
		return
	var desired := to_target.normalized()
	velocity = desired * move_speed * surge_infusion_field_move_speed_factor()
	_planar_facing = desired


func _update_shooter(delta: float) -> void:
	var to_target := _target_player.global_position - global_position
	var distance := to_target.length()
	var desired := Vector2.ZERO
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent != null and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	if distance > ranged_preferred_distance:
		desired = to_target.normalized()
	elif distance < ranged_backoff_distance and to_target.length_squared() > 0.0001:
		desired = -to_target.normalized()
	velocity = desired * move_speed * 0.82 * surge_infusion_field_move_speed_factor()
	if to_target.length_squared() > 0.0001:
		var max_step := deg_to_rad(turn_toward_target_deg_per_sec) * delta
		_planar_facing = step_planar_facing_toward(_planar_facing, to_target.normalized(), max_step)
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta * surge_infusion_field_cooldown_tick_factor())
	if _cooldown_remaining <= 0.0 and distance <= projectile_max_distance:
		_fire_projectiles(_planar_facing)
		_cooldown_remaining = projectile_cooldown


func _fire_projectiles(direction: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spawn_position := global_position + direction.normalized() * projectile_spawn_distance
	for projectile_index in range(projectile_count):
		var dir := _volley_direction_for(direction, projectile_index)
		var projectile := ArrowProjectilePoolScript.acquire_projectile(parent)
		if projectile == null:
			continue
		projectile.speed = projectile_speed
		projectile.max_distance = projectile_max_distance
		projectile.damage = projectile_damage
		projectile.mesh_scale = Vector3(1.0, 1.0, 1.0) * 0.65
		if projectile.has_method(&"set_authoritative_damage"):
			projectile.call(&"set_authoritative_damage", is_damage_authority())
		projectile.configure(spawn_position, dir, _vw, false, &"purple")


func _volley_direction_for(base_direction: Vector2, projectile_index: int) -> Vector2:
	var dir := base_direction.normalized() if base_direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	if projectile_count <= 1:
		return dir
	var total_spread := projectile_total_spread_degrees
	var start_deg := -total_spread * 0.5
	var step_deg := total_spread / float(maxi(1, projectile_count - 1))
	var offset_deg := start_deg + step_deg * float(projectile_index)
	return dir.rotated(deg_to_rad(offset_deg)).normalized()


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(true)
	var moving := velocity.length_squared() > 0.04
	_visual.mesh_scale = mesh_scale * _growth_scale
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _planar_facing)
