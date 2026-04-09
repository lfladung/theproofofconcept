class_name EdgeFamilyBase
extends EnemyBase

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const EdgeLineTelegraphMeshScript = preload("res://scripts/entities/edge_line_telegraph_mesh.gd")

@export var target_refresh_interval := 0.3
@export var mesh_ground_y := 0.2
@export var mesh_scale := Vector3.ONE
@export var edge_clip_scale := 2.5
@export var facing_yaw_offset_deg := 180.0
@export var turn_toward_facing_deg_per_sec := 360.0
@export var telegraph_ground_y := 0.06
@export var telegraph_line_half_width := 0.16
@export var telegraph_progress_steps := 10
@export var telegraph_outline_color := Color(0.0, 0.0, 0.0, 1.0)
@export var telegraph_fill_color := Color(1.0, 0.18, 0.12, 0.78)

var _visual: EnemyStateVisual
var _vw: Node3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _planar_facing := Vector2(0.0, -1.0)
var _telegraph_mesh: MeshInstance3D
var _telegraph_outline_mat: StandardMaterial3D
var _telegraph_fill_mat: StandardMaterial3D
var _telegraph_meshes: Array[Mesh] = []
var _telegraph_progress_step := -1
var _telegraph_cached_length := -1.0
var _telegraph_cached_half_width := -1.0
var _edge_attack_sequence := 0


func get_shadow_visual_root() -> Node3D:
	return _visual


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func _ready() -> void:
	super._ready()
	_vw = _resolve_visual_world_3d()
	if _vw != null:
		_visual = EnemyStateVisualScript.new()
		_visual.name = &"EdgeVisual"
		_visual.mesh_ground_y = mesh_ground_y
		_visual.mesh_scale = mesh_scale
		_visual.facing_yaw_offset_deg = facing_yaw_offset_deg
		_visual.configure_states(_build_visual_state_config())
		_vw.add_child(_visual)
		_telegraph_mesh = MeshInstance3D.new()
		_telegraph_mesh.name = &"EdgeTelegraph"
		_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_mesh.visible = false
		_telegraph_outline_mat = EdgeLineTelegraphMeshScript.create_outline_material(
			telegraph_outline_color
		)
		_telegraph_fill_mat = EdgeLineTelegraphMeshScript.create_fill_material(
			telegraph_fill_color
		)
		_vw.add_child(_telegraph_mesh)
	_sync_visual_from_body()
	_target_player = _pick_target_player()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func _enemy_network_compact_state() -> Dictionary:
	var state := {
		"pf": _planar_facing,
	}
	_edge_network_write_state(state)
	return state


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	var facing_v: Variant = state.get("pf", _planar_facing)
	if facing_v is Vector2:
		var facing := facing_v as Vector2
		if facing.length_squared() > 0.0001:
			_planar_facing = facing.normalized()
	_edge_network_read_state(state)


func _edge_network_write_state(_state: Dictionary) -> void:
	pass


func _edge_network_read_state(_state: Dictionary) -> void:
	pass


func _edge_character_scene() -> PackedScene:
	return null


func _build_visual_state_config() -> Dictionary:
	var scene := _edge_character_scene()
	if scene == null:
		return {}
	return build_single_scene_visual_state_config(scene, edge_clip_scale)


func _resolve_visual_state_name() -> StringName:
	if velocity.length_squared() > 0.01:
		return &"walk"
	return &"idle"


func _resolve_visual_facing_direction() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	if velocity.length_squared() > 1e-6:
		return velocity.normalized()
	return Vector2(0.0, -1.0)


func _current_attack_shake_progress() -> float:
	return 0.0


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(_edge_should_use_high_detail_visuals())
	_visual.set_attack_shake_progress(_current_attack_shake_progress())
	_visual.set_state(_resolve_visual_state_name())
	_visual.sync_from_2d(global_position, _resolve_visual_facing_direction())


func _edge_should_use_high_detail_visuals() -> bool:
	if _target_player != null and is_instance_valid(_target_player):
		return global_position.distance_squared_to(_target_player.global_position) <= 20.0 * 20.0
	return velocity.length_squared() > 0.04


func _pick_target_player() -> Node2D:
	return _pick_nearest_player_target()


func _refresh_target_player(delta: float, allow_retarget: bool = true) -> void:
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		allow_retarget,
		Callable(self, "_pick_target_player")
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(
		refresh.get("refresh_time_remaining", _target_refresh_time_remaining)
	)


func _steer_planar_facing_toward(direction: Vector2, delta: float, max_deg_per_sec: float = -1.0) -> void:
	var desired := direction
	if desired.length_squared() <= 0.0001:
		return
	var turn_rate := turn_toward_facing_deg_per_sec if max_deg_per_sec < 0.0 else max_deg_per_sec
	var max_step := deg_to_rad(maxf(0.0, turn_rate)) * maxf(0.0, delta)
	_planar_facing = EnemyBase.step_planar_facing_toward(_planar_facing, desired, max_step)


func _set_single_line_telegraph(
	active: bool,
	start_pos: Vector2,
	direction: Vector2,
	line_length: float,
	progress: float,
	line_half_width: float = -1.0
) -> void:
	if _telegraph_mesh == null or not is_instance_valid(_telegraph_mesh):
		return
	if not active:
		_telegraph_mesh.visible = false
		_telegraph_progress_step = -1
		return
	var half_width := telegraph_line_half_width if line_half_width <= 0.0 else line_half_width
	if (
		not is_equal_approx(line_length, _telegraph_cached_length)
		or not is_equal_approx(half_width, _telegraph_cached_half_width)
	):
		_telegraph_cached_length = line_length
		_telegraph_cached_half_width = half_width
		_telegraph_meshes.clear()
		for step in range(telegraph_progress_steps + 1):
			_telegraph_meshes.append(
				EdgeLineTelegraphMeshScript.build_mesh_for_step(
					step,
					telegraph_progress_steps,
					line_length,
					half_width,
					_telegraph_outline_mat,
					_telegraph_fill_mat
				)
			)
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	_telegraph_mesh.visible = true
	_telegraph_mesh.global_position = Vector3(start_pos.x, telegraph_ground_y, start_pos.y)
	_telegraph_mesh.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
	var progress_step := int(round(clampf(progress, 0.0, 1.0) * float(telegraph_progress_steps)))
	if progress_step == _telegraph_progress_step:
		return
	_telegraph_progress_step = progress_step
	if progress_step >= 0 and progress_step < _telegraph_meshes.size():
		_telegraph_mesh.mesh = _telegraph_meshes[progress_step]


func _edge_apply_precision_line_damage(
	line_start: Vector2,
	line_end: Vector2,
	full_half_width: float,
	full_damage: int,
	reduced_half_width: float,
	reduced_damage: int,
	debug_label: StringName,
	attack_instance_id: int = -1,
	blockable: bool = true,
	guard_split_ratio: float = 0.5,
	knockback: float = 0.0,
	ignore_directional_guard: bool = false
) -> bool:
	if not is_damage_authority():
		return false
	var path := line_end - line_start
	if path.length_squared() <= 0.0001:
		return false
	var attack_id := attack_instance_id
	if attack_id <= 0:
		attack_id = _consume_edge_attack_instance_id()
	var direction := path.normalized()
	var did_hit := false
	var strongest_half_width := maxf(full_half_width, reduced_half_width)
	for candidate in _targetable_player_candidates():
		if not _is_targetable_player(candidate):
			continue
		var receiver := _edge_player_damage_receiver(candidate)
		var hurtbox := _edge_player_hurtbox(candidate)
		if receiver == null or hurtbox == null:
			continue
		var body_radius := _edge_player_body_radius(hurtbox)
		var closest := Geometry2D.get_closest_point_to_segment(candidate.global_position, line_start, line_end)
		var dist := candidate.global_position.distance_to(closest)
		if dist > strongest_half_width + body_radius:
			continue
		var damage := full_damage if dist <= full_half_width + body_radius else reduced_damage
		if damage <= 0:
			continue
		var packet := DamagePacketScript.new() as DamagePacket
		packet.amount = damage
		packet.kind = &"edge_line"
		packet.source_node = self
		packet.source_uid = get_instance_id()
		packet.attack_instance_id = attack_id
		packet.origin = closest
		packet.direction = direction
		packet.knockback = knockback
		packet.apply_iframes = true
		packet.blockable = blockable
		packet.guard_stamina_split_ratio = guard_split_ratio
		packet.ignore_directional_guard = ignore_directional_guard
		packet.debug_label = debug_label
		var result := receiver.receive_damage(packet, hurtbox)
		if bool(result.get("consume_hit", false)):
			did_hit = true
	return did_hit


func _edge_player_hurtbox(candidate: Node2D) -> Hurtbox2D:
	if candidate == null:
		return null
	var hurtbox := candidate.get_node_or_null("PlayerHurtbox") as Hurtbox2D
	if hurtbox != null:
		return hurtbox
	for child in candidate.get_children():
		if child is Hurtbox2D:
			return child as Hurtbox2D
	return null


func _edge_player_damage_receiver(candidate: Node2D) -> DamageReceiverComponent:
	var hurtbox := _edge_player_hurtbox(candidate)
	if hurtbox != null:
		return hurtbox.get_receiver_component()
	return null


func _edge_player_body_radius(hurtbox: Hurtbox2D) -> float:
	if hurtbox == null:
		return 0.76
	var shape_node := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius
	return 0.76


func _consume_edge_attack_instance_id() -> int:
	_edge_attack_sequence += 1
	return _edge_attack_sequence


func _hit_non_player_wall_this_frame() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var collider: Variant = collision.get_collider()
		if collider == null:
			return true
		if collider is Area2D:
			continue
		if collider is Node and (collider as Node).is_in_group(&"player"):
			continue
		return true
	return false
