class_name FlowformDashHotspot2D
extends Node2D
## Server-side lingering dash hazard: tick damage to player hurtboxes via Hitbox2D overlap queries.

const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")

@export var damage_per_tick := 2
@export var tick_interval_sec := 0.35
@export var lifetime_sec := 3.0
@export var visual_only := false
@export var glow_ground_y := 0.05
@export var glow_radius := 1.05
@export var glow_color := Color(0.12, 0.95, 1.0, 0.58)

@onready var _hitbox: Hitbox2D = $Hitbox
var _visual_mesh: MeshInstance3D


func _ready() -> void:
	_create_visual_mesh()
	if visual_only:
		_hitbox.deactivate()
		_hitbox.monitoring = false
		_hitbox.monitorable = false
	else:
		var pkt := DamagePacketScript.new() as DamagePacket
		pkt.amount = maxi(1, damage_per_tick)
		pkt.kind = &"contact"
		pkt.source_node = null
		pkt.origin = global_position
		pkt.direction = Vector2.ZERO
		pkt.knockback = 0.0
		pkt.apply_iframes = true
		pkt.blockable = true
		pkt.debug_label = &"flowform_trail"
		_hitbox.repeat_mode = Hitbox2D.RepeatMode.INTERVAL
		_hitbox.repeat_interval_sec = maxf(0.08, tick_interval_sec)
		_hitbox.activate(pkt, maxf(0.05, lifetime_sec))
	get_tree().create_timer(lifetime_sec + 0.08).timeout.connect(queue_free)


func _exit_tree() -> void:
	if _visual_mesh != null and is_instance_valid(_visual_mesh):
		_visual_mesh.queue_free()


func _create_visual_mesh() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var visual_world := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
	if visual_world == null:
		return
	_visual_mesh = MeshInstance3D.new()
	_visual_mesh.name = &"FlowformTrailGlow"
	_visual_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := CylinderMesh.new()
	mesh.top_radius = glow_radius
	mesh.bottom_radius = glow_radius * 1.08
	mesh.height = 0.06
	mesh.radial_segments = 16
	_visual_mesh.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = glow_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visual_mesh.material_override = material
	_visual_mesh.global_position = Vector3(global_position.x, glow_ground_y, global_position.y)
	visual_world.add_child(_visual_mesh)
