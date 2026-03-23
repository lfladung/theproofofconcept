class_name DasherMob
extends EnemyBase

@export var min_speed := 10.0
@export var max_speed := 18.0
## Feet-to-ground mob; stomp when player.height exceeds this while falling.
@export var stomp_top_height := 1.02
@export var stop_distance := 1.2
@export var repath_interval := 0.2
@export var speed_scale := 0.75
@export var attack_trigger_distance_multiplier := 1.0
@export var telegraph_duration := 1.0
@export var dash_distance := 5.0
@export var dash_duration := 0.25
@export var dash_hit_width := 1.8
@export var dash_damage := 25
@export var arrow_ground_y := 0.06
@export var arrow_length := 7.8
@export var arrow_head_length := 0.8
@export var arrow_half_width := 0.32
@export var hit_stun_duration := 1.0
@export var hit_knockback_duration := 0.22

var _squash_applied: bool = false
var _visual: Node3D
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn: bool = false
var _move_speed := 12.0
var _speed_multiplier := 1.0
var _repath_time_remaining := 0.0
var _target_player: Node2D
var _is_telegraphing := false
var _is_dashing := false
var _telegraph_time := 0.0
var _dash_time := 0.0
var _dash_start := Vector2.ZERO
var _dash_end := Vector2.ZERO
var _dash_dir := Vector2.ZERO
var _dash_hit_applied := false
var _stun_time_remaining := 0.0
var _knockback_time_remaining := 0.0
var _knockback_velocity := Vector2.ZERO
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func _ready() -> void:
	super._ready()
	# Stay off collision layers until positioned — packed scene used to spawn at (0,0) with
	# layer 2 for one tick, overlapping the player and tripping MobDetector instantly.
	if _has_spawn:
		_apply_spawn(_spawn_start, _spawn_target)
	var vw := get_node_or_null("../../VisualWorld3D")
	_vw = vw as Node3D
	if vw:
		var vis: Node = preload("res://mob_visual.tscn").instantiate()
		vw.add_child(vis)
		_visual = vis as Node3D
		_sync_visual_from_body()
		_telegraph_mesh = MeshInstance3D.new()
		_telegraph_mesh.name = &"MobTelegraphArrow"
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
	_sync_visual_anim_speed()
	_target_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _nav_agent:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = stop_distance
		_nav_agent.avoidance_enabled = false
	if _has_spawn:
		set_deferred(&"collision_layer", 2)
		set_deferred(&"collision_mask", 7)
	else:
		push_warning("Mob entered tree without configure_spawn; removing.")
		queue_free()


func _exit_tree() -> void:
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func _physics_process(delta: float) -> void:
	_update_attack_state(delta)
	move_and_slide()
	_sync_visual_from_body()
	_update_telegraph_visual()


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, 0.0, global_position.y)
	# Match PlayerVisual: 2D (x, y) plane maps to 3D XZ; Godot2D Node2D.rotation ≠ this heading.
	if velocity.length_squared() > 0.0001:
		_visual.rotation.y = atan2(velocity.x, velocity.y) + PI


func _apply_spawn(start_position: Vector2, player_position: Vector2) -> void:
	global_position = start_position
	var random_speed := randf_range(min_speed, max_speed)
	_move_speed = random_speed * speed_scale * _speed_multiplier
	var to_player := player_position - start_position
	velocity = to_player.normalized() * _move_speed if to_player.length_squared() > 0.01 else Vector2.ZERO
	_sync_visual_anim_speed(_move_speed)


func _update_attack_state(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group(&"player") as Node2D
		if _target_player == null:
			velocity = Vector2.ZERO
			_is_telegraphing = false
			_is_dashing = false
			return
	if _stun_time_remaining > 0.0:
		_update_stun(delta)
		return
	if _is_dashing:
		_update_dash(delta)
		return
	if _is_telegraphing:
		_update_telegraph(delta)
		return
	_update_chase_velocity(delta)
	var to_player := _target_player.global_position - global_position
	var trigger_distance := arrow_length * attack_trigger_distance_multiplier
	if to_player.length() <= trigger_distance:
		_start_telegraph(to_player.normalized())


func _update_chase_velocity(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		_target_player = get_tree().get_first_node_in_group(&"player") as Node2D
		if _target_player == null:
			velocity = Vector2.ZERO
			return
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	var desired := Vector2.ZERO
	if _nav_agent and _nav_agent.get_navigation_map() != RID():
		var next_pos := _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		if to_next.length_squared() > 0.001:
			desired = to_next.normalized()
		else:
			# Navigation can return current position when no path is baked; fall back to direct chase.
			var to_player_fallback := _target_player.global_position - global_position
			desired = to_player_fallback.normalized() if to_player_fallback.length_squared() > 0.001 else Vector2.ZERO
	else:
		var to_player := _target_player.global_position - global_position
		desired = to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.ZERO
	var distance_to_player := global_position.distance_to(_target_player.global_position)
	if distance_to_player <= stop_distance:
		velocity = Vector2.ZERO
	else:
		velocity = desired * _move_speed
	_sync_visual_anim_speed()


func _start_telegraph(dir_to_player: Vector2) -> void:
	_is_telegraphing = true
	_telegraph_time = 0.0
	_dash_dir = dir_to_player if dir_to_player.length_squared() > 0.0001 else Vector2(1.0, 0.0)
	velocity = Vector2.ZERO
	_sync_visual_anim_speed(0.0)


func _update_telegraph(delta: float) -> void:
	telegraph_duration = maxf(0.01, telegraph_duration)
	_telegraph_time += delta
	velocity = Vector2.ZERO
	if _telegraph_time >= telegraph_duration:
		_start_dash()


func _start_dash() -> void:
	_is_telegraphing = false
	_is_dashing = true
	_dash_time = 0.0
	_dash_start = global_position
	_dash_end = _dash_start + _dash_dir.normalized() * dash_distance
	_dash_hit_applied = false
	velocity = _dash_dir.normalized() * (dash_distance / maxf(0.01, dash_duration))


func _update_dash(delta: float) -> void:
	_dash_time += delta
	var u := clampf(_dash_time / maxf(0.01, dash_duration), 0.0, 1.0)
	var target_pos := _dash_start.lerp(_dash_end, u)
	var to_target := target_pos - global_position
	if to_target.length_squared() > 0.0001:
		velocity = to_target / maxf(delta, 0.0001)
	else:
		velocity = Vector2.ZERO
	if not _dash_hit_applied:
		_try_apply_dash_hit()
	if u >= 1.0:
		_is_dashing = false
		velocity = Vector2.ZERO
		_sync_visual_anim_speed(0.0)


func _try_apply_dash_hit() -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		return
	var hit := _point_in_dash_sweep(_target_player.global_position)
	if not hit:
		return
	if _target_player.has_method(&"take_damage"):
		_target_player.call(&"take_damage", dash_damage)
	_dash_hit_applied = true


func _point_in_dash_sweep(point: Vector2) -> bool:
	var seg := _dash_end - _dash_start
	var seg_len := seg.length()
	if seg_len <= 0.0001:
		return false
	var dir := seg / seg_len
	var rel := point - _dash_start
	var along := rel.dot(dir)
	if along < 0.0 or along > seg_len:
		return false
	var normal := Vector2(-dir.y, dir.x)
	var lateral := absf(rel.dot(normal))
	return lateral <= dash_hit_width * 0.5


func _update_telegraph_visual() -> void:
	if _telegraph_mesh == null:
		return
	if not _is_telegraphing:
		_telegraph_mesh.visible = false
		return
	_telegraph_mesh.visible = true
	var progress := clampf(_telegraph_time / maxf(0.01, telegraph_duration), 0.0, 1.0)
	var dir := _dash_dir.normalized()
	var right := Vector2(-dir.y, dir.x)
	var base := global_position
	var shaft_end := base + dir * maxf(0.1, arrow_length - arrow_head_length)
	var tip := base + dir * arrow_length
	var l0 := base + right * arrow_half_width
	var r0 := base - right * arrow_half_width
	var l1 := shaft_end + right * arrow_half_width
	var r1 := shaft_end - right * arrow_half_width
	var h1 := shaft_end + right * (arrow_half_width * 1.8)
	var h2 := shaft_end - right * (arrow_half_width * 1.8)
	var fill_tip := base + dir * (arrow_length * progress)

	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
	for pair in [[l0, l1], [l1, h1], [h1, tip], [tip, h2], [h2, r1], [r1, r0], [r0, l0]]:
		var a := pair[0] as Vector2
		var b := pair[1] as Vector2
		imm.surface_add_vertex(Vector3(a.x, arrow_ground_y, a.y))
		imm.surface_add_vertex(Vector3(b.x, arrow_ground_y, b.y))
	imm.surface_end()

	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
	var tri_a := base + right * (arrow_half_width * 0.55)
	var tri_b := base - right * (arrow_half_width * 0.55)
	for v in [tri_a, tri_b, fill_tip]:
		imm.surface_add_vertex(Vector3(v.x, arrow_ground_y + 0.001, v.y))
	imm.surface_end()
	_telegraph_mesh.mesh = imm


func _sync_visual_anim_speed(for_speed: float = -1.0) -> void:
	if _visual == null:
		return
	var ap: AnimationPlayer = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		var s := for_speed if for_speed > 0.0 else velocity.length()
		ap.speed_scale = s / min_speed


func take_hit(damage: int, knockback_dir: Vector2, knockback_strength: float) -> void:
	if damage <= 0 or _squash_applied:
		return
	super.take_hit(damage, knockback_dir, knockback_strength)


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	_is_telegraphing = false
	_is_dashing = false
	_telegraph_time = 0.0
	_dash_time = 0.0
	_dash_hit_applied = false
	var dir := knockback_dir.normalized() if knockback_dir.length_squared() > 0.0001 else Vector2.ZERO
	_knockback_velocity = dir * maxf(0.0, knockback_strength) * 1.3
	_knockback_time_remaining = hit_knockback_duration
	_stun_time_remaining = hit_stun_duration
	_sync_visual_anim_speed(0.0)


func _update_stun(delta: float) -> void:
	_stun_time_remaining = maxf(0.0, _stun_time_remaining - delta)
	if _knockback_time_remaining > 0.0:
		_knockback_time_remaining = maxf(0.0, _knockback_time_remaining - delta)
		velocity = _knockback_velocity
	else:
		velocity = Vector2.ZERO
	if _stun_time_remaining <= 0.0:
		velocity = Vector2.ZERO
		_knockback_velocity = Vector2.ZERO
		_sync_visual_anim_speed(0.0)


func can_contact_damage() -> bool:
	return _is_dashing


func squash() -> void:
	if _squash_applied:
		return
	_squash_applied = true
	super.squash()
