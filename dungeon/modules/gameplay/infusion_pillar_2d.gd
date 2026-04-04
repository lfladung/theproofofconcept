extends Node2D
class_name InfusionPillar2D

const IC := preload("res://scripts/infusion/infusion_constants.gd")
const DEFAULT_PILLAR_VISUAL_SCENE := preload("res://dungeon/modules/gameplay/infusion_edge_pillar_visual.tscn")
const InfusionEdgePillarVisualScript := preload("res://dungeon/modules/gameplay/infusion_edge_pillar_visual.gd")

@export var infusion_pillar_id: StringName = IC.PILLAR_EDGE
@export var stack_contribution: float = IC.STACK_NORMAL
@export var source_kind: int = IC.SourceKind.NORMAL
@export var pillar_visual_scene: PackedScene

@onready var _hurtbox: Hurtbox2D = $Hurtbox
@onready var _health: HealthComponent = $HealthComponent
@onready var _visual: Polygon2D = $Visual

var _triggered := false
## When true, melee cannot deplete health until cleared (e.g. boss-room pillar until encounter ends).
var _pickup_locked := false
var _pillar_3d: Node3D


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
	if pillar_visual_scene == null:
		pillar_visual_scene = DEFAULT_PILLAR_VISUAL_SCENE
	_health.depleted.connect(_on_health_depleted)
	_apply_pickup_lock_state()
	call_deferred(&"_deferred_setup_mesh")


func _exit_tree() -> void:
	if _pillar_3d != null and is_instance_valid(_pillar_3d):
		_pillar_3d.queue_free()
		_pillar_3d = null


func _physics_process(_delta: float) -> void:
	_sync_pillar_mesh_transform()


func is_damage_authority() -> bool:
	var mp := multiplayer
	if mp == null or mp.multiplayer_peer == null:
		return true
	return mp.is_server()


func set_pickup_locked(locked: bool) -> void:
	if _triggered:
		return
	_pickup_locked = locked
	if is_node_ready():
		_apply_pickup_lock_state()
	else:
		call_deferred(&"_apply_pickup_lock_state")


func _apply_pickup_lock_state() -> void:
	if not is_inside_tree() or _triggered:
		return
	if _hurtbox != null:
		_hurtbox.set_active(not _pickup_locked)
	_refresh_lock_visual()


func _pillar_placeholder_color() -> Color:
	var c := IC.ui_pillar_dot_color(infusion_pillar_id)
	if _pickup_locked:
		c = c.darkened(0.38)
		c.a = 0.42
	else:
		c.a = 0.88
	return c


func _refresh_lock_visual() -> void:
	if _visual != null:
		_visual.color = _pillar_placeholder_color()
	if _pillar_3d != null and is_instance_valid(_pillar_3d) and _pillar_3d.has_method(&"set_locked_look"):
		_pillar_3d.call(&"set_locked_look", _pickup_locked)


func _deferred_setup_mesh() -> void:
	if not is_inside_tree() or pillar_visual_scene == null:
		return
	var vw := _find_visual_world(self)
	if vw == null:
		return
	var root := pillar_visual_scene.instantiate() as Node3D
	if root == null:
		return
	if root.get_script() == InfusionEdgePillarVisualScript:
		root.set(&"infusion_pillar_id", infusion_pillar_id)
	vw.add_child(root)
	_pillar_3d = root
	_sync_pillar_mesh_transform()
	if _visual != null:
		_visual.visible = false
	_refresh_lock_visual()


func _sync_pillar_mesh_transform() -> void:
	if _pillar_3d == null or not is_instance_valid(_pillar_3d):
		return
	_pillar_3d.global_position = Vector3(global_position.x, 0.0, global_position.y)


func _can_grant_infusion_to_source(source: Node) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var im := source.get_node_or_null(^"InfusionManager") as InfusionManager
	if im == null:
		return true
	return not im.is_at_pickup_cap_for_pillar(infusion_pillar_id)


func _on_health_depleted(packet: DamagePacket) -> void:
	if _triggered or _pickup_locked:
		return
	var source := packet.source_node
	if not _can_grant_infusion_to_source(source):
		return
	_triggered = true
	_hurtbox.set_active(false)

	if source != null and is_instance_valid(source) and source.has_method(&"receive_infusion_pickup"):
		source.call(&"receive_infusion_pickup", infusion_pillar_id, stack_contribution, source_kind)

	if _visual != null:
		var spent := IC.ui_pillar_dot_color(infusion_pillar_id)
		spent.a = 0.45
		_visual.color = spent
	if _pillar_3d != null and is_instance_valid(_pillar_3d):
		_pillar_3d.queue_free()
		_pillar_3d = null
