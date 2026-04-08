extends DamageReceiverComponent
class_name CallbackDamageReceiverComponent

@export var callback_owner_path: NodePath
@export var can_receive_method: StringName = &"can_receive_callback_damage"
@export var accepted_callback_method: StringName = &"on_callback_damage_received"
@export var consume_without_damage := true


func get_callback_owner() -> Node:
	if callback_owner_path != NodePath():
		return get_node_or_null(callback_owner_path)
	return get_owner_node()


func _process_damage(
	packet: DamagePacket, hurtbox: Area2D, _health_component: HealthComponent
) -> Dictionary:
	var owner := get_callback_owner()
	if owner == null or not is_instance_valid(owner):
		return _result(false, false, &"missing_callback_owner", 0)
	if owner.has_method(can_receive_method) and not bool(owner.call(can_receive_method, packet, hurtbox)):
		return _result(false, false, &"callback_rejected", 0)
	if owner.has_method(accepted_callback_method):
		owner.call(accepted_callback_method, packet, hurtbox)
	return _result(true, consume_without_damage, &"callback_applied", 0)
