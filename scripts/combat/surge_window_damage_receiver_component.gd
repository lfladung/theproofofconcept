extends DamageReceiverComponent
class_name SurgeWindowDamageReceiverComponent

@export var damage_gate_method: StringName = &"surge_allows_incoming_damage"
@export var damage_scale_method: StringName = &"surge_damage_taken_multiplier"


func _process_damage(
	packet: DamagePacket, _hurtbox: Area2D, health_component: HealthComponent
) -> Dictionary:
	var owner_node := get_owner_node()
	if owner_node != null and owner_node.has_method(damage_gate_method):
		if not bool(owner_node.call(damage_gate_method, packet)):
			return _result(false, false, &"surge_window_closed", 0)
	var incoming := packet
	if owner_node != null and owner_node.has_method(damage_scale_method):
		var scale_v: Variant = owner_node.call(damage_scale_method, packet)
		if scale_v is float or scale_v is int:
			var scale := maxf(0.0, float(scale_v))
			if absf(scale - 1.0) > 0.0001:
				incoming = packet.duplicate_packet()
				incoming.amount = maxi(1, int(round(float(packet.amount) * scale)))
	return health_component.apply_damage(incoming)
