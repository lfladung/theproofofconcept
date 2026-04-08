extends Node3D
class_name InfusionEdgePillarVisual
## Boss-room pillar: `pillar.gltf` + handgun projectile mesh (texture matches `infusion_pillar_id`).

const IC := preload("res://scripts/infusion/infusion_constants.gd")
const PILLAR_SCENE := preload("res://assets/structure/pillar.gltf")
const ORB_RED := preload("res://art/combat/projectiles/projectile_red_texture.glb")
const ORB_BLUE := preload("res://art/combat/projectiles/projectile_blue_texture.glb")
const ORB_GREEN := preload("res://art/combat/projectiles/projectile_green_texture.glb")
const ORB_ORANGE := preload("res://art/combat/projectiles/projectile_orange_texture.glb")
const ORB_PURPLE := preload("res://art/combat/projectiles/projectile_purple_texture.glb")
const ORB_PINK := preload("res://art/combat/projectiles/projectile_pink_texture.glb")
const ORB_YELLOW := preload("res://art/combat/projectiles/projectile_yellow_texture.glb")

@export var infusion_pillar_id: StringName = IC.PILLAR_EDGE

@export var float_height := 2.75
@export var bob_amplitude := 0.14
@export var bob_speed := 2.4
@export var orb_scale := Vector3(1.2, 1.2, 1.2)

var _orb: Node3D
var _orb_base_y: float


func set_locked_look(locked: bool) -> void:
	var t := 0.52 if locked else 0.0
	_apply_geometry_transparency(self, t)


func _apply_geometry_transparency(n: Node, transparency: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = transparency
	for c in n.get_children():
		_apply_geometry_transparency(c, transparency)


func _orb_scene_for_pillar_id(pillar_id: StringName) -> PackedScene:
	match IC.handgun_projectile_style_id(pillar_id):
		&"blue":
			return ORB_BLUE
		&"green":
			return ORB_GREEN
		&"orange":
			return ORB_ORANGE
		&"purple":
			return ORB_PURPLE
		&"pink":
			return ORB_PINK
		&"yellow":
			return ORB_YELLOW
		_:
			return ORB_RED


func _ready() -> void:
	var pr = PILLAR_SCENE.instantiate()
	if pr != null:
		if pr is Node3D:
			add_child(pr as Node3D)
		else:
			var wrap_root := Node3D.new()
			wrap_root.name = &"PillarVisualRoot"
			var n := pr as Node
			while n.get_child_count() > 0:
				var c: Node = n.get_child(0)
				n.remove_child(c)
				wrap_root.add_child(c)
			n.queue_free()
			add_child(wrap_root)
	var orb_scene := _orb_scene_for_pillar_id(infusion_pillar_id)
	_orb = orb_scene.instantiate() as Node3D
	if _orb != null:
		add_child(_orb)
		_orb_base_y = float_height
		_orb.scale = orb_scale
		_sync_orb(0.0)


func _physics_process(_delta: float) -> void:
	if _orb == null:
		return
	var t := Time.get_ticks_msec() * 0.001 * bob_speed
	_sync_orb(sin(t) * bob_amplitude)


func _sync_orb(bob: float) -> void:
	_orb.position = Vector3(0.0, _orb_base_y + bob, 0.0)
