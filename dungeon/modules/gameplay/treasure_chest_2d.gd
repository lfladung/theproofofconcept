extends Node2D
class_name TreasureChest2D

signal opened

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")
const _DEFAULT_CHEST_MESH := preload("res://art/treasure_chest_texture.glb")

@export var coin_count := 10
## Spawn distance in front of the chest (world units); keep min large enough to clear the solid body.
@export var spew_radius_min := 3.5
@export var spew_radius_max := 6.5
## Delay between each coin when the chest opens.
@export var spew_interval_sec := 0.2
## Half-angle (degrees) for random yaw around "forward"; coins still shoot roughly toward the player.
@export var spew_front_cone_deg := 14.0
@export var closed_color := Color(0.55, 0.35, 0.18, 1.0)
@export var open_color := Color(0.42, 0.38, 0.32, 1.0)
## Optional override; defaults to `treasure_chest_texture.glb`.
@export var chest_3d_scene: PackedScene
## World Y for the chest model root (GLB pivot is often low — raise until the body clears the floor).
@export var mesh_ground_y := 1.05
@export var mesh_scale := Vector3(2.5, 2.5, 2.5)

@onready var _open_trigger: Area2D = $OpenTrigger
@onready var _solid_shape: CollisionShape2D = $Solid/CollisionShape2D
@onready var _visual: Polygon2D = $Visual

var _opened := false
var _spew_started := false
var _chest_3d: Node3D


static func _find_visual_world(from: Node) -> Node3D:
	var tree := from.get_tree()
	if tree != null and tree.current_scene != null:
		var direct := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
		if direct != null:
			return direct
	var n: Node = from
	while n != null:
		var par := n.get_parent()
		if par == null:
			break
		var gpr := par.get_parent()
		if gpr != null:
			var vw := gpr.get_node_or_null("VisualWorld3D") as Node3D
			if vw != null:
				return vw
		n = par
	return null


func _ready() -> void:
	if _open_trigger:
		_open_trigger.body_entered.connect(_on_open_trigger_body_entered)
	if _visual:
		_visual.color = closed_color
	call_deferred(&"_deferred_setup_chest_mesh")


func _exit_tree() -> void:
	if _chest_3d != null and is_instance_valid(_chest_3d):
		_chest_3d.queue_free()
		_chest_3d = null


func _deferred_setup_chest_mesh() -> void:
	if not is_inside_tree():
		return
	var vw := _find_visual_world(self)
	var src := chest_3d_scene if chest_3d_scene != null else _DEFAULT_CHEST_MESH
	if vw == null or src == null:
		return
	var root := src.instantiate() as Node3D
	if root == null:
		return
	root.scale = mesh_scale
	vw.add_child(root)
	_chest_3d = root
	_sync_chest_mesh_transform()
	if _visual:
		_visual.visible = false


func _sync_chest_mesh_transform() -> void:
	if _chest_3d == null:
		return
	_chest_3d.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)
	_chest_3d.global_rotation = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	_sync_chest_mesh_transform()


func _on_open_trigger_body_entered(body: Node2D) -> void:
	if _opened or body == null or not body.is_in_group(&"player"):
		return
	_opened = true
	if _solid_shape != null:
		_solid_shape.set_deferred("disabled", true)
	if _open_trigger != null:
		_open_trigger.set_deferred("monitoring", false)
		_open_trigger.set_deferred("monitorable", false)
	if _visual:
		_visual.color = open_color
	opened.emit()
	call_deferred("_spew_coins")


func _spew_forward_dir() -> Vector2:
	var tree := get_tree()
	if tree != null:
		var p := tree.get_first_node_in_group(&"player") as Node2D
		if p != null:
			var d := p.global_position - global_position
			if d.length_squared() > 0.01:
				return d.normalized()
	return Vector2(0.0, 1.0)


func _spew_coins() -> void:
	if _spew_started:
		return
	_spew_started = true
	if get_parent() == null:
		return
	var n := maxi(0, coin_count)
	if n <= 0:
		return
	var cone := deg_to_rad(spew_front_cone_deg)
	for i in n:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		var fwd := _spew_forward_dir()
		var base_ang := atan2(fwd.y, fwd.x)
		var ang := base_ang + randf_range(-cone, cone)
		var dir := Vector2.from_angle(ang)
		var rad := randf_range(spew_radius_min, spew_radius_max)
		var offset := dir * rad
		call_deferred("_spawn_coin_deferred", global_position + offset, global_position)
		if i < n - 1:
			await get_tree().create_timer(spew_interval_sec).timeout


func _spawn_coin_deferred(spawn_pos: Vector2, chest_origin: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var coin := DROPPED_COIN_SCENE.instantiate() as DroppedCoin
	if coin == null:
		return
	coin.bias_jump_away_from(chest_origin, 0.5)
	parent.add_child(coin)
	coin.global_position = spawn_pos
