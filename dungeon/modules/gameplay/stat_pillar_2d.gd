extends Node2D
class_name StatPillar2D

const LoadoutConstants = preload("res://scripts/loadout/loadout_constants.gd")

## Which stat this pillar grants when the player attacks it.
@export var bonus_stat_key: StringName = LoadoutConstants.STAT_MAX_HEALTH
## Amount added to that stat.
@export var bonus_amount: float = 10.0
## Optional 3D scene used as the pillar mesh (replaces the polygon visual when assigned).
@export var pillar_3d_scene: PackedScene

@onready var _hurtbox: Hurtbox2D = $Hurtbox
@onready var _health: HealthComponent = $HealthComponent
@onready var _visual: Polygon2D = $Visual

var _triggered := false
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
	_health.depleted.connect(_on_health_depleted)
	call_deferred(&"_deferred_setup_mesh")


func _exit_tree() -> void:
	if _pillar_3d != null and is_instance_valid(_pillar_3d):
		_pillar_3d.queue_free()
		_pillar_3d = null


func _physics_process(_delta: float) -> void:
	_sync_pillar_mesh_transform()


## Returns true only on the server (or in single-player). Used by DamageReceiverComponent
## to gate authoritative-only damage processing.
func is_damage_authority() -> bool:
	var mp := multiplayer
	if mp == null or mp.multiplayer_peer == null:
		return true
	return mp.is_server()


func _deferred_setup_mesh() -> void:
	if not is_inside_tree() or pillar_3d_scene == null:
		return
	var vw := _find_visual_world(self)
	if vw == null:
		return
	var root := pillar_3d_scene.instantiate() as Node3D
	if root == null:
		return
	vw.add_child(root)
	_pillar_3d = root
	_sync_pillar_mesh_transform()
	if _visual != null:
		_visual.visible = false


func _sync_pillar_mesh_transform() -> void:
	if _pillar_3d == null or not is_instance_valid(_pillar_3d):
		return
	_pillar_3d.global_position = Vector3(global_position.x, 0.0, global_position.y)


func _on_health_depleted(packet: DamagePacket) -> void:
	if _triggered:
		return
	_triggered = true
	_hurtbox.set_active(false)

	var source := packet.source_node
	if source != null and is_instance_valid(source) and source.has_method(&"receive_pillar_bonus"):
		source.call(&"receive_pillar_bonus", bonus_stat_key, bonus_amount)

	if _visual != null:
		_visual.color = Color(1.0, 0.85, 0.0, 0.5)
	if _pillar_3d != null and is_instance_valid(_pillar_3d):
		_pillar_3d.queue_free()
		_pillar_3d = null
