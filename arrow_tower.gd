extends EnemyBase
class_name ArrowTowerMob

const TOWER_VISUAL_SCENE := preload("res://art/Meshy_AI_stylized_arrow_tower_0322220212_texture.glb")
const ARROW_PROJECTILE_SCENE := preload("res://arrow_projectile.tscn")

@export var range_tiles := 10.0
@export var world_units_per_tile := 3.0
@export var fire_cooldown := 1.0
@export var arrow_damage := 15
@export var arrow_max_tiles := 10.0
@export var arrow_speed := 21.0
@export var mesh_ground_y := 0.95
@export var mesh_scale := Vector3(2.3, 2.3, 2.3)
@export var facing_yaw_offset_deg := -90.0

var _target_player: Node2D
var _cooldown_remaining := 0.0
var _visual: Node3D
var _vw: Node3D


func _ready() -> void:
	super._ready()
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null and TOWER_VISUAL_SCENE != null:
		var vis := TOWER_VISUAL_SCENE.instantiate() as Node3D
		if vis != null:
			vis.scale = mesh_scale
			vw.add_child(vis)
			_visual = vis
	_sync_visual()
	_target_player = get_tree().get_first_node_in_group(&"player") as Node2D


func _physics_process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _target_player == null or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group(&"player") as Node2D
		_sync_visual()
		return
	var to_player := _target_player.global_position - global_position
	var range_world := range_tiles * world_units_per_tile
	if to_player.length() <= range_world:
		_face_direction(to_player.normalized())
		if _cooldown_remaining <= 0.0:
			_fire_arrow(to_player.normalized())
			_cooldown_remaining = fire_cooldown
	_sync_visual()


func _face_direction(dir: Vector2) -> void:
	if _visual == null:
		return
	if dir.length_squared() <= 0.0001:
		return
	_visual.rotation.y = atan2(dir.x, dir.y) + deg_to_rad(facing_yaw_offset_deg)


func _fire_arrow(dir: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var arrow := ARROW_PROJECTILE_SCENE.instantiate() as ArrowProjectile
	if arrow == null:
		return
	arrow.speed = arrow_speed
	arrow.max_distance = arrow_max_tiles * world_units_per_tile
	arrow.damage = arrow_damage
	arrow.configure(global_position, dir, _vw)
	parent.add_child(arrow)


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	# Stationary enemy: it only loses HP and keeps its position.
	pass


func can_contact_damage() -> bool:
	return false


func apply_speed_multiplier(_multiplier: float) -> void:
	# Stationary enemy does not use movement speed scaling.
	pass


func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
