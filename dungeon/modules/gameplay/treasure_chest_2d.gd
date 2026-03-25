extends Node2D
class_name TreasureChest2D

signal opened
signal coin_spawn_requested(chest_center: Vector2, land_pos: Vector2)

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")
const _DEFAULT_CHEST_MESH := preload("res://art/props/interactables/treasure_chest_texture.glb")

@export var coin_count := 10
## Coins arc from the chest center and land on this radius (evenly spaced around a full circle).
@export var spew_radius := 5.0
## Delay between each coin when the chest opens.
@export var spew_interval_sec := 0.2
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
var _interaction_enabled := true


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
	if not _opened and _interaction_enabled:
		_poll_player_touch_open()


func _on_open_trigger_body_entered(body: Node2D) -> void:
	if not _interaction_enabled:
		return
	if body == null or not body.is_in_group(&"player"):
		return
	_open_from_player(true)


## Area2D overlap often misses edge contact vs StaticBody2D (zero penetration). Match the solid AABB instead.
func _poll_player_touch_open() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var p := tree.get_first_node_in_group(&"player") as Node2D
	if p == null or not _player_circle_hits_solid_aabb(p):
		return
	_open_from_player(true)


static func _approx_player_collision_radius(body: Node2D) -> float:
	const FALLBACK := 2.55
	for c in body.get_children():
		if c is CollisionShape2D:
			var circ := (c as CollisionShape2D).shape as CircleShape2D
			if circ != null:
				var gs := (c as CollisionShape2D).global_scale
				return circ.radius * maxf(absf(gs.x), absf(gs.y))
	return FALLBACK


func _solid_aabb_center_half() -> Vector2:
	if _solid_shape == null:
		return Vector2.ZERO
	var rect := _solid_shape.shape as RectangleShape2D
	if rect == null:
		return Vector2.ZERO
	var half := rect.size * 0.5
	var gs := _solid_shape.global_scale
	return Vector2(half.x * absf(gs.x), half.y * absf(gs.y))


func _player_circle_hits_solid_aabb(player: Node2D) -> bool:
	var half := _solid_aabb_center_half()
	if half.x <= 0.0 or half.y <= 0.0:
		return false
	var center := _solid_shape.global_position
	var pc := player.global_position
	var r := _approx_player_collision_radius(player)
	var qx := clampf(pc.x, center.x - half.x, center.x + half.x)
	var qy := clampf(pc.y, center.y - half.y, center.y + half.y)
	var d2 := pc.distance_squared_to(Vector2(qx, qy))
	return d2 <= r * r + 0.02


func _open_from_player(spawn_coins: bool) -> void:
	if _opened:
		return
	_opened = true
	if _open_trigger != null:
		_open_trigger.set_deferred("monitoring", false)
		_open_trigger.set_deferred("monitorable", false)
	if _visual:
		_visual.color = open_color
	opened.emit()
	if spawn_coins:
		call_deferred("_spew_coins")


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	if _open_trigger != null:
		_open_trigger.set_deferred("monitoring", enabled)
		_open_trigger.set_deferred("monitorable", enabled)


func open_visual_only() -> void:
	_open_from_player(false)


func _spew_coins() -> void:
	if _spew_started:
		return
	_spew_started = true
	if get_parent() == null:
		return
	var n := maxi(0, coin_count)
	if n <= 0:
		return
	var r := maxf(0.1, spew_radius)
	for i in n:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		var ang := TAU * float(i) / float(n)
		var land := global_position + Vector2.from_angle(ang) * r
		call_deferred("_spawn_coin_deferred", global_position, land)
		if i < n - 1:
			await get_tree().create_timer(spew_interval_sec).timeout


func _spawn_coin_deferred(chest_center: Vector2, land_pos: Vector2) -> void:
	if not coin_spawn_requested.get_connections().is_empty():
		coin_spawn_requested.emit(chest_center, land_pos)
		return
	var parent := get_parent()
	if parent == null:
		return
	var coin := DROPPED_COIN_SCENE.instantiate() as DroppedCoin
	if coin == null:
		return
	coin.set_planar_arc_end(land_pos)
	parent.add_child(coin)
	coin.global_position = chest_center
