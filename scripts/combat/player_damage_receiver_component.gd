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
			var split_ratio := clampf(packet.guard_stamina_split_ratio, 0.0, 1.0)
			var stamina_amount := maxi(0, int(roundf(float(packet.amount) * split_ratio)))
			var health_amount := maxi(0, packet.amount - stamina_amount)
			if stamina_amount > 0 and player.has_method(&"_apply_guard_stamina_damage"):
				player.call(&"_apply_guard_stamina_damage", stamina_amount)
			if player.has_method(&"anchor_on_guard_block_success"):
				player.call(&"anchor_on_guard_block_success", packet)
			if health_amount <= 0:
				return _result(false, true, &"blocked_to_stamina", 0)
			var split_packet := packet.duplicate_packet()
			split_packet.amount = health_amount
			return health_component.apply_damage(split_packet)
	var processed: DamagePacket = packet
	if player != null and is_instance_valid(player) and player.has_method(&"anchor_preprocess_incoming_damage"):
		var v: Variant = player.call(&"anchor_preprocess_incoming_damage", packet)
		if v is DamagePacket:
			processed = v as DamagePacket
	return health_component.apply_damage(processed)
