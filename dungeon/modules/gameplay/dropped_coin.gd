extends Node2D
class_name DroppedCoin

const JUMP_DURATION_SEC := 0.48
const PICKUP_DELAY_AFTER_LAND_MS := 1000
const ARC_PEAK := 2.35
const START_HEIGHT := 0.88
const COIN_REST_CENTER_Y := 1.05
const PLANAR_KICK_MIN := 1.4
const PLANAR_KICK_MAX := 3.1

@onready var _pickup_area: Area2D = $PickupArea
@onready var _pickup_shape: CollisionShape2D = $PickupArea/CollisionShape2D

var _visual: MeshInstance3D
var _vw: Node3D
var _start_2d: Vector2
var _end_2d: Vector2
var _jump_u := 0.0
var _landed := false
var _pickup_enabled := false
var _pickup_after_ms: int = 0
var _spin := 0.0
var _collected := false
var _setup_done := false
var _chest_center_2d := Vector2.ZERO
var _bias_jump_outward := false
var _chest_kick_scale := 1.0
var _fixed_arc_end_2d: Vector2
var _use_fixed_arc_end := false


## VisualWorld3D is a sibling of GameWorld2D under the scene root — not a child of GameWorld2D.
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
	_pickup_area.body_entered.connect(_on_pickup_body_entered)
	call_deferred(&"_deferred_setup_drop")


func _exit_tree() -> void:
	# Ensure floor-regeneration cleanup removes the detached 3D coin mesh too.
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null


## Call before `add_child` / setting position when spawning from a chest so the hop continues outward.
## `kick_scale` scales the extra planar kick (1.0 = legacy chest strength; use ~0.5 for shorter tosses).
func bias_jump_away_from(world_origin_2d: Vector2, kick_scale: float = 1.0) -> void:
	_bias_jump_outward = true
	_chest_center_2d = world_origin_2d
	_chest_kick_scale = kick_scale


## Chest burst: hop along a straight line in XZ from current position to this landing point (no random kick).
func set_planar_arc_end(world_end_2d: Vector2) -> void:
	_fixed_arc_end_2d = world_end_2d
	_use_fixed_arc_end = true


## Runs after the spawner sets our global_position (mob sets it after add_child).
func _deferred_setup_drop() -> void:
	if not is_inside_tree():
		return
	_start_2d = global_position
	var kick: Vector2
	if _use_fixed_arc_end:
		kick = _fixed_arc_end_2d - _start_2d
	elif _bias_jump_outward:
		var away := _start_2d - _chest_center_2d
		if away.length_squared() < 0.25:
			away = Vector2(1.0, 0.0)
		var dir := away.normalized()
		var tang := Vector2(-dir.y, dir.x)
		var ks := _chest_kick_scale
		kick = (
			dir * randf_range(PLANAR_KICK_MIN + 2.2, PLANAR_KICK_MAX + 4.0) * ks
			+ tang * randf_range(-2.0, 2.0) * ks
		)
	else:
		kick = Vector2.from_angle(randf() * TAU) * randf_range(PLANAR_KICK_MIN, PLANAR_KICK_MAX)
	_end_2d = _start_2d + kick

	_vw = _find_visual_world(self)
	if _vw == null:
		push_warning("DroppedCoin: could not find VisualWorld3D; 3D coin mesh skipped.")
	if _vw:
		# No texture/sprite — a MeshInstance3D + CylinderMesh only (easier to spot at dungeon scale).
		_visual = MeshInstance3D.new()
		_visual.name = &"DroppedCoinMesh"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.15
		cyl.bottom_radius = 1.15
		cyl.height = 0.35
		cyl.radial_segments = 24
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.88, 0.15)
		mat.emission_enabled = true
		mat.emission = Color(0.45, 0.35, 0.02)
		mat.emission_energy_multiplier = 1.15
		cyl.material = mat
		_visual.mesh = cyl
		_visual.rotation_degrees.x = 90.0
		_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vw.add_child(_visual)

	_pickup_area.collision_layer = 0
	_pickup_area.collision_mask = 1
	_pickup_area.set_deferred("monitoring", false)
	_pickup_area.set_deferred("monitorable", false)
	_pickup_shape.set_deferred("disabled", true)
	_setup_done = true


func _physics_process(delta: float) -> void:
	if not _setup_done:
		return
	if not _landed:
		_jump_u = minf(1.0, _jump_u + delta / JUMP_DURATION_SEC)
		var u := _jump_u
		var smooth := u * u * (3.0 - 2.0 * u)
		var y := lerpf(START_HEIGHT, COIN_REST_CENTER_Y, smooth) + sin(PI * u) * ARC_PEAK
		var planar := _start_2d.lerp(_end_2d, u)
		global_position = planar
		if _visual:
			_spin += delta * 5.5
			_visual.global_position = Vector3(planar.x, y, planar.y)
			_visual.rotation_degrees = Vector3(90.0, rad_to_deg(_spin), 0.0)
		if _jump_u >= 1.0:
			_land()
	elif not _pickup_enabled and Time.get_ticks_msec() >= _pickup_after_ms:
		_enable_pickup()
	elif _visual:
		_spin += delta * 2.6
		_visual.rotation_degrees = Vector3(90.0, rad_to_deg(_spin), 0.0)


func _land() -> void:
	_landed = true
	global_position = _end_2d
	_pickup_after_ms = Time.get_ticks_msec() + PICKUP_DELAY_AFTER_LAND_MS
	if _visual:
		_visual.global_position = Vector3(_end_2d.x, COIN_REST_CENTER_Y, _end_2d.y)


func _enable_pickup() -> void:
	_pickup_enabled = true
	_pickup_shape.set_deferred("disabled", false)
	_pickup_area.set_deferred("monitoring", true)
	_pickup_area.set_deferred("monitorable", true)
	call_deferred(&"_try_pickup_overlapping_player")


func _try_pickup_overlapping_player() -> void:
	if _collected or not is_instance_valid(self):
		return
	for b in _pickup_area.get_overlapping_bodies():
		_on_pickup_body_entered(b as Node2D)


func _on_pickup_body_entered(body: Node2D) -> void:
	if _collected or not _pickup_enabled or body == null or not body.is_in_group(&"player"):
		return
	_collected = true
	for n in get_tree().get_nodes_in_group(&"score_ui"):
		if n.has_method(&"add_score"):
			n.call(&"add_score", 1)
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	queue_free()
