extends Node
class_name FakeShadow3D

## Spiral Knights-style fake shadow:
## - One unshaded circular Sprite3D
## - One downward RayCast3D for floor probing
## - Scale/alpha vary with floor distance

@export var base_scale := 2.35
@export var min_scale := 1.25
@export var base_alpha := 0.82
@export var min_alpha := 0.52
@export var max_shadow_distance := 8.0
@export var floor_offset := 0.07
@export var ray_start_height := 3.0
@export_flags_3d_physics var ground_collision_mask := -1
@export var non_mob_shadow_update_interval := 0.06
@export var mob_shadow_update_interval := 0.12
@export var disable_for_mobs := true

var _actor: Node2D
var _visual_world: Node3D
var _anchor_3d: Node3D
var _shadow_sprite: Sprite3D
var _shadow_ray: RayCast3D
var _disabled_actor_shadow_casting := false
var _shadow_update_time_remaining := 0.0
var _last_sampled_actor_pos := Vector2.INF

static var _shared_shadow_texture: Texture2D


func _ready() -> void:
	_actor = get_parent() as Node2D
	_visual_world = _resolve_visual_world_3d()
	if _actor == null:
		return
	if disable_for_mobs and _actor.is_in_group(&"mob"):
		set_physics_process(false)
		return
	set_physics_process(true)
	if _visual_world == null:
		call_deferred("_late_init_shadow_nodes")
		return
	_ensure_shadow_nodes()
	_physics_process(0.0)


func _exit_tree() -> void:
	if _anchor_3d != null and is_instance_valid(_anchor_3d):
		_anchor_3d.queue_free()
	_anchor_3d = null
	_shadow_sprite = null
	_shadow_ray = null


func _physics_process(_delta: float) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if _anchor_3d == null or not is_instance_valid(_anchor_3d):
		return
	var update_interval := non_mob_shadow_update_interval
	if _actor.is_in_group(&"mob"):
		update_interval = mob_shadow_update_interval
	if update_interval > 0.0:
		_shadow_update_time_remaining = maxf(0.0, _shadow_update_time_remaining - _delta)
		var actor_pos_now := _actor.global_position
		var moved_enough := (
			_last_sampled_actor_pos == Vector2.INF
			or actor_pos_now.distance_squared_to(_last_sampled_actor_pos) > 0.01
		)
		if _shadow_update_time_remaining > 0.0 and not moved_enough:
			return
		_shadow_update_time_remaining = update_interval
	_try_disable_actor_visual_shadows()

	var actor_pos := _actor.global_position
	_last_sampled_actor_pos = actor_pos
	_anchor_3d.global_position = Vector3(actor_pos.x, ray_start_height, actor_pos.y)
	_shadow_ray.target_position = Vector3(0.0, -(ray_start_height + max_shadow_distance), 0.0)
	_shadow_ray.force_raycast_update()

	if not _shadow_ray.is_colliding():
		_shadow_sprite.visible = false
		return

	var hit := _shadow_ray.get_collision_point()
	var y_dist := maxf(0.0, _anchor_3d.global_position.y - hit.y)
	var t := clampf(y_dist / maxf(0.001, max_shadow_distance), 0.0, 1.0)
	var s := lerpf(base_scale, min_scale, t)
	var a := lerpf(base_alpha, min_alpha, t)

	_shadow_sprite.visible = true
	_shadow_sprite.global_position = hit + Vector3(0.0, floor_offset, 0.0)
	_shadow_sprite.scale = Vector3(s, s, 1.0)
	var c := _shadow_sprite.modulate
	c.a = a
	_shadow_sprite.modulate = c


func _resolve_visual_world_3d() -> Node3D:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var direct := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
		if direct != null:
			return direct
		var deep := tree.current_scene.find_child("VisualWorld3D", true, false) as Node3D
		if deep != null:
			return deep
	var n: Node = self
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


func _late_init_shadow_nodes() -> void:
	if _anchor_3d != null and is_instance_valid(_anchor_3d):
		return
	_visual_world = _resolve_visual_world_3d()
	if _actor == null or _visual_world == null:
		return
	_ensure_shadow_nodes()
	_physics_process(0.0)


func _ensure_shadow_nodes() -> void:
	_anchor_3d = Node3D.new()
	_anchor_3d.name = &"FakeShadowAnchor3D"
	_visual_world.add_child(_anchor_3d)

	_shadow_ray = RayCast3D.new()
	_shadow_ray.name = &"ShadowRay"
	_shadow_ray.enabled = true
	_shadow_ray.collide_with_areas = false
	_shadow_ray.collide_with_bodies = true
	_shadow_ray.collision_mask = ground_collision_mask
	_anchor_3d.add_child(_shadow_ray)

	_shadow_sprite = Sprite3D.new()
	_shadow_sprite.name = &"Shadow"
	_shadow_sprite.shaded = false
	_shadow_sprite.double_sided = true
	_shadow_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_shadow_sprite.no_depth_test = false
	_shadow_sprite.modulate = Color(0.0, 0.0, 0.0, base_alpha)
	_shadow_sprite.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_shadow_sprite.texture = _ensure_shared_texture()
	_anchor_3d.add_child(_shadow_sprite)


func _ensure_shared_texture() -> Texture2D:
	if _shared_shadow_texture != null:
		return _shared_shadow_texture
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cx := float(size - 1) * 0.5
	var cy := float(size - 1) * 0.5
	var radius := float(size) * 0.47
	var hard_center := 0.72
	for y in range(size):
		for x in range(size):
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var u := clampf(d / radius, 0.0, 1.0)
			var alpha := 0.0
			if u <= hard_center:
				alpha = 1.0
			else:
				var t := clampf((u - hard_center) / maxf(0.0001, 1.0 - hard_center), 0.0, 1.0)
				alpha = 1.0 - (t * t)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var tex := ImageTexture.create_from_image(img)
	_shared_shadow_texture = tex
	return _shared_shadow_texture


func _try_disable_actor_visual_shadows() -> void:
	if _disabled_actor_shadow_casting:
		return
	if _actor == null:
		return
	if not _actor.has_method(&"get_shadow_visual_root"):
		return
	var node: Variant = _actor.call(&"get_shadow_visual_root")
	if node is not Node3D:
		return
	_disable_cast_shadows_recursive(node as Node)
	_disabled_actor_shadow_casting = true


func _disable_cast_shadows_recursive(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		if c is Node:
			_disable_cast_shadows_recursive(c as Node)
