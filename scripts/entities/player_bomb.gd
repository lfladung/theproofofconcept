extends Node2D
class_name PlayerBomb

const BOMB_VISUAL_SCENE := preload("res://art/combat/projectiles/black_projectile_texture.glb")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const STYLE_RED: StringName = &"red"
const STYLE_BLUE: StringName = &"blue"

@export var mesh_scale := Vector3(2.0, 2.0, 2.0)
@export var mesh_yaw_offset_deg := 90.0
## Extra height at the apex of the arc (mid-flight).
@export var arc_peak := 2.25
## 3D Y when the bomb rests on the ground at impact (matches arrow-style projectiles).
@export var ground_mesh_y := 1.15
## Seconds after the bomb lands before damage is applied and the preview is removed.
@export var fuse_delay_after_land := 0.5
## Thin disc height; center is placed so the bottom sits near `ground_mesh_y`.
@export var aoe_preview_height := 0.14

var _damage := 30
var _aoe_radius := 5.0
var _knockback_strength := 0.0
var _start_2d := Vector2.ZERO
var _end_2d := Vector2.ZERO
var _arc_start_y := 4.0
var _flight_time := 0.5
var _vw: Node3D
var _visual: Node3D
var _aoe_preview: MeshInstance3D
var _facing := Vector2(0.0, -1.0)
var _authoritative_damage := true
var _visual_style_id: StringName = STYLE_RED
var _attack_instance_id := -1


func configure(
	spawn_planar: Vector2,
	direction: Vector2,
	owner_visual_world: Node3D,
	damage_amount: int,
	aoe_radius: float,
	landing_distance: float,
	flight_duration: float,
	arc_start_height: float,
	knockback: float,
	authoritative_damage: bool = true,
	visual_style_id: StringName = STYLE_RED,
	attack_instance_id: int = -1
) -> void:
	_start_2d = spawn_planar
	_facing = direction.normalized() if direction.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	_end_2d = spawn_planar + _facing * landing_distance
	_vw = owner_visual_world
	_damage = damage_amount
	_aoe_radius = aoe_radius
	_flight_time = maxf(0.05, flight_duration)
	_arc_start_y = arc_start_height
	_knockback_strength = knockback
	_authoritative_damage = authoritative_damage
	_visual_style_id = visual_style_id if visual_style_id != &"" else STYLE_RED
	_attack_instance_id = attack_instance_id


func _ready() -> void:
	global_position = _start_2d
	call_deferred("_deferred_begin")


func _deferred_begin() -> void:
	_deferred_setup_visual()
	_start_arc()


func _deferred_setup_visual() -> void:
	if _vw == null:
		return
	var root := BOMB_VISUAL_SCENE.instantiate()
	if root == null:
		return
	var vis: Node3D
	if root is Node3D:
		vis = root as Node3D
	else:
		# GLB root is sometimes a plain Node; wrap mesh children so we can place/rotate in 3D.
		vis = Node3D.new()
		vis.name = &"BombVisualRoot"
		var n := root as Node
		while n.get_child_count() > 0:
			var c: Node = n.get_child(0)
			n.remove_child(c)
			vis.add_child(c)
		n.queue_free()
	vis.scale = mesh_scale
	_vw.add_child(vis)
	_visual = vis
	_apply_visual_style(_visual)
	_sync_visual(0.0)


func _start_arc() -> void:
	var tw := create_tween()
	tw.tween_method(_sync_visual, 0.0, 1.0, _flight_time)
	tw.tween_callback(_on_landed)
	tw.tween_interval(maxf(0.0, fuse_delay_after_land))
	tw.tween_callback(_explode)


func _sync_visual(t: float) -> void:
	var p2 := _start_2d.lerp(_end_2d, t)
	global_position = p2
	if _visual == null:
		return
	var y: float = lerpf(_arc_start_y, ground_mesh_y, t) + sin(PI * t) * arc_peak
	_visual.global_position = Vector3(p2.x, y, p2.y)
	var yaw := atan2(_facing.x, _facing.y) + deg_to_rad(mesh_yaw_offset_deg)
	_visual.rotation = Vector3(0.0, yaw, 0.0)


func _on_landed() -> void:
	_sync_visual(1.0)
	_setup_aoe_preview()


func _setup_aoe_preview() -> void:
	if _vw == null or _aoe_preview != null:
		return
	var mi := MeshInstance3D.new()
	mi.name = &"BombAoEPreview"
	var cyl := CylinderMesh.new()
	cyl.top_radius = _aoe_radius
	cyl.bottom_radius = _aoe_radius
	cyl.height = aoe_preview_height
	cyl.radial_segments = 48
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = _aoe_preview_color()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	_vw.add_child(mi)
	_aoe_preview = mi
	var cy := ground_mesh_y + aoe_preview_height * 0.5
	_aoe_preview.global_position = Vector3(_end_2d.x, cy, _end_2d.y)


func _explode() -> void:
	if not _authoritative_damage:
		queue_free()
		return
	var world_2d := get_world_2d()
	if world_2d != null:
		var circle := CircleShape2D.new()
		circle.radius = _aoe_radius
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = circle
		params.transform = Transform2D(0.0, _end_2d)
		params.collision_mask = 16
		params.collide_with_areas = true
		params.collide_with_bodies = false
		var hits := world_2d.direct_space_state.intersect_shape(params, 32)
		var hit_hurtboxes: Dictionary = {}
		for hit_v in hits:
			var hit: Dictionary = hit_v
			var collider_v: Variant = hit.get("collider", null)
			if collider_v is not Hurtbox2D:
				continue
			var hurtbox := collider_v as Hurtbox2D
			if not hurtbox.is_active():
				continue
			var target_uid := hurtbox.get_target_uid()
			if hit_hurtboxes.has(target_uid):
				continue
			hit_hurtboxes[target_uid] = hurtbox
		for hurtbox_v in hit_hurtboxes.values():
			var hurtbox := hurtbox_v as Hurtbox2D
			var receiver := hurtbox.get_receiver_component()
			if receiver == null:
				continue
			var target_node := hurtbox.get_target_node() as Node2D
			var away := Vector2.ZERO
			if target_node != null:
				away = target_node.global_position - _end_2d
			var kb_dir := away.normalized() if away.length_squared() > 1e-6 else Vector2.ZERO
			var packet := DamagePacketScript.new() as DamagePacket
			packet.amount = _damage
			packet.kind = &"bomb"
			packet.source_node = self
			packet.source_uid = get_instance_id()
			packet.attack_instance_id = _attack_instance_id if _attack_instance_id > 0 else get_instance_id()
			packet.origin = _end_2d
			packet.direction = kb_dir
			packet.knockback = _knockback_strength
			packet.apply_iframes = false
			packet.blockable = false
			packet.debug_label = &"player_bomb"
			receiver.receive_damage(packet, hurtbox)
	queue_free()


func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null
	if _aoe_preview != null and is_instance_valid(_aoe_preview):
		_aoe_preview.queue_free()
	_aoe_preview = null


func _apply_visual_style(root: Node) -> void:
	if root == null:
		return
	var tint := _bomb_tint_color()
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = _create_tint_material(tint)
	for child in root.get_children():
		_apply_visual_style(child)


func _create_tint_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = 0.1
	mat.roughness = 0.28
	mat.emission_enabled = true
	mat.emission = tint * 0.18
	return mat


func _bomb_tint_color() -> Color:
	if _visual_style_id == STYLE_BLUE:
		return Color(0.18, 0.48, 1.0, 1.0)
	return Color(0.92, 0.18, 0.15, 1.0)


func _aoe_preview_color() -> Color:
	if _visual_style_id == STYLE_BLUE:
		return Color(0.18, 0.48, 1.0, 0.42)
	return Color(0.96, 0.28, 0.12, 0.42)
