extends Area2D
class_name ArrowProjectile

const ARROW_VISUAL_SCENE := preload("res://art/a_regular_wooden_arrow_texture.glb")

@export var speed := 42.0
@export var max_distance := 30.0
@export var damage := 15
@export var mesh_ground_y := 1.15
@export var mesh_scale := Vector3(1.6, 1.6, 1.6)
@export var mesh_yaw_offset_deg := 90.0
@export var show_debug_hitbox := true
@export var debug_hitbox_ground_y := 0.08
@export var debug_hitbox_height := 0.08

@onready var _shape: CollisionShape2D = $CollisionShape2D

var _direction := Vector2.RIGHT
var _start_pos := Vector2.ZERO
var _traveled := 0.0
var _visual: Node3D
var _debug_hitbox: MeshInstance3D
var _vw: Node3D


func configure(spawn_position: Vector2, direction: Vector2, owner_visual_world: Node3D) -> void:
	global_position = spawn_position
	_start_pos = spawn_position
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_vw = owner_visual_world


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if _shape != null:
		_shape.set_deferred("disabled", false)
	call_deferred("_deferred_setup_visual")


func _deferred_setup_visual() -> void:
	if _vw == null:
		return
	if ARROW_VISUAL_SCENE != null:
		var vis := ARROW_VISUAL_SCENE.instantiate() as Node3D
		if vis != null:
			vis.scale = mesh_scale
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
		mat.albedo_color = Color(1.0, 0.15, 0.15, 0.45)
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
		queue_free()


func _sync_visual() -> void:
	var yaw := atan2(_direction.x, _direction.y) + deg_to_rad(mesh_yaw_offset_deg)
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)
		_visual.rotation = Vector3(0.0, yaw, 0.0)
	if _debug_hitbox != null:
		_debug_hitbox.global_position = Vector3(global_position.x, debug_hitbox_ground_y, global_position.y)
		_debug_hitbox.rotation = Vector3(0.0, yaw, 0.0)


func _on_body_entered(body: Node2D) -> void:
	if body == null:
		return
	if body.is_in_group(&"player"):
		if body.has_method(&"take_damage"):
			body.call(&"take_damage", damage)
		queue_free()


func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _debug_hitbox != null and is_instance_valid(_debug_hitbox):
		_debug_hitbox.queue_free()
