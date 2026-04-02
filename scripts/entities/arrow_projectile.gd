extends Area2D
class_name ArrowProjectile

signal projectile_finished(final_position: Vector2)

const ArrowProjectilePoolScript = preload("res://scripts/entities/arrow_projectile_pool.gd")
const ARROW_VISUAL_SCENE := preload("res://art/combat/projectiles/a_regular_wooden_arrow_texture.glb")
const PLAYER_PROJECTILE_VISUAL_SCENE := preload("res://art/combat/projectiles/projectile_red_texture.glb")
const PLAYER_PROJECTILE_BLUE_VISUAL_SCENE := preload("res://art/combat/projectiles/projectile_blue_texture.glb")
const HOSTILE_PROJECTILE_GREEN_VISUAL_SCENE := preload("res://art/combat/projectiles/projectile_green_texture.glb")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")

@export var speed := 42.0
@export var max_distance := 30.0
@export var damage := 15
@export var mesh_ground_y := 1.15
@export var mesh_scale := Vector3(1.6, 1.6, 1.6)
@export var mesh_yaw_offset_deg := 90.0
@export var show_debug_hitbox := false
@export var debug_hitbox_ground_y := 0.08
@export var debug_hitbox_height := 0.08
@export var knockback_strength := 8.0

@onready var _world_shape: CollisionShape2D = $CollisionShape2D
@onready var _hitbox: Hitbox2D = $DamageHitbox
@onready var _shape: CollisionShape2D = $DamageHitbox/CollisionShape2D

var _direction := Vector2.RIGHT
var _start_pos := Vector2.ZERO
var _traveled := 0.0
var _visual: Node3D
var _debug_hitbox: MeshInstance3D
var _vw: Node3D
## Tower shots use hostile attack layer/mask. Player shots use player attack layer/mask.
var _fired_by_player := false
var _authoritative_damage := true
var _finished := false
var _projectile_style_id: StringName = &"red"
var _attack_instance_id := -1
var _charge_size_mult := 1.0
var _pooled_enabled := false
var _base_world_radius := 0.4
var _base_hitbox_radius := 0.4
var _visuals_by_key: Dictionary = {}
var _active_visual_key := ""


func configure(
	spawn_position: Vector2,
	direction: Vector2,
	owner_visual_world: Node3D,
	fired_by_player: bool = false,
	projectile_style_id: StringName = &"red",
	attack_instance_id: int = -1,
	charge_size_mult: float = 1.0
) -> void:
	global_position = spawn_position
	_start_pos = spawn_position
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_vw = owner_visual_world
	_fired_by_player = fired_by_player
	_projectile_style_id = projectile_style_id
	_attack_instance_id = attack_instance_id
	_charge_size_mult = clampf(charge_size_mult, 1.0, 2.5)
	_finished = false
	_traveled = 0.0
	if is_inside_tree():
		_activate_runtime_state()


func set_authoritative_damage(enabled: bool) -> void:
	_authoritative_damage = enabled
	if is_inside_tree():
		_apply_hitbox_runtime()


func set_pooled_enabled(enabled: bool) -> void:
	_pooled_enabled = enabled


func reactivate_from_pool() -> void:
	if not is_inside_tree():
		return
	show()
	set_physics_process(true)
	_activate_runtime_state()


func deactivate_for_pool() -> void:
	hide()
	set_physics_process(false)
	monitoring = false
	if _hitbox != null:
		_hitbox.deactivate()
	if _visual != null and is_instance_valid(_visual):
		_visual.visible = false
	if _debug_hitbox != null and is_instance_valid(_debug_hitbox):
		_debug_hitbox.visible = false


func _ready() -> void:
	if _world_shape != null and _world_shape.shape is CircleShape2D:
		_base_world_radius = (_world_shape.shape as CircleShape2D).radius
	if _shape != null and _shape.shape is CircleShape2D:
		_base_hitbox_radius = (_shape.shape as CircleShape2D).radius
	if not body_entered.is_connected(_on_world_body_entered):
		body_entered.connect(_on_world_body_entered)
	if _hitbox != null and not _hitbox.target_resolved.is_connected(_on_hitbox_target_resolved):
		_hitbox.target_resolved.connect(_on_hitbox_target_resolved)
	_activate_runtime_state()


func _activate_runtime_state() -> void:
	_apply_charge_scale_to_collision_shapes()
	monitoring = true
	_apply_hitbox_runtime()
	_ensure_visual_for_current_style()
	_sync_visual()


func _apply_charge_scale_to_collision_shapes() -> void:
	if _world_shape != null and _world_shape.shape is CircleShape2D:
		var dup_w := (_world_shape.shape as CircleShape2D).duplicate() as CircleShape2D
		dup_w.radius = _base_world_radius * _charge_size_mult
		_world_shape.shape = dup_w
	if _shape != null and _shape.shape is CircleShape2D:
		var dup_h := (_shape.shape as CircleShape2D).duplicate() as CircleShape2D
		dup_h.radius = _base_hitbox_radius * _charge_size_mult
		_shape.shape = dup_h
	if _debug_hitbox != null and is_instance_valid(_debug_hitbox) and _debug_hitbox.mesh is BoxMesh:
		var box := _debug_hitbox.mesh as BoxMesh
		box.size.x = _base_hitbox_radius * _charge_size_mult * 2.0
		box.size.z = _base_hitbox_radius * _charge_size_mult * 2.0


func _apply_hitbox_runtime() -> void:
	if _hitbox == null:
		return
	_hitbox.deactivate()
	_hitbox.collision_layer = 32 if _fired_by_player else 64
	_hitbox.collision_mask = 16 if _fired_by_player else 8
	_hitbox.debug_draw_enabled = show_debug_hitbox
	_hitbox.debug_logging = show_debug_hitbox
	_hitbox.repeat_mode = Hitbox2D.RepeatMode.NONE
	_hitbox.stop_after_first_consume_hit = true
	if not _authoritative_damage:
		return
	var packet := DamagePacketScript.new() as DamagePacket
	packet.amount = damage
	packet.kind = &"projectile"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.attack_instance_id = _attack_instance_id
	packet.origin = global_position
	packet.direction = _direction
	packet.knockback = knockback_strength
	packet.apply_iframes = true
	packet.blockable = not _fired_by_player
	packet.debug_label = &"arrow_projectile"
	_hitbox.activate(packet)


func _ensure_visual_for_current_style() -> void:
	if _vw == null:
		return
	var visual_key := _visual_cache_key()
	if visual_key != _active_visual_key:
		if _visual != null and is_instance_valid(_visual):
			_visual.visible = false
		_visual = null
		_active_visual_key = visual_key
		var cached_v: Variant = _visuals_by_key.get(visual_key, null)
		if cached_v is Node3D and is_instance_valid(cached_v):
			_visual = cached_v as Node3D
		else:
			var vis_scene := _visual_scene_for_current_style()
			if vis_scene != null:
				var vis := vis_scene.instantiate() as Node3D
				if vis != null:
					_disable_cast_shadows_recursive(vis)
					_visuals_by_key[visual_key] = vis
					_visual = vis
		if _visual != null and _visual.get_parent() != _vw:
			if _visual.get_parent() != null:
				_visual.get_parent().remove_child(_visual)
			_vw.add_child(_visual)
	if _visual != null and is_instance_valid(_visual):
		_visual.visible = true
		_visual.scale = _current_visual_scale()
	if show_debug_hitbox and _debug_hitbox == null:
		_debug_hitbox = MeshInstance3D.new()
		_debug_hitbox.name = &"ArrowDebugHitbox"
		var box := BoxMesh.new()
		box.size = Vector3(_base_hitbox_radius * 2.0, debug_hitbox_height, _base_hitbox_radius * 2.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = (
			Color(0.2, 0.45, 1.0, 0.45)
			if _fired_by_player and _projectile_style_id == &"blue"
			else Color(0.15, 0.9, 0.3, 0.45)
			if not _fired_by_player and _projectile_style_id == &"green"
			else Color(1.0, 0.15, 0.15, 0.45)
		)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		box.material = mat
		_debug_hitbox.mesh = box
		_debug_hitbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vw.add_child(_debug_hitbox)
	if _debug_hitbox != null and is_instance_valid(_debug_hitbox):
		_debug_hitbox.visible = show_debug_hitbox


func _visual_scene_for_current_style() -> PackedScene:
	if _fired_by_player:
		return (
			PLAYER_PROJECTILE_BLUE_VISUAL_SCENE
			if _projectile_style_id == &"blue"
			else PLAYER_PROJECTILE_VISUAL_SCENE
		)
	if _projectile_style_id == &"green":
		return HOSTILE_PROJECTILE_GREEN_VISUAL_SCENE
	return ARROW_VISUAL_SCENE


func _visual_cache_key() -> String:
	var scene := _visual_scene_for_current_style()
	if scene == null:
		return ""
	return "%s|%s|%s" % [scene.resource_path, String(_projectile_style_id), "p" if _fired_by_player else "e"]


func _current_visual_scale() -> Vector3:
	return mesh_scale * (0.5 if _fired_by_player else 1.0) * _charge_size_mult


func _disable_cast_shadows_recursive(node: Node) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_cast_shadows_recursive(child)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	var step := _direction * speed * delta
	global_position += step
	_traveled = global_position.distance_to(_start_pos)
	_sync_visual()
	if _traveled >= max_distance:
		_finish_projectile()


func _sync_visual() -> void:
	var yaw := atan2(_direction.x, _direction.y) + deg_to_rad(mesh_yaw_offset_deg)
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)
		_visual.rotation = Vector3(0.0, yaw, 0.0)
	if _debug_hitbox != null:
		_debug_hitbox.global_position = Vector3(global_position.x, debug_hitbox_ground_y, global_position.y)
		_debug_hitbox.rotation = Vector3(0.0, yaw, 0.0)


func _finish_projectile() -> void:
	if _finished:
		return
	_finished = true
	if _hitbox != null:
		_hitbox.deactivate()
	monitoring = false
	projectile_finished.emit(global_position)
	if _pooled_enabled:
		ArrowProjectilePoolScript.release_projectile(self)
	else:
		queue_free()


func _on_world_body_entered(body: Node2D) -> void:
	if body == null:
		return
	_finish_projectile()


func _on_hitbox_target_resolved(
	_packet: DamagePacket,
	_target_uid: int,
	_accepted: bool,
	consume_hit: bool,
	_reason: StringName
) -> void:
	if not consume_hit:
		return
	_finish_projectile()


func _exit_tree() -> void:
	for visual_v in _visuals_by_key.values():
		if visual_v is Node3D and is_instance_valid(visual_v):
			(visual_v as Node3D).queue_free()
	_visuals_by_key.clear()
	if _debug_hitbox != null and is_instance_valid(_debug_hitbox):
		_debug_hitbox.queue_free()
