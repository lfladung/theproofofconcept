extends EnemyBase
class_name RobotMob

const ARROW_PROJECTILE_SCENE := preload("res://scenes/entities/arrow_projectile.tscn")
const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const ROBOT_IDLE_SCENE_PATH := "res://art/characters/enemies/robot_mob_texture.glb"
const ROBOT_WALK_SCENE_PATH := "res://art/characters/enemies/robot_Walking_withSkin.glb"

@export var move_speed := 7.0
@export var attack_trigger_distance := 11.0
@export var stop_distance := 4.5
@export var repath_interval := 0.2
@export var target_refresh_interval := 0.35
@export var charge_duration := 1.05
@export var charge_fire_fraction := 0.82
@export var attack_cooldown := 1.6
@export var projectile_count := 3
@export var projectile_total_spread_degrees := 34.0
@export var projectile_damage := 12
@export var projectile_speed := 18.0
@export var projectile_max_distance := 9.0
@export var projectile_spawn_distance := 1.2
@export var projectile_visual_scale_multiplier := 0.5
@export var mesh_ground_y := 0.24
@export var mesh_scale := Vector3(2.6, 2.6, 2.6)
@export var facing_yaw_offset_deg := 180.0
@export var telegraph_ground_y := 0.06
@export var telegraph_range := 9.0

var _visual
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _aggro_enabled := true
var _speed_multiplier := 1.0
var _is_charging := false
var _charge_elapsed := 0.0
var _charge_fire_time := 0.0
var _charge_dir := Vector2(0.0, -1.0)
var _charge_fired := false
var _cooldown_remaining := 0.0
var _server_volley_event_sequence := 0
var _last_applied_volley_event_sequence := -1

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		_target_player = null
		velocity = Vector2.ZERO
		_cancel_charge()
		_update_charge_telegraph_visual(false, Vector2.ZERO, 0.0)
		_sync_visual()


func _ready() -> void:
	super._ready()
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"RobotMobVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = facing_yaw_offset_deg
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_create_telegraph_mesh(vw)
	_sync_visual()
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = stop_distance
		_nav_agent.avoidance_enabled = false


func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_charge_telegraph_visual(_is_charging, _charge_dir, _charge_progress())
		_sync_visual()
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		_update_charge_telegraph_visual(false, Vector2.ZERO, 0.0)
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	_refresh_target_player(delta, not _is_charging)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_target_player()
	if _is_charging:
		_update_charge(delta)
	else:
		_update_behavior(delta)
	move_and_slide()
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ch": _is_charging,
		"ce": _charge_elapsed,
		"cf": _charge_fire_time,
		"dir": _charge_dir,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_is_charging = bool(state.get("ch", false))
	_charge_elapsed = maxf(0.0, float(state.get("ce", 0.0)))
	_charge_fire_time = maxf(0.01, float(state.get("cf", _resolve_charge_fire_time())))
	var dir_v: Variant = state.get("dir", _charge_dir)
	if dir_v is Vector2:
		var next_dir := dir_v as Vector2
		if next_dir.length_squared() > 0.0001:
			_charge_dir = next_dir.normalized()
	if not _is_charging:
		_charge_elapsed = 0.0


func _update_behavior(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		_update_charge_telegraph_visual(false, Vector2.ZERO, 0.0)
		return
	var to_target := _target_player.global_position - global_position
	if to_target.length_squared() <= attack_trigger_distance * attack_trigger_distance and _cooldown_remaining <= 0.0:
		_start_charge(to_target.normalized())
		return
	_update_chase_velocity(delta)
	_update_charge_telegraph_visual(false, Vector2.ZERO, 0.0)


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
		velocity = desired * move_speed * _speed_multiplier


func _start_charge(direction: Vector2) -> void:
	_is_charging = true
	_charge_elapsed = 0.0
	_charge_fired = false
	_charge_dir = direction if direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	_charge_fire_time = _resolve_charge_fire_time()
	velocity = Vector2.ZERO
	_update_charge_telegraph_visual(true, _charge_dir, 0.0)


func _update_charge(delta: float) -> void:
	velocity = Vector2.ZERO
	_charge_elapsed += delta
	var progress := _charge_progress()
	_update_charge_telegraph_visual(true, _charge_dir, progress)
	if not _charge_fired and _charge_elapsed >= _charge_fire_time:
		_charge_fired = true
		_fire_projectile_volley(_charge_dir)
		_cooldown_remaining = attack_cooldown
	if _charge_elapsed >= charge_duration:
		_cancel_charge()


func _cancel_charge() -> void:
	_is_charging = false
	_charge_elapsed = 0.0
	_charge_fired = false
	_update_charge_telegraph_visual(false, Vector2.ZERO, 0.0)


func _charge_progress() -> float:
	return clampf(_charge_elapsed / maxf(0.01, _charge_fire_time), 0.0, 1.0)


func _resolve_charge_fire_time() -> float:
	return maxf(0.05, charge_duration * clampf(charge_fire_fraction, 0.1, 1.0))


func _fire_projectile_volley(direction: Vector2) -> void:
	if _multiplayer_active() and not _is_server_peer():
		return
	_server_volley_event_sequence += 1
	var volley_event_id := _server_volley_event_sequence
	var spawn_position := global_position + direction.normalized() * projectile_spawn_distance
	for projectile_index in range(projectile_count):
		var spread_dir := _volley_direction_for(direction, projectile_index)
		_spawn_robot_projectile(
			spawn_position,
			spread_dir,
			true,
			_projectile_event_id_for(volley_event_id, projectile_index)
		)
	if _can_broadcast_world_replication():
		_rpc_receive_robot_volley_event.rpc(volley_event_id, spawn_position, direction)


func _spawn_robot_projectile(
	spawn_position: Vector2,
	direction: Vector2,
	authoritative_damage: bool,
	projectile_event_id: int
) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var projectile := ARROW_PROJECTILE_SCENE.instantiate() as ArrowProjectile
	if projectile == null:
		return
	projectile.speed = projectile_speed
	projectile.max_distance = projectile_max_distance
	projectile.damage = projectile_damage
	projectile.mesh_scale *= projectile_visual_scale_multiplier
	if projectile.has_method(&"set_authoritative_damage"):
		projectile.call(&"set_authoritative_damage", authoritative_damage)
	projectile.configure(
		spawn_position,
		direction,
		_vw,
		false,
		&"green",
		projectile_event_id
	)
	parent.add_child(projectile)


func _volley_direction_for(base_direction: Vector2, projectile_index: int) -> Vector2:
	var dir := base_direction.normalized() if base_direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	if projectile_count <= 1:
		return dir
	var total_spread := projectile_total_spread_degrees
	var start_deg := -total_spread * 0.5
	var step_deg := total_spread / float(maxi(1, projectile_count - 1))
	var offset_deg := start_deg + step_deg * float(projectile_index)
	return dir.rotated(deg_to_rad(offset_deg)).normalized()


func _projectile_event_id_for(volley_event_id: int, projectile_index: int) -> int:
	return volley_event_id * 10 + projectile_index + 1


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_robot_volley_event(
	volley_event_id: int, spawn_position: Vector2, direction: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if volley_event_id <= _last_applied_volley_event_sequence:
		return
	_last_applied_volley_event_sequence = volley_event_id
	for projectile_index in range(projectile_count):
		_spawn_robot_projectile(
			spawn_position,
			_volley_direction_for(direction, projectile_index),
			false,
			_projectile_event_id_for(volley_event_id, projectile_index)
		)


func _refresh_target_player(delta: float, allow_retarget: bool = true) -> void:
	_target_refresh_time_remaining = maxf(0.0, _target_refresh_time_remaining - delta)
	if (
		_target_player == null
		or not is_instance_valid(_target_player)
		or (allow_retarget and _target_refresh_time_remaining <= 0.0)
	):
		_target_player = _pick_target_player()
		_target_refresh_time_remaining = maxf(0.05, target_refresh_interval)


func _sync_visual() -> void:
	if _visual == null:
		return
	var state := &"idle"
	if not _is_charging and velocity.length_squared() > 0.01:
		state = &"walk"
	_visual.set_state(state)
	var facing := _resolve_visual_facing_direction()
	_visual.sync_from_2d(global_position, facing)
	var playback_scale := clampf(
		velocity.length() / maxf(move_speed * maxf(_speed_multiplier, 0.01), 0.01),
		0.35,
		2.0
	) if state == &"walk" else 1.0
	_visual.set_playback_speed_scale(playback_scale)


func _resolve_visual_facing_direction() -> Vector2:
	if _is_charging and _charge_dir.length_squared() > 0.0001:
		return _charge_dir.normalized()
	if velocity.length_squared() > 0.0001:
		return velocity.normalized()
	if _target_player != null and is_instance_valid(_target_player):
		var to_target := _target_player.global_position - global_position
		if to_target.length_squared() > 0.0001:
			return to_target.normalized()
	if _charge_dir.length_squared() > 0.0001:
		return _charge_dir.normalized()
	return Vector2(0.0, -1.0)


func _create_telegraph_mesh(parent: Node3D) -> void:
	_telegraph_mesh = MeshInstance3D.new()
	_telegraph_mesh.name = &"RobotChargeTelegraph"
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.albedo_color = Color(0.12, 0.95, 0.28, 0.7)
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_mesh.visible = false
	parent.add_child(_telegraph_mesh)


func _update_charge_telegraph_visual(active: bool, direction: Vector2, progress: float) -> void:
	if _telegraph_mesh == null:
		return
	if not active:
		_telegraph_mesh.visible = false
		return
	_telegraph_mesh.visible = true
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	var half_angle := deg_to_rad(projectile_total_spread_degrees * 0.5)
	var center_angle := dir.angle()
	var radius := maxf(0.5, telegraph_range)
	var fill_radius := radius * clampf(progress, 0.0, 1.0)
	var segments := maxi(8, int(ceil(projectile_total_spread_degrees / 6.0)))
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
	var start_point := global_position + Vector2.from_angle(center_angle - half_angle) * radius
	var end_point := global_position + Vector2.from_angle(center_angle + half_angle) * radius
	imm.surface_add_vertex(Vector3(global_position.x, telegraph_ground_y, global_position.y))
	imm.surface_add_vertex(Vector3(start_point.x, telegraph_ground_y, start_point.y))
	imm.surface_add_vertex(Vector3(global_position.x, telegraph_ground_y, global_position.y))
	imm.surface_add_vertex(Vector3(end_point.x, telegraph_ground_y, end_point.y))
	for segment_index in range(segments):
		var t0 := float(segment_index) / float(segments)
		var t1 := float(segment_index + 1) / float(segments)
		var a0 := lerpf(center_angle - half_angle, center_angle + half_angle, t0)
		var a1 := lerpf(center_angle - half_angle, center_angle + half_angle, t1)
		var p0 := global_position + Vector2.from_angle(a0) * radius
		var p1 := global_position + Vector2.from_angle(a1) * radius
		imm.surface_add_vertex(Vector3(p0.x, telegraph_ground_y, p0.y))
		imm.surface_add_vertex(Vector3(p1.x, telegraph_ground_y, p1.y))
	imm.surface_end()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
	for segment_index in range(segments):
		var t0 := float(segment_index) / float(segments)
		var t1 := float(segment_index + 1) / float(segments)
		var a0 := lerpf(center_angle - half_angle, center_angle + half_angle, t0)
		var a1 := lerpf(center_angle - half_angle, center_angle + half_angle, t1)
		var p0 := global_position + Vector2.from_angle(a0) * fill_radius
		var p1 := global_position + Vector2.from_angle(a1) * fill_radius
		imm.surface_add_vertex(Vector3(global_position.x, telegraph_ground_y + 0.001, global_position.y))
		imm.surface_add_vertex(Vector3(p0.x, telegraph_ground_y + 0.001, p0.y))
		imm.surface_add_vertex(Vector3(p1.x, telegraph_ground_y + 0.001, p1.y))
	imm.surface_end()
	_telegraph_mesh.mesh = imm


func _build_visual_state_config() -> Dictionary:
	var idle_scene := _load_visual_scene(ROBOT_IDLE_SCENE_PATH)
	var walk_scene := _load_visual_scene(ROBOT_WALK_SCENE_PATH)
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
			"scene_scale": 114.5,
			"facing_yaw_offset_deg": 0.0,
			"keywords": ["walk", "run", "moving"],
		},
	}


func _load_visual_scene(path: String) -> PackedScene:
	var resource := load(path)
	return resource as PackedScene if resource is PackedScene else null


func _pick_target_player() -> Node2D:
	return _pick_nearest_player_target()


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	_cancel_charge()
	velocity = Vector2.ZERO


func can_contact_damage() -> bool:
	return false


func get_shadow_visual_root() -> Node3D:
	return _visual
