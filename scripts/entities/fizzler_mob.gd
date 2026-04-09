class_name FizzlerMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const SurgeExplosionHelperScript = preload("res://scripts/entities/surge_explosion_helper.gd")
const MODEL_SCENE := preload("res://art/characters/enemies/Fizzler.glb")

enum State { SEEK, DETONATE }

@export var min_speed := 14.0
@export var max_speed := 18.0
@export var speed_scale := 1.0
@export var target_refresh_interval := 0.2
@export var explosion_radius := 1.5
@export var explosion_damage := 12
@export var explosion_knockback := 16.0
@export var detonation_duration := 0.12
@export var mesh_ground_y := 0.08
@export var mesh_scale := Vector3(0.85, 0.85, 0.85)
@export var edge_clip_scale := 2.8

var _visual: EnemyStateVisual
var _spawn_start := Vector2.ZERO
var _spawn_target := Vector2.ZERO
var _has_spawn := false
var _speed_multiplier := 1.0
var _move_speed := 18.0
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _aggro_enabled := true
var _state := State.SEEK
var _detonation_time_remaining := 0.0
var _planar_facing := Vector2(0.0, -1.0)
var _exploded := false
var _explosion_visual_played := false
var _glow_mesh: MeshInstance3D
var _glow_material: StandardMaterial3D


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not enabled and _state == State.SEEK:
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
		push_warning("Fizzler entered tree without configure_spawn; removing.")
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
	_update_seek_velocity()
	move_and_slide_with_mob_separation()
	if _hit_trigger_surface_this_frame():
		_enter_detonate()
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"st": _state,
		"dt": _detonation_time_remaining,
		"pf": _planar_facing,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	var next_state := int(state.get("st", _state)) as State
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
		Color(1.0, 0.55, 0.18, 0.72),
		1.1
	)


func _should_defer_death(_packet: DamagePacket) -> bool:
	return _state != State.DETONATE


func _begin_deferred_death(_packet: DamagePacket) -> void:
	_enter_detonate()


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


func _update_seek_velocity() -> void:
	var desired := _planar_facing
	if _target_player != null and is_instance_valid(_target_player) and not _is_player_downed_node(_target_player):
		var to_player := _target_player.global_position - global_position
		if to_player.length_squared() > 0.0001:
			desired = to_player.normalized()
	if desired.length_squared() <= 0.0001:
		desired = Vector2(0.0, -1.0)
	_planar_facing = desired.normalized()
	velocity = _planar_facing * _move_speed * _speed_multiplier * surge_infusion_field_move_speed_factor()


func _hit_trigger_surface_this_frame() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var collider: Variant = collision.get_collider()
		if collider is Area2D:
			continue
		return true
	return false


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
	_visual.name = &"FizzlerVisual"
	_visual.mesh_ground_y = mesh_ground_y
	_visual.mesh_scale = mesh_scale
	_visual.facing_yaw_offset_deg = 0.0
	_visual.configure_states(build_single_scene_visual_state_config(MODEL_SCENE, edge_clip_scale))
	vw.add_child(_visual)
	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.name = &"FizzlerGlow"
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
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
		_visual.set_attack_shake_progress(1.0 if _state == State.DETONATE else 0.0)
		_visual.set_state(&"walk" if velocity.length_squared() > 0.02 else &"idle")
		_visual.sync_from_2d(global_position, _planar_facing)
	if _glow_mesh == null or _glow_material == null:
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.016)
	var intensity := 1.0 if _state == State.DETONATE else (0.35 + pulse * 0.45)
	_glow_mesh.global_position = Vector3(global_position.x, mesh_ground_y + 0.55, global_position.y)
	_glow_mesh.scale = Vector3.ONE * (0.65 + intensity * 0.35)
	var color := Color(1.0, 0.4 + intensity * 0.35, 0.08, 0.18 + intensity * 0.28)
	_glow_material.albedo_color = color
	_glow_material.emission = color
	_glow_material.emission_energy_multiplier = 1.0 + intensity * 2.8


func _play_local_explosion_visual() -> void:
	if _explosion_visual_played:
		return
	_explosion_visual_played = true
	SurgeExplosionHelperScript.play_explosion_visual(
		self,
		global_position,
		explosion_radius,
		Color(1.0, 0.55, 0.18, 0.72),
		1.1
	)
