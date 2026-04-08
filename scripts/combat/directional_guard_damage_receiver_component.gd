extends DamageReceiverComponent
class_name DirectionalGuardDamageReceiverComponent

@export var guard_owner_path: NodePath
@export var block_arc_degrees := 145.0
@export var guard_active_method: StringName = &"is_directional_guard_active"
@export var guard_facing_method: StringName = &"get_directional_guard_facing"
@export var guard_blocked_callback_method: StringName = &"on_directional_guard_blocked_hit"


func get_guard_owner() -> Node:
	if guard_owner_path != NodePath():
		return get_node_or_null(guard_owner_path)
	return get_owner_node()


func _process_damage(
	packet: DamagePacket, hurtbox: Area2D, health_component: HealthComponent
) -> Dictionary:
	var guard_owner := get_guard_owner()
	if _should_block_packet(guard_owner, packet):
		if guard_owner != null and guard_owner.has_method(guard_blocked_callback_method):
			guard_owner.call(guard_blocked_callback_method, packet, hurtbox)
		return _result(false, true, &"blocked_guard", 0)
	var incoming := packet
	if guard_owner != null and guard_owner.has_method(&"directional_guard_incoming_damage_scale"):
		var scale_v: Variant = guard_owner.call(&"directional_guard_incoming_damage_scale", packet)
		if scale_v is float or scale_v is int:
			var s := float(scale_v)
			if absf(s - 1.0) > 0.0001:
				incoming = packet.duplicate_packet()
				incoming.amount = maxi(1, int(round(float(packet.amount) * s)))
	return health_component.apply_damage(incoming)


func _should_block_packet(guard_owner: Node, packet: DamagePacket) -> bool:
	if packet == null or guard_owner == null or not is_instance_valid(guard_owner):
		return false
	if packet.ignore_directional_guard:
		return false
	if not guard_owner.has_method(guard_active_method):
		return false
	if not bool(guard_owner.call(guard_active_method)):
		return false
	if guard_owner is not Node2D:
		return false
	var owner_2d := guard_owner as Node2D
	var attack_origin_dir := packet.origin - owner_2d.global_position
	if attack_origin_dir.length_squared() <= 0.0001 and packet.direction.length_squared() > 0.0001:
		attack_origin_dir = -packet.direction
	if attack_origin_dir.length_squared() <= 0.0001:
		return false
	var guard_facing := Vector2.ZERO
	if guard_owner.has_method(guard_facing_method):
		var facing_v: Variant = guard_owner.call(guard_facing_method)
		if facing_v is Vector2:
			guard_facing = facing_v as Vector2
	if guard_facing.length_squared() <= 0.0001:
		guard_facing = Vector2(0.0, -1.0)
	else:
		guard_facing = guard_facing.normalized()
	var half_arc_radians := deg_to_rad(clampf(block_arc_degrees, 0.0, 360.0) * 0.5)
	return guard_facing.dot(attack_origin_dir.normalized()) >= cos(half_arc_radians)
