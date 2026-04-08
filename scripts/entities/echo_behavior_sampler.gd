extends RefCounted
class_name EchoBehaviorSampler

enum EchoStyle {
	MELEE = 0,
	RANGED = 1,
}

var _damage_by_style := {
	EchoStyle.MELEE: 0.0,
	EchoStyle.RANGED: 0.0,
}
var _damage_by_player_id: Dictionary = {}
var _style_by_player_id: Dictionary = {}


static func classify_packet_style(packet: DamagePacket) -> int:
	if packet == null:
		return EchoStyle.RANGED
	if packet.kind == &"melee" or packet.kind == &"contact":
		return EchoStyle.MELEE
	return EchoStyle.RANGED


static func resolve_attacker_node(packet: DamagePacket) -> Node2D:
	if packet == null:
		return null
	var src := packet.source_node
	if src == null or not is_instance_valid(src):
		return null
	if src is Node2D and (src as Node).is_in_group(&"player"):
		return src as Node2D
	if src.has_method(&"get_knockback_attribution_owner"):
		var owner_v: Variant = src.call(&"get_knockback_attribution_owner")
		if owner_v is Node2D and is_instance_valid(owner_v) and (owner_v as Node).is_in_group(&"player"):
			return owner_v as Node2D
	if src.get_parent() is Node2D and (src.get_parent() as Node).is_in_group(&"player"):
		return src.get_parent() as Node2D
	return null


func reset() -> void:
	_damage_by_style[EchoStyle.MELEE] = 0.0
	_damage_by_style[EchoStyle.RANGED] = 0.0
	_damage_by_player_id.clear()
	_style_by_player_id.clear()


func record_packet(packet: DamagePacket, hp_damage: int) -> void:
	var amount := maxf(1.0, float(maxi(1, hp_damage)))
	var style := classify_packet_style(packet)
	_damage_by_style[style] = float(_damage_by_style.get(style, 0.0)) + amount
	var attacker := resolve_attacker_node(packet)
	if attacker == null:
		return
	var key := attacker.get_instance_id()
	_damage_by_player_id[key] = float(_damage_by_player_id.get(key, 0.0)) + amount
	_style_by_player_id[key] = style


func dominant_style(default_style: int = EchoStyle.RANGED) -> int:
	var melee_damage := float(_damage_by_style.get(EchoStyle.MELEE, 0.0))
	var ranged_damage := float(_damage_by_style.get(EchoStyle.RANGED, 0.0))
	if melee_damage <= 0.0 and ranged_damage <= 0.0:
		return default_style
	return EchoStyle.MELEE if melee_damage > ranged_damage else EchoStyle.RANGED


func highest_damage_player() -> Node2D:
	var best_damage := -1.0
	var best_node: Node2D = null
	for player_id_v in _damage_by_player_id.keys():
		var player_id := int(player_id_v)
		var damage := float(_damage_by_player_id.get(player_id, 0.0))
		var obj := instance_from_id(player_id)
		if obj is Node2D and is_instance_valid(obj):
			if damage > best_damage:
				best_damage = damage
				best_node = obj as Node2D
	return best_node


func style_for_player(player: Node2D, default_style: int = EchoStyle.RANGED) -> int:
	if player == null or not is_instance_valid(player):
		return default_style
	return int(_style_by_player_id.get(player.get_instance_id(), default_style))
