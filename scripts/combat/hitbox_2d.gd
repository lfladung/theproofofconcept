extends Area2D
class_name Hitbox2D

signal hitbox_activated(packet: DamagePacket, attack_instance_id: int)
signal hitbox_deactivated()

enum RepeatMode { NONE, INTERVAL }

@export var owner_path: NodePath
@export var repeat_mode: RepeatMode = RepeatMode.NONE
@export var repeat_interval_sec := 0.65
@export var debug_logging := false
@export var debug_draw_enabled := false
@export var debug_label: StringName = &""
@export var max_query_results := 32

var _active := false
var _duration_remaining := -1.0
var _packet_template: DamagePacket
var _target_states: Dictionary = {}
var _present_targets: Dictionary = {}
var _attack_sequence := 0
var _last_resolved_count := 0


func _ready() -> void:
	monitoring = false
	monitorable = false
	set_physics_process(false)
	queue_redraw()


func activate(packet_template: DamagePacket, duration_sec: float = -1.0) -> int:
	if packet_template == null:
		return -1
	_packet_template = packet_template.duplicate_packet()
	if _packet_template.source_node == null:
		_packet_template.source_node = get_owner_node()
	if _packet_template.source_uid <= 0:
		_packet_template.source_uid = get_instance_id()
	if _packet_template.attack_instance_id <= 0:
		_packet_template.attack_instance_id = _consume_attack_instance_id()
	_active = true
	_duration_remaining = duration_sec
	_target_states.clear()
	_present_targets.clear()
	_last_resolved_count = 0
	set_physics_process(true)
	queue_redraw()
	_log("activated %s" % [_packet_template.describe()])
	hitbox_activated.emit(_packet_template, _packet_template.attack_instance_id)
	_scan_hurtboxes()
	return _packet_template.attack_instance_id


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_duration_remaining = -1.0
	_target_states.clear()
	_present_targets.clear()
	_last_resolved_count = 0
	set_physics_process(false)
	queue_redraw()
	_log("deactivated")
	hitbox_deactivated.emit()


func is_active() -> bool:
	return _active


func get_last_resolved_count() -> int:
	return _last_resolved_count


func update_packet_template(packet_template: DamagePacket) -> void:
	if packet_template == null:
		return
	var existing_attack_id := _packet_template.attack_instance_id if _packet_template != null else -1
	_packet_template = packet_template.duplicate_packet()
	if _packet_template.source_node == null:
		_packet_template.source_node = get_owner_node()
	if _packet_template.source_uid <= 0:
		_packet_template.source_uid = get_instance_id()
	if _packet_template.attack_instance_id <= 0 and existing_attack_id > 0:
		_packet_template.attack_instance_id = existing_attack_id


func get_owner_node() -> Node:
	if owner_path != NodePath():
		return get_node_or_null(owner_path)
	return get_parent()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _duration_remaining > 0.0:
		_duration_remaining = maxf(0.0, _duration_remaining - delta)
	_scan_hurtboxes()
	if _duration_remaining == 0.0:
		deactivate()
	queue_redraw()


func _scan_hurtboxes() -> void:
	if _packet_template == null:
		return
	var now := _now_sec()
	var seen_targets: Dictionary = {}
	var resolved_count := 0
	for hurtbox in _query_hurtboxes():
		if hurtbox == null or not is_instance_valid(hurtbox):
			continue
		var target_uid := hurtbox.get_target_uid()
		seen_targets[target_uid] = true
		if not _present_targets.has(target_uid):
			_present_targets[target_uid] = true
			_log("overlap_began target=%s hurtbox=%s" % [target_uid, String(hurtbox.debug_label)])
		var state: Dictionary = _target_states.get(
			target_uid,
			{
				"resolved_once": false,
				"next_allowed_time": 0.0,
			}
		)
		if repeat_mode == RepeatMode.NONE and bool(state.get("resolved_once", false)):
			continue
		if now < float(state.get("next_allowed_time", 0.0)):
			continue
		var packet := _packet_template.duplicate_packet()
		if repeat_mode == RepeatMode.INTERVAL and bool(state.get("resolved_once", false)):
			packet.attack_instance_id = _consume_attack_instance_id()
		var receiver := hurtbox.get_receiver_component()
		if receiver == null:
			_log("rejected_missing_receiver target=%s" % [target_uid])
			continue
		var result := receiver.receive_damage(packet, hurtbox)
		var consume_hit := bool(result.get("consume_hit", false))
		var accepted := bool(result.get("accepted", false))
		var reason := StringName(String(result.get("reason", "")))
		if accepted:
			_log("applied target=%s attack=%s" % [target_uid, packet.attack_instance_id])
		else:
			_log("rejected target=%s attack=%s reason=%s" % [
				target_uid,
				packet.attack_instance_id,
				String(reason),
			])
		if consume_hit:
			resolved_count += 1
			state["resolved_once"] = true
			if repeat_mode == RepeatMode.INTERVAL:
				state["next_allowed_time"] = now + maxf(0.0, repeat_interval_sec)
			else:
				state["next_allowed_time"] = INF
			_target_states[target_uid] = state
	for target_uid in _present_targets.keys():
		if not seen_targets.has(target_uid):
			_present_targets.erase(target_uid)
	_last_resolved_count = resolved_count


func _query_hurtboxes() -> Array[Hurtbox2D]:
	var hurtboxes_by_target: Dictionary = {}
	var world_2d := get_world_2d()
	if world_2d == null:
		return []
	var direct_space_state := world_2d.direct_space_state
	for shape_node in _shape_nodes():
		if shape_node.disabled or shape_node.shape == null:
			continue
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = shape_node.shape
		params.transform = shape_node.global_transform
		params.collision_mask = collision_mask
		params.collide_with_areas = true
		params.collide_with_bodies = false
		params.exclude = _query_exclude_rids()
		var hits := direct_space_state.intersect_shape(params, max_query_results)
		for hit_v in hits:
			var hit: Dictionary = hit_v
			var collider_v: Variant = hit.get("collider", null)
			if collider_v is not Hurtbox2D:
				continue
			var hurtbox := collider_v as Hurtbox2D
			if not hurtbox.is_active():
				continue
			var target_uid := hurtbox.get_target_uid()
			if not hurtboxes_by_target.has(target_uid):
				hurtboxes_by_target[target_uid] = hurtbox
	var hurtboxes: Array[Hurtbox2D] = []
	for hurtbox_v in hurtboxes_by_target.values():
		hurtboxes.append(hurtbox_v as Hurtbox2D)
	return hurtboxes


func _query_exclude_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	var owner_node := get_owner_node()
	if owner_node is CollisionObject2D:
		rids.append((owner_node as CollisionObject2D).get_rid())
	return rids


func _shape_nodes() -> Array[CollisionShape2D]:
	var nodes: Array[CollisionShape2D] = []
	for child in get_children():
		if child is CollisionShape2D:
			nodes.append(child as CollisionShape2D)
	return nodes


func _consume_attack_instance_id() -> int:
	_attack_sequence += 1
	return _attack_sequence


func _draw() -> void:
	if not debug_draw_enabled:
		return
	var color := Color(1.0, 0.35, 0.12, 0.72) if _active else Color(0.6, 0.6, 0.6, 0.35)
	for shape_node in _shape_nodes():
		if shape_node.shape is CircleShape2D:
			var circle := shape_node.shape as CircleShape2D
			draw_arc(shape_node.position, circle.radius, 0.0, TAU, 32, color, 2.0)
		elif shape_node.shape is RectangleShape2D:
			var rect := shape_node.shape as RectangleShape2D
			var half := rect.size * 0.5
			var transform_2d := shape_node.transform
			var points := PackedVector2Array([
				transform_2d * Vector2(-half.x, -half.y),
				transform_2d * Vector2(half.x, -half.y),
				transform_2d * Vector2(half.x, half.y),
				transform_2d * Vector2(-half.x, half.y),
			])
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, color, 2.0)


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0


func _log(message: String) -> void:
	if not debug_logging:
		return
	print("[Combat][Hitbox][%s] %s" % [String(debug_label), message])
