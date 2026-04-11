class_name DetonatorMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const SurgeExplosionHelperScript = preload("res://scripts/entities/surge_explosion_helper.gd")
const MODEL_SCENE := preload("res://art/characters/enemies/Detonator.glb")
const FIZZLER_KIND := 18

enum State { ADVANCE, VENT_WINDOW, DEATH_SEQUENCE }

@export var min_speed := 2.5
@export var max_speed := 3.5
@export var speed_scale := 1.0
@export var stop_distance := 1.35
@export var repath_interval := 0.28
@export var target_refresh_interval := 0.4
@export var spawn_interval := 5.0
@export var vent_interval := 10.0
@export var vent_duration := 1.5
@export var max_active_fizzlers := 6
@export var death_sequence_duration := 0.18
@export var death_explosion_radius := 7.0
@export var death_explosion_damage := 80
@export var death_explosion_knockback := 34.0
@export var vent_damage_multiplier := 2.0
@export var mesh_ground_y := 0.18
@export var mesh_scale := Vector3(1.35, 1.35, 1.35)
@export var edge_clip_scale := 2.35
@export var spawn_offsets: Array[Vector2] = [
	Vector2(0.95, -0.55),
	Vector2(-0.95, -0.4),
	Vector2(0.72, 0.82),
	Vector2(-0.78, 0.7),
]

var _visual: EnemyStateVisual
var _spawn_start := Vector2.ZERO
var _spawn_target := Vector2.ZERO
var _has_spawn := false
var _speed_multiplier := 1.0
var _move_speed := 3.0
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _aggro_enabled := true
var _state := State.ADVANCE
var _planar_facing := Vector2(0.0, -1.0)
var _spawn_time_remaining := 0.0
var _vent_time_remaining := 0.0
var _vent_cooldown_remaining := 0.0
var _death_time_remaining := 0.0
var _spawned_fizzler_ids: Array[int] = []
var _exploded := false
var _explosion_visual_played := false
var _glow_mesh: MeshInstance3D
var _glow_material: StandardMaterial3D
var _vent_mesh: MeshInstance3D
var _vent_material: StandardMaterial3D
var _spawn_marker_offsets: Array[Vector2] = []
var _spawn_marker_cursor := 0

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func set_aggro_enabled(enabled: bool) -> void:
	var was_aggro_enabled := _aggro_enabled
	_aggro_enabled = enabled
	if not enabled and _state != State.DEATH_SEQUENCE:
		velocity = Vector2.ZERO
	elif enabled and not was_aggro_enabled and _state != State.DEATH_SEQUENCE:
		_spawn_time_remaining = 0.0


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func surge_allows_incoming_damage(_packet: DamagePacket) -> bool:
	return _state != State.DEATH_SEQUENCE


func surge_damage_taken_multiplier(_packet: DamagePacket) -> float:
	return vent_damage_multiplier if _state == State.VENT_WINDOW else 1.0


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Detonator entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	_move_speed = randf_range(min_speed, max_speed) * speed_scale
	var initial_dir := _spawn_target - _spawn_start
	if initial_dir.length_squared() > 0.0001:
		_planar_facing = initial_dir.normalized()
	_spawn_time_remaining = 0.0 if _aggro_enabled else spawn_interval
	_vent_cooldown_remaining = vent_interval
	_collect_spawn_offsets()
	_create_visuals()
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.8
		_nav_agent.target_desired_distance = stop_distance
		_nav_agent.avoidance_enabled = false
	_sync_visual()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _glow_mesh != null and is_instance_valid(_glow_mesh):
		_glow_mesh.queue_free()
	if _vent_mesh != null and is_instance_valid(_vent_mesh):
		_vent_mesh.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual()
		return
	surge_infusion_tick_server_field_decay()
	if _state == State.DEATH_SEQUENCE:
		velocity = Vector2.ZERO
		_death_time_remaining = maxf(0.0, _death_time_remaining - delta)
		if _death_time_remaining <= 0.0:
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
	_tick_spawn_cycle(delta)
	_tick_vent_cycle(delta)
	_update_advance_velocity(delta)
	ignore_player_body_collisions()
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"st": _state,
		"vc": _vent_cooldown_remaining,
		"vt": _vent_time_remaining,
		"sp": _spawn_time_remaining,
		"dt": _death_time_remaining,
		"pf": _planar_facing,
		"fc": _spawned_fizzler_ids.size(),
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	var next_state := int(state.get("st", _state)) as State
	_vent_cooldown_remaining = maxf(0.0, float(state.get("vc", _vent_cooldown_remaining)))
	_vent_time_remaining = maxf(0.0, float(state.get("vt", _vent_time_remaining)))
	_spawn_time_remaining = maxf(0.0, float(state.get("sp", _spawn_time_remaining)))
	_death_time_remaining = maxf(0.0, float(state.get("dt", _death_time_remaining)))
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()
	if next_state != _state:
		_state = next_state
		if _state == State.DEATH_SEQUENCE:
			_play_local_explosion_visual()


func explode() -> void:
	if not is_damage_authority() or _exploded:
		return
	_exploded = true
	_play_local_explosion_visual()
	SurgeExplosionHelperScript.apply_explosion(
		self,
		global_position,
		death_explosion_radius,
		death_explosion_damage,
		death_explosion_knockback,
		true,
		true,
		true,
		Color(1.0, 0.92, 0.82, 0.9),
		2.0
	)


func enter_vent_window() -> void:
	if _state == State.DEATH_SEQUENCE:
		return
	_state = State.VENT_WINDOW
	_vent_time_remaining = vent_duration


func spawn_fizzler() -> void:
	if not is_damage_authority():
		return
	_prune_spawned_fizzlers()
	if _spawned_fizzler_ids.size() >= max_active_fizzlers:
		return
	var orchestrator := _runtime_orchestrator()
	if orchestrator == null:
		return
	var encounter_id := StringName(get_meta(&"encounter_id", &""))
	var spawn_pos := _resolve_spawn_position()
	var target_pos := (
		_target_player.global_position
		if _target_player != null and is_instance_valid(_target_player)
		else global_position + _planar_facing * 2.0
	)
	var child_v: Variant = orchestrator.call(
		&"spawn_runtime_enemy_by_kind",
		encounter_id,
		FIZZLER_KIND,
		spawn_pos,
		target_pos,
		1.0,
		_aggro_enabled
	)
	if child_v is EnemyBase and is_instance_valid(child_v):
		_spawned_fizzler_ids.append((child_v as EnemyBase).get_instance_id())


func _should_defer_death(_packet: DamagePacket) -> bool:
	return _state != State.DEATH_SEQUENCE


func _begin_deferred_death(_packet: DamagePacket) -> void:
	_state = State.DEATH_SEQUENCE
	_death_time_remaining = death_sequence_duration
	velocity = Vector2.ZERO
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	if _hurtbox != null:
		_hurtbox.set_active(false)
	explode()


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	pass


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


func _tick_spawn_cycle(delta: float) -> void:
	_prune_spawned_fizzlers()
	var tick_scale := surge_infusion_field_cooldown_tick_factor()
	_spawn_time_remaining = maxf(0.0, _spawn_time_remaining - delta * tick_scale)
	if _spawn_time_remaining <= 0.0:
		_spawn_time_remaining = spawn_interval
		spawn_fizzler()


func _tick_vent_cycle(delta: float) -> void:
	var tick_scale := surge_infusion_field_cooldown_tick_factor()
	if _state == State.VENT_WINDOW:
		_vent_time_remaining = maxf(0.0, _vent_time_remaining - delta * tick_scale)
		if _vent_time_remaining <= 0.0:
			_state = State.ADVANCE
			_vent_cooldown_remaining = vent_interval
		return
	_vent_cooldown_remaining = maxf(0.0, _vent_cooldown_remaining - delta * tick_scale)
	if _vent_cooldown_remaining <= 0.0:
		enter_vent_window()


func _update_advance_velocity(delta: float) -> void:
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


func _collect_spawn_offsets() -> void:
	_spawn_marker_offsets.clear()
	for child in get_children():
		if child is Marker2D and String(child.name).to_lower().contains("spawn"):
			_spawn_marker_offsets.append((child as Marker2D).position)
		elif child is Node2D and String(child.name).to_lower().contains("spawn"):
			_spawn_marker_offsets.append((child as Node2D).position)
	if _spawn_marker_offsets.is_empty():
		_spawn_marker_offsets = spawn_offsets.duplicate()
	if _spawn_marker_offsets.is_empty():
		_spawn_marker_offsets = [Vector2(1.0, 0.0)]


func _resolve_spawn_position() -> Vector2:
	if _spawn_marker_offsets.is_empty():
		return global_position
	var local_offset := _spawn_marker_offsets[_spawn_marker_cursor % _spawn_marker_offsets.size()]
	_spawn_marker_cursor += 1
	return global_position + local_offset.rotated(_planar_facing.angle() + PI * 0.5)


func _prune_spawned_fizzlers() -> void:
	var next_ids: Array[int] = []
	for id in _spawned_fizzler_ids:
		var inst := instance_from_id(id)
		if inst is FizzlerMob and is_instance_valid(inst):
			next_ids.append(id)
	_spawned_fizzler_ids = next_ids


func _runtime_orchestrator() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


func _create_visuals() -> void:
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	_visual = EnemyStateVisualScript.new()
	_visual.name = &"DetonatorVisual"
	_visual.mesh_ground_y = mesh_ground_y
	_visual.mesh_scale = mesh_scale
	_visual.facing_yaw_offset_deg = 0.0
	_visual.configure_states(build_single_scene_visual_state_config(MODEL_SCENE, edge_clip_scale))
	vw.add_child(_visual)
	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.name = &"DetonatorGlow"
	var sphere := SphereMesh.new()
	sphere.radius = 1.05
	sphere.height = 2.1
	_glow_mesh.mesh = sphere
	_glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.emission_enabled = true
	_glow_mesh.material_override = _glow_material
	vw.add_child(_glow_mesh)
	_vent_mesh = MeshInstance3D.new()
	_vent_mesh.name = &"DetonatorVent"
	var ring := CylinderMesh.new()
	ring.top_radius = 1.3
	ring.bottom_radius = 1.3
	ring.height = 0.16
	ring.radial_segments = 36
	_vent_mesh.mesh = ring
	_vent_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vent_material = StandardMaterial3D.new()
	_vent_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_vent_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_vent_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vent_material.emission_enabled = true
	_vent_mesh.material_override = _vent_material
	vw.add_child(_vent_mesh)


func _sync_visual() -> void:
	if _visual != null:
		_visual.set_high_detail_enabled(true)
		var shake := 0.2
		if _state == State.VENT_WINDOW:
			shake = 0.85
		elif _state == State.DEATH_SEQUENCE:
			shake = 1.0
		_visual.set_attack_shake_progress(shake)
		_visual.set_state(&"walk" if velocity.length_squared() > 0.02 else &"idle")
		_visual.sync_from_2d(global_position, _planar_facing)
	if _glow_mesh != null and _glow_material != null:
		var vent_progress := (
			clampf(_vent_time_remaining / maxf(0.01, vent_duration), 0.0, 1.0)
			if _state == State.VENT_WINDOW
			else 0.0
		)
		var pulse_rate := 1.8 if _state != State.VENT_WINDOW else 9.0
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * pulse_rate * TAU)
		var intensity := 0.45 + pulse * 0.25 + vent_progress * 1.1
		if _state == State.DEATH_SEQUENCE:
			intensity = 2.35
		_glow_mesh.global_position = Vector3(global_position.x, mesh_ground_y + 1.15, global_position.y)
		_glow_mesh.scale = Vector3.ONE * (1.0 + intensity * 0.16)
		var color := (
			Color(1.0, 0.98, 0.92, 0.42 + intensity * 0.1)
			if _state == State.VENT_WINDOW or _state == State.DEATH_SEQUENCE
			else Color(1.0, 0.45, 0.16, 0.18 + intensity * 0.1)
		)
		_glow_material.albedo_color = color
		_glow_material.emission = color
		_glow_material.emission_energy_multiplier = 1.1 + intensity * 2.2
	if _vent_mesh != null and _vent_material != null:
		var vent_strength := (
			1.0 - clampf(_vent_time_remaining / maxf(0.01, vent_duration), 0.0, 1.0)
			if _state == State.VENT_WINDOW
			else 0.0
		)
		var death_strength := 1.0 if _state == State.DEATH_SEQUENCE else 0.0
		var strength := maxf(vent_strength, death_strength)
		_vent_mesh.visible = strength > 0.001
		_vent_mesh.global_position = Vector3(global_position.x, 0.08, global_position.y)
		_vent_mesh.scale = Vector3.ONE * (1.1 + strength * 2.6)
		var vent_color := Color(1.0, 1.0, 1.0, 0.18 + strength * 0.26)
		_vent_material.albedo_color = vent_color
		_vent_material.emission = vent_color
		_vent_material.emission_energy_multiplier = 1.4 + strength * 2.8


func _play_local_explosion_visual() -> void:
	if _explosion_visual_played:
		return
	_explosion_visual_played = true
	SurgeExplosionHelperScript.play_explosion_visual(
		self,
		global_position,
		death_explosion_radius,
		Color(1.0, 0.92, 0.82, 0.9),
		2.0
	)
