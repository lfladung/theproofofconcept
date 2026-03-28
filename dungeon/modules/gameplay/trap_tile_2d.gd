extends Node2D
class_name TrapTile2D

const _DEFAULT_TRAP_MESH := preload("res://art/hazards/spike_trap_texture.glb")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")

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
@onready var _damage_hitbox: Hitbox2D = $DamageHitbox

var _trap_3d: Node3D
var _authoritative_damage := true


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
	_setup_hitbox_shape()
	_apply_authoritative_damage_runtime()
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


func _setup_hitbox_shape() -> void:
	if _damage_hitbox == null:
		return
	var cs := _damage_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape is not RectangleShape2D:
		return
	var rect := cs.shape as RectangleShape2D
	rect.size = footprint
	_damage_hitbox.repeat_mode = Hitbox2D.RepeatMode.INTERVAL
	_damage_hitbox.repeat_interval_sec = maxf(0.0, hit_cooldown_sec)


func _physics_process(_delta: float) -> void:
	_sync_trap_mesh_transform()


func set_authoritative_damage(enabled: bool) -> void:
	_authoritative_damage = enabled
	if is_inside_tree():
		_apply_authoritative_damage_runtime()


func _apply_authoritative_damage_runtime() -> void:
	if _damage_hitbox == null:
		return
	_damage_hitbox.deactivate()
	if not _authoritative_damage:
		return
	var packet := DamagePacketScript.new() as DamagePacket
	packet.amount = damage
	packet.kind = &"hazard"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = global_position
	packet.direction = Vector2.ZERO
	packet.knockback = 0.0
	packet.apply_iframes = true
	packet.blockable = false
	packet.debug_label = &"trap_tile"
	_damage_hitbox.activate(packet)
