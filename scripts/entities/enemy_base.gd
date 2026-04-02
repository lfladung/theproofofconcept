extends CharacterBody2D
class_name EnemyBase

signal squashed
signal coin_drop_requested(spawn_position: Vector2, coin_value: int)

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const DAMAGE_TEXT_STYLE_HP := &"hp"
const DAMAGE_TEXT_STYLE_BLOCK := &"block"
const DAMAGE_TEXT_HP_COLOR := Color(1.0, 0.15, 0.15, 1.0)
const DAMAGE_TEXT_BLOCK_COLOR := Color(0.25, 0.62, 1.0, 1.0)
const DAMAGE_TEXT_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const _PLAYER_ROSTER_CACHE_INTERVAL_USEC := 100000

static var _cached_player_nodes: Array = []
static var _cached_player_tree_id := 0
static var _cached_player_snapshot_usec := 0

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

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _damage_receiver: DamageReceiverComponent = $DamageReceiver
@onready var _hurtbox: Hurtbox2D = $EnemyHurtbox

var _health := 0
var _dead := false
var _last_authoritative_hit_event_id := -1
var _network_sync_time_accum := 0.0
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _remote_has_state := false


func _ready() -> void:
	if _health_component != null:
		_health_component.max_health = max_health
		_health_component.starting_health = max_health
		_health_component.set_current_health(max_health)
		_health_component.health_changed.connect(_on_health_component_changed)
		_health_component.depleted.connect(_on_health_component_depleted)
		_health = _health_component.current_health
	if _damage_receiver != null:
		_damage_receiver.damage_applied.connect(_on_receiver_damage_applied)
		_damage_receiver.damage_rejected.connect(_on_receiver_damage_rejected)
	if _multiplayer_active() and not _is_server_peer():
		# Client enemy nodes are visual proxies only; server owns gameplay collisions.
		set_deferred(&"collision_layer", 0)
		set_deferred(&"collision_mask", 0)
		if _hurtbox != null:
			_hurtbox.set_active(false)
	elif _hurtbox != null:
		_hurtbox.set_active(true)


func is_damage_authority() -> bool:
	return not _multiplayer_active() or _is_server_peer()


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
	if not _multiplayer_active():
		return false
	if not _is_server_peer():
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
	var packet := _build_damage_packet(
		damage,
		&"player_attack",
		global_position - knockback_dir.normalized(),
		knockback_dir,
		knockback_strength,
		false,
		hit_event_id
	)
	_receive_packet(packet)
	return true


func take_hit(damage: int, knockback_dir: Vector2, knockback_strength: float) -> void:
	var packet := _build_damage_packet(
		damage,
		&"player_attack",
		global_position - knockback_dir.normalized(),
		knockback_dir,
		knockback_strength,
		false
	)
	_receive_packet(packet)


func _receive_packet(packet: DamagePacket) -> void:
	if _damage_receiver == null:
		return
	_damage_receiver.receive_damage(packet, _hurtbox)


func _build_damage_packet(
	damage: int,
	kind: StringName,
	origin: Vector2,
	direction: Vector2,
	knockback_strength: float,
	blockable: bool,
	attack_instance_id: int = -1
) -> DamagePacket:
	var packet := DamagePacketScript.new() as DamagePacket
	packet.amount = damage
	packet.kind = kind
	packet.origin = origin
	packet.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO
	packet.knockback = knockback_strength
	packet.blockable = blockable
	packet.apply_iframes = false
	packet.attack_instance_id = attack_instance_id
	packet.debug_label = &"enemy_receive"
	return packet


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, _hurtbox_area: Area2D) -> void:
	if hp_damage <= 0:
		return
	_health = _health_component.current_health if _health_component != null else _health
	if show_damage_text:
		_show_floating_damage_text(hp_damage)
		_broadcast_damage_text(hp_damage)
	if _health > 0:
		_on_nonlethal_hit(packet.direction, packet.knockback)


func _on_receiver_damage_rejected(
	packet: DamagePacket, reason: StringName, _hurtbox_area: Area2D
) -> void:
	if reason != &"blocked_guard" or packet == null:
		return
	var blocked_damage := maxi(0, int(packet.amount))
	if blocked_damage <= 0:
		return
	if show_damage_text:
		_show_floating_damage_text_at(blocked_damage, global_position, DAMAGE_TEXT_STYLE_BLOCK)
		_broadcast_damage_text(blocked_damage, DAMAGE_TEXT_STYLE_BLOCK)


func _on_health_component_changed(current: int, _maximum: int) -> void:
	_health = current


func _on_health_component_depleted(_packet: DamagePacket) -> void:
	_health = 0
	squash()


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
	_show_floating_damage_text_at(damage, global_position, DAMAGE_TEXT_STYLE_HP)


func _show_floating_damage_text_at(
	damage: int, world_pos: Vector2, style_id: StringName = DAMAGE_TEXT_STYLE_HP
) -> void:
	var text := "-%s HP" % [damage]
	var color := DAMAGE_TEXT_HP_COLOR
	if style_id == DAMAGE_TEXT_STYLE_BLOCK:
		text = "-%s BLOCK" % [damage]
		color = DAMAGE_TEXT_BLOCK_COLOR
	_show_floating_combat_text_at(text, color, world_pos)


func _show_floating_combat_text_at(text_value: String, color: Color, world_pos: Vector2) -> void:
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	var text := Label3D.new()
	text.text = text_value
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.font_size = damage_text_font_size
	text.outline_size = 64
	text.outline_modulate = DAMAGE_TEXT_OUTLINE_COLOR
	text.modulate = color
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


func _broadcast_damage_text(
	damage: int, style_id: StringName = DAMAGE_TEXT_STYLE_HP
) -> void:
	if not _multiplayer_active() or not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_show_damage_text.rpc(damage, global_position, style_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_show_damage_text(
	damage: int, world_pos: Vector2, style_id: StringName = DAMAGE_TEXT_STYLE_HP
) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	_show_floating_damage_text_at(damage, world_pos, style_id)


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


func _peer_id_for_player_candidate(candidate: Node2D) -> int:
	if candidate == null:
		return 0
	var peer_id := int(candidate.get_meta(&"peer_id", 0))
	if peer_id <= 0 and candidate.has_meta(&"network_owner_peer_id"):
		peer_id = int(candidate.get_meta(&"network_owner_peer_id", 0))
	return peer_id


func _is_better_player_target_choice(
	candidate_d2: float,
	candidate_peer_id: int,
	candidate_name: String,
	best_d2: float,
	best_peer_id: int,
	best_name: String
) -> bool:
	if not is_equal_approx(candidate_d2, best_d2):
		return candidate_d2 < best_d2
	if candidate_peer_id != best_peer_id:
		return candidate_peer_id < best_peer_id
	return candidate_name < best_name


func _pick_nearest_player_target() -> Node2D:
	var best_node: Node2D = null
	var best_d2 := INF
	var best_peer_id := 0
	var best_name := ""
	for candidate in _targetable_player_candidates():
		if not _is_targetable_player(candidate):
			continue
		var candidate_d2 := global_position.distance_squared_to(candidate.global_position)
		var candidate_peer_id := _peer_id_for_player_candidate(candidate)
		var candidate_name := String(candidate.name)
		if (
			best_node == null
			or _is_better_player_target_choice(
				candidate_d2,
				candidate_peer_id,
				candidate_name,
				best_d2,
				best_peer_id,
				best_name
			)
		):
			best_node = candidate
			best_d2 = candidate_d2
			best_peer_id = candidate_peer_id
			best_name = candidate_name
	return best_node


func _targetable_player_candidates() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return out
	var tree_id := tree.get_instance_id()
	var now_usec := Time.get_ticks_usec()
	if (
		tree_id != _cached_player_tree_id
		or now_usec - _cached_player_snapshot_usec >= _PLAYER_ROSTER_CACHE_INTERVAL_USEC
	):
		_cached_player_nodes.clear()
		for node in tree.get_nodes_in_group(&"player"):
			if node is Node2D and is_instance_valid(node):
				_cached_player_nodes.append(node)
		_cached_player_tree_id = tree_id
		_cached_player_snapshot_usec = now_usec
	for node in _cached_player_nodes:
		if node is Node2D and is_instance_valid(node):
			out.append(node as Node2D)
	return out
