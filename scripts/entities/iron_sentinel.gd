extends EnemyBase
class_name IronSentinelMob

const SENTINEL_IDLE_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Idle.glb")
const SENTINEL_BLOCK_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Block.glb")
const SENTINEL_WALK_BLOCK_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Walk_and_Block.glb")
const SENTINEL_RUN_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Running.glb")
const SENTINEL_PUNCH_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Left_Hook_from_Guard.glb")
const SENTINEL_STOMP_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Ground_Stomp.glb")
const SENTINEL_FALL_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Falling_down.glb")
const SENTINEL_STAND_UP_SCENE := preload("res://art/characters/enemies/Iron_Sentinel/Iron_Sentinel_Stand_Up.glb")
const SentinelDamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")

enum AttackState {
	NONE,
	PUNCH,
	STOMP,
}

enum RecoveryState {
	NONE,
	FALLING,
	DOWNED_HOLD,
	STANDING_UP,
}

@export var move_speed := 5.5
@export var guard_move_multiplier := 0.58
@export var melee_range := 6.5
@export var punch_reach := 13.0
@export var punch_width := 11.0
@export var punch_damage := 22
@export var punch_hitbox_duration := 0.12
@export var punch_fallback_duration := 1.0
@export var punch_hit_fraction := 0.72
@export var stomp_radius := 10.5
@export var stomp_damage := 18
@export var stomp_hitbox_duration := 0.12
@export var stomp_fallback_duration := 1.2
@export var stomp_hit_fraction := 0.82
@export var attack_finish_buffer := 0.08
@export var attack_cooldown := 0.9
@export var attack_choice_stomp_weight := 0.45
@export var repath_interval := 0.22
@export var target_refresh_interval := 0.3
@export var block_arc_degrees := 145.0
@export var guard_break_damage_threshold := 50.0
@export var fallen_hold_duration := 3.0
@export var fall_fallback_duration := 0.9
@export var stand_up_fallback_duration := 1.0
@export var stand_up_duration_reduction := 1.0
@export var mesh_ground_y := 0.0
@export var mesh_scale := Vector3(5.1, 5.1, 5.1)
@export var facing_yaw_offset_deg := 0.0
@export var telegraph_ground_y := 0.06
## How fast the sentinel rotates to track the player while advancing (lower = easier to flank).
@export var turn_toward_target_deg_per_sec := 100.0
@export var show_guard_debug_visual := false
@export var guard_debug_ground_y := 0.08
@export var guard_debug_radius := 8.5

var _visual
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _guard_debug_mesh: MeshInstance3D
var _guard_debug_outline_mat: StandardMaterial3D
var _guard_debug_fill_mat: StandardMaterial3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _speed_multiplier := 1.0
var _aggro_enabled := true
var _guard_advancing := false
var _attack_state := AttackState.NONE
var _attack_elapsed := 0.0
var _attack_total_duration := 0.0
var _attack_hit_time := 0.0
var _attack_end_time := 0.0
var _attack_has_triggered := false
var _attack_dir := Vector2(0.0, -1.0)
var _facing_dir := Vector2(0.0, -1.0)
var _cooldown_remaining := 0.0
var _recovery_state := RecoveryState.NONE
var _recovery_elapsed := 0.0
var _recovery_duration := 0.0
var _recovery_playback_speed_scale := 1.0
var _guard_break_accumulated_damage := 0.0

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _punch_hitbox: Hitbox2D = $PunchHitbox
@onready var _stomp_hitbox: Hitbox2D = $StompHitbox
@onready var _punch_shape_node: CollisionShape2D = $PunchHitbox/CollisionShape2D
@onready var _stomp_shape_node: CollisionShape2D = $StompHitbox/CollisionShape2D


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		_target_player = null
		_guard_advancing = false
		_cancel_attack()
		_clear_recovery_state()
		velocity = Vector2.ZERO
		_update_attack_telegraph_visual(false, AttackState.NONE, Vector2.ZERO, 0.0)
		_sync_visual()


func _ready() -> void:
	super._ready()
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"IronSentinelVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = facing_yaw_offset_deg
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_create_telegraph_mesh(vw)
		if show_guard_debug_visual:
			_create_guard_debug_mesh(vw)
	_sync_visual()
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.75
		_nav_agent.target_desired_distance = melee_range * 0.8
		_nav_agent.avoidance_enabled = false
	_refresh_attack_hitboxes()


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()
	if _guard_debug_mesh != null and is_instance_valid(_guard_debug_mesh):
		_guard_debug_mesh.queue_free()


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_attack_telegraph_visual(
			_attack_state != AttackState.NONE and not _attack_has_triggered,
			_attack_state,
			_attack_dir,
			_attack_progress()
		)
		_sync_visual()
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		_update_attack_telegraph_visual(false, AttackState.NONE, Vector2.ZERO, 0.0)
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	if _recovery_state != RecoveryState.NONE:
		_update_recovery(delta)
		move_and_slide()
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	_refresh_target_player(delta, _attack_state == AttackState.NONE)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_target_player()
	if _attack_state != AttackState.NONE:
		_update_attack(delta)
	else:
		_update_behavior(delta)
	move_and_slide()
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"gv": _guard_advancing,
		"as": _attack_state,
		"ae": _attack_elapsed,
		"ad": _attack_total_duration,
		"ah": _attack_has_triggered,
		"dir": _attack_dir,
		"fd": _facing_dir,
		"rs": _recovery_state,
		"re": _recovery_elapsed,
		"rd": _recovery_duration,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_guard_advancing = bool(state.get("gv", false))
	_attack_state = int(state.get("as", AttackState.NONE)) as AttackState
	_attack_elapsed = maxf(0.0, float(state.get("ae", 0.0)))
	_attack_total_duration = maxf(0.0, float(state.get("ad", 0.0)))
	_attack_has_triggered = bool(state.get("ah", false))
	var attack_dir_v: Variant = state.get("dir", _attack_dir)
	if attack_dir_v is Vector2:
		var next_attack_dir := attack_dir_v as Vector2
		if next_attack_dir.length_squared() > 0.0001:
			_attack_dir = next_attack_dir.normalized()
	var facing_dir_v: Variant = state.get("fd", _facing_dir)
	if facing_dir_v is Vector2:
		var next_facing_dir := facing_dir_v as Vector2
		if next_facing_dir.length_squared() > 0.0001:
			_facing_dir = next_facing_dir.normalized()
	_recovery_state = int(state.get("rs", RecoveryState.NONE)) as RecoveryState
	_recovery_elapsed = maxf(0.0, float(state.get("re", 0.0)))
	_recovery_duration = maxf(0.0, float(state.get("rd", 0.0)))


func _update_behavior(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		_guard_advancing = false
		_guard_break_accumulated_damage = 0.0
		velocity = Vector2.ZERO
		_update_attack_telegraph_visual(false, AttackState.NONE, Vector2.ZERO, 0.0)
		return
	var to_target := _target_player.global_position - global_position
	if to_target.length_squared() > 0.0001:
		var max_step := deg_to_rad(turn_toward_target_deg_per_sec) * delta
		_facing_dir = EnemyBase.step_planar_facing_toward(
			_facing_dir, to_target.normalized(), max_step
		)
	if to_target.length_squared() <= melee_range * melee_range and _cooldown_remaining <= 0.0:
		_guard_break_accumulated_damage = 0.0
		_start_attack(_choose_attack_state(), _facing_dir)
		return
	_guard_advancing = true
	_update_guard_advance_velocity(delta)
	_update_attack_telegraph_visual(false, AttackState.NONE, Vector2.ZERO, 0.0)


func _update_guard_advance_velocity(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent != null and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	var desired := Vector2.ZERO
	if _nav_agent != null and _nav_agent.get_navigation_map() != RID():
		var next_pos := _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		if to_next.length_squared() > 0.001:
			desired = to_next.normalized()
	var to_target := _target_player.global_position - global_position
	if desired.length_squared() <= 0.0001 and to_target.length_squared() > 0.001:
		desired = to_target.normalized()
	velocity = desired * move_speed * guard_move_multiplier * _speed_multiplier


func _start_attack(next_attack_state: AttackState, direction: Vector2) -> void:
	_attack_state = next_attack_state
	_attack_elapsed = 0.0
	_attack_has_triggered = false
	_attack_dir = direction if direction.length_squared() > 0.0001 else _facing_dir
	if _attack_dir.length_squared() <= 0.0001:
		_attack_dir = Vector2(0.0, -1.0)
	else:
		_attack_dir = _attack_dir.normalized()
	_facing_dir = _attack_dir
	_guard_advancing = false
	_guard_break_accumulated_damage = 0.0
	velocity = Vector2.ZERO
	_refresh_attack_hitboxes()
	var visual_state := _visual_state_name()
	var attack_duration := 0.0
	if _visual != null:
		attack_duration = _visual.set_state(visual_state, true)
	attack_duration = maxf(attack_duration, _attack_fallback_duration(next_attack_state))
	_attack_total_duration = attack_duration
	_attack_hit_time = attack_duration * _attack_hit_fraction(next_attack_state)
	_attack_end_time = maxf(_attack_hit_time, attack_duration - attack_finish_buffer)
	_update_attack_telegraph_visual(true, _attack_state, _attack_dir, 0.0)


func _update_attack(delta: float) -> void:
	velocity = Vector2.ZERO
	_attack_elapsed += delta
	var telegraph_active := not _attack_has_triggered
	_update_attack_telegraph_visual(
		telegraph_active,
		_attack_state,
		_attack_dir,
		_attack_progress()
	)
	if not _attack_has_triggered and _attack_elapsed >= _attack_hit_time:
		_attack_has_triggered = true
		_trigger_attack_hit()
		_cooldown_remaining = attack_cooldown
	if _attack_elapsed >= _attack_end_time:
		_cancel_attack()


func _cancel_attack() -> void:
	_attack_state = AttackState.NONE
	_attack_elapsed = 0.0
	_attack_total_duration = 0.0
	_attack_hit_time = 0.0
	_attack_end_time = 0.0
	_attack_has_triggered = false
	if _punch_hitbox != null:
		_punch_hitbox.deactivate()
	if _stomp_hitbox != null:
		_stomp_hitbox.deactivate()
	_update_attack_telegraph_visual(false, AttackState.NONE, Vector2.ZERO, 0.0)


func _update_recovery(delta: float) -> void:
	velocity = Vector2.ZERO
	_guard_advancing = false
	_guard_break_accumulated_damage = 0.0
	_cancel_attack()
	_recovery_elapsed += delta
	match _recovery_state:
		RecoveryState.FALLING:
			if _recovery_elapsed >= _recovery_duration:
				_begin_downed_hold()
		RecoveryState.DOWNED_HOLD:
			if _recovery_elapsed >= _recovery_duration:
				_begin_stand_up_recovery()
		RecoveryState.STANDING_UP:
			if _recovery_elapsed >= _recovery_duration:
				_clear_recovery_state()


func _start_guard_break_recovery() -> void:
	_cancel_attack()
	_recovery_state = RecoveryState.FALLING
	_recovery_elapsed = 0.0
	_recovery_duration = _visual_duration_for_state(&"fallen", fall_fallback_duration)
	_recovery_playback_speed_scale = 1.0
	_guard_break_accumulated_damage = 0.0
	_cooldown_remaining = maxf(_cooldown_remaining, _recovery_duration + fallen_hold_duration)
	_update_attack_telegraph_visual(false, AttackState.NONE, Vector2.ZERO, 0.0)
	if _visual != null:
		_visual.set_playback_paused(false)
		_visual.set_state(&"fallen", true)


func _begin_downed_hold() -> void:
	_recovery_state = RecoveryState.DOWNED_HOLD
	_recovery_elapsed = 0.0
	_recovery_duration = maxf(0.0, fallen_hold_duration)
	_recovery_playback_speed_scale = 1.0
	if _visual != null:
		_visual.set_state(&"fallen")
		_visual.seek_current_animation_seconds(_visual.get_current_animation_duration_seconds())
		_visual.set_playback_paused(true)


func _begin_stand_up_recovery() -> void:
	_recovery_state = RecoveryState.STANDING_UP
	_recovery_elapsed = 0.0
	var base_duration := _visual_duration_for_state(&"stand_up", stand_up_fallback_duration)
	_recovery_duration = maxf(0.05, base_duration - maxf(0.0, stand_up_duration_reduction))
	_recovery_playback_speed_scale = (
		base_duration / _recovery_duration if _recovery_duration > 0.0 else 1.0
	)
	if _visual != null:
		_visual.set_playback_paused(false)


func _clear_recovery_state() -> void:
	_recovery_state = RecoveryState.NONE
	_recovery_elapsed = 0.0
	_recovery_duration = 0.0
	_recovery_playback_speed_scale = 1.0
	if _visual != null:
		_visual.set_playback_paused(false)


func _visual_duration_for_state(state_name: StringName, fallback_duration: float) -> float:
	if _visual == null:
		return maxf(0.01, fallback_duration)
	var duration: float = float(_visual.set_state(state_name, true))
	return maxf(0.01, duration if duration > 0.0 else fallback_duration)


func _trigger_attack_hit() -> void:
	match _attack_state:
		AttackState.PUNCH:
			_activate_punch_hitbox()
		AttackState.STOMP:
			_activate_stomp_hitbox()


func _activate_punch_hitbox() -> void:
	if _punch_hitbox == null or not is_damage_authority():
		return
	var packet := SentinelDamagePacketScript.new() as DamagePacket
	packet.amount = punch_damage
	packet.kind = &"melee"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = global_position
	packet.direction = _attack_dir
	packet.knockback = 9.0
	packet.apply_iframes = true
	packet.blockable = true
	packet.debug_label = &"sentinel_punch"
	_punch_hitbox.activate(packet, punch_hitbox_duration)


func _activate_stomp_hitbox() -> void:
	if _stomp_hitbox == null or not is_damage_authority():
		return
	var packet := SentinelDamagePacketScript.new() as DamagePacket
	packet.amount = stomp_damage
	packet.kind = &"stomp"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = global_position
	packet.direction = _attack_dir
	packet.knockback = 6.0
	packet.apply_iframes = true
	packet.blockable = false
	packet.debug_label = &"sentinel_stomp"
	_stomp_hitbox.activate(packet, stomp_hitbox_duration)


func _refresh_attack_hitboxes() -> void:
	if _punch_hitbox != null:
		if _punch_shape_node != null and _punch_shape_node.shape is RectangleShape2D:
			var rect := _punch_shape_node.shape as RectangleShape2D
			rect.size = Vector2(punch_width, punch_reach)
		_punch_hitbox.position = _attack_dir * (punch_reach * 0.45)
		_punch_hitbox.rotation = _attack_dir.angle() + PI * 0.5
	if _stomp_hitbox != null:
		if _stomp_shape_node != null and _stomp_shape_node.shape is CircleShape2D:
			var circle := _stomp_shape_node.shape as CircleShape2D
			circle.radius = stomp_radius
		_stomp_hitbox.position = Vector2.ZERO


func _attack_progress() -> float:
	return clampf(_attack_elapsed / maxf(0.01, _attack_hit_time), 0.0, 1.0)


func _choose_attack_state() -> int:
	return AttackState.STOMP if randf() < attack_choice_stomp_weight else AttackState.PUNCH


func _attack_fallback_duration(attack_state: int) -> float:
	return stomp_fallback_duration if attack_state == AttackState.STOMP else punch_fallback_duration


func _attack_hit_fraction(attack_state: int) -> float:
	return stomp_hit_fraction if attack_state == AttackState.STOMP else punch_hit_fraction


func _visual_state_name() -> StringName:
	match _attack_state:
		AttackState.PUNCH:
			return &"punch"
		AttackState.STOMP:
			return &"stomp"
		_:
			match _recovery_state:
				RecoveryState.FALLING, RecoveryState.DOWNED_HOLD:
					return &"fallen"
				RecoveryState.STANDING_UP:
					return &"stand_up"
			if _guard_advancing:
				return &"walk_block"
			if velocity.length_squared() > 0.01:
				return &"walk"
			return &"idle"


func _sync_visual() -> void:
	if _visual == null:
		_sync_guard_debug_visual()
		return
	var facing_dir := _resolve_visual_facing_direction()
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	_visual.set_state(_visual_state_name())
	_visual.sync_from_2d(global_position, facing_dir)
	if _recovery_state == RecoveryState.DOWNED_HOLD:
		_visual.seek_current_animation_seconds(_visual.get_current_animation_duration_seconds())
		_visual.set_playback_paused(true)
	elif _recovery_state != RecoveryState.NONE:
		_visual.set_playback_paused(false)
	var playback_scale := clampf(
		velocity.length() / maxf(move_speed * maxf(_speed_multiplier, 0.01), 0.01),
		0.35,
		1.8
	) if velocity.length_squared() > 0.01 else 1.0
	if _recovery_state == RecoveryState.STANDING_UP:
		playback_scale *= _recovery_playback_speed_scale
	_visual.set_playback_speed_scale(playback_scale)
	_sync_guard_debug_visual(facing_dir)


func _should_use_high_detail_visuals() -> bool:
	if _attack_state != AttackState.NONE or _recovery_state != RecoveryState.NONE:
		return true
	if _target_player != null and is_instance_valid(_target_player):
		var detail_range := maxf(melee_range, punch_reach) + 8.0
		return global_position.distance_squared_to(_target_player.global_position) <= detail_range * detail_range
	return _guard_advancing or velocity.length_squared() > 0.04


func _resolve_visual_facing_direction() -> Vector2:
	if _attack_state != AttackState.NONE and _attack_dir.length_squared() > 0.0001:
		return _attack_dir.normalized()
	if _facing_dir.length_squared() > 0.0001:
		return _facing_dir.normalized()
	if velocity.length_squared() > 0.0001:
		return velocity.normalized()
	return Vector2(0.0, -1.0)


func _refresh_target_player(delta: float, allow_retarget: bool = true) -> void:
	_target_refresh_time_remaining = maxf(0.0, _target_refresh_time_remaining - delta)
	if (
		_target_player == null
		or not is_instance_valid(_target_player)
		or (allow_retarget and _target_refresh_time_remaining <= 0.0)
	):
		_target_player = _pick_target_player()
		_target_refresh_time_remaining = maxf(0.05, target_refresh_interval)


func _build_visual_state_config() -> Dictionary:
	var idle_scene := SENTINEL_IDLE_SCENE
	var block_scene := SENTINEL_BLOCK_SCENE
	var walk_block_scene := SENTINEL_WALK_BLOCK_SCENE
	var walk_scene := SENTINEL_RUN_SCENE
	var punch_scene := SENTINEL_PUNCH_SCENE
	var stomp_scene := SENTINEL_STOMP_SCENE
	var fall_scene := SENTINEL_FALL_SCENE
	var stand_up_scene := SENTINEL_STAND_UP_SCENE
	if block_scene == null:
		block_scene = idle_scene
	if walk_block_scene == null:
		walk_block_scene = block_scene if block_scene != null else idle_scene
	if walk_scene == null:
		walk_scene = idle_scene
	if punch_scene == null:
		punch_scene = block_scene if block_scene != null else idle_scene
	if stomp_scene == null:
		stomp_scene = block_scene if block_scene != null else idle_scene
	if fall_scene == null:
		fall_scene = idle_scene
	if stand_up_scene == null:
		stand_up_scene = idle_scene
	return {
		&"idle": {
			"scene": idle_scene,
			"keywords": ["idle", "stand", "reset"],
		},
		&"block": {
			"scene": block_scene,
			"keywords": ["block", "guard"],
		},
		&"walk_block": {
			"scene": walk_block_scene,
			"keywords": ["walk", "block", "guard"],
		},
		&"walk": {
			"scene": walk_scene,
			"keywords": ["run", "walk", "moving"],
		},
		&"punch": {
			"scene": punch_scene,
			"keywords": ["hook", "attack", "punch"],
		},
		&"stomp": {
			"scene": stomp_scene,
			"keywords": ["stomp", "attack"],
		},
		&"fallen": {
			"scene": fall_scene,
			"keywords": ["fall", "down"],
		},
		&"stand_up": {
			"scene": stand_up_scene,
			"keywords": ["stand", "up", "rise"],
		},
	}


func _create_telegraph_mesh(parent: Node3D) -> void:
	_telegraph_mesh = MeshInstance3D.new()
	_telegraph_mesh.name = &"IronSentinelTelegraph"
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.albedo_color = Color(0.95, 0.32, 0.18, 0.72)
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_mesh.visible = false
	parent.add_child(_telegraph_mesh)


func _create_guard_debug_mesh(parent: Node3D) -> void:
	_guard_debug_mesh = MeshInstance3D.new()
	_guard_debug_mesh.name = &"IronSentinelGuardDebug"
	_guard_debug_outline_mat = StandardMaterial3D.new()
	_guard_debug_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_guard_debug_outline_mat.albedo_color = Color(0.08, 0.26, 0.9, 1.0)
	_guard_debug_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guard_debug_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_guard_debug_fill_mat = StandardMaterial3D.new()
	_guard_debug_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_guard_debug_fill_mat.albedo_color = Color(0.2, 0.58, 1.0, 0.26)
	_guard_debug_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guard_debug_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_guard_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guard_debug_mesh.visible = false
	_guard_debug_mesh.mesh = _build_guard_debug_mesh()
	parent.add_child(_guard_debug_mesh)


func _build_guard_debug_mesh() -> ImmediateMesh:
	var imm := ImmediateMesh.new()
	var radius := maxf(1.0, guard_debug_radius)
	var clamped_arc_degrees := clampf(block_arc_degrees, 10.0, 360.0)
	var half_arc_radians := deg_to_rad(clamped_arc_degrees * 0.5)
	var segments := maxi(10, int(ceil(clamped_arc_degrees / 12.0)))
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _guard_debug_fill_mat)
	for segment_index in range(segments):
		var t0 := float(segment_index) / float(segments)
		var t1 := float(segment_index + 1) / float(segments)
		var angle_0 := lerpf(-half_arc_radians, half_arc_radians, t0)
		var angle_1 := lerpf(-half_arc_radians, half_arc_radians, t1)
		var edge_0 := Vector3(sin(angle_0) * radius, 0.0, cos(angle_0) * radius)
		var edge_1 := Vector3(sin(angle_1) * radius, 0.0, cos(angle_1) * radius)
		imm.surface_add_vertex(Vector3.ZERO)
		imm.surface_add_vertex(edge_0)
		imm.surface_add_vertex(edge_1)
	imm.surface_end()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _guard_debug_outline_mat)
	var first_edge := Vector3(sin(-half_arc_radians) * radius, 0.0, cos(-half_arc_radians) * radius)
	var last_edge := Vector3(sin(half_arc_radians) * radius, 0.0, cos(half_arc_radians) * radius)
	imm.surface_add_vertex(Vector3.ZERO)
	imm.surface_add_vertex(first_edge)
	imm.surface_add_vertex(Vector3.ZERO)
	imm.surface_add_vertex(last_edge)
	imm.surface_add_vertex(Vector3.ZERO)
	imm.surface_add_vertex(Vector3(0.0, 0.0, radius))
	for segment_index in range(segments):
		var t0 := float(segment_index) / float(segments)
		var t1 := float(segment_index + 1) / float(segments)
		var angle_0 := lerpf(-half_arc_radians, half_arc_radians, t0)
		var angle_1 := lerpf(-half_arc_radians, half_arc_radians, t1)
		var arc_0 := Vector3(sin(angle_0) * radius, 0.0, cos(angle_0) * radius)
		var arc_1 := Vector3(sin(angle_1) * radius, 0.0, cos(angle_1) * radius)
		imm.surface_add_vertex(arc_0)
		imm.surface_add_vertex(arc_1)
	imm.surface_end()
	return imm


func _sync_guard_debug_visual(facing_dir: Vector2 = Vector2.ZERO) -> void:
	if not show_guard_debug_visual or _guard_debug_mesh == null:
		return
	var guard_active := is_directional_guard_active()
	_guard_debug_mesh.visible = guard_active
	if not guard_active:
		return
	var resolved_facing := facing_dir
	if resolved_facing.length_squared() <= 0.0001:
		resolved_facing = _resolve_visual_facing_direction()
	if resolved_facing.length_squared() <= 0.0001:
		resolved_facing = Vector2(0.0, -1.0)
	else:
		resolved_facing = resolved_facing.normalized()
	_guard_debug_mesh.global_position = Vector3(global_position.x, guard_debug_ground_y, global_position.y)
	_guard_debug_mesh.rotation = Vector3(0.0, atan2(resolved_facing.x, resolved_facing.y), 0.0)


func _update_attack_telegraph_visual(
	active: bool, attack_state: int, direction: Vector2, progress: float
) -> void:
	if _telegraph_mesh == null:
		return
	if not active or attack_state == AttackState.NONE:
		_telegraph_mesh.visible = false
		return
	_telegraph_mesh.visible = true
	var p := clampf(progress, 0.0, 1.0)
	if attack_state == AttackState.PUNCH:
		var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
		_telegraph_mesh.global_position = Vector3(global_position.x, telegraph_ground_y, global_position.y)
		_telegraph_mesh.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
	else:
		_telegraph_mesh.global_position = Vector3(global_position.x, telegraph_ground_y, global_position.y)
		_telegraph_mesh.rotation = Vector3.ZERO
	var imm := ImmediateMesh.new()
	if attack_state == AttackState.STOMP:
		_fill_mat.albedo_color = Color(0.95, 0.55, 0.18, 0.68)
		var radius := stomp_radius * p
		var outer_radius := maxf(stomp_radius, 0.1)
		var segments := 24
		imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
		for segment_index in range(segments):
			var t0 := float(segment_index) / float(segments)
			var t1 := float(segment_index + 1) / float(segments)
			var a0 := lerpf(0.0, TAU, t0)
			var a1 := lerpf(0.0, TAU, t1)
			var p0 := Vector3(sin(a0) * outer_radius, 0.0, cos(a0) * outer_radius)
			var p1 := Vector3(sin(a1) * outer_radius, 0.0, cos(a1) * outer_radius)
			imm.surface_add_vertex(p0)
			imm.surface_add_vertex(p1)
		imm.surface_end()
		imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
		for segment_index in range(segments):
			var t0 := float(segment_index) / float(segments)
			var t1 := float(segment_index + 1) / float(segments)
			var a0 := lerpf(0.0, TAU, t0)
			var a1 := lerpf(0.0, TAU, t1)
			var p0 := Vector3(sin(a0) * radius, 0.001, cos(a0) * radius)
			var p1 := Vector3(sin(a1) * radius, 0.001, cos(a1) * radius)
			imm.surface_add_vertex(Vector3(0.0, 0.001, 0.0))
			imm.surface_add_vertex(p0)
			imm.surface_add_vertex(p1)
		imm.surface_end()
	else:
		_fill_mat.albedo_color = Color(0.95, 0.18, 0.18, 0.72)
		var half_width := punch_width * 0.5
		var fill_depth := punch_reach * p
		var l0 := Vector3(half_width, 0.0, 0.0)
		var r0 := Vector3(-half_width, 0.0, 0.0)
		var l1 := Vector3(half_width, 0.0, punch_reach)
		var r1 := Vector3(-half_width, 0.0, punch_reach)
		var lf := Vector3(half_width, 0.001, fill_depth)
		var rf := Vector3(-half_width, 0.001, fill_depth)
		imm.surface_begin(Mesh.PRIMITIVE_LINES, _outline_mat)
		for pair in [[l0, l1], [l1, r1], [r1, r0], [r0, l0]]:
			imm.surface_add_vertex(pair[0] as Vector3)
			imm.surface_add_vertex(pair[1] as Vector3)
		imm.surface_end()
		imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill_mat)
		for tri in [[l0, r0, rf], [l0, rf, lf]]:
			for v in tri:
				imm.surface_add_vertex(v as Vector3)
		imm.surface_end()
	_telegraph_mesh.mesh = imm


func _pick_target_player() -> Node2D:
	return _pick_nearest_player_target()


func is_directional_guard_active() -> bool:
	return (
		_guard_advancing
		and _attack_state == AttackState.NONE
		and _recovery_state == RecoveryState.NONE
		and _aggro_enabled
	)


func get_directional_guard_facing() -> Vector2:
	return _resolve_visual_facing_direction()


func get_combat_planar_facing() -> Vector2:
	return _resolve_visual_facing_direction()


func on_directional_guard_blocked_hit(packet: DamagePacket, _blocked_hurtbox: Area2D) -> void:
	if _recovery_state != RecoveryState.NONE:
		return
	_guard_break_accumulated_damage += maxf(0.0, float(packet.amount))
	if _guard_break_accumulated_damage >= maxf(1.0, guard_break_damage_threshold):
		_start_guard_break_recovery()
		return
	_cooldown_remaining = maxf(_cooldown_remaining, 0.2)


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	if _recovery_state != RecoveryState.NONE:
		return
	# HP damage during punch/stomp should not cancel the attack; that restarts the
	# windup/hit timing and looks like the swing keeps resetting every player hit.
	if _attack_state != AttackState.NONE:
		return
	_cancel_attack()
	_guard_advancing = false
	_guard_break_accumulated_damage = 0.0
	velocity = Vector2.ZERO


func can_contact_damage() -> bool:
	return false


func get_shadow_visual_root() -> Node3D:
	return _visual
