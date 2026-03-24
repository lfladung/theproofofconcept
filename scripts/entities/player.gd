extends CharacterBody2D

signal hit
signal health_changed(current: int, max_health: int)
signal weapon_mode_changed(display_name: String)

const ARROW_PROJECTILE_SCENE := preload("res://scenes/entities/arrow_projectile.tscn")
const PLAYER_BOMB_SCENE := preload("res://scenes/entities/player_bomb.tscn")

enum WeaponMode { SWORD, GUN, BOMB }

## Horizontal speed (matches former 3D XZ plane).
@export var speed := 14.0
## Feet stay grounded in this combat milestone.
@export var height := 0.0
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
@export var melee_depth := 6.0
@export var melee_width := 6.0
@export var attack_hitbox_visual_duration := 0.2
@export var melee_attack_cooldown := 0.5
@export var melee_attack_damage := 25
@export var melee_knockback_strength := 11.0
## Ground Y for debug mesh (XZ play plane ↔ 3D).
@export var melee_debug_ground_y := 0.04
@export var show_melee_hit_debug := true
## Y offset on XZ plane for body collision overlays (below melee quad so layers read clearly).
@export var hitbox_debug_ground_y := 0.028
@export var show_player_hitbox_debug := true
@export var show_mob_hitbox_debug := true
@export var hitbox_debug_circle_segments := 40
@export var dodge_speed := 36.0
@export var dodge_duration := 0.16
@export var dodge_cooldown := 0.05
## Ranged (gun) — aligned loosely with arrow towers.
@export var ranged_cooldown := 0.45
@export var ranged_damage := 15
@export var ranged_knockback := 8.0
@export var ranged_speed := 24.0
@export var ranged_max_tiles := 8.0
@export var ranged_spawn_beyond_body := 0.75
@export var world_units_per_tile := 3.0
## Thrown bomb: Tab cycles weapons (see project input map; Space is dodge).
@export var bomb_damage := 30
@export var bomb_cooldown := 0.85
@export var bomb_landing_distance := 14.0
@export var bomb_aoe_radius := 5.0
@export var bomb_flight_time := 0.48
@export var bomb_arc_start_height := 4.0
@export var bomb_knockback_strength := 0.0

@onready var _visual: Node3D = get_node_or_null("../../VisualWorld3D/PlayerVisual") as Node3D
@onready var _body_shape: CollisionShape2D = $CollisionShape2D

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
var _dodge_time_remaining := 0.0
var _dodge_cooldown_remaining := 0.0
var _dodge_direction := Vector2.ZERO
var _is_dead := false
var _attack_hitbox_visual_time_remaining := 0.0
var _melee_attack_cooldown_remaining := 0.0
var weapon_mode: WeaponMode = WeaponMode.SWORD
var _ranged_cooldown_remaining := 0.0
var _bomb_cooldown_remaining := 0.0
var _rmb_down := false
## Right-click attacks: face mouse this frame, resolve attack next physics frame.
var _pending_rmb_kind: StringName = &""
var _pending_rmb_facing := Vector2(0.0, -1.0)


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


func get_weapon_mode_display() -> String:
	match weapon_mode:
		WeaponMode.GUN:
			return "Gun"
		WeaponMode.BOMB:
			return "Bomb"
		_:
			return "Sword"


func _cycle_weapon() -> void:
	if _is_dead:
		return
	match weapon_mode:
		WeaponMode.SWORD:
			weapon_mode = WeaponMode.GUN
		WeaponMode.GUN:
			weapon_mode = WeaponMode.BOMB
		_:
			weapon_mode = WeaponMode.SWORD
	weapon_mode_changed.emit(get_weapon_mode_display())


func _face_toward_mouse_planar() -> void:
	var t := _mouse_planar_world() - global_position
	if t.length_squared() > 0.0001:
		_facing_planar = t.normalized()


func _clear_pending_rmb_attack() -> void:
	_pending_rmb_kind = &""


func _queue_rmb_attack_after_facing_mouse() -> void:
	_face_toward_mouse_planar()
	_pending_rmb_facing = _facing_planar
	if weapon_mode == WeaponMode.GUN and _ranged_cooldown_remaining <= 0.0:
		_pending_rmb_kind = &"gun"
	elif weapon_mode == WeaponMode.SWORD and _melee_attack_cooldown_remaining <= 0.0:
		_pending_rmb_kind = &"melee"
	elif weapon_mode == WeaponMode.BOMB and _bomb_cooldown_remaining <= 0.0:
		_pending_rmb_kind = &"bomb"


func _execute_pending_rmb_attack_if_any() -> void:
	if _pending_rmb_kind == &"":
		return
	var kind := _pending_rmb_kind
	_pending_rmb_kind = &""
	_facing_planar = _pending_rmb_facing
	if kind == &"gun":
		if weapon_mode != WeaponMode.GUN or _ranged_cooldown_remaining > 0.0:
			return
		if _visual and _visual.has_method(&"try_play_attack"):
			_visual.try_play_attack()
		_try_fire_ranged_arrow()
	elif kind == &"melee":
		if weapon_mode != WeaponMode.SWORD or _melee_attack_cooldown_remaining > 0.0:
			return
		if _visual and _visual.has_method(&"try_play_attack"):
			_visual.try_play_attack()
		_squash_mobs_in_melee_hit()
		_melee_attack_cooldown_remaining = melee_attack_cooldown
		_attack_hitbox_visual_time_remaining = maxf(
			_attack_hitbox_visual_time_remaining,
			attack_hitbox_visual_duration
		)
	elif kind == &"bomb":
		if weapon_mode != WeaponMode.BOMB or _bomb_cooldown_remaining > 0.0:
			return
		if _visual and _visual.has_method(&"try_play_attack"):
			_visual.try_play_attack()
		_try_throw_bomb()


func _try_throw_bomb() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	var bomb := PLAYER_BOMB_SCENE.instantiate() as PlayerBomb
	if bomb == null:
		return
	var dir := _facing_planar
	if dir.length_squared() <= 1e-6:
		dir = Vector2(0.0, -1.0)
	bomb.configure(
		global_position,
		dir,
		vw,
		bomb_damage,
		bomb_aoe_radius,
		bomb_landing_distance,
		bomb_flight_time,
		bomb_arc_start_height,
		bomb_knockback_strength
	)
	parent.add_child(bomb)
	_bomb_cooldown_remaining = bomb_cooldown


func _try_fire_ranged_arrow() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	var arrow := ARROW_PROJECTILE_SCENE.instantiate() as ArrowProjectile
	if arrow == null:
		return
	arrow.damage = ranged_damage
	arrow.speed = ranged_speed
	arrow.max_distance = ranged_max_tiles * world_units_per_tile
	arrow.knockback_strength = ranged_knockback
	var dir := _facing_planar
	if dir.length_squared() <= 1e-6:
		dir = Vector2(0.0, -1.0)
	var spawn := global_position + dir * (_get_player_body_radius() + ranged_spawn_beyond_body)
	arrow.configure(spawn, dir, vw, true)
	parent.add_child(arrow)
	_ranged_cooldown_remaining = ranged_cooldown


func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0 or _is_dead:
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
	var opaque := int(floor(float(Time.get_ticks_msec()) / float(ms))) % 2 == 0
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
	var hit_pos := from + dir * t
	return Vector2(hit_pos.x, hit_pos.z)


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


func _melee_hit_polygon_world() -> PackedVector2Array:
	var f := _facing_planar
	var r := Vector2(-f.y, f.x)
	var half_w := melee_width * 0.5
	var inner := _melee_range_start()
	var p := global_position
	var poly := PackedVector2Array()
	poly.append(p + f * inner + r * (-half_w))
	poly.append(p + f * inner + r * half_w)
	poly.append(p + f * (inner + melee_depth) + r * half_w)
	poly.append(p + f * (inner + melee_depth) + r * (-half_w))
	return poly


func _melee_hit_overlaps_mob(mob: CharacterBody2D) -> bool:
	var melee_poly := _melee_hit_polygon_world()
	var mob_poly := HitboxOverlap2D.mob_collision_polygon_world(mob)
	if mob_poly.size() >= 3:
		return HitboxOverlap2D.convex_polygons_overlap(melee_poly, mob_poly)
	return _planar_point_in_melee_hit(mob.global_position)


func _squash_mobs_in_melee_hit() -> void:
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is CharacterBody2D:
			continue
		var mob := node as CharacterBody2D
		if _melee_hit_overlaps_mob(mob):
			if mob.has_method(&"take_hit"):
				mob.call(&"take_hit", melee_attack_damage, _facing_planar, melee_knockback_strength)


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
	if _is_dead:
		return
	_melee_attack_cooldown_remaining = maxf(0.0, _melee_attack_cooldown_remaining - delta)
	_ranged_cooldown_remaining = maxf(0.0, _ranged_cooldown_remaining - delta)
	_bomb_cooldown_remaining = maxf(0.0, _bomb_cooldown_remaining - delta)

	if Input.is_action_just_pressed(&"weapon_switch"):
		_clear_pending_rmb_attack()
		_cycle_weapon()

	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var rmb_click := rmb and not _rmb_down
	_rmb_down = rmb
	var ui_blocks_attack := get_viewport().gui_get_hovered_control() != null

	var direction := Vector2.ZERO
	if _mouse_steering_active():
		var target := _mouse_planar_world()
		var to_target := target - global_position
		if to_target.length_squared() > 0.01:
			direction = to_target.normalized()

	_update_facing_planar(direction)
	_execute_pending_rmb_attack_if_any()

	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	if _dodge_time_remaining > 0.0:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
	elif Input.is_action_just_pressed(&"dodge") and _dodge_cooldown_remaining <= 0.0:
		_dodge_direction = _facing_planar.normalized()
		if _dodge_direction.length_squared() <= 1e-6:
			_dodge_direction = Vector2(0.0, -1.0)
		_dodge_time_remaining = dodge_duration
		_dodge_cooldown_remaining = dodge_cooldown

	var planar_speed := 0.0
	if _dodge_time_remaining > 0.0:
		velocity = _dodge_direction * dodge_speed
		planar_speed = dodge_speed
	elif direction != Vector2.ZERO:
		velocity = direction * speed
		planar_speed = speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	if rmb_click and not ui_blocks_attack:
		_queue_rmb_attack_after_facing_mouse()

	if _visual:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)
		_visual.rotation.y = atan2(_facing_planar.x, _facing_planar.y)
		if _visual.has_method(&"set_locomotion_from_planar_speed"):
			_visual.set_locomotion_from_planar_speed(planar_speed, speed)

	var want_melee := false
	if weapon_mode == WeaponMode.SWORD:
		if Input.is_action_just_pressed(&"melee_attack"):
			want_melee = true
	if want_melee and _melee_attack_cooldown_remaining <= 0.0:
		if _visual and _visual.has_method(&"try_play_attack"):
			_visual.try_play_attack()
		_squash_mobs_in_melee_hit()
		_melee_attack_cooldown_remaining = melee_attack_cooldown
		_attack_hitbox_visual_time_remaining = maxf(
			_attack_hitbox_visual_time_remaining,
			attack_hitbox_visual_duration
		)

	_attack_hitbox_visual_time_remaining = maxf(0.0, _attack_hitbox_visual_time_remaining - delta)
	if show_melee_hit_debug and _attack_hitbox_visual_time_remaining > 0.0:
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


func die() -> void:
	_is_dead = true
	velocity = Vector2.ZERO
	height = 0.0
	_dodge_time_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_invuln_time_remaining = 0.0
	_rmb_down = false
	_clear_pending_rmb_attack()
	_bomb_cooldown_remaining = 0.0
	if _body_shape != null:
		_body_shape.disabled = true
	_free_world_debug_meshes()
	_reset_player_visual_transparency()
	hit.emit()


func reset_for_retry(world_pos: Vector2) -> void:
	_is_dead = false
	_clear_pending_rmb_attack()
	weapon_mode = WeaponMode.SWORD
	weapon_mode_changed.emit(get_weapon_mode_display())
	heal_to_full()
	global_position = world_pos
	velocity = Vector2.ZERO
	height = 0.0
	_invuln_time_remaining = 0.0
	_dodge_time_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_rmb_down = false
	_bomb_cooldown_remaining = 0.0
	if _body_shape != null:
		_body_shape.disabled = false
	_reset_player_visual_transparency()
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)


func heal_to_full() -> void:
	health = max_health
	health_changed.emit(health, max_health)


func _free_world_debug_meshes() -> void:
	for mi in [_melee_debug_mi, _player_hitbox_mi, _mob_hitboxes_mi]:
		if mi != null and is_instance_valid(mi):
			mi.queue_free()
	_melee_debug_mi = null
	_player_hitbox_mi = null
	_mob_hitboxes_mi = null


func get_shadow_visual_root() -> Node3D:
	return _visual


func _on_mob_detector_body_entered(body: Node2D) -> void:
	# Only creeps kill the player; avoids spurious Area2D overlaps (e.g. parent body quirks).
	if body == null or body == self or not body.is_in_group(&"mob"):
		return
	if body.has_method(&"can_contact_damage") and not bool(body.call(&"can_contact_damage")):
		return
	var planar_d := body.global_position.distance_to(global_position)
	if planar_d > mob_kill_max_planar_dist:
		return
	take_damage(mob_hit_damage)
