extends EnemyBase
class_name ArrowTowerMob

const TOWER_VISUAL_SCENE := preload("res://art/combat/towers/stylized_arrow_tower_texture.glb")
const ARROW_PROJECTILE_SCENE := preload("res://scenes/entities/arrow_projectile.tscn")

@export var range_tiles := 5.0
@export var world_units_per_tile := 3.0
@export var fire_cooldown := 2.0
@export var arrow_damage := 15
@export var arrow_max_tiles := 5.0
@export var arrow_speed := 21.0
@export var mesh_ground_y := 0.95
@export var mesh_scale := Vector3(2.3, 2.3, 2.3)
@export var facing_yaw_offset_deg := 90.0
## Same visual language as dasher telegraph: hollow outline + red fill toward target.
@export var telegraph_ground_y := 0.06
@export var telegraph_arrow_length := 7.8
@export var telegraph_arrow_head_length := 0.8
@export var telegraph_arrow_half_width := 0.32

var _target_player: Node2D
var _cooldown_remaining := 0.0
var _visual: Node3D
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _aggro_enabled := true
var _in_range_presence_by_instance_id: Dictionary = {}
var _net_telegraph_in_range := false
var _net_telegraph_dir := Vector2(0.0, -1.0)
var _net_telegraph_progress := 0.0
var _server_arrow_event_sequence := 0
var _last_applied_arrow_event_sequence := -1
var _remote_projectiles_by_event_id: Dictionary = {}


func _ready() -> void:
	super._ready()
	# Require a full wind-up before the first shot.
	_cooldown_remaining = maxf(0.01, fire_cooldown)
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null and TOWER_VISUAL_SCENE != null:
		var vis := TOWER_VISUAL_SCENE.instantiate() as Node3D
		if vis != null:
			vis.scale = mesh_scale
			vw.add_child(vis)
			_visual = vis
	if vw != null:
		_telegraph_mesh = MeshInstance3D.new()
		_telegraph_mesh.name = &"TowerTelegraphArrow"
		_outline_mat = StandardMaterial3D.new()
		_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fill_mat.albedo_color = Color(0.9, 0.08, 0.08, 0.75)
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_mesh.visible = false
		vw.add_child(_telegraph_mesh)
	_sync_visual()
	_target_player = null


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		if _aggro_enabled and _net_telegraph_in_range:
			_face_direction(_net_telegraph_dir)
		_update_telegraph_visual(_aggro_enabled and _net_telegraph_in_range, _net_telegraph_dir, _net_telegraph_progress)
		_sync_visual()
		return
	if not _aggro_enabled:
		_target_player = null
		_in_range_presence_by_instance_id.clear()
		_net_telegraph_in_range = false
		_net_telegraph_progress = 0.0
		_update_telegraph_visual(false, Vector2.ZERO, 0.0)
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	var range_world := range_tiles * world_units_per_tile
	_refresh_target_lock(range_world)
	if _target_player == null or not is_instance_valid(_target_player):
		_net_telegraph_in_range = false
		_net_telegraph_progress = 0.0
		_update_telegraph_visual(false, Vector2.ZERO, 0.0)
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	var to_player := _target_player.global_position - global_position
	var in_range := to_player.length() <= range_world
	var aim_dir := to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	if in_range:
		_face_direction(aim_dir)
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
		if _cooldown_remaining <= 0.0:
			_fire_arrow(aim_dir)
			_cooldown_remaining = fire_cooldown
	else:
		# Leaving range cancels stored charge; next shot needs a full wind-up.
		_cooldown_remaining = maxf(0.01, fire_cooldown)
	var denom := maxf(0.01, fire_cooldown)
	var charge_progress := 1.0 - clampf(_cooldown_remaining / denom, 0.0, 1.0)
	_net_telegraph_in_range = in_range
	_net_telegraph_dir = aim_dir
	_net_telegraph_progress = charge_progress
	_update_telegraph_visual(in_range, aim_dir, charge_progress)
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _refresh_target_lock(range_world: float) -> void:
	var current_presence: Dictionary = {}
	var best_entrant: Node2D = null
	var best_entrant_d2 := INF
	var best_entrant_peer_id := 0
	var best_entrant_name := ""
	var tree := get_tree()
	if tree != null:
		var range_world_sq := range_world * range_world
		for node in tree.get_nodes_in_group(&"player"):
			if node is not Node2D:
				continue
			var candidate := node as Node2D
			if not _is_targetable_player(candidate):
				continue
			var candidate_d2 := global_position.distance_squared_to(candidate.global_position)
			if candidate_d2 > range_world_sq:
				continue
			var instance_id := candidate.get_instance_id()
			current_presence[instance_id] = true
			var was_in_range := bool(_in_range_presence_by_instance_id.get(instance_id, false))
			if was_in_range:
				continue
			var candidate_peer_id := _peer_id_for_player_candidate(candidate)
			var candidate_name := String(candidate.name)
			if (
				best_entrant == null
				or _is_better_player_target_choice(
					candidate_d2,
					candidate_peer_id,
					candidate_name,
					best_entrant_d2,
					best_entrant_peer_id,
					best_entrant_name
				)
			):
				best_entrant = candidate
				best_entrant_d2 = candidate_d2
				best_entrant_peer_id = candidate_peer_id
				best_entrant_name = candidate_name
	var keep_target := false
	if _target_player != null and is_instance_valid(_target_player):
		keep_target = (
			current_presence.has(_target_player.get_instance_id())
			and not _is_player_downed_node(_target_player)
		)
	if not keep_target:
		_target_player = best_entrant
		if _target_player != null:
			# New lock always starts from a full charge to keep behavior predictable.
			_cooldown_remaining = maxf(0.01, fire_cooldown)
	_in_range_presence_by_instance_id = current_presence


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ir": _net_telegraph_in_range,
		"dir": _net_telegraph_dir,
		"cp": _net_telegraph_progress,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_net_telegraph_in_range = bool(state.get("ir", _net_telegraph_in_range))
	var dir_v: Variant = state.get("dir", _net_telegraph_dir)
	if dir_v is Vector2:
		var dir := dir_v as Vector2
		if dir.length_squared() > 0.0001:
			_net_telegraph_dir = dir.normalized()
	_net_telegraph_progress = clampf(float(state.get("cp", _net_telegraph_progress)), 0.0, 1.0)


func _face_direction(dir: Vector2) -> void:
	if _visual == null:
		return
	if dir.length_squared() <= 0.0001:
		return
	_visual.rotation.y = atan2(dir.x, dir.y) + deg_to_rad(facing_yaw_offset_deg)


func _fire_arrow(dir: Vector2) -> void:
	if not is_damage_authority():
		return
	_server_arrow_event_sequence += 1
	var event_sequence := _server_arrow_event_sequence
	if not _spawn_tower_arrow(global_position, dir, true, event_sequence):
		return
	if _can_broadcast_world_replication():
		_rpc_receive_tower_arrow_event.rpc(event_sequence, global_position, dir)


func _spawn_tower_arrow(
	spawn_position: Vector2,
	dir: Vector2,
	authoritative_damage: bool,
	projectile_event_id: int = -1
) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	if not authoritative_damage and projectile_event_id > 0:
		var existing_v: Variant = _remote_projectiles_by_event_id.get(projectile_event_id, null)
		if existing_v is ArrowProjectile and is_instance_valid(existing_v):
			return true
	var arrow := ARROW_PROJECTILE_SCENE.instantiate() as ArrowProjectile
	if arrow == null:
		return false
	arrow.speed = arrow_speed
	arrow.max_distance = arrow_max_tiles * world_units_per_tile
	arrow.damage = arrow_damage
	if arrow.has_method(&"set_authoritative_damage"):
		arrow.call(&"set_authoritative_damage", authoritative_damage)
	arrow.configure(spawn_position, dir, _vw, false, &"red", projectile_event_id)
	parent.add_child(arrow)
	if authoritative_damage and _is_server_peer() and projectile_event_id > 0 and arrow.has_signal(&"projectile_finished"):
		arrow.projectile_finished.connect(
			_on_server_authoritative_tower_projectile_finished.bind(projectile_event_id),
			CONNECT_ONE_SHOT
		)
	elif not authoritative_damage and projectile_event_id > 0:
		_remote_projectiles_by_event_id[projectile_event_id] = arrow
	return true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_tower_arrow_event(
	event_sequence: int, spawn_position: Vector2, facing_dir: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_arrow_event_sequence:
		return
	_last_applied_arrow_event_sequence = event_sequence
	_spawn_tower_arrow(spawn_position, facing_dir, false, event_sequence)


func _on_server_authoritative_tower_projectile_finished(
	final_position: Vector2, projectile_event_id: int
) -> void:
	if not _is_server_peer():
		return
	if not _multiplayer_active():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_receive_tower_arrow_projectile_finished.rpc(projectile_event_id, final_position)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_tower_arrow_projectile_finished(
	projectile_event_id: int, final_position: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var projectile_v: Variant = _remote_projectiles_by_event_id.get(projectile_event_id, null)
	if projectile_v == null or not is_instance_valid(projectile_v):
		_remote_projectiles_by_event_id.erase(projectile_event_id)
		return
	var projectile := projectile_v as ArrowProjectile
	if projectile == null:
		_remote_projectiles_by_event_id.erase(projectile_event_id)
		return
	projectile.global_position = final_position
	if projectile.has_method(&"_finish_projectile"):
		projectile.call(&"_finish_projectile")
	else:
		projectile.queue_free()
	_remote_projectiles_by_event_id.erase(projectile_event_id)


func _update_telegraph_visual(in_range: bool, dir: Vector2, progress: float) -> void:
	if _telegraph_mesh == null:
		return
	if not in_range:
		_telegraph_mesh.visible = false
		return
	_telegraph_mesh.visible = true
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	var right := Vector2(-d.y, d.x)
	var base := global_position
	var shaft_len := maxf(0.1, telegraph_arrow_length - telegraph_arrow_head_length)
	var shaft_end := base + d * shaft_len
	var tip := base + d * telegraph_arrow_length
	var l0 := base + right * telegraph_arrow_half_width
	var r0 := base - right * telegraph_arrow_half_width
	var l1 := shaft_end + right * telegraph_arrow_half_width
	var r1 := shaft_end - right * telegraph_arrow_half_width
	var h1 := shaft_end + right * (telegraph_arrow_half_width * 1.8)
	var h2 := shaft_end - right * (telegraph_arrow_half_width * 1.8)
	var fill_tip := base + d * (telegraph_arrow_length * progress)

	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
	for pair in [[l0, l1], [l1, h1], [h1, tip], [tip, h2], [h2, r1], [r1, r0], [r0, l0]]:
		var a := pair[0] as Vector2
		var b := pair[1] as Vector2
		imm.surface_add_vertex(Vector3(a.x, telegraph_ground_y, a.y))
		imm.surface_add_vertex(Vector3(b.x, telegraph_ground_y, b.y))
	imm.surface_end()

	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
	var tri_a := base + right * (telegraph_arrow_half_width * 0.55)
	var tri_b := base - right * (telegraph_arrow_half_width * 0.55)
	for v in [tri_a, tri_b, fill_tip]:
		imm.surface_add_vertex(Vector3(v.x, telegraph_ground_y + 0.001, v.y))
	imm.surface_end()
	_telegraph_mesh.mesh = imm


func _sync_visual() -> void:
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	pass


func can_contact_damage() -> bool:
	return false


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		_target_player = null
		_in_range_presence_by_instance_id.clear()
		_cooldown_remaining = maxf(0.01, fire_cooldown)
		_update_telegraph_visual(false, Vector2.ZERO, 0.0)


func _exit_tree() -> void:
	_remote_projectiles_by_event_id.clear()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func get_shadow_visual_root() -> Node3D:
	return _visual


func _pick_target_player() -> Node2D:
	return _pick_nearest_player_target()
