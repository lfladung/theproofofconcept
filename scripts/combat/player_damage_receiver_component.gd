extends DamageReceiverComponent
class_name PlayerDamageReceiverComponent

@export var player_path: NodePath


func get_player() -> Node:
	if player_path != NodePath():
		return get_node_or_null(player_path)
	return get_owner_node()


func _process_damage(
	packet: DamagePacket, _hurtbox: Area2D, health_component: HealthComponent
) -> Dictionary:
	var player := get_player()
	if packet.blockable and player != null and is_instance_valid(player):
		if player.has_method(&"_is_attack_inside_block_arc") and bool(
			player.call(&"_is_attack_inside_block_arc", packet.origin, packet.direction)
		):
			if player.has_method(&"_apply_guard_stamina_damage"):
				player.call(&"_apply_guard_stamina_damage", packet.amount)
			if player.has_method(&"anchor_on_guard_block_success"):
				player.call(&"anchor_on_guard_block_success", packet)
			return _result(false, true, &"blocked_to_stamina", 0)
	var processed: DamagePacket = packet
	if player != null and is_instance_valid(player) and player.has_method(&"anchor_preprocess_incoming_damage"):
		var v: Variant = player.call(&"anchor_preprocess_incoming_damage", packet)
		if v is DamagePacket:
			processed = v as DamagePacket
	return health_component.apply_damage(processed)
