extends Node2D
class_name TrapTile2D

const _DEFAULT_TRAP_MESH := preload("res://art/Meshy_AI_spike_trap_0322233059_texture.glb")

@export var damage := 18
@export var hit_cooldown_sec := 1.1
@export var trap_color := Color(1.0, 0.89, 0.10, 0.92)
@export var footprint := Vector2(6.0, 6.0)
## If set, used instead of the default spike GLB.
@export var trap_3d_scene: PackedScene
## World-space Y for the imported mesh root; nudged up so room floor quads don’t bury the spikes.
@export var mesh_ground_y := 0.2
@export var mesh_scale := Vector3(2.8, 2.8, 2.8)

@onready var _visual: Polygon2D = $Visual
@onready var _hurtbox: Area2D = $Hurtbox

var _next_hit_time: Dictionary = {}
var _trap_3d: Node3D


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
	_rebuild_visual()
	_setup_hurtbox()
	_hurtbox.body_exited.connect(_on_hurtbox_body_exited)
	call_deferred(&"_deferred_setup_trap_mesh")


func _exit_tree() -> void:
	if _trap_3d != null and is_instance_valid(_trap_3d):
		_trap_3d.queue_free()
		_trap_3d = null


func _deferred_setup_trap_mesh() -> void:
	if not is_inside_tree():
		return
	var vw := _find_visual_world(self)
	var src := trap_3d_scene if trap_3d_scene != null else _DEFAULT_TRAP_MESH
	if vw == null or src == null:
		return
	var root := src.instantiate() as Node3D
	if root == null:
		return
	root.scale = mesh_scale
	vw.add_child(root)
	_trap_3d = root
	_sync_trap_mesh_transform()
	if _visual:
		_visual.visible = false


func _sync_trap_mesh_transform() -> void:
	if _trap_3d == null:
		return
	_trap_3d.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)
	_trap_3d.global_rotation = Vector3.ZERO


func _rebuild_visual() -> void:
	if _visual == null:
		return
	var half := footprint * 0.5
	_visual.color = trap_color
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


func _setup_hurtbox() -> void:
	var cs := _hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	if cs == null or not cs.shape is RectangleShape2D:
		return
	var r := cs.shape as RectangleShape2D
	r.size = footprint


func _physics_process(_delta: float) -> void:
	_sync_trap_mesh_transform()
	for body in _hurtbox.get_overlapping_bodies():
		if body is Node2D and body.is_in_group(&"player"):
			_try_damage(body as Node2D)


func _on_hurtbox_body_exited(body: Node2D) -> void:
	if body != null:
		_next_hit_time.erase(body.get_instance_id())


func _try_damage(body: Node2D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var id := body.get_instance_id()
	var due: float = float(_next_hit_time.get(id, 0.0))
	if now < due:
		return
	if body.has_method(&"take_damage"):
		body.call(&"take_damage", damage)
	_next_hit_time[id] = now + hit_cooldown_sec
