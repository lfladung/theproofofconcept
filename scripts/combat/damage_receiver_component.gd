extends Node
class_name DamageReceiverComponent

signal damage_applied(packet: DamagePacket, hp_damage: int, hurtbox: Area2D)
signal damage_rejected(packet: DamagePacket, reason: StringName, hurtbox: Area2D)

const _SEEN_ATTACK_ID_MEMORY_SEC := 5.0

@export var owner_path: NodePath
@export var health_component_path: NodePath
@export var authoritative_only := true
@export var debug_logging := false
@export var debug_label: StringName = &""

var _active := true
var _seen_attack_ids: Dictionary = {}


func _ready() -> void:
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _seen_attack_ids.is_empty():
		return
	var now := _now_sec()
	var stale: Array = []
	for key in _seen_attack_ids.keys():
		if now >= float(_seen_attack_ids[key]):
			stale.append(key)
	for key in stale:
		_seen_attack_ids.erase(key)


func set_active(enabled: bool) -> void:
	_active = enabled


func get_owner_node() -> Node:
	if owner_path != NodePath():
		return get_node_or_null(owner_path)
	return get_parent()


func get_health_component() -> HealthComponent:
	if health_component_path != NodePath():
		return get_node_or_null(health_component_path) as HealthComponent
	for child in get_children():
		if child is HealthComponent:
			return child as HealthComponent
	return null


func get_current_health() -> int:
	var health_component := get_health_component()
	if health_component == null:
		return 0
	return health_component.current_health


func receive_damage(packet: DamagePacket, hurtbox: Area2D = null) -> Dictionary:
	if packet == null:
		return _finalize_result(packet, hurtbox, _result(false, false, &"missing_packet", 0))
	if not _active:
		return _finalize_result(packet, hurtbox, _result(false, false, &"inactive", 0))
	if authoritative_only and not _is_damage_authority():
		return _finalize_result(packet, hurtbox, _result(false, false, &"not_authority", 0))
	var health_component := get_health_component()
	if health_component == null:
		return _finalize_result(packet, hurtbox, _result(false, false, &"missing_health", 0))
	var attack_key := _attack_key_for(packet)
	if attack_key != "" and _seen_attack_ids.has(attack_key):
		return _finalize_result(packet, hurtbox, _result(false, true, &"duplicate_attack", 0))
	var result := _process_damage(packet, hurtbox, health_component)
	return _finalize_result(packet, hurtbox, result)


func _process_damage(
	packet: DamagePacket, _hurtbox: Area2D, health_component: HealthComponent
) -> Dictionary:
	return health_component.apply_damage(packet)


func _finalize_result(packet: DamagePacket, hurtbox: Area2D, result: Dictionary) -> Dictionary:
	var consume_hit := bool(result.get("consume_hit", false))
	var accepted := bool(result.get("accepted", false))
	var reason := StringName(String(result.get("reason", "")))
	var attack_key := _attack_key_for(packet)
	var packet_desc := packet.describe() if packet != null else "<null>"
	if consume_hit and attack_key != "":
		_seen_attack_ids[attack_key] = _now_sec() + _SEEN_ATTACK_ID_MEMORY_SEC
	if accepted:
		damage_applied.emit(packet, int(result.get("hp_damage", 0)), hurtbox)
		_log("applied %s" % [packet_desc])
	else:
		damage_rejected.emit(packet, reason, hurtbox)
		_log("rejected %s reason=%s" % [packet_desc, String(reason)])
	return result


func _result(accepted: bool, consume_hit: bool, reason: StringName, hp_damage: int) -> Dictionary:
	return {
		"accepted": accepted,
		"consume_hit": consume_hit,
		"reason": reason,
		"hp_damage": hp_damage,
	}


func _attack_key_for(packet: DamagePacket) -> String:
	if packet == null or packet.attack_instance_id <= 0:
		return ""
	return "%s:%s" % [packet.resolve_source_uid(), packet.attack_instance_id]


func _is_damage_authority() -> bool:
	var owner_node := get_owner_node()
	if owner_node == null:
		return true
	if owner_node.has_method(&"is_damage_authority"):
		return bool(owner_node.call(&"is_damage_authority"))
	if owner_node.has_method(&"_multiplayer_active") and owner_node.has_method(&"_is_server_peer"):
		var multiplayer_active := bool(owner_node.call(&"_multiplayer_active"))
		if not multiplayer_active:
			return true
		return bool(owner_node.call(&"_is_server_peer"))
	return true


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0


func _log(message: String) -> void:
	if not debug_logging:
		return
	print("[Combat][Receiver][%s] %s" % [String(debug_label), message])
