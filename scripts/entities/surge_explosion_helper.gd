extends RefCounted
class_name SurgeExplosionHelper

const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")


static func apply_explosion(
	source: Node2D,
	origin: Vector2,
	radius: float,
	damage: int,
	knockback: float,
	affects_players: bool = true,
	chain_fizzlers: bool = false,
	chain_bursters: bool = false,
	visual_color: Color = Color(1.0, 0.5, 0.18, 0.75),
	visual_intensity: float = 1.0
) -> void:
	if source == null or not is_instance_valid(source):
		return
	play_explosion_visual(source, origin, radius, visual_color, visual_intensity)
	if affects_players:
		_damage_players_in_radius(source, origin, radius, damage, knockback)
	if chain_fizzlers or chain_bursters:
		_trigger_surge_chain(source, origin, radius, chain_fizzlers, chain_bursters)


static func play_explosion_visual(
	host: Node,
	origin: Vector2,
	radius: float,
	visual_color: Color = Color(1.0, 0.5, 0.18, 0.75),
	visual_intensity: float = 1.0,
	duration: float = 0.18
) -> void:
	if host == null or not is_instance_valid(host) or OS.has_feature("dedicated_server"):
		return
	var vw := _resolve_visual_world(host)
	if vw == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = &"SurgeExplosionVisual"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.14
	mesh.radial_segments = 36
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = visual_color
	mat.emission_enabled = true
	mat.emission = visual_color
	mat.emission_energy_multiplier = maxf(0.5, visual_intensity * 1.8)
	mi.material_override = mat
	vw.add_child(mi)
	mi.global_position = Vector3(origin.x, 0.08, origin.y)
	mi.scale = Vector3(radius * 0.3, 1.0, radius * 0.3)
	var tween := host.create_tween()
	tween.tween_property(mi, "scale", Vector3(radius, 1.0, radius), maxf(0.05, duration))
	tween.parallel().tween_property(mi, "transparency", 1.0, maxf(0.05, duration))
	tween.finished.connect(
		func() -> void:
			if is_instance_valid(mi):
				mi.queue_free()
	)


static func _damage_players_in_radius(
	source: Node2D, origin: Vector2, radius: float, damage: int, knockback: float
) -> void:
	var tree := source.get_tree()
	if tree == null:
		return
	var hit_players: Dictionary = {}
	for node in tree.get_nodes_in_group(&"player"):
		if node is not Node2D:
			continue
		var player := node as Node2D
		if not is_instance_valid(player):
			continue
		var d2 := player.global_position.distance_squared_to(origin)
		if d2 > radius * radius:
			continue
		hit_players[player.get_instance_id()] = player
	for player_v in hit_players.values():
		var player := player_v as Node2D
		var receiver := player.get_node_or_null("DamageReceiver")
		var hurtbox := player.get_node_or_null("PlayerHurtbox")
		if receiver == null or hurtbox == null:
			continue
		var away := player.global_position - origin
		var dir := away.normalized() if away.length_squared() > 0.0001 else Vector2.ZERO
		var packet := DamagePacketScript.new() as DamagePacket
		packet.amount = damage
		packet.kind = &"explosion"
		packet.source_node = source
		packet.source_uid = source.get_instance_id()
		packet.attack_instance_id = source.get_instance_id()
		packet.origin = origin
		packet.direction = dir
		packet.knockback = knockback
		packet.apply_iframes = false
		packet.blockable = false
		packet.debug_label = &"surge_explosion"
		receiver.receive_damage(packet, hurtbox)


static func _trigger_surge_chain(
	source: Node2D, origin: Vector2, radius: float, chain_fizzlers: bool, chain_bursters: bool
) -> void:
	var tree := source.get_tree()
	if tree == null:
		return
	var radius_sq := radius * radius
	for node in tree.get_nodes_in_group(&"mob"):
		if node == source or node is not Node2D or not is_instance_valid(node):
			continue
		var mob := node as Node2D
		if mob.global_position.distance_squared_to(origin) > radius_sq:
			continue
		if chain_fizzlers and mob is FizzlerMob and mob.has_method(&"trigger_chain_reaction"):
			mob.call(&"trigger_chain_reaction", origin)
		elif chain_bursters and mob is BursterMob and mob.has_method(&"trigger_chain_reaction"):
			mob.call(&"trigger_chain_reaction", origin)


static func _resolve_visual_world(host: Node) -> Node3D:
	if host == null or not is_instance_valid(host):
		return null
	if host.has_method(&"_resolve_visual_world_3d"):
		var direct_v: Variant = host.call(&"_resolve_visual_world_3d")
		if direct_v is Node3D:
			return direct_v as Node3D
	var tree := host.get_tree()
	if tree != null and tree.current_scene != null:
		var vw := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
		if vw != null:
			return vw
	return null
