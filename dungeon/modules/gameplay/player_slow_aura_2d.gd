class_name PlayerSlowAura2D
extends Node2D

@export var radius := 24.0
@export var move_speed_multiplier := 0.6
@export var visual_ground_y := 0.06
@export var ring_color := Color(0.48, 0.48, 0.54, 0.22)
@export var pulse_color := Color(0.72, 0.72, 0.82, 0.12)
@export var enabled := true

var _affected_player_ids: Dictionary = {}
var _visual_root: Node3D
var _ring_mesh: MeshInstance3D
var _pulse_mesh: MeshInstance3D


func _ready() -> void:
	call_deferred("_ensure_visual")


func _physics_process(_delta: float) -> void:
	if not enabled:
		_clear_all_players()
		return
	_update_player_modifiers()


func _process(_delta: float) -> void:
	_update_visual_state()


func set_enabled(next_enabled: bool) -> void:
	enabled = next_enabled
	if not enabled:
		_clear_all_players()
	_update_visual_state()


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
	return StringName("slow_aura_%s" % [str(get_instance_id())])


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
	_visual_root.name = &"PlayerSlowAuraVisual"
	visual_world.add_child(_visual_root)
	_ring_mesh = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = radius
	ring.bottom_radius = radius
	ring.height = 0.03
	ring.radial_segments = 48
	_ring_mesh.mesh = ring
	_ring_mesh.material_override = _build_material(ring_color)
	_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(_ring_mesh)
	_pulse_mesh = MeshInstance3D.new()
	var pulse := CylinderMesh.new()
	pulse.top_radius = radius * 0.55
	pulse.bottom_radius = radius * 0.55
	pulse.height = 0.02
	pulse.radial_segments = 32
	_pulse_mesh.mesh = pulse
	_pulse_mesh.material_override = _build_material(pulse_color)
	_pulse_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(_pulse_mesh)
	_update_visual_state()


func _update_visual_state() -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	_visual_root.visible = enabled
	_visual_root.global_position = Vector3(global_position.x, visual_ground_y, global_position.y)
	if _pulse_mesh != null and is_instance_valid(_pulse_mesh):
		var t := float(Time.get_ticks_msec()) * 0.001
		var pulse_scale := 0.92 + sin(t * 1.85) * 0.08
		_pulse_mesh.scale = Vector3.ONE * pulse_scale


func _build_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
