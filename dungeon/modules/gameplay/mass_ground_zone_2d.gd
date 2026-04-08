class_name MassGroundZone2D
extends Node2D

@export var radius := 15.0
@export var move_speed_multiplier := 0.72
@export var lifetime_sec := 5.0
@export var visual_ground_y := 0.05
@export var zone_color := Color(0.38, 0.32, 0.28, 0.36)
@export var ring_color := Color(0.62, 0.56, 0.48, 0.32)

var _affected_player_ids: Dictionary = {}
var _visual_root: Node3D
var _disc_mesh: MeshInstance3D
var _ring_mesh: MeshInstance3D


func _ready() -> void:
	call_deferred("_ensure_visual")
	get_tree().create_timer(maxf(0.1, lifetime_sec)).timeout.connect(queue_free)


func _physics_process(_delta: float) -> void:
	_update_player_modifiers()


func _process(_delta: float) -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.global_position = Vector3(global_position.x, visual_ground_y, global_position.y)


func _exit_tree() -> void:
	_clear_all_players()
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()


func _update_player_modifiers() -> void:
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group(&"player"):
		if node == null or not is_instance_valid(node):
			continue
		if node is not CharacterBody2D:
			continue
		var player := node as CharacterBody2D
		var inside := player.global_position.distance_squared_to(global_position) <= radius * radius
		var instance_id := player.get_instance_id()
		if inside:
			seen[instance_id] = true
			if player.has_method(&"set_external_move_speed_multiplier"):
				player.call(&"set_external_move_speed_multiplier", _modifier_key(), move_speed_multiplier)
	for key in _affected_player_ids.keys():
		if seen.has(key):
			continue
		var player_node := instance_from_id(int(key))
		if player_node != null and is_instance_valid(player_node) and player_node.has_method(&"clear_external_move_speed_multiplier"):
			player_node.call(&"clear_external_move_speed_multiplier", _modifier_key())
	_affected_player_ids = seen


func _clear_all_players() -> void:
	for key in _affected_player_ids.keys():
		var player_node := instance_from_id(int(key))
		if player_node != null and is_instance_valid(player_node) and player_node.has_method(&"clear_external_move_speed_multiplier"):
			player_node.call(&"clear_external_move_speed_multiplier", _modifier_key())
	_affected_player_ids.clear()


func _modifier_key() -> StringName:
	return StringName("mass_ground_zone_%s" % [str(get_instance_id())])


func _ensure_visual() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var visual_world := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
	if visual_world == null:
		return
	_visual_root = Node3D.new()
	_visual_root.name = &"MassGroundZoneVisual"
	visual_world.add_child(_visual_root)
	_disc_mesh = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius * 1.06
	disc.height = 0.04
	disc.radial_segments = 40
	_disc_mesh.mesh = disc
	_disc_mesh.material_override = _build_material(zone_color)
	_disc_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(_disc_mesh)
	_ring_mesh = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(0.35, radius * 0.92)
	ring.outer_radius = ring.inner_radius + maxf(0.18, radius * 0.05)
	_ring_mesh.mesh = ring
	_ring_mesh.material_override = _build_material(ring_color)
	_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_visual_root.add_child(_ring_mesh)
	_visual_root.global_position = Vector3(global_position.x, visual_ground_y, global_position.y)


func _build_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
