extends CharacterBody2D
class_name EnemyBase

signal squashed
signal coin_drop_requested(spawn_position: Vector2, coin_value: int)

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")

@export var max_health := 50
@export var drops_coin_on_death := true
@export var coin_drop_value := 1
@export var show_damage_text := true
@export var damage_text_world_y := 2.8
@export var damage_text_rise := 1.6
@export var damage_text_duration := 0.7
@export var damage_text_font_size := 220
@export var network_sync_interval := 0.05
@export var remote_interpolation_lerp_rate := 14.0
@export var remote_interpolation_snap_distance := 6.0

var _health := 0
var _dead := false
var _last_authoritative_hit_event_id := -1
var _network_sync_time_accum := 0.0
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _remote_has_state := false


func _ready() -> void:
	_health = max_health
	if _multiplayer_active() and not _is_server_peer():
		# Client enemy nodes are visual proxies only; server owns gameplay collisions.
		set_deferred(&"collision_layer", 0)
		set_deferred(&"collision_mask", 0)


func _multiplayer_api_safe() -> MultiplayerAPI:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_multiplayer()


func _multiplayer_active() -> bool:
	var mp := _multiplayer_api_safe()
	return mp != null and mp.multiplayer_peer != null


func _is_server_peer() -> bool:
	var mp := _multiplayer_api_safe()
	return mp != null and mp.multiplayer_peer != null and mp.is_server()


func _can_broadcast_world_replication() -> bool:
	if not _multiplayer_active() or not _is_server_peer():
		return true
	var session := get_node_or_null("/root/NetworkSession")
	if session != null and session.has_method("can_broadcast_world_replication"):
		return bool(session.call("can_broadcast_world_replication"))
	return true

func _enemy_network_compact_state() -> Dictionary:
	return {}


func _enemy_network_apply_remote_state(_state: Dictionary) -> void:
	pass


func _enemy_network_server_broadcast(delta: float) -> void:
	if not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_network_sync_time_accum += delta
	if _network_sync_time_accum < network_sync_interval:
		return
	_network_sync_time_accum = 0.0
	_rpc_receive_enemy_transform_state.rpc(global_position, velocity, _enemy_network_compact_state())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_enemy_transform_state(
	world_pos: Vector2, planar_velocity: Vector2, compact_state: Dictionary
) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	_remote_target_position = world_pos
	_remote_target_velocity = planar_velocity
	_remote_has_state = true
	_enemy_network_apply_remote_state(compact_state)


func _enemy_network_client_interpolate(delta: float) -> void:
	if not _remote_has_state:
		return
	var dist_to_target := global_position.distance_to(_remote_target_position)
	if dist_to_target >= remote_interpolation_snap_distance:
		global_position = _remote_target_position
		velocity = _remote_target_velocity
		return
	var alpha := clampf(delta * remote_interpolation_lerp_rate, 0.0, 1.0)
	global_position = global_position.lerp(_remote_target_position, alpha)
	velocity = velocity.lerp(_remote_target_velocity, alpha)


func configure_spawn(start_position: Vector2, _player_position: Vector2) -> void:
	global_position = start_position


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func set_aggro_enabled(_enabled: bool) -> void:
	pass


func apply_authoritative_hit_event(
	hit_event_id: int, damage: int, knockback_dir: Vector2, knockback_strength: float
) -> bool:
	if hit_event_id >= 0 and hit_event_id <= _last_authoritative_hit_event_id:
		return false
	if hit_event_id >= 0:
		_last_authoritative_hit_event_id = hit_event_id
	take_hit(damage, knockback_dir, knockback_strength)
	return true


func take_hit(damage: int, knockback_dir: Vector2, knockback_strength: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		return
	if damage <= 0 or _dead:
		return
	if show_damage_text:
		_show_floating_damage_text(damage)
		_broadcast_damage_text(damage)
	_health = maxi(0, _health - damage)
	if _health <= 0:
		squash()
		return
	_on_nonlethal_hit(knockback_dir, knockback_strength)


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	pass


func can_contact_damage() -> bool:
	return false


func squash() -> void:
	if _dead:
		return
	_dead = true
	squashed.emit()
	if drops_coin_on_death:
		_spawn_dropped_coin()
	queue_free()


func _spawn_dropped_coin() -> void:
	if not coin_drop_requested.get_connections().is_empty():
		coin_drop_requested.emit(global_position, maxi(1, coin_drop_value))
		return
	var parent := get_parent()
	if parent == null:
		return
	var coin := DROPPED_COIN_SCENE.instantiate() as Node2D
	if coin == null:
		return
	# add_child during body_entered / physics flush mutates Area2D state; defer to next idle/safe frame.
	coin.position = parent.to_local(global_position)
	parent.call_deferred("add_child", coin)


func _resolve_visual_world_3d() -> Node3D:
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		var direct := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
		if direct != null:
			return direct
	var n: Node = self
	while n != null:
		var par := n.get_parent()
		if par == null:
			break
		var gpr := par.get_parent()
		if gpr != null:
			var vw := gpr.get_node_or_null("VisualWorld3D") as Node3D
			if vw != null:
				return vw
		n = par
	return null


func _show_floating_damage_text(damage: int) -> void:
	_show_floating_damage_text_at(damage, global_position)


func _show_floating_damage_text_at(damage: int, world_pos: Vector2) -> void:
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	var text := Label3D.new()
	text.text = "-%s HP" % [damage]
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.font_size = damage_text_font_size
	text.outline_size = 16
	text.modulate = Color(1.0, 0.15, 0.15, 1.0)
	text.position = Vector3(world_pos.x, damage_text_world_y, world_pos.y)
	vw.add_child(text)
	var tween := text.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		text,
		"position",
		text.position + Vector3(0.0, damage_text_rise, 0.0),
		damage_text_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(text, "modulate:a", 0.0, damage_text_duration).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN
	)
	tween.chain().tween_callback(text.queue_free)


func _broadcast_damage_text(damage: int) -> void:
	if not _multiplayer_active() or not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_show_damage_text.rpc(damage, global_position)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_show_damage_text(damage: int, world_pos: Vector2) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	_show_floating_damage_text_at(damage, world_pos)


func _is_player_downed_node(candidate: Node2D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if candidate.has_method(&"is_downed"):
		return bool(candidate.call(&"is_downed"))
	return false


func _is_targetable_player(candidate: Node2D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	return not _is_player_downed_node(candidate)


func _pick_nearest_player_target() -> Node2D:
	var candidates: Array[Dictionary] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(&"player"):
		if node is not Node2D:
			continue
		var candidate := node as Node2D
		if not _is_targetable_player(candidate):
			continue
		var peer_id := int(candidate.get_meta(&"peer_id", 0))
		if peer_id <= 0 and candidate.has_meta(&"network_owner_peer_id"):
			peer_id = int(candidate.get_meta(&"network_owner_peer_id", 0))
		candidates.append(
			{
				"node": candidate,
				"d2": global_position.distance_squared_to(candidate.global_position),
				"peer_id": peer_id,
				"name": String(candidate.name),
			}
		)
	if candidates.is_empty():
		return null
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var d2_a := float(a.get("d2", INF))
			var d2_b := float(b.get("d2", INF))
			if not is_equal_approx(d2_a, d2_b):
				return d2_a < d2_b
			var peer_a := int(a.get("peer_id", 0))
			var peer_b := int(b.get("peer_id", 0))
			if peer_a != peer_b:
				return peer_a < peer_b
			var name_a := String(a.get("name", ""))
			var name_b := String(b.get("name", ""))
			return name_a < name_b
	)
	var best_v: Variant = candidates[0].get("node", null)
	return best_v as Node2D
