extends Node2D
class_name PuzzleFloorButton2D

signal activated

const BUTTON_GLB := preload("res://art/props/interactables/button_texture.glb")

@export var mesh_ground_y := 0.5
@export var mesh_scale := Vector3(2.2, 2.2, 2.2)

@onready var _press_area: Area2D = $PressArea

var _visual: Node3D
var _done := false
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
	if _press_area:
		_press_area.body_entered.connect(_on_press_area_body_entered)
		_press_area.set_deferred("monitoring", _interaction_enabled)
		_press_area.set_deferred("monitorable", _interaction_enabled)
	call_deferred(&"_deferred_setup_visual")


func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null


func _physics_process(_delta: float) -> void:
	_sync_visual()


func _deferred_setup_visual() -> void:
	if not is_inside_tree() or _done:
		return
	var vw := _find_visual_world(self)
	if vw == null or BUTTON_GLB == null:
		return
	var root := BUTTON_GLB.instantiate() as Node3D
	if root == null:
		return
	root.scale = mesh_scale
	vw.add_child(root)
	_visual = root
	_sync_visual()


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)


func _on_press_area_body_entered(body: Node2D) -> void:
	if _done or not _interaction_enabled or body == null or not body.is_in_group(&"player"):
		return
	_done = true
	activated.emit()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	if _press_area != null:
		_press_area.set_deferred("monitoring", enabled)
		_press_area.set_deferred("monitorable", enabled)
