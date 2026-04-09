class_name BursterMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const SurgeExplosionHelperScript = preload("res://scripts/entities/surge_explosion_helper.gd")
const MODEL_SCENE := preload("res://art/characters/enemies/Burster.glb")

enum State { CHASE, CHARGING, DETONATE, RESET }

@export var min_speed := 7.0
@export var max_speed := 10.0
@export var speed_scale := 0.88
@export var stop_distance := 0.95
@export var repath_interval := 0.22
@export var target_refresh_interval := 0.35
@export var full_charge_time := 7.0
@export var interrupt_damage_threshold := 15
@export var reset_flash_duration := 0.45
@export var detonation_duration := 0.14
@export var explosion_radius := 4.0
@export var explosion_damage := 50
@export var explosion_knockback := 24.0
@export var instability_knockback_multiplier := 1.35
@export var mesh_ground_y := 0.13
@export var mesh_scale := Vector3(1.08, 1.08, 1.08)
@export var edge_clip_scale := 2.5

var _visual: EnemyStateVisual
var _spawn_start := Vector2.ZERO
var _spawn_target := Vector2.ZERO
var _has_spawn := false
var _speed_multiplier := 1.0
var _move_speed := 9.0
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _aggro_enabled := true
var _state := State.CHASE
var _charge_progress := 0.0
var _reset_flash_time_remaining := 0.0
var _detonation_time_remaining := 0.0
var _planar_facing := Vector2(0.0, -1.0)
var _exploded := false
var _explosion_visual_played := false
var _glow_mesh: MeshInstance3D
var _glow_material: StandardMaterial3D

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not enabled and _state != State.DETONATE:
		velocity = Vector2.ZERO


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Burster entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	_move_speed = randf_range(min_speed, max_speed) * speed_scale
	var initial_dir := _spawn_target - _spawn_start
	if initial_dir.length_squared() > 0.0001:
		_planar_facing = initial_dir.normalized()
	_create_visuals()
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = stop_distance
		_nav_agent.avoidance_enabled = false
	_sync_visual()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _glow_mesh != null and is_instance_valid(_glow_mesh):
		_glow_mesh.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual()
		return
	surge_infusion_tick_server_field_decay()
	if _state == State.DETONATE:
		velocity = Vector2.ZERO
		_detonation_time_remaining = maxf(0.0, _detonation_time_remaining - delta)
		if _detonation_time_remaining <= 0.0:
			squash()
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		move_and_slide_with_mob_separation()
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	_refresh_target_player(delta)
	_update_charge(delta)
	_update_chase_velocity(delta)
	ignore_player_body_collisions()
	apply_hit_knockback_to_body_velocity()
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"st": _state,
		"cp": _charge_progress,
		"rf": _reset_flash_time_remaining,
		"dt": _detonation_time_remaining,
		"pf": _planar_facing,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	var next_state := int(state.get("st", _state)) as State
	_charge_progress = clampf(float(state.get("cp", _charge_progress)), 0.0, 1.0)
	_reset_flash_time_remaining = maxf(0.0, float(state.get("rf", _reset_flash_time_remaining)))
	_detonation_time_remaining = maxf(0.0, float(state.get("dt", _detonation_time_remaining)))
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()
	if next_state != _state:
		_state = next_state
		if _state == State.DETONATE:
			_play_local_explosion_visual()


func trigger_chain_reaction(_source_position: Vector2) -> void:
	if not is_damage_authority():
		return
	_enter_detonate()


func explode() -> void:
	if not is_damage_authority() or _exploded:
		return
	_exploded = true
	_play_local_explosion_visual()
	SurgeExplosionHelperScript.apply_explosion(
		self,
		global_position,
		explosion_radius,
		explosion_damage,
		explosion_knockback,
		true,
		true,
		false,
		Color(1.0, 0.68, 0.22, 0.8),
		1.5
	)


func reset_charge() -> void:
	_charge_progress = 0.0
	_reset_flash_time_remaining = reset_flash_duration
	if _state != State.DETONATE:
		_state = State.RESET


func _should_defer_death(_packet: DamagePacket) -> bool:
	return _state != State.DETONATE


func _begin_deferred_death(_packet: DamagePacket) -> void:
	_enter_detonate()


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, hurtbox_area: Area2D) -> void:
	super._on_receiver_damage_applied(packet, hp_damage, hurtbox_area)
	if not is_damage_authority() or hp_damage <= 0 or _state == State.DETONATE:
		return
	if hp_damage > interrupt_damage_threshold:
		reset_charge()


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	super._on_nonlethal_hit(knockback_dir, knockback_strength * instability_knockback_multiplier)


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
	_target_refresh_time_remaining = float(
		refresh.get("refresh_time_remaining", _target_refresh_time_remaining)
	)


func _update_charge(delta: float) -> void:
	if _state == State.DETONATE:
		return
	if _reset_flash_time_remaining > 0.0:
		_reset_flash_time_remaining = maxf(0.0, _reset_flash_time_remaining - delta)
		if _reset_flash_time_remaining <= 0.0:
			_state = State.CHARGING
	var charge_delta := delta / maxf(0.01, full_charge_time)
	charge_delta *= surge_infusion_field_cooldown_tick_factor()
	_charge_progress = clampf(_charge_progress + charge_delta, 0.0, 1.0)
	if _charge_progress >= 1.0:
		_enter_detonate()
	elif _state != State.RESET:
		_state = State.CHARGING


func _update_chase_velocity(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player) or _is_player_downed_node(_target_player):
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
		if to_next.length_squared() > 0.0001:
			desired = to_next.normalized()
	if desired.length_squared() <= 0.0001:
		var to_player := _target_player.global_position - global_position
		if to_player.length_squared() > 0.0001:
			desired = to_player.normalized()
	if desired.length_squared() <= 0.0001:
		velocity = Vector2.ZERO
		return
	_planar_facing = desired.normalized()
	var speed := _move_speed * _speed_multiplier * surge_infusion_field_move_speed_factor()
	velocity = _planar_facing * speed


func _enter_detonate() -> void:
	if _state == State.DETONATE:
		return
	_state = State.DETONATE
	_detonation_time_remaining = detonation_duration
	velocity = Vector2.ZERO
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	if _hurtbox != null:
		_hurtbox.set_active(false)
	explode()


func _create_visuals() -> void:
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	_visual = EnemyStateVisualScript.new()
	_visual.name = &"BursterVisual"
	_visual.mesh_ground_y = mesh_ground_y
	_visual.mesh_scale = mesh_scale
	_visual.facing_yaw_offset_deg = 0.0
	_visual.configure_states(build_single_scene_visual_state_config(MODEL_SCENE, edge_clip_scale))
	vw.add_child(_visual)
	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.name = &"BursterGlow"
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	_glow_mesh.mesh = sphere
	_glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.emission_enabled = true
	_glow_mesh.material_override = _glow_material
	vw.add_child(_glow_mesh)


func _sync_visual() -> void:
	if _visual != null:
		_visual.set_high_detail_enabled(true)
		var shake := 0.0
		if _state == State.DETONATE:
			shake = 1.0
		elif _state == State.RESET:
			shake = 0.65
		else:
			shake = _charge_progress
		_visual.set_attack_shake_progress(shake)
		_visual.set_state(&"walk" if velocity.length_squared() > 0.02 else &"idle")
		_visual.sync_from_2d(global_position, _planar_facing)
	if _glow_mesh == null or _glow_material == null:
		return
	var pulse_rate := 4.5 + _charge_progress * 10.0
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * pulse_rate * TAU)
	var cracked_boost := 0.35 if _charge_progress >= 0.66 else 0.0
	var intensity := clampf(0.2 + _charge_progress * 1.4 + pulse * 0.35 + cracked_boost, 0.0, 2.1)
	if _state == State.RESET:
		intensity = 0.95 + pulse * 0.55
	if _state == State.DETONATE:
		intensity = 2.3
	_glow_mesh.global_position = Vector3(global_position.x, mesh_ground_y + 0.85, global_position.y)
	_glow_mesh.scale = Vector3.ONE * (0.82 + intensity * 0.18)
	var alpha := 0.14 + intensity * 0.13
	var color := Color(1.0, 0.42 + _charge_progress * 0.48, 0.12, clampf(alpha, 0.12, 0.62))
	_glow_material.albedo_color = color
	_glow_material.emission = color
	_glow_material.emission_energy_multiplier = 0.8 + intensity * 2.3


func _play_local_explosion_visual() -> void:
	if _explosion_visual_played:
		return
	_explosion_visual_played = true
	SurgeExplosionHelperScript.play_explosion_visual(
		self,
		global_position,
		explosion_radius,
		Color(1.0, 0.68, 0.22, 0.8),
		1.5
	)
