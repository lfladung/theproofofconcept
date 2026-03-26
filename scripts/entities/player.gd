extends CharacterBody2D

signal hit
signal health_changed(current: int, max_health: int)
signal weapon_mode_changed(display_name: String)
signal downed_state_changed(is_downed: bool)

const ARROW_PROJECTILE_SCENE := preload("res://scenes/entities/arrow_projectile.tscn")
const PLAYER_BOMB_SCENE := preload("res://scenes/entities/player_bomb.tscn")
const PLAYER_VISUAL_SCENE := preload("res://scenes/visuals/player_visual.tscn")
const REVIVE_HEALTH := 50

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
@export var melee_facing_lock_fallback_duration := 0.25
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
## Milestone 3: movement input stream + server state replication.
@export var network_sync_interval := 0.05
@export var prediction_correction_snap_distance := 1.8
@export var prediction_correction_lerp_rate := 18.0
@export var remote_interpolation_lerp_rate := 14.0
@export var remote_interpolation_snap_distance := 6.0

@onready var _visual: Node3D
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
var _facing_lock_time_remaining := 0.0
var _facing_lock_planar := Vector2(0.0, -1.0)
var _melee_attack_cooldown_remaining := 0.0
var weapon_mode: WeaponMode = WeaponMode.SWORD
var _ranged_cooldown_remaining := 0.0
var _bomb_cooldown_remaining := 0.0
var _rmb_down := false
## Right-click attacks: face mouse this frame, resolve attack next physics frame.
var _pending_rmb_kind: StringName = &""
var _pending_rmb_facing := Vector2(0.0, -1.0)
var network_owner_peer_id := 1
var _remote_planar_speed := 0.0
var _net_sync_time_accum := 0.0
var _input_sequence := 0
var _last_acknowledged_input_sequence := -1
var _pending_input_commands: Array[Dictionary] = []
var _local_prev_dodge_down := false
var _server_last_input_sequence := -1
var _server_input_move_active := false
var _server_input_target_world := Vector2.ZERO
var _server_input_dodge_down := false
var _server_prev_dodge_down := false
var _server_has_received_input := false
var _local_weapon_switch_request_sequence := 0
var _server_last_weapon_switch_request_sequence := -1
var _local_melee_request_sequence := 0
var _server_last_melee_request_sequence := -1
var _server_melee_event_sequence := 0
var _server_melee_hit_event_sequence := 0
var _last_applied_melee_event_sequence := -1
var _local_ranged_request_sequence := 0
var _server_last_ranged_request_sequence := -1
var _server_ranged_event_sequence := 0
var _last_applied_ranged_event_sequence := -1
var _remote_ranged_projectiles_by_event_id: Dictionary = {}
var _local_bomb_request_sequence := 0
var _server_last_bomb_request_sequence := -1
var _server_bomb_event_sequence := 0
var _last_applied_bomb_event_sequence := -1
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _remote_has_state := false
var _reconcile_target_position := Vector2.ZERO
var _reconcile_target_velocity := Vector2.ZERO
var _reconcile_target_facing := Vector2(0.0, -1.0)
var _reconcile_target_dodge_time_remaining := 0.0
var _reconcile_target_dodge_cooldown_remaining := 0.0
var _reconcile_target_dodge_direction := Vector2.ZERO
var _reconcile_target_facing_lock_time_remaining := 0.0
var _reconcile_target_facing_lock_planar := Vector2(0.0, -1.0)
var _reconcile_has_target := false
var _authoritative_weapon_mode_id := int(WeaponMode.SWORD)
var _authoritative_melee_cooldown_remaining := 0.0
var _authoritative_ranged_cooldown_remaining := 0.0
var _authoritative_bomb_cooldown_remaining := 0.0


func _ready() -> void:
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_visual = _resolve_or_create_visual_root(vw)
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
	network_owner_peer_id = get_multiplayer_authority()
	_authoritative_weapon_mode_id = int(weapon_mode)
	_authoritative_melee_cooldown_remaining = 0.0
	_authoritative_ranged_cooldown_remaining = 0.0
	_authoritative_bomb_cooldown_remaining = 0.0
	_apply_visual_downed_state()
	_sync_sword_visual()
	call_deferred("_sync_sword_visual")


func set_network_owner_peer_id(peer_id: int) -> void:
	network_owner_peer_id = max(1, peer_id)
	set_multiplayer_authority(network_owner_peer_id, true)
	if OS.is_debug_build():
		var has_peer := multiplayer.multiplayer_peer != null
		var local_peer := multiplayer.get_unique_id() if has_peer else 1
		var local_authority := is_multiplayer_authority() if has_peer else network_owner_peer_id == local_peer
		print(
			"[M2][PlayerAuthority] node=%s owner_peer=%s local_peer=%s is_local_authority=%s" % [
				name,
				network_owner_peer_id,
				local_peer,
				local_authority,
			]
		)


func _resolve_or_create_visual_root(vw: Node3D) -> Node3D:
	if vw == null:
		return null
	var vis := PLAYER_VISUAL_SCENE.instantiate() as Node3D
	if vis == null:
		return null
	vis.name = "PlayerVisual_%s" % [name]
	vis.set_meta(&"owned_by_player", true)
	vw.add_child(vis)
	return vis


func suppress_placeholder_visual() -> void:
	# Dedicated-session placeholder players should not own/claim any visible 3D proxy.
	_free_world_debug_meshes()
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.queue_free()
	_visual = null


func _multiplayer_active() -> bool:
	return multiplayer.multiplayer_peer != null


func _local_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


func _is_server_peer() -> bool:
	return _multiplayer_active() and multiplayer.is_server()


func _can_broadcast_world_replication() -> bool:
	if not _multiplayer_active() or not _is_server_peer():
		return true
	var session := get_node_or_null("/root/NetworkSession")
	if session != null and session.has_method("can_broadcast_world_replication"):
		return bool(session.call("can_broadcast_world_replication"))
	return true

func _is_local_owner_peer() -> bool:
	return network_owner_peer_id == _local_peer_id()


func _update_remote_proxy_visual() -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, height, global_position.y)
	_visual.rotation.y = atan2(_facing_planar.x, _facing_planar.y)
	if _visual.has_method(&"set_locomotion_from_planar_speed"):
		_visual.set_locomotion_from_planar_speed(_remote_planar_speed, speed)


func _update_visual_from_planar_speed(planar_speed: float) -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, height, global_position.y)
	_visual.rotation.y = atan2(_facing_planar.x, _facing_planar.y)
	if _visual.has_method(&"set_locomotion_from_planar_speed"):
		_visual.set_locomotion_from_planar_speed(planar_speed, speed)


func _apply_visual_downed_state() -> void:
	if _visual == null:
		return
	if _visual.has_method(&"set_downed_state"):
		_visual.call(&"set_downed_state", _is_dead)


func _sync_sword_visual() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	if _visual.has_method(&"set_sword_active"):
		_visual.call(&"set_sword_active", weapon_mode == WeaponMode.SWORD)


func _set_downed_state(next_downed: bool, emit_hit_signal: bool = false) -> void:
	if _is_dead == next_downed:
		return
	_is_dead = next_downed
	if _is_dead:
		velocity = Vector2.ZERO
		height = 0.0
		_dodge_time_remaining = 0.0
		_dodge_cooldown_remaining = 0.0
		_facing_lock_time_remaining = 0.0
		_invuln_time_remaining = 0.0
		_attack_hitbox_visual_time_remaining = 0.0
		_rmb_down = false
		_clear_pending_rmb_attack()
	else:
		_invuln_time_remaining = 0.0
	if _body_shape != null:
		_body_shape.disabled = _is_dead
	_reset_player_visual_transparency()
	_apply_visual_downed_state()
	if emit_hit_signal and _is_dead:
		hit.emit()
	downed_state_changed.emit(_is_dead)


func _resolve_melee_facing_lock_duration() -> float:
	if _visual != null and _visual.has_method(&"get_attack_duration_seconds"):
		var duration_v: Variant = _visual.call(&"get_attack_duration_seconds")
		var duration := float(duration_v)
		if duration > 0.0:
			return duration
	return maxf(melee_facing_lock_fallback_duration, attack_hitbox_visual_duration)


func _start_facing_lock(direction: Vector2, duration_seconds: float = -1.0) -> void:
	var lock_dir := direction
	if lock_dir.length_squared() <= 1e-6:
		lock_dir = _facing_planar
	if lock_dir.length_squared() <= 1e-6:
		lock_dir = Vector2(0.0, -1.0)
	_facing_lock_planar = lock_dir.normalized()
	_facing_planar = _facing_lock_planar
	var duration := duration_seconds if duration_seconds >= 0.0 else _resolve_melee_facing_lock_duration()
	_facing_lock_time_remaining = maxf(_facing_lock_time_remaining, maxf(0.0, duration))


func _tick_facing_lock(delta: float) -> void:
	if _facing_lock_time_remaining <= 0.0:
		return
	_facing_lock_time_remaining = maxf(0.0, _facing_lock_time_remaining - delta)
	_facing_planar = _facing_lock_planar


func _is_facing_locked() -> bool:
	return _facing_lock_time_remaining > 0.0


func _broadcast_server_state(delta: float) -> void:
	if not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_net_sync_time_accum += delta
	if _net_sync_time_accum < network_sync_interval:
		return
	_net_sync_time_accum = 0.0
	_rpc_receive_server_state.rpc(
		global_position,
		velocity,
		_facing_planar,
		health,
		int(weapon_mode),
		_is_dead,
		_dodge_time_remaining,
		_dodge_cooldown_remaining,
		_dodge_direction,
		_facing_lock_time_remaining,
		_melee_attack_cooldown_remaining,
		_ranged_cooldown_remaining,
		_bomb_cooldown_remaining,
		_server_last_input_sequence
	)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_submit_movement_input(
	sequence: int,
	move_active: bool,
	target_world: Vector2,
	dodge_down: bool
) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if sequence < _server_last_input_sequence:
		return
	_server_has_received_input = true
	_server_last_input_sequence = sequence
	_server_input_move_active = move_active
	_server_input_target_world = target_world
	_server_input_dodge_down = dodge_down


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_receive_server_state(
	world_pos: Vector2,
	planar_velocity: Vector2,
	facing_planar: Vector2,
	health_value: int,
	weapon_value: int,
	dead_state: bool,
	dodge_time_remaining_value: float,
	dodge_cooldown_remaining_value: float,
	dodge_direction_value: Vector2,
	facing_lock_time_remaining_value: float,
	melee_cooldown_remaining_value: float,
	ranged_cooldown_remaining_value: float,
	bomb_cooldown_remaining_value: float,
	ack_input_sequence: int
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if facing_planar.length_squared() > 1e-6:
		_facing_planar = facing_planar.normalized()
	var normalized_health := clampi(health_value, 0, max_health)
	if health != normalized_health:
		health = normalized_health
		health_changed.emit(health, max_health)
	var next_weapon := weapon_mode
	match weapon_value:
		1:
			next_weapon = WeaponMode.GUN
		2:
			next_weapon = WeaponMode.BOMB
		_:
			next_weapon = WeaponMode.SWORD
	if weapon_mode != next_weapon:
		weapon_mode = next_weapon
		weapon_mode_changed.emit(get_weapon_mode_display())
	_authoritative_weapon_mode_id = int(next_weapon)
	_authoritative_melee_cooldown_remaining = maxf(0.0, melee_cooldown_remaining_value)
	_authoritative_ranged_cooldown_remaining = maxf(0.0, ranged_cooldown_remaining_value)
	_authoritative_bomb_cooldown_remaining = maxf(0.0, bomb_cooldown_remaining_value)
	_set_downed_state(dead_state)
	_sync_sword_visual()
	_facing_lock_time_remaining = maxf(0.0, facing_lock_time_remaining_value)
	if _facing_lock_time_remaining > 0.0:
		_facing_lock_planar = _facing_planar
	if _is_local_owner_peer():
		_reconcile_target_position = world_pos
		_reconcile_target_velocity = planar_velocity
		_reconcile_target_facing = _facing_planar
		_reconcile_target_dodge_time_remaining = maxf(0.0, dodge_time_remaining_value)
		_reconcile_target_dodge_cooldown_remaining = maxf(0.0, dodge_cooldown_remaining_value)
		_reconcile_target_dodge_direction = dodge_direction_value.normalized()
		_reconcile_target_facing_lock_time_remaining = _facing_lock_time_remaining
		_reconcile_target_facing_lock_planar = _facing_lock_planar
		_reconcile_has_target = true
		_last_acknowledged_input_sequence = max(_last_acknowledged_input_sequence, ack_input_sequence)
		_prune_acknowledged_pending_inputs(_last_acknowledged_input_sequence)
		return
	_remote_target_position = world_pos
	_remote_target_velocity = planar_velocity
	_remote_has_state = true


func _prune_acknowledged_pending_inputs(ack_sequence: int) -> void:
	if _pending_input_commands.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for command in _pending_input_commands:
		var seq_v: Variant = command.get("seq", -1)
		var seq := int(seq_v)
		if seq > ack_sequence:
			remaining.append(command)
	_pending_input_commands = remaining


func _apply_local_reconciliation(_delta: float) -> void:
	if not _reconcile_has_target:
		return
	if _is_dead:
		global_position = _reconcile_target_position
		velocity = Vector2.ZERO
		_pending_input_commands.clear()
		_reconcile_has_target = false
		return
	# Reconciliation for owner client: reset to authoritative server state, then replay
	# still-pending local commands so responsiveness remains while staying correct.
	global_position = _reconcile_target_position
	velocity = _reconcile_target_velocity
	_facing_planar = _reconcile_target_facing
	_dodge_time_remaining = _reconcile_target_dodge_time_remaining
	_dodge_cooldown_remaining = _reconcile_target_dodge_cooldown_remaining
	_dodge_direction = _reconcile_target_dodge_direction
	_facing_lock_time_remaining = _reconcile_target_facing_lock_time_remaining
	_facing_lock_planar = _reconcile_target_facing_lock_planar
	for command in _pending_input_commands:
		var move_active := bool(command.get("move_active", false))
		var target_world_variant: Variant = command.get("target_world", global_position)
		var target_world: Vector2 = (
			target_world_variant if target_world_variant is Vector2 else global_position
		)
		var dodge_pressed := bool(command.get("dodge_pressed", false))
		var command_delta := float(command.get("delta", 1.0 / maxf(1.0, float(Engine.physics_ticks_per_second))))
		_apply_movement_step(command_delta, move_active, target_world, dodge_pressed)
	_reconcile_has_target = false


func _apply_movement_step(
	delta: float, move_active: bool, target_world: Vector2, dodge_pressed: bool
) -> float:
	var direction := Vector2.ZERO
	if move_active:
		var to_target := target_world - global_position
		if to_target.length_squared() > 0.01:
			direction = to_target.normalized()
	_update_facing_planar(direction, false)
	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	if _dodge_time_remaining > 0.0:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
	elif dodge_pressed and _dodge_cooldown_remaining <= 0.0:
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
	_update_visual_from_planar_speed(planar_speed)
	return planar_speed


func _server_authoritative_step(delta: float) -> void:
	var move_active := false
	var target_world := global_position
	var dodge_down := false
	if _is_local_owner_peer():
		move_active = _mouse_steering_active()
		target_world = _mouse_planar_world()
		dodge_down = Input.is_action_pressed(&"dodge")
		_server_last_input_sequence += 1
	elif _server_has_received_input:
		move_active = _server_input_move_active
		target_world = _server_input_target_world
		dodge_down = _server_input_dodge_down
	var dodge_pressed := dodge_down and not _server_prev_dodge_down
	_server_prev_dodge_down = dodge_down
	_apply_movement_step(delta, move_active, target_world, dodge_pressed)
	_broadcast_server_state(delta)


func _client_predicted_step(delta: float) -> void:
	var move_active := _mouse_steering_active()
	var target_world := _mouse_planar_world()
	var dodge_down := Input.is_action_pressed(&"dodge")
	var dodge_pressed := dodge_down and not _local_prev_dodge_down
	_local_prev_dodge_down = dodge_down
	var sequence := _input_sequence
	_input_sequence += 1
	var command: Dictionary = {
		"seq": sequence,
		"move_active": move_active,
		"target_world": target_world,
		"dodge_down": dodge_down,
		"dodge_pressed": dodge_pressed,
		"delta": delta,
	}
	_pending_input_commands.append(command)
	_apply_movement_step(delta, move_active, target_world, dodge_pressed)
	_rpc_submit_movement_input.rpc(sequence, move_active, target_world, dodge_down)
	_apply_local_reconciliation(delta)


func _client_remote_step(delta: float) -> void:
	if not _remote_has_state:
		_update_remote_proxy_visual()
		return
	var dist_to_target := global_position.distance_to(_remote_target_position)
	if dist_to_target >= remote_interpolation_snap_distance:
		global_position = _remote_target_position
		velocity = _remote_target_velocity
		if velocity.length_squared() > 1e-6 and not _is_facing_locked():
			_facing_planar = velocity.normalized()
		_remote_planar_speed = velocity.length()
		_update_remote_proxy_visual()
		return
	var alpha := clampf(delta * remote_interpolation_lerp_rate, 0.0, 1.0)
	global_position = global_position.lerp(_remote_target_position, alpha)
	velocity = velocity.lerp(_remote_target_velocity, alpha)
	if velocity.length_squared() > 1e-6 and not _is_facing_locked():
		_facing_planar = velocity.normalized()
	_remote_planar_speed = velocity.length()
	_update_remote_proxy_visual()


func _run_shared_cooldown_and_debug_tick(delta: float) -> void:
	_tick_facing_lock(delta)
	_melee_attack_cooldown_remaining = maxf(0.0, _melee_attack_cooldown_remaining - delta)
	_ranged_cooldown_remaining = maxf(0.0, _ranged_cooldown_remaining - delta)
	_bomb_cooldown_remaining = maxf(0.0, _bomb_cooldown_remaining - delta)
	if _is_server_peer() or not _multiplayer_active():
		_authoritative_weapon_mode_id = int(weapon_mode)
		_authoritative_melee_cooldown_remaining = _melee_attack_cooldown_remaining
		_authoritative_ranged_cooldown_remaining = _ranged_cooldown_remaining
		_authoritative_bomb_cooldown_remaining = _bomb_cooldown_remaining
	else:
		_authoritative_melee_cooldown_remaining = maxf(
			0.0, _authoritative_melee_cooldown_remaining - delta
		)
		_authoritative_ranged_cooldown_remaining = maxf(
			0.0, _authoritative_ranged_cooldown_remaining - delta
		)
		_authoritative_bomb_cooldown_remaining = maxf(
			0.0, _authoritative_bomb_cooldown_remaining - delta
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


func _play_melee_attack_presentation() -> void:
	_play_attack_animation_presentation(&"melee")
	_attack_hitbox_visual_time_remaining = maxf(
		_attack_hitbox_visual_time_remaining,
		attack_hitbox_visual_duration
	)


func _play_attack_animation_presentation(mode: StringName = &"melee") -> void:
	if _visual == null:
		return
	if _visual.has_method(&"try_play_attack_for_mode"):
		_visual.call(&"try_play_attack_for_mode", mode)
	elif _visual.has_method(&"try_play_attack"):
		_visual.call(&"try_play_attack")


func _normalized_attack_facing(facing: Vector2) -> Vector2:
	if facing.length_squared() > 1e-6:
		return facing.normalized()
	if _facing_planar.length_squared() > 1e-6:
		return _facing_planar.normalized()
	return Vector2(0.0, -1.0)


func _compute_ranged_spawn(facing: Vector2) -> Vector2:
	return global_position + facing * (_get_player_body_radius() + ranged_spawn_beyond_body)


func _spawn_player_ranged_arrow(
	spawn_position: Vector2,
	facing: Vector2,
	authoritative_damage: bool,
	apply_cooldown: bool,
	projectile_event_id: int = -1
) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	if not authoritative_damage and projectile_event_id > 0:
		var existing_v: Variant = _remote_ranged_projectiles_by_event_id.get(projectile_event_id, null)
		if existing_v is ArrowProjectile and is_instance_valid(existing_v):
			return true
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	var arrow := ARROW_PROJECTILE_SCENE.instantiate() as ArrowProjectile
	if arrow == null:
		return false
	arrow.damage = ranged_damage
	arrow.speed = ranged_speed
	arrow.max_distance = ranged_max_tiles * world_units_per_tile
	arrow.knockback_strength = ranged_knockback
	if arrow.has_method(&"set_authoritative_damage"):
		arrow.call(&"set_authoritative_damage", authoritative_damage)
	arrow.configure(spawn_position, facing, vw, true)
	parent.add_child(arrow)
	if authoritative_damage and _is_server_peer() and projectile_event_id > 0 and arrow.has_signal(&"projectile_finished"):
		arrow.projectile_finished.connect(
			_on_server_authoritative_ranged_projectile_finished.bind(projectile_event_id),
			CONNECT_ONE_SHOT
		)
	elif not authoritative_damage and projectile_event_id > 0:
		_remote_ranged_projectiles_by_event_id[projectile_event_id] = arrow
	if apply_cooldown:
		_ranged_cooldown_remaining = ranged_cooldown
	return true


func _spawn_player_bomb(
	spawn_position: Vector2, facing: Vector2, authoritative_damage: bool, apply_cooldown: bool
) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	var bomb := PLAYER_BOMB_SCENE.instantiate() as PlayerBomb
	if bomb == null:
		return false
	bomb.configure(
		spawn_position,
		facing,
		vw,
		bomb_damage,
		bomb_aoe_radius,
		bomb_landing_distance,
		bomb_flight_time,
		bomb_arc_start_height,
		bomb_knockback_strength,
		authoritative_damage
	)
	parent.add_child(bomb)
	if apply_cooldown:
		_bomb_cooldown_remaining = bomb_cooldown
	return true


func _try_execute_server_melee_attack(requested_facing: Vector2) -> bool:
	if not _is_server_peer() or _is_dead:
		return false
	if weapon_mode != WeaponMode.SWORD:
		return false
	if _melee_attack_cooldown_remaining > 0.0:
		return false
	var resolved_facing := requested_facing
	if resolved_facing.length_squared() > 1e-6:
		_facing_planar = resolved_facing.normalized()
	_start_facing_lock(_facing_planar)
	_play_melee_attack_presentation()
	_server_melee_hit_event_sequence += 1
	var hit_event_id := _server_melee_hit_event_sequence
	var hit_count := _squash_mobs_in_melee_hit(hit_event_id)
	_melee_attack_cooldown_remaining = melee_attack_cooldown
	_server_melee_event_sequence += 1
	var event_sequence := _server_melee_event_sequence
	_last_applied_melee_event_sequence = max(_last_applied_melee_event_sequence, event_sequence)
	if _can_broadcast_world_replication():
		_rpc_receive_melee_attack_event.rpc(event_sequence, _facing_planar, hit_count)
	if OS.is_debug_build():
		print(
			"[M4][Melee] peer=%s attack_event=%s hit_event=%s hits=%s" % [
				network_owner_peer_id,
				event_sequence,
				hit_event_id,
				hit_count,
			]
		)
	return true


func _try_execute_server_ranged_attack(requested_facing: Vector2) -> bool:
	if not _is_server_peer() or _is_dead:
		return false
	if weapon_mode != WeaponMode.GUN:
		return false
	if _ranged_cooldown_remaining > 0.0:
		return false
	var resolved_facing := _normalized_attack_facing(requested_facing)
	_facing_planar = resolved_facing
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"ranged")
	var spawn := _compute_ranged_spawn(_facing_planar)
	_server_ranged_event_sequence += 1
	var event_sequence := _server_ranged_event_sequence
	if not _spawn_player_ranged_arrow(spawn, _facing_planar, true, true, event_sequence):
		return false
	_last_applied_ranged_event_sequence = max(_last_applied_ranged_event_sequence, event_sequence)
	if _can_broadcast_world_replication():
		_rpc_receive_ranged_attack_event.rpc(event_sequence, spawn, _facing_planar)
	if OS.is_debug_build():
		print(
			"[M4][Ranged] peer=%s attack_event=%s spawn=%s" % [
				network_owner_peer_id,
				event_sequence,
				spawn,
			]
		)
	return true


func _try_execute_server_bomb_attack(requested_facing: Vector2) -> bool:
	if not _is_server_peer() or _is_dead:
		return false
	if weapon_mode != WeaponMode.BOMB:
		return false
	if _bomb_cooldown_remaining > 0.0:
		return false
	var resolved_facing := _normalized_attack_facing(requested_facing)
	_facing_planar = resolved_facing
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"bomb")
	if not _spawn_player_bomb(global_position, _facing_planar, true, true):
		return false
	_server_bomb_event_sequence += 1
	var event_sequence := _server_bomb_event_sequence
	_last_applied_bomb_event_sequence = max(_last_applied_bomb_event_sequence, event_sequence)
	if _can_broadcast_world_replication():
		_rpc_receive_bomb_attack_event.rpc(event_sequence, global_position, _facing_planar)
	if OS.is_debug_build():
		print(
			"[M4][Bomb] peer=%s attack_event=%s origin=%s" % [
				network_owner_peer_id,
				event_sequence,
				global_position,
			]
		)
	return true


func _submit_local_melee_attack_request() -> void:
	if weapon_mode != WeaponMode.SWORD or _melee_attack_cooldown_remaining > 0.0:
		return
	if _is_server_peer():
		_try_execute_server_melee_attack(_facing_planar)
		return
	_local_melee_request_sequence += 1
	_start_facing_lock(_facing_planar)
	_rpc_request_melee_attack.rpc_id(1, _local_melee_request_sequence, _facing_planar)
	# Client-side throttle while awaiting authoritative result.
	_melee_attack_cooldown_remaining = melee_attack_cooldown


func _submit_local_ranged_attack_request() -> void:
	if weapon_mode != WeaponMode.GUN or _ranged_cooldown_remaining > 0.0:
		return
	if _is_server_peer():
		_try_execute_server_ranged_attack(_facing_planar)
		return
	_local_ranged_request_sequence += 1
	_start_facing_lock(_facing_planar)
	_rpc_request_ranged_attack.rpc_id(1, _local_ranged_request_sequence, _facing_planar)
	_ranged_cooldown_remaining = ranged_cooldown


func _submit_local_bomb_attack_request() -> void:
	if weapon_mode != WeaponMode.BOMB or _bomb_cooldown_remaining > 0.0:
		return
	if _is_server_peer():
		_try_execute_server_bomb_attack(_facing_planar)
		return
	_local_bomb_request_sequence += 1
	_start_facing_lock(_facing_planar)
	_rpc_request_bomb_attack.rpc_id(1, _local_bomb_request_sequence, _facing_planar)
	_bomb_cooldown_remaining = bomb_cooldown


func _submit_local_weapon_switch_request() -> void:
	if _is_dead:
		return
	if _is_server_peer():
		_cycle_weapon()
		return
	_local_weapon_switch_request_sequence += 1
	_cycle_weapon()
	_rpc_request_cycle_weapon.rpc_id(1, _local_weapon_switch_request_sequence)


func _handle_local_multiplayer_combat_input() -> void:
	if not _is_local_owner_peer() or _is_dead:
		return
	if Input.is_action_just_pressed(&"weapon_switch"):
		_clear_pending_rmb_attack()
		_submit_local_weapon_switch_request()
	if weapon_mode == WeaponMode.SWORD and Input.is_action_just_pressed(&"melee_attack"):
		_submit_local_melee_attack_request()
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var rmb_click := rmb and not _rmb_down
	_rmb_down = rmb
	var ui_blocks_attack := get_viewport().gui_get_hovered_control() != null
	if rmb_click and not ui_blocks_attack:
		_face_toward_mouse_planar()
		match weapon_mode:
			WeaponMode.GUN:
				_submit_local_ranged_attack_request()
			WeaponMode.BOMB:
				_submit_local_bomb_attack_request()
			_:
				_submit_local_melee_attack_request()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_cycle_weapon(request_sequence: int) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_weapon_switch_request_sequence:
		return
	_server_last_weapon_switch_request_sequence = request_sequence
	_cycle_weapon()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_melee_attack(request_sequence: int, facing_planar: Vector2) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_melee_request_sequence:
		return
	_server_last_melee_request_sequence = request_sequence
	_try_execute_server_melee_attack(facing_planar)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_ranged_attack(request_sequence: int, facing_planar: Vector2) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_ranged_request_sequence:
		return
	_server_last_ranged_request_sequence = request_sequence
	_try_execute_server_ranged_attack(facing_planar)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_bomb_attack(request_sequence: int, facing_planar: Vector2) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_bomb_request_sequence:
		return
	_server_last_bomb_request_sequence = request_sequence
	_try_execute_server_bomb_attack(facing_planar)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_melee_attack_event(
	event_sequence: int, facing_planar: Vector2, hit_count: int
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_melee_event_sequence:
		return
	_last_applied_melee_event_sequence = event_sequence
	if facing_planar.length_squared() > 1e-6:
		_facing_planar = facing_planar.normalized()
	_start_facing_lock(_facing_planar)
	_play_melee_attack_presentation()
	_melee_attack_cooldown_remaining = maxf(_melee_attack_cooldown_remaining, melee_attack_cooldown)
	if OS.is_debug_build():
		print(
			"[M4][Melee][Remote] peer=%s attack_event=%s hits=%s" % [
				network_owner_peer_id,
				event_sequence,
				hit_count,
			]
		)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_ranged_attack_event(
	event_sequence: int, spawn_position: Vector2, facing_planar: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_ranged_event_sequence:
		return
	_last_applied_ranged_event_sequence = event_sequence
	var dir := _normalized_attack_facing(facing_planar)
	_facing_planar = dir
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"ranged")
	_spawn_player_ranged_arrow(spawn_position, dir, false, false, event_sequence)
	_ranged_cooldown_remaining = maxf(_ranged_cooldown_remaining, ranged_cooldown)
	if OS.is_debug_build():
		print(
			"[M4][Ranged][Remote] peer=%s attack_event=%s spawn=%s" % [
				network_owner_peer_id,
				event_sequence,
				spawn_position,
			]
		)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_bomb_attack_event(
	event_sequence: int, spawn_position: Vector2, facing_planar: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_bomb_event_sequence:
		return
	_last_applied_bomb_event_sequence = event_sequence
	var dir := _normalized_attack_facing(facing_planar)
	_facing_planar = dir
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"bomb")
	_spawn_player_bomb(spawn_position, dir, false, false)
	_bomb_cooldown_remaining = maxf(_bomb_cooldown_remaining, bomb_cooldown)
	if OS.is_debug_build():
		print(
			"[M4][Bomb][Remote] peer=%s attack_event=%s origin=%s" % [
				network_owner_peer_id,
				event_sequence,
				spawn_position,
			]
		)


func _on_server_authoritative_ranged_projectile_finished(
	final_position: Vector2, projectile_event_id: int
) -> void:
	if not _is_server_peer():
		return
	if not _multiplayer_active():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_receive_ranged_projectile_finished.rpc(projectile_event_id, final_position)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_ranged_projectile_finished(
	projectile_event_id: int, final_position: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var projectile_v: Variant = _remote_ranged_projectiles_by_event_id.get(projectile_event_id, null)
	if projectile_v == null or not is_instance_valid(projectile_v):
		_remote_ranged_projectiles_by_event_id.erase(projectile_event_id)
		return
	var projectile := projectile_v as ArrowProjectile
	if projectile == null:
		_remote_ranged_projectiles_by_event_id.erase(projectile_event_id)
		return
	projectile.global_position = final_position
	if projectile.has_method(&"_finish_projectile"):
		projectile.call(&"_finish_projectile")
	else:
		projectile.queue_free()
	_remote_ranged_projectiles_by_event_id.erase(projectile_event_id)


func _physics_process_multiplayer(delta: float) -> void:
	_run_shared_cooldown_and_debug_tick(delta)
	_handle_local_multiplayer_combat_input()
	if _is_dead:
		if _is_server_peer():
			_broadcast_server_state(delta)
		elif _is_local_owner_peer():
			_apply_local_reconciliation(delta)
		return
	if _is_server_peer():
		_server_authoritative_step(delta)
		return
	if _is_local_owner_peer():
		_client_predicted_step(delta)
		return
	_client_remote_step(delta)


func get_combat_debug_snapshot() -> Dictionary:
	return {
		"weapon_mode": get_weapon_mode_display(),
		"weapon_mode_id": int(weapon_mode),
		"authoritative_weapon_mode": _weapon_mode_display_from_id(_authoritative_weapon_mode_id),
		"authoritative_weapon_mode_id": _authoritative_weapon_mode_id,
		"is_downed": _is_dead,
		"melee_cooldown": maxf(0.0, _melee_attack_cooldown_remaining),
		"ranged_cooldown": maxf(0.0, _ranged_cooldown_remaining),
		"bomb_cooldown": maxf(0.0, _bomb_cooldown_remaining),
		"authoritative_melee_cooldown": maxf(0.0, _authoritative_melee_cooldown_remaining),
		"authoritative_ranged_cooldown": maxf(0.0, _authoritative_ranged_cooldown_remaining),
		"authoritative_bomb_cooldown": maxf(0.0, _authoritative_bomb_cooldown_remaining),
		"facing_lock_time": maxf(0.0, _facing_lock_time_remaining),
		"is_server_peer": _is_server_peer(),
		"is_local_owner_peer": _is_local_owner_peer(),
		"network_owner_peer_id": network_owner_peer_id,
		"multiplayer_authority": get_multiplayer_authority(),
		"local_peer_id": _local_peer_id(),
		"has_peer": _multiplayer_active(),
}


func _weapon_mode_display_from_id(mode_id: int) -> String:
	match mode_id:
		int(WeaponMode.GUN):
			return "Gun"
		int(WeaponMode.BOMB):
			return "Bomb"
		_:
			return "Sword"


func get_weapon_mode_display() -> String:
	return _weapon_mode_display_from_id(int(weapon_mode))


func is_downed() -> bool:
	return _is_dead


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
	_sync_sword_visual()


func _face_toward_mouse_planar() -> void:
	if _is_facing_locked():
		return
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
		_play_attack_animation_presentation(&"ranged")
		_try_fire_ranged_arrow()
	elif kind == &"melee":
		if weapon_mode != WeaponMode.SWORD or _melee_attack_cooldown_remaining > 0.0:
			return
		_play_attack_animation_presentation(&"melee")
		_start_facing_lock(_facing_planar)
		_squash_mobs_in_melee_hit()
		_melee_attack_cooldown_remaining = melee_attack_cooldown
		_attack_hitbox_visual_time_remaining = maxf(
			_attack_hitbox_visual_time_remaining,
			attack_hitbox_visual_duration
		)
	elif kind == &"bomb":
		if weapon_mode != WeaponMode.BOMB or _bomb_cooldown_remaining > 0.0:
			return
		_play_attack_animation_presentation(&"bomb")
		_try_throw_bomb()


func _try_throw_bomb() -> void:
	var dir := _normalized_attack_facing(_facing_planar)
	_facing_planar = dir
	_spawn_player_bomb(global_position, dir, true, true)


func _try_fire_ranged_arrow() -> void:
	var dir := _normalized_attack_facing(_facing_planar)
	_facing_planar = dir
	var spawn := _compute_ranged_spawn(dir)
	_spawn_player_ranged_arrow(spawn, dir, true, true)


func take_damage(amount: int) -> void:
	if _multiplayer_active() and not _is_server_peer():
		return
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


func _update_facing_planar(direction: Vector2, allow_mouse_fallback: bool = true) -> void:
	if _is_facing_locked():
		_facing_planar = _facing_lock_planar
		return
	var f := direction
	if allow_mouse_fallback and f.length_squared() <= 1e-6 and _mouse_steering_active():
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


func _squash_mobs_in_melee_hit(hit_event_id: int = -1) -> int:
	var hit_count := 0
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is CharacterBody2D:
			continue
		var mob := node as CharacterBody2D
		if _melee_hit_overlaps_mob(mob):
			if hit_event_id >= 0 and mob.has_method(&"apply_authoritative_hit_event"):
				var applied := bool(
					mob.call(
						&"apply_authoritative_hit_event",
						hit_event_id,
						melee_attack_damage,
						_facing_planar,
						melee_knockback_strength
					)
				)
				if applied:
					hit_count += 1
			elif mob.has_method(&"take_hit"):
				mob.call(&"take_hit", melee_attack_damage, _facing_planar, melee_knockback_strength)
				hit_count += 1
	return hit_count


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
	if _multiplayer_active():
		_physics_process_multiplayer(delta)
		return
	if _is_dead:
		return
	_tick_facing_lock(delta)
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
		_play_attack_animation_presentation(&"melee")
		_start_facing_lock(_facing_planar)
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


func _exit_tree() -> void:
	_free_world_debug_meshes()
	_remote_ranged_projectiles_by_event_id.clear()
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.queue_free()


func die() -> void:
	_set_downed_state(true, true)


func reset_for_retry(world_pos: Vector2) -> void:
	_set_downed_state(false)
	_clear_pending_rmb_attack()
	weapon_mode = WeaponMode.SWORD
	weapon_mode_changed.emit(get_weapon_mode_display())
	_sync_sword_visual()
	heal_to_full()
	global_position = world_pos
	velocity = Vector2.ZERO
	height = 0.0
	_invuln_time_remaining = 0.0
	_dodge_time_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_facing_lock_time_remaining = 0.0
	_rmb_down = false
	_bomb_cooldown_remaining = 0.0
	if _body_shape != null:
		_body_shape.disabled = false
	_reset_player_visual_transparency()
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)


func revive(health_after_revive: int = -1) -> void:
	if _multiplayer_active() and not _is_server_peer():
		return
	if not _is_dead:
		return
	var resolved_health := health_after_revive
	if resolved_health <= 0:
		resolved_health = REVIVE_HEALTH
	health = clampi(resolved_health, 1, max_health)
	health_changed.emit(health, max_health)
	_set_downed_state(false)


func revive_to_full() -> void:
	revive(max_health)


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
