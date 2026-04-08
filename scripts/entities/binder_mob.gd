class_name BinderMob
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const BinderTetherProjectileScene = preload("res://scenes/entities/binder_tether_projectile.tscn")

enum PhaseState { POSITION, FIRE_TETHER, ROOTED_TARGET, FOLLOW_UP }

@export var move_speed := 6.0
@export var strafe_speed_multiplier := 0.65
@export var maintain_distance_min := 5.0
@export var maintain_distance_max := 8.0
@export var target_refresh_interval := 0.3
@export var fire_windup_duration := 0.35
@export var tether_cooldown_duration := 1.4
@export var post_shot_materialize_duration := 0.5
@export var tether_speed := 8.0
@export var tether_damage := 10
@export var tether_max_distance := 18.0
@export var max_active_tethers := 3
@export var root_duration := 0.8
@export var follow_up_speed := 8.5
@export var follow_up_hit_distance := 1.35
@export var follow_up_damage := 30
@export var follow_up_recovery_duration := 1.25
@export var mesh_ground_y := 0.14
@export var mesh_scale := Vector3(1.1, 1.1, 1.1)
@export var edge_clip_scale := 2.5
@export var tether_link_radius := 0.08
@export var tether_link_height := 1.1
@export_range(0.0, 1.0, 0.05) var phased_transparency := 0.48
@export_range(0.0, 1.0, 0.05) var materialized_transparency := 0.0

var _visual: Node3D
var _vw: Node3D
var _phase := PhaseState.POSITION
var _phase_time_remaining := 0.0
var _target_player: Node2D
var _rooted_player: Node2D
var _target_refresh_time_remaining := 0.0
var _tether_cooldown_remaining := 0.0
var _planar_facing := Vector2(0.0, -1.0)
var _fire_direction := Vector2(0.0, -1.0)
var _fire_target_position := Vector2.ZERO
var _strafe_sign := 1.0
var _follow_up_hit_pending := false
var _post_shot_materialize_time_remaining := 0.0
var _active_tethers: Dictionary = {}
var _remote_projectiles_by_event_id: Dictionary = {}
var _projectile_event_sequence := 0
var _tether_link_mesh: MeshInstance3D
var _tether_link_material: StandardMaterial3D


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
		vis.name = &"BinderVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		_vw.add_child(vis)
		_visual = vis
		_tether_link_mesh = MeshInstance3D.new()
		_tether_link_mesh.name = &"BinderTetherLink"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = tether_link_radius
		cylinder.bottom_radius = tether_link_radius
		cylinder.height = 1.0
		_tether_link_mesh.mesh = cylinder
		_tether_link_material = StandardMaterial3D.new()
		_tether_link_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tether_link_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tether_link_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tether_link_material.albedo_color = Color(0.68, 0.9, 1.0, 0.78)
		_tether_link_material.emission_enabled = true
		_tether_link_material.emission = Color(0.72, 0.95, 1.0, 1.0)
		_tether_link_material.emission_energy_multiplier = 1.8
		_tether_link_mesh.material_override = _tether_link_material
		_tether_link_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tether_link_mesh.visible = false
		_vw.add_child(_tether_link_mesh)
	_apply_phase_collision_state()


func _exit_tree() -> void:
	_clear_rooted_player_control()
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _tether_link_mesh != null and is_instance_valid(_tether_link_mesh):
		_tether_link_mesh.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_visuals()
		return
	_tether_cooldown_remaining = maxf(0.0, _tether_cooldown_remaining - delta)
	_post_shot_materialize_time_remaining = maxf(0.0, _post_shot_materialize_time_remaining - delta)
	_tick_server_state(delta)
	move_and_slide_with_mob_separation()
	_enemy_network_server_broadcast(delta)
	_update_visuals()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ph": _phase,
		"tr": maxf(0.0, _phase_time_remaining),
		"pf": _planar_facing,
		"fd": _fire_direction,
		"fp": _fire_target_position,
		"ri": _rooted_player.get_instance_id() if _rooted_player != null and is_instance_valid(_rooted_player) else 0,
		"ps": _post_shot_materialize_time_remaining,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_phase = int(state.get("ph", _phase)) as PhaseState
	_phase_time_remaining = maxf(0.0, float(state.get("tr", _phase_time_remaining)))
	var facing_v: Variant = state.get("pf", _planar_facing)
	if facing_v is Vector2:
		var facing := facing_v as Vector2
		if facing.length_squared() > 1e-6:
			_planar_facing = facing.normalized()
	var dir_v: Variant = state.get("fd", _fire_direction)
	if dir_v is Vector2:
		var dir := dir_v as Vector2
		if dir.length_squared() > 1e-6:
			_fire_direction = dir.normalized()
	var pos_v: Variant = state.get("fp", _fire_target_position)
	if pos_v is Vector2:
		_fire_target_position = pos_v as Vector2
	_rooted_player = _find_player_by_instance_id(int(state.get("ri", 0)))
	_post_shot_materialize_time_remaining = maxf(
		0.0,
		float(state.get("ps", _post_shot_materialize_time_remaining))
	)
	_apply_phase_collision_state()


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Binder.glb")
	return build_single_scene_visual_state_config(scene, edge_clip_scale)


func _tick_server_state(delta: float) -> void:
	_phase_time_remaining = maxf(0.0, _phase_time_remaining - delta)
	match _phase:
		PhaseState.POSITION:
			_tick_position(delta)
		PhaseState.FIRE_TETHER:
			_tick_fire_tether()
		PhaseState.ROOTED_TARGET:
			_tick_rooted_target()
		PhaseState.FOLLOW_UP:
			_tick_follow_up()


func _tick_position(delta: float) -> void:
	_refresh_target_player(delta)
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	_prune_finished_tethers()
	var to_target := _target_player.global_position - global_position
	var distance := to_target.length()
	var desired := Vector2.ZERO
	if distance < maintain_distance_min and distance > 0.001:
		desired = -to_target.normalized()
	elif distance > maintain_distance_max and distance > 0.001:
		desired = to_target.normalized()
	else:
		var lateral := Vector2(-to_target.y, to_target.x).normalized()
		desired = lateral * _strafe_sign
	if desired.length_squared() > 0.001:
		var speed_scale := 1.0 if distance < maintain_distance_min or distance > maintain_distance_max else strafe_speed_multiplier
		velocity = desired * move_speed * speed_scale
		_planar_facing = desired
	else:
		velocity = Vector2.ZERO
	if _can_fire_tether(distance):
		_begin_fire_tether()


func _begin_fire_tether() -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		return
	_phase = PhaseState.FIRE_TETHER
	_phase_time_remaining = fire_windup_duration
	_fire_target_position = _target_player.global_position
	var to_target := _fire_target_position - global_position
	_fire_direction = to_target.normalized() if to_target.length_squared() > 0.001 else _planar_facing
	_planar_facing = _fire_direction
	velocity = Vector2.ZERO
	_apply_phase_collision_state()


func _tick_fire_tether() -> void:
	velocity = Vector2.ZERO
	if _phase_time_remaining > 0.0:
		return
	_spawn_tether_projectile(global_position, true)
	_phase = PhaseState.POSITION
	_phase_time_remaining = 0.0
	_tether_cooldown_remaining = tether_cooldown_duration
	_post_shot_materialize_time_remaining = post_shot_materialize_duration
	_strafe_sign *= -1.0
	_apply_phase_collision_state()


func _tick_rooted_target() -> void:
	velocity = Vector2.ZERO
	if _rooted_player == null or not is_instance_valid(_rooted_player):
		_clear_rooted_player_control()
		_phase = PhaseState.POSITION
		_apply_phase_collision_state()
		return
	_phase = PhaseState.FOLLOW_UP
	_follow_up_hit_pending = true
	_apply_phase_collision_state()


func _tick_follow_up() -> void:
	if _rooted_player == null or not is_instance_valid(_rooted_player):
		_clear_rooted_player_control()
		_phase = PhaseState.POSITION
		_apply_phase_collision_state()
		return
	if _phase_time_remaining <= 0.0:
		_clear_rooted_player_control()
		_phase = PhaseState.POSITION
		_follow_up_hit_pending = false
		_apply_phase_collision_state()
		return
	var to_target := _rooted_player.global_position - global_position
	var distance := to_target.length()
	if distance > 0.001:
		_planar_facing = to_target.normalized()
	if _follow_up_hit_pending and distance <= follow_up_hit_distance:
		if _rooted_player.has_method(&"take_attack_damage"):
			_rooted_player.call(&"take_attack_damage", follow_up_damage, global_position, _planar_facing)
		_follow_up_hit_pending = false
		_clear_rooted_player_control()
		_phase = PhaseState.POSITION
		_phase_time_remaining = follow_up_recovery_duration
		velocity = Vector2.ZERO
		_tether_cooldown_remaining = maxf(_tether_cooldown_remaining, follow_up_recovery_duration)
		_apply_phase_collision_state()
		return
	velocity = _planar_facing * follow_up_speed


func _refresh_target_player(delta: float) -> void:
	var refresh: Dictionary = refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		_phase == PhaseState.POSITION
	)
	_target_player = refresh.get("target", null) as Node2D
	_target_refresh_time_remaining = float(refresh.get("refresh_time_remaining", 0.0))
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()


func _can_fire_tether(distance_to_target: float) -> bool:
	if _target_player == null or not is_instance_valid(_target_player):
		return false
	if _tether_cooldown_remaining > 0.0:
		return false
	if _active_tethers.size() >= max_active_tethers:
		return false
	return distance_to_target <= max(maintain_distance_max + 2.0, 10.0)


func _spawn_tether_projectile(
	spawn_position: Vector2, authoritative_damage: bool, projectile_event_id: int = -1
) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	if not authoritative_damage and projectile_event_id > 0:
		var existing_v: Variant = _remote_projectiles_by_event_id.get(projectile_event_id, null)
		if existing_v != null and is_instance_valid(existing_v):
			return true
	var projectile: Node = BinderTetherProjectileScene.instantiate()
	if projectile == null:
		return false
	parent.add_child(projectile)
	projectile.set("speed", tether_speed)
	projectile.set("max_distance", tether_max_distance)
	projectile.set("damage", tether_damage)
	projectile.call(&"set_authoritative_damage", authoritative_damage)
	projectile.call(
		&"configure",
		spawn_position,
		_fire_direction,
		self,
		_vw,
		authoritative_damage,
		projectile_event_id
	)
	if authoritative_damage:
		var event_id := projectile_event_id
		if event_id <= 0:
			_projectile_event_sequence += 1
			event_id = _projectile_event_sequence
		_active_tethers[event_id] = projectile
		projectile.tether_connected.connect(_on_server_tether_connected.bind(event_id), CONNECT_ONE_SHOT)
		projectile.tether_finished.connect(_on_server_tether_finished.bind(event_id), CONNECT_ONE_SHOT)
		if _multiplayer_active() and _is_server_peer() and _can_broadcast_world_replication():
			_rpc_receive_tether_spawn.rpc(event_id, spawn_position, _fire_direction)
	else:
		_remote_projectiles_by_event_id[projectile_event_id] = projectile
	return true


func _on_server_tether_connected(target_uid: int, final_position: Vector2, projectile_event_id: int) -> void:
	var player := _find_player_by_instance_id(target_uid)
	if player == null:
		return
	_apply_root_to_player(player)


func _on_server_tether_finished(final_position: Vector2, projectile_event_id: int) -> void:
	_active_tethers.erase(projectile_event_id)
	if _multiplayer_active() and _is_server_peer() and _can_broadcast_world_replication():
		_rpc_receive_tether_finish.rpc(projectile_event_id, final_position)


func _apply_root_to_player(player: Node2D) -> void:
	_clear_rooted_player_control()
	_rooted_player = player
	if _rooted_player.has_method(&"enemy_control_apply_root"):
		_rooted_player.call(&"enemy_control_apply_root", get_instance_id(), _rooted_player.global_position)
	_phase = PhaseState.ROOTED_TARGET
	_phase_time_remaining = root_duration
	_follow_up_hit_pending = true
	_apply_phase_collision_state()


func _clear_rooted_player_control() -> void:
	if _rooted_player != null and is_instance_valid(_rooted_player):
		if _rooted_player.has_method(&"enemy_control_clear_root"):
			_rooted_player.call(&"enemy_control_clear_root", get_instance_id())
	_rooted_player = null


func _prune_finished_tethers() -> void:
	var stale: Array = []
	for key in _active_tethers.keys():
		var projectile_v: Variant = _active_tethers.get(key, null)
		if projectile_v == null or not is_instance_valid(projectile_v):
			stale.append(key)
	for key in stale:
		_active_tethers.erase(key)


func _find_player_by_instance_id(instance_id: int) -> Node2D:
	if instance_id == 0:
		return null
	for candidate in _targetable_player_candidates():
		if candidate != null and is_instance_valid(candidate) and candidate.get_instance_id() == instance_id:
			return candidate
	return null


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_tether_spawn(
	projectile_event_id: int, spawn_position: Vector2, facing_dir: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_fire_direction = facing_dir.normalized() if facing_dir.length_squared() > 0.001 else _planar_facing
	_spawn_tether_projectile(spawn_position, false, projectile_event_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_tether_finish(projectile_event_id: int, final_position: Vector2) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var projectile_v: Variant = _remote_projectiles_by_event_id.get(projectile_event_id, null)
	if projectile_v != null and is_instance_valid(projectile_v):
		var projectile: Node = projectile_v as Node
		if projectile != null:
			projectile.set("global_position", final_position)
			projectile.queue_free()
	_remote_projectiles_by_event_id.erase(projectile_event_id)


func _update_visuals() -> void:
	if _visual != null:
		var moving := velocity.length_squared() > 0.04
		_visual.set_mesh_transparency(_resolve_visual_transparency())
		_visual.set_state(&"walk" if moving else &"idle")
		_visual.sync_from_2d(global_position, _planar_facing)
	if _tether_link_mesh != null:
		_tether_link_mesh.visible = _rooted_player != null and is_instance_valid(_rooted_player)
		if _tether_link_mesh.visible:
			_update_tether_link_visual(_rooted_player.global_position)


func _update_tether_link_visual(target_pos: Vector2) -> void:
	var start := Vector3(global_position.x, tether_link_height, global_position.y)
	var finish := Vector3(target_pos.x, tether_link_height, target_pos.y)
	var delta := finish - start
	var distance := maxf(0.01, delta.length())
	_tether_link_mesh.global_position = start.lerp(finish, 0.5)
	_tether_link_mesh.scale = Vector3(1.0, distance * 0.5, 1.0)
	_tether_link_mesh.look_at(finish, Vector3.UP, true)
	_tether_link_mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	if _tether_link_material != null:
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.01)
		_tether_link_material.emission_energy_multiplier = 1.2 + pulse * 1.4
		_tether_link_material.albedo_color = Color(0.68, 0.9, 1.0, 0.48 + pulse * 0.26)


func _resolve_visual_transparency() -> float:
	if not _is_phased_out():
		return materialized_transparency
	return phased_transparency


func _apply_phase_collision_state() -> void:
	if _hurtbox != null:
		_hurtbox.set_active(not _is_phased_out() and is_damage_authority())


func _is_phased_out() -> bool:
	if _phase != PhaseState.POSITION:
		return false
	return _post_shot_materialize_time_remaining <= 0.0
