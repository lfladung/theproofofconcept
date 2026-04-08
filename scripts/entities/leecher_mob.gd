class_name LeecherMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")

enum PhaseState { CHASE, LATCH, DRAIN, DETACH }

@export var move_speed := 6.5
@export var latch_distance := 1.15
@export var target_refresh_interval := 0.3
@export var repath_interval := 0.2
@export var drain_per_second := 5.0
@export var max_total_drain := 30.0
@export var latch_attach_duration := 0.12
@export var detach_recovery_duration := 1.2
@export var break_free_presses := 5
@export var detach_hop_distance := 2.4
@export var materialize_distance := 10
@export var mesh_ground_y := 0.13
@export var mesh_scale := Vector3(1.05, 1.05, 1.05)
@export var edge_clip_scale := 2.45
@export var latch_beam_radius := 0.09
@export var latch_beam_height := 1.15
@export_range(0.0, 1.0, 0.05) var phased_transparency := 0.52
@export_range(0.0, 1.0, 0.05) var materialized_transparency := 0.0

var _visual: Node3D
var _vw: Node3D
var _phase := PhaseState.CHASE
var _phase_time_remaining := 0.0
var _target_player: Node2D
var _latched_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _drain_accumulator := 0.0
var _total_drained := 0.0
var _planar_facing := Vector2(0.0, -1.0)
var _distance_to_target := INF
var _is_materialized := false
var _beam_mesh: MeshInstance3D
var _beam_material: StandardMaterial3D
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func get_shadow_visual_root() -> Node3D:
	return _visual


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func _ready() -> void:
	super._ready()
	_vw = get_node_or_null("../../VisualWorld3D") as Node3D
	if _vw != null:
		var vis := EnemyStateVisualScript.new()
		vis.name = &"LeecherVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		_vw.add_child(vis)
		_visual = vis
		_beam_mesh = MeshInstance3D.new()
		_beam_mesh.name = &"LeecherLatchBeam"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = latch_beam_radius
		cylinder.bottom_radius = latch_beam_radius
		cylinder.height = 1.0
		_beam_mesh.mesh = cylinder
		_beam_material = StandardMaterial3D.new()
		_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_material.albedo_color = Color(0.32, 1.0, 0.9, 0.72)
		_beam_material.emission_enabled = true
		_beam_material.emission = Color(0.4, 1.0, 0.92, 1.0)
		_beam_material.emission_energy_multiplier = 1.6
		_beam_mesh.material_override = _beam_material
		_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam_mesh.visible = false
		_vw.add_child(_beam_mesh)
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = 0.85
		_nav_agent.avoidance_enabled = false
	_apply_phase_collision_state()


func _exit_tree() -> void:
	_clear_latched_player_control()
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _beam_mesh != null and is_instance_valid(_beam_mesh):
		_beam_mesh.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_visuals()
		return
	_tick_server_state(delta)
	move_and_slide_with_mob_separation()
	_enemy_network_server_broadcast(delta)
	_update_visuals()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ph": _phase,
		"tr": maxf(0.0, _phase_time_remaining),
		"pf": _planar_facing,
		"li": _latched_player.get_instance_id() if _latched_player != null and is_instance_valid(_latched_player) else 0,
		"ep": _escape_progress_for_remote(),
		"td": _distance_to_target,
		"mat": 1 if _is_materialized else 0,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_phase = int(state.get("ph", _phase)) as PhaseState
	_phase_time_remaining = maxf(0.0, float(state.get("tr", _phase_time_remaining)))
	var facing_v: Variant = state.get("pf", _planar_facing)
	if facing_v is Vector2:
		var facing := facing_v as Vector2
		if facing.length_squared() > 1e-6:
			_planar_facing = facing.normalized()
	var latched_id := int(state.get("li", 0))
	_latched_player = _find_player_by_instance_id(latched_id)
	_distance_to_target = float(state.get("td", _distance_to_target))
	_is_materialized = bool(int(state.get("mat", 0)))
	_apply_phase_collision_state()


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, hurtbox_area: Area2D) -> void:
	if hp_damage <= 0:
		super._on_receiver_damage_applied(packet, hp_damage, hurtbox_area)
		return
	if not is_damage_authority():
		super._on_receiver_damage_applied(packet, hp_damage, hurtbox_area)
		return
	if _phase == PhaseState.LATCH or _phase == PhaseState.DRAIN:
		var restored := mini(max_health, _health + hp_damage)
		if _health_component != null:
			_health_component.set_current_health(restored)
		_health = restored
		if packet != null and packet.source_node != _latched_player:
			_start_detach()
		return
	super._on_receiver_damage_applied(packet, hp_damage, hurtbox_area)


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Leecher.glb")
	return build_single_scene_visual_state_config(scene, edge_clip_scale)


func _tick_server_state(delta: float) -> void:
	_phase_time_remaining = maxf(0.0, _phase_time_remaining - delta)
	match _phase:
		PhaseState.CHASE:
			_tick_chase(delta)
		PhaseState.LATCH:
			_tick_latch()
		PhaseState.DRAIN:
			_tick_drain(delta)
		PhaseState.DETACH:
			_tick_detach()


func _tick_chase(delta: float) -> void:
	_refresh_target_player(delta)
	if _target_player == null or not is_instance_valid(_target_player):
		_distance_to_target = INF
		_is_materialized = false
		velocity = Vector2.ZERO
		return
	_distance_to_target = _target_player.global_position.distance_to(global_position)
	_is_materialized = _distance_to_target <= materialize_distance
	_apply_phase_collision_state()
	if _distance_to_target <= latch_distance:
		_begin_latch(_target_player)
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
	if desired == Vector2.ZERO:
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 0.001:
			desired = to_target.normalized()
	velocity = desired * move_speed
	if desired.length_squared() > 0.001:
		_planar_facing = desired
	ignore_player_body_collisions()


func _begin_latch(player: Node2D) -> void:
	_latched_player = player
	_target_player = player
	_phase = PhaseState.LATCH
	_phase_time_remaining = latch_attach_duration
	_is_materialized = true
	velocity = Vector2.ZERO
	_drain_accumulator = 0.0
	_total_drained = 0.0
	if _latched_player is CollisionObject2D:
		add_collision_exception_with(_latched_player as CollisionObject2D)
	if _latched_player != null and _latched_player.has_method(&"enemy_control_begin_latch"):
		_latched_player.call(&"enemy_control_begin_latch", self, break_free_presses)
	_apply_phase_collision_state()


func _tick_latch() -> void:
	if not _sync_to_latched_player():
		return
	if _phase_time_remaining <= 0.0:
		_phase = PhaseState.DRAIN
		_phase_time_remaining = 0.0


func _tick_drain(delta: float) -> void:
	if not _sync_to_latched_player():
		return
	if _latched_player.has_method(&"enemy_control_latch_break_ready") and bool(
		_latched_player.call(&"enemy_control_latch_break_ready")
	):
		_start_detach()
		return
	_drain_accumulator += maxf(0.0, drain_per_second) * delta
	var drain_steps := int(floor(_drain_accumulator))
	if drain_steps <= 0:
		return
	_drain_accumulator -= float(drain_steps)
	for _step in range(drain_steps):
		if _phase != PhaseState.DRAIN:
			return
		if not _apply_drain_tick():
			return


func _apply_drain_tick() -> bool:
	if _latched_player == null or not is_instance_valid(_latched_player):
		_start_detach()
		return false
	if _is_player_downed_node(_latched_player):
		_start_detach()
		return false
	if _latched_player.has_method(&"take_attack_damage"):
		_latched_player.call(&"take_attack_damage", 1, global_position, _planar_facing)
	_total_drained += 1.0
	if _health_component != null:
		_health_component.set_current_health(mini(max_health, _health_component.current_health + 1))
	_health = _health_component.current_health if _health_component != null else mini(max_health, _health + 1)
	if _total_drained >= max_total_drain:
		_start_detach()
		return false
	return true


func _start_detach() -> void:
	_clear_latched_player_control()
	_phase = PhaseState.DETACH
	_phase_time_remaining = detach_recovery_duration
	_is_materialized = false
	_drain_accumulator = 0.0
	_total_drained = 0.0
	if _target_player != null and is_instance_valid(_target_player):
		var away := global_position - _target_player.global_position
		if away.length_squared() <= 1e-6:
			away = Vector2.RIGHT.rotated(randf() * TAU)
		away = away.normalized()
		global_position = _target_player.global_position + away * detach_hop_distance
		_planar_facing = away
	velocity = Vector2.ZERO
	_latched_player = null
	_apply_phase_collision_state()


func _tick_detach() -> void:
	_distance_to_target = INF
	_is_materialized = false
	velocity = Vector2.ZERO
	if _phase_time_remaining <= 0.0:
		_phase = PhaseState.CHASE
		_apply_phase_collision_state()


func _sync_to_latched_player() -> bool:
	if _latched_player == null or not is_instance_valid(_latched_player):
		_start_detach()
		return false
	if _is_player_downed_node(_latched_player):
		_start_detach()
		return false
	var target_pos := _latched_player.global_position
	var to_target := target_pos - global_position
	if to_target.length_squared() > 0.0001:
		_planar_facing = to_target.normalized()
	global_position = target_pos
	velocity = Vector2.ZERO
	return true


func _refresh_target_player(delta: float) -> void:
	var refresh: Dictionary = refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		_phase == PhaseState.CHASE
	)
	_target_player = refresh.get("target", null) as Node2D
	_target_refresh_time_remaining = float(refresh.get("refresh_time_remaining", 0.0))
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()


func _clear_latched_player_control() -> void:
	if _latched_player != null and is_instance_valid(_latched_player):
		if _latched_player.has_method(&"enemy_control_end_latch"):
			_latched_player.call(&"enemy_control_end_latch", self)


func _find_player_by_instance_id(instance_id: int) -> Node2D:
	if instance_id == 0:
		return null
	for candidate in _targetable_player_candidates():
		if candidate != null and is_instance_valid(candidate) and candidate.get_instance_id() == instance_id:
			return candidate
	return null


func _escape_progress_for_remote() -> float:
	if _latched_player == null or not is_instance_valid(_latched_player):
		return 0.0
	if _latched_player.has_method(&"enemy_control_latch_escape_progress"):
		return float(_latched_player.call(&"enemy_control_latch_escape_progress"))
	return 0.0


func _update_visuals() -> void:
	if _visual != null:
		var moving := _phase == PhaseState.CHASE and velocity.length_squared() > 0.04
		_visual.set_mesh_transparency(_resolve_visual_transparency())
		_visual.set_state(&"walk" if moving else &"idle")
		_visual.sync_from_2d(global_position, _planar_facing)
	if _beam_mesh != null:
		_beam_mesh.visible = _phase == PhaseState.LATCH or _phase == PhaseState.DRAIN
		if _beam_mesh.visible and _latched_player != null and is_instance_valid(_latched_player):
			_update_beam_visual(_latched_player.global_position)


func _update_beam_visual(target_pos: Vector2) -> void:
	if _beam_mesh == null:
		return
	var start := Vector3(global_position.x, latch_beam_height, global_position.y)
	var finish := Vector3(target_pos.x, latch_beam_height, target_pos.y)
	var delta := finish - start
	# While latched, 2D positions match so start == finish; look_at() requires a non-zero direction.
	if delta.length_squared() < 1e-10:
		var pf := get_combat_planar_facing()
		var dir3 := Vector3(pf.x, 0.0, pf.y)
		if dir3.length_squared() < 1e-10:
			dir3 = Vector3(0.0, 0.0, -1.0)
		else:
			dir3 = dir3.normalized()
		finish = start + dir3 * 0.35
		delta = finish - start
	var distance := maxf(0.01, delta.length())
	_beam_mesh.global_position = start.lerp(finish, 0.5)
	_beam_mesh.scale = Vector3(1.0, distance * 0.5, 1.0)
	_beam_mesh.look_at(finish, Vector3.UP, true)
	_beam_mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	if _beam_material != null:
		var pulse := 0.65 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.012)
		_beam_material.emission_energy_multiplier = 1.2 + pulse
		_beam_material.albedo_color = Color(0.32, 1.0, 0.9, 0.52 + pulse * 0.22)


func _resolve_visual_transparency() -> float:
	if _phase == PhaseState.LATCH or _phase == PhaseState.DRAIN:
		return materialized_transparency
	if _phase == PhaseState.CHASE and _is_materialized:
		return materialized_transparency
	return phased_transparency


func _apply_phase_collision_state() -> void:
	if _hurtbox != null:
		_hurtbox.set_active(not _is_phased_out() and is_damage_authority())


func _is_phased_out() -> bool:
	if _phase == PhaseState.DETACH:
		return true
	if _phase == PhaseState.CHASE:
		return not _is_materialized
	return false
