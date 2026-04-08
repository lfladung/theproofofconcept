extends RefCounted
class_name EchoReflectionHelper

const ArrowProjectilePoolScript = preload("res://scripts/entities/arrow_projectile_pool.gd")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const EchoSamplerScript = preload("res://scripts/entities/echo_behavior_sampler.gd")


static func is_reflectable(packet: DamagePacket) -> bool:
	if packet == null:
		return false
	if packet.is_echo or packet.suppress_echo_procs:
		return false
	return packet.amount > 0


static func reflect_to_attacker(
	owner: EnemyBase,
	packet: DamagePacket,
	damage_ratio: float,
	reflection_count: int,
	visual_world: Node3D,
	projectile_damage: int,
	projectile_speed: float,
	projectile_distance: float,
	melee_range: float
) -> void:
	if owner == null or not is_instance_valid(owner) or packet == null:
		return
	var attacker = EchoSamplerScript.resolve_attacker_node(packet)
	if attacker == null or not is_instance_valid(attacker):
		return
	var hits := maxi(1, reflection_count)
	var each_damage := maxi(1, int(roundf(float(maxi(1, packet.amount)) * maxf(0.05, damage_ratio))))
	var style := EchoSamplerScript.classify_packet_style(packet)
	for _i in range(hits):
		if style == EchoSamplerScript.EchoStyle.MELEE:
			_reflect_melee(owner, attacker, each_damage, melee_range)
		else:
			_reflect_projectile(
				owner,
				attacker,
				each_damage if projectile_damage <= 0 else projectile_damage,
				projectile_speed,
				projectile_distance,
				visual_world
			)


static func _reflect_melee(owner: EnemyBase, attacker: Node2D, damage: int, melee_range: float) -> void:
	if owner == null or attacker == null:
		return
	var to_attacker := attacker.global_position - owner.global_position
	if to_attacker.length_squared() > melee_range * melee_range:
		return
	if attacker.has_method(&"take_attack_damage"):
		attacker.call(&"take_attack_damage", maxi(1, damage), owner.global_position, to_attacker.normalized())


static func _reflect_projectile(
	owner: EnemyBase,
	attacker: Node2D,
	damage: int,
	projectile_speed: float,
	projectile_distance: float,
	visual_world: Node3D
) -> void:
	if owner == null or attacker == null:
		return
	var parent := owner.get_parent()
	if parent == null:
		return
	var to_attacker := attacker.global_position - owner.global_position
	var dir := to_attacker.normalized() if to_attacker.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	var projectile := ArrowProjectilePoolScript.acquire_projectile(parent)
	if projectile == null:
		return
	projectile.speed = projectile_speed
	projectile.max_distance = projectile_distance
	projectile.damage = maxi(1, damage)
	projectile.mesh_scale = Vector3(1.0, 1.0, 1.0) * 0.8
	if projectile.has_method(&"set_authoritative_damage"):
		projectile.call(&"set_authoritative_damage", owner.is_damage_authority())
	projectile.configure(owner.global_position + dir * 0.8, dir, visual_world, false, &"purple")
