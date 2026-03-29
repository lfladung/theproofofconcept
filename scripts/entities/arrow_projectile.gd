extends Area2D
class_name ArrowProjectile

signal projectile_finished(final_position: Vector2)

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


func configure(
	spawn_position: Vector2,
	direction: Vector2,
	owner_visual_world: Node3D,
	fired_by_player: bool = false,
	projectile_style_id: StringName = &"red",
	attack_instance_id: int = -1
) -> void:
	global_position = spawn_position
	_start_pos = spawn_position
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_vw = owner_visual_world
	_fired_by_player = fired_by_player
	_projectile_style_id = projectile_style_id
	_attack_instance_id = attack_instance_id


func set_authoritative_damage(enabled: bool) -> void:
	_authoritative_damage = enabled
	if is_inside_tree():
		_apply_hitbox_runtime()


func _ready() -> void:
	body_entered.connect(_on_world_body_entered)
	if _hitbox != null and not _hitbox.target_resolved.is_connected(_on_hitbox_target_resolved):
		_hitbox.target_resolved.connect(_on_hitbox_target_resolved)
	_apply_hitbox_runtime()
	call_deferred("_deferred_setup_visual")


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


func _deferred_setup_visual() -> void:
	if _vw == null:
		return
	var vis_scene: PackedScene = ARROW_VISUAL_SCENE
	if _fired_by_player:
		vis_scene = (
			PLAYER_PROJECTILE_BLUE_VISUAL_SCENE
			if _projectile_style_id == &"blue"
			else PLAYER_PROJECTILE_VISUAL_SCENE
		)
	elif _projectile_style_id == &"green":
		vis_scene = HOSTILE_PROJECTILE_GREEN_VISUAL_SCENE
	if vis_scene != null:
		var vis := vis_scene.instantiate() as Node3D
		if vis != null:
			vis.scale = mesh_scale * (0.5 if _fired_by_player else 1.0)
			_vw.add_child(vis)
			_visual = vis
	if show_debug_hitbox:
		_debug_hitbox = MeshInstance3D.new()
		_debug_hitbox.name = &"ArrowDebugHitbox"
		var box := BoxMesh.new()
		var r := 0.4
		if _shape != null and _shape.shape is CircleShape2D:
			r = (_shape.shape as CircleShape2D).radius
		box.size = Vector3(r * 2.0, debug_hitbox_height, r * 2.0)
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
	_sync_visual()


func _physics_process(delta: float) -> void:
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
	projectile_finished.emit(global_position)
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
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _debug_hitbox != null and is_instance_valid(_debug_hitbox):
		_debug_hitbox.queue_free()
