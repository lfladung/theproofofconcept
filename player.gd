extends CharacterBody2D

signal hit
signal health_changed(current: int, max_health: int)

## Horizontal speed (matches former 3D XZ plane).
@export var speed := 14.0
@export var jump_impulse := 20.0
@export var bounce_impulse := 16.0
@export var fall_acceleration := 75.0
## Altitude of feet above the ground plane (jump); not CharacterBody2D.position.y.
@export var height := 0.0
## 2D radius used for stomp proximity vs mob origin.
@export var stomp_radius := 2.2
## Ignore MobDetector kills while feet are above this height.
@export var mob_detector_safe_height := 2.3
## Max planar center distance for a kill; filters spurious Area2D body_entered at large separation.
@export var mob_kill_max_planar_dist := 6.5
@export var max_health := 100
@export var mob_hit_damage := 25
@export var hit_invulnerability_duration := 2.0
## Extra transparency during flash (0 = opaque, 1 = invisible). Alternates with fully opaque.
@export var hit_flash_transparency := 0.42
@export var hit_flash_blink_interval := 0.1

## Melee hit box along planar facing: starts just outside body circle, then depth × width (centered).
@export var melee_start_beyond_body := 0.03
@export var melee_depth := 3.375
@export var melee_width := 3.3
## Ground Y for debug mesh (XZ play plane ↔ 3D).
@export var melee_debug_ground_y := 0.04
@export var show_melee_hit_debug := true
## Y offset on XZ plane for body collision overlays (below melee quad so layers read clearly).
@export var hitbox_debug_ground_y := 0.028
@export var show_player_hitbox_debug := true
@export var show_mob_hitbox_debug := true
@export var hitbox_debug_circle_segments := 40

@onready var _visual: Node3D = get_node_or_null("../../VisualWorld3D/PlayerVisual") as Node3D
@onready var _body_shape: CollisionShape2D = $CollisionShape2D

var vertical_velocity := 0.0
var health: int = 100
var _invuln_time_remaining := 0.0
## Last planar facing (2D x,y ↔ 3D x,z); default “forward” for attacks when idle.
var _facing_planar := Vector2(0.0, -1.0)

var _melee_debug_mi: MeshInstance3D
var _melee_debug_mat: StandardMaterial3D
var _player_hitbox_mi: MeshInstance3D
var _player_hitbox_mat: StandardMaterial3D
var _mob_hitboxes_mi: MeshInstance3D
var _mob_hitbox_mat: StandardMaterial3D


func _ready() -> void:
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	if vw:
		_melee_debug_mi = MeshInstance3D.new()
		_melee_debug_mi.name = &"MeleeHitDebugMesh"
		_melee_debug_mat = StandardMaterial3D.new()
		_melee_debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_melee_debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_melee_debug_mat.albedo_color = Color(1.0, 0.35, 0.08, 0.42)
		_melee_debug_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_melee_debug_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vw.add_child(_melee_debug_mi)

		_player_hitbox_mi = MeshInstance3D.new()
		_player_hitbox_mi.name = &"PlayerHitboxDebugMesh"
		_player_hitbox_mat = StandardMaterial3D.new()
		_player_hitbox_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_player_hitbox_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_player_hitbox_mat.albedo_color = Color(0.55, 0.98, 0.62, 0.48)
		_player_hitbox_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_player_hitbox_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vw.add_child(_player_hitbox_mi)

		_mob_hitboxes_mi = MeshInstance3D.new()
		_mob_hitboxes_mi.name = &"MobHitboxesDebugMesh"
		_mob_hitbox_mat = StandardMaterial3D.new()
		_mob_hitbox_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mob_hitbox_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mob_hitbox_mat.albedo_color = Color(1.0, 0.52, 0.12, 0.48)
		_mob_hitbox_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mob_hitboxes_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vw.add_child(_mob_hitboxes_mi)

	health = max_health
	health_changed.emit(health, max_health)


func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0:
		return
	if _invuln_time_remaining > 0.0:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0:
		_reset_player_visual_transparency()
		die()
		return
	_invuln_time_remaining = hit_invulnerability_duration
	_update_invulnerability_flash_visual()


func _set_mesh_instances_transparency(root: Node, transparency_amount: float) -> void:
	for c in root.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).transparency = transparency_amount
		_set_mesh_instances_transparency(c, transparency_amount)


func _update_invulnerability_flash_visual() -> void:
	if _visual == null:
		return
	var ms := maxi(1, int(roundf(hit_flash_blink_interval * 1000.0)))
	var opaque := (Time.get_ticks_msec() / ms) % 2 == 0
	_set_mesh_instances_transparency(_visual, 0.0 if opaque else hit_flash_transparency)


func _reset_player_visual_transparency() -> void:
	if _visual:
		_set_mesh_instances_transparency(_visual, 0.0)


func _mouse_steering_active() -> bool:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return false
	# Don't steal movement when a Control is under the cursor (e.g. game-over overlay).
	return get_viewport().gui_get_hovered_control() == null


## Screen mouse → GameWorld2D plane (same coords as global_position: x, y ↔ 3D x, z).
func _mouse_planar_world() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if absf(dir.y) < 1e-5:
		return global_position
	var t := -from.y / dir.y
	if t < 0.0:
		return global_position
	var hit := from + dir * t
	return Vector2(hit.x, hit.z)


func _update_facing_planar(direction: Vector2) -> void:
	var f := direction
	if f.length_squared() <= 1e-6 and _mouse_steering_active():
		var t := _mouse_planar_world() - global_position
		if t.length_squared() > 0.01:
			f = t.normalized()
	if f.length_squared() > 1e-6:
		_facing_planar = f.normalized()


func _get_player_body_radius() -> float:
	if _body_shape and _body_shape.shape is CircleShape2D:
		return (_body_shape.shape as CircleShape2D).radius
	return 1.2676448


func _melee_range_start() -> float:
	return _get_player_body_radius() + melee_start_beyond_body


func _planar_point_in_melee_hit(mob_pos: Vector2) -> bool:
	var inner := _melee_range_start()
	var f := _facing_planar
	var r := Vector2(-f.y, f.x)
	var v := mob_pos - global_position
	var along := v.dot(f)
	var lateral := v.dot(r)
	var half_w := melee_width * 0.5
	return along >= inner and along <= inner + melee_depth and absf(lateral) <= half_w


func _squash_mobs_in_melee_hit() -> void:
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is CharacterBody2D or not node.has_method(&"squash"):
			continue
		var mob := node as CharacterBody2D
		if _planar_point_in_melee_hit(mob.global_position):
			mob.squash()


func _rebuild_melee_debug_mesh() -> void:
	if _melee_debug_mi == null:
		return
	_melee_debug_mi.visible = true
	var f2 := _facing_planar
	var p0 := global_position
	var f3 := Vector3(f2.x, 0.0, f2.y)
	var r3 := Vector3(-f3.z, 0.0, f3.x)
	var origin3 := Vector3(p0.x, melee_debug_ground_y, p0.y)
	var half_w := melee_width * 0.5
	var inner := _melee_range_start()
	var near_o := f3 * inner
	var far_o := f3 * (inner + melee_depth)
	var c0 := origin3 + near_o + r3 * (-half_w)
	var c1 := origin3 + near_o + r3 * half_w
	var c2 := origin3 + far_o + r3 * half_w
	var c3 := origin3 + far_o + r3 * (-half_w)
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _melee_debug_mat)
	var up := Vector3.UP
	for v in [c0, c1, c2, c0, c2, c3]:
		imm.surface_set_normal(up)
		imm.surface_add_vertex(v)
	imm.surface_end()
	_melee_debug_mi.mesh = imm


func _append_circle_fan_xz(
	imm: ImmediateMesh, mat: Material, center2: Vector2, radius: float, ground_y: float, segments: int
) -> void:
	if radius <= 0.0 or segments < 3:
		return
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var up := Vector3.UP
	var c := Vector3(center2.x, ground_y, center2.y)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var e0 := Vector3(center2.x + cos(a0) * radius, ground_y, center2.y + sin(a0) * radius)
		var e1 := Vector3(center2.x + cos(a1) * radius, ground_y, center2.y + sin(a1) * radius)
		for v in [c, e0, e1]:
			imm.surface_set_normal(up)
			imm.surface_add_vertex(v)
	imm.surface_end()


func _rebuild_player_hitbox_debug() -> void:
	if _player_hitbox_mi == null:
		return
	if not show_player_hitbox_debug:
		_player_hitbox_mi.visible = false
		return
	_player_hitbox_mi.visible = true
	var radius := 1.2676448
	var center2 := global_position
	if _body_shape:
		center2 = _body_shape.global_position
		if _body_shape.shape is CircleShape2D:
			radius = (_body_shape.shape as CircleShape2D).radius
	var imm := ImmediateMesh.new()
	_append_circle_fan_xz(
		imm,
		_player_hitbox_mat,
		center2,
		radius,
		hitbox_debug_ground_y,
		maxi(3, hitbox_debug_circle_segments)
	)
	_player_hitbox_mi.mesh = imm


func _rebuild_mob_hitboxes_debug() -> void:
	if _mob_hitboxes_mi == null:
		return
	if not show_mob_hitbox_debug:
		_mob_hitboxes_mi.visible = false
		return
	var gy := hitbox_debug_ground_y
	var up := Vector3.UP
	var verts: PackedVector3Array = PackedVector3Array()
	for node in get_tree().get_nodes_in_group(&"mob"):
		var cs := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null:
			continue
		var sh := cs.shape
		if sh is RectangleShape2D:
			var rect := sh as RectangleShape2D
			var hw := rect.size.x * 0.5
			var hh := rect.size.y * 0.5
			var xf := cs.global_transform
			var g0: Vector2 = xf * Vector2(-hw, -hh)
			var g1: Vector2 = xf * Vector2(hw, -hh)
			var g2: Vector2 = xf * Vector2(hw, hh)
			var g3: Vector2 = xf * Vector2(-hw, hh)
			var p0 := Vector3(g0.x, gy, g0.y)
			var p1 := Vector3(g1.x, gy, g1.y)
			var p2 := Vector3(g2.x, gy, g2.y)
			var p3 := Vector3(g3.x, gy, g3.y)
			verts.append_array([p0, p1, p2, p0, p2, p3])
	if verts.is_empty():
		_mob_hitboxes_mi.mesh = null
		_mob_hitboxes_mi.visible = false
		return
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mob_hitbox_mat)
	for k in range(verts.size()):
		imm.surface_set_normal(up)
		imm.surface_add_vertex(verts[k])
	imm.surface_end()
	_mob_hitboxes_mi.visible = true
	_mob_hitboxes_mi.mesh = imm


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if _mouse_steering_active():
		var target := _mouse_planar_world()
		var to_target := target - global_position
		if to_target.length_squared() > 0.01:
			direction = to_target.normalized()

	_update_facing_planar(direction)

	var planar_speed := 0.0
	if direction != Vector2.ZERO:
		velocity = direction * speed
		planar_speed = speed
	else:
		velocity = Vector2.ZERO

	if height <= 0.001 and Input.is_action_just_pressed(&"jump"):
		vertical_velocity = jump_impulse

	vertical_velocity -= fall_acceleration * delta
	height += vertical_velocity * delta
	if height <= 0.0:
		height = 0.0
		if vertical_velocity < 0.0:
			vertical_velocity = 0.0

	move_and_slide()

	_try_stomp_from_above()

	if _visual:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)
		_visual.rotation.y = atan2(_facing_planar.x, _facing_planar.y)
		if _visual.has_method(&"set_locomotion_from_planar_speed"):
			_visual.set_locomotion_from_planar_speed(planar_speed, speed)
		if _visual.has_method(&"set_jump_tilt"):
			_visual.set_jump_tilt(vertical_velocity, jump_impulse)

	if Input.is_action_just_pressed(&"melee_attack"):
		if _visual and _visual.has_method(&"try_play_attack"):
			_visual.try_play_attack()
		_squash_mobs_in_melee_hit()

	if show_melee_hit_debug:
		_rebuild_melee_debug_mesh()
	elif _melee_debug_mi:
		_melee_debug_mi.visible = false

	if show_player_hitbox_debug:
		_rebuild_player_hitbox_debug()
	elif _player_hitbox_mi:
		_player_hitbox_mi.visible = false

	if show_mob_hitbox_debug:
		_rebuild_mob_hitboxes_debug()
	elif _mob_hitboxes_mi:
		_mob_hitboxes_mi.visible = false

	if _invuln_time_remaining > 0.0:
		_invuln_time_remaining = maxf(0.0, _invuln_time_remaining - delta)
		if _invuln_time_remaining <= 0.0:
			_reset_player_visual_transparency()
		else:
			_update_invulnerability_flash_visual()


func _try_stomp_from_above() -> void:
	if vertical_velocity > 0.0:
		return
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is CharacterBody2D or not node.has_method(&"squash"):
			continue
		var mob := node as CharacterBody2D
		if global_position.distance_to(mob.global_position) > stomp_radius:
			continue
		var top_h: float = 1.0
		var st: Variant = mob.get(&"stomp_top_height")
		if st != null:
			top_h = float(st)
		if height < top_h + 0.05:
			continue
		mob.squash()
		vertical_velocity = bounce_impulse
		break


func die() -> void:
	_free_world_debug_meshes()
	hit.emit()
	queue_free()


func _free_world_debug_meshes() -> void:
	for mi in [_melee_debug_mi, _player_hitbox_mi, _mob_hitboxes_mi]:
		if mi != null and is_instance_valid(mi):
			mi.queue_free()
	_melee_debug_mi = null
	_player_hitbox_mi = null
	_mob_hitboxes_mi = null


func _on_mob_detector_body_entered(body: Node2D) -> void:
	# Only creeps kill the player; avoids spurious Area2D overlaps (e.g. parent body quirks).
	if body == null or body == self or not body.is_in_group(&"mob"):
		return
	if height >= mob_detector_safe_height:
		return
	var planar_d := body.global_position.distance_to(global_position)
	if planar_d > mob_kill_max_planar_dist:
		return
	take_damage(mob_hit_damage)
