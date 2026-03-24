extends EnemyBase
class_name ArrowTowerMob

const TOWER_VISUAL_SCENE := preload("res://art/combat/towers/stylized_arrow_tower_texture.glb")
const ARROW_PROJECTILE_SCENE := preload("res://scenes/entities/arrow_projectile.tscn")

@export var range_tiles := 5.0
@export var world_units_per_tile := 3.0
@export var fire_cooldown := 1.0
@export var arrow_damage := 15
@export var arrow_max_tiles := 5.0
@export var arrow_speed := 21.0
@export var mesh_ground_y := 0.95
@export var mesh_scale := Vector3(2.3, 2.3, 2.3)
@export var facing_yaw_offset_deg := 90.0
## Same visual language as dasher telegraph: hollow outline + red fill toward target.
@export var telegraph_ground_y := 0.06
@export var telegraph_arrow_length := 7.8
@export var telegraph_arrow_head_length := 0.8
@export var telegraph_arrow_half_width := 0.32

var _target_player: Node2D
var _cooldown_remaining := 0.0
var _visual: Node3D
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null and TOWER_VISUAL_SCENE != null:
		var vis := TOWER_VISUAL_SCENE.instantiate() as Node3D
		if vis != null:
			vis.scale = mesh_scale
			vw.add_child(vis)
			_visual = vis
	if vw != null:
		_telegraph_mesh = MeshInstance3D.new()
		_telegraph_mesh.name = &"TowerTelegraphArrow"
		_outline_mat = StandardMaterial3D.new()
		_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fill_mat = StandardMaterial3D.new()
		_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fill_mat.albedo_color = Color(0.9, 0.08, 0.08, 0.75)
		_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_mesh.visible = false
		vw.add_child(_telegraph_mesh)
	_sync_visual()
	_target_player = get_tree().get_first_node_in_group(&"player") as Node2D


func _physics_process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _target_player == null or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group(&"player") as Node2D
		_update_telegraph_visual(false, Vector2.ZERO, 0.0)
		_sync_visual()
		return
	var to_player := _target_player.global_position - global_position
	var range_world := range_tiles * world_units_per_tile
	var in_range := to_player.length() <= range_world
	var aim_dir := to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	if in_range:
		_face_direction(aim_dir)
		if _cooldown_remaining <= 0.0:
			_fire_arrow(aim_dir)
			_cooldown_remaining = fire_cooldown
	var denom := maxf(0.01, fire_cooldown)
	var charge_progress := 1.0 - clampf(_cooldown_remaining / denom, 0.0, 1.0)
	_update_telegraph_visual(in_range, aim_dir, charge_progress)
	_sync_visual()


func _face_direction(dir: Vector2) -> void:
	if _visual == null:
		return
	if dir.length_squared() <= 0.0001:
		return
	_visual.rotation.y = atan2(dir.x, dir.y) + deg_to_rad(facing_yaw_offset_deg)


func _fire_arrow(dir: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var arrow := ARROW_PROJECTILE_SCENE.instantiate() as ArrowProjectile
	if arrow == null:
		return
	arrow.speed = arrow_speed
	arrow.max_distance = arrow_max_tiles * world_units_per_tile
	arrow.damage = arrow_damage
	arrow.configure(global_position, dir, _vw)
	parent.add_child(arrow)


func _update_telegraph_visual(in_range: bool, dir: Vector2, progress: float) -> void:
	if _telegraph_mesh == null:
		return
	if not in_range:
		_telegraph_mesh.visible = false
		return
	_telegraph_mesh.visible = true
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	var right := Vector2(-d.y, d.x)
	var base := global_position
	var shaft_len := maxf(0.1, telegraph_arrow_length - telegraph_arrow_head_length)
	var shaft_end := base + d * shaft_len
	var tip := base + d * telegraph_arrow_length
	var l0 := base + right * telegraph_arrow_half_width
	var r0 := base - right * telegraph_arrow_half_width
	var l1 := shaft_end + right * telegraph_arrow_half_width
	var r1 := shaft_end - right * telegraph_arrow_half_width
	var h1 := shaft_end + right * (telegraph_arrow_half_width * 1.8)
	var h2 := shaft_end - right * (telegraph_arrow_half_width * 1.8)
	var fill_tip := base + d * (telegraph_arrow_length * progress)

	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
	for pair in [[l0, l1], [l1, h1], [h1, tip], [tip, h2], [h2, r1], [r1, r0], [r0, l0]]:
		var a := pair[0] as Vector2
		var b := pair[1] as Vector2
		imm.surface_add_vertex(Vector3(a.x, telegraph_ground_y, a.y))
		imm.surface_add_vertex(Vector3(b.x, telegraph_ground_y, b.y))
	imm.surface_end()

	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
	var tri_a := base + right * (telegraph_arrow_half_width * 0.55)
	var tri_b := base - right * (telegraph_arrow_half_width * 0.55)
	for v in [tri_a, tri_b, fill_tip]:
		imm.surface_add_vertex(Vector3(v.x, telegraph_ground_y + 0.001, v.y))
	imm.surface_end()
	_telegraph_mesh.mesh = imm


func _sync_visual() -> void:
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	pass


func can_contact_damage() -> bool:
	return false


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()
