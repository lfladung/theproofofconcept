extends "res://scripts/entities/player/player_internals.gd"

var _cached_ui_hovered_physics_frame := -1
var _cached_ui_blocks_attack := false

## Presentation tick, debug overlays, and lifecycle helpers.

func _rebuild_melee_debug_mesh() -> void:
	if _melee_debug_mi == null:
		return
	_melee_debug_mi.visible = true
	var f2 := _resolve_melee_hit_facing()
	var p0 := global_position
	var f3 := Vector3(f2.x, 0.0, f2.y)
	var r3 := Vector3(-f3.z, 0.0, f3.x)
	var origin3 := Vector3(p0.x, melee_debug_ground_y, p0.y)
	var sz2 := _melee_hit_effective_width_depth()
	var half_w := sz2.x * 0.5
	var inner := _melee_range_start()
	var near_o := f3 * inner
	var far_o := f3 * (inner + sz2.y)
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


func _append_sector_fan_xz(
	imm: ImmediateMesh,
	mat: Material,
	center2: Vector2,
	facing2: Vector2,
	radius: float,
	ground_y: float,
	total_angle_radians: float,
	segments: int
) -> void:
	if radius <= 0.0 or segments < 1 or total_angle_radians <= 0.0:
		return
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var up := Vector3.UP
	var c := Vector3(center2.x, ground_y, center2.y)
	var center_angle := atan2(facing2.y, facing2.x)
	var half_angle := total_angle_radians * 0.5
	for i in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var a0 := center_angle - half_angle + total_angle_radians * t0
		var a1 := center_angle - half_angle + total_angle_radians * t1
		var e0 := Vector3(center2.x + cos(a0) * radius, ground_y, center2.y + sin(a0) * radius)
		var e1 := Vector3(center2.x + cos(a1) * radius, ground_y, center2.y + sin(a1) * radius)
		for v in [c, e0, e1]:
			imm.surface_set_normal(up)
			imm.surface_add_vertex(v)
	imm.surface_end()


func _rebuild_shield_block_debug_mesh() -> void:
	if _shield_block_debug_mi == null or _shield_block_debug_mat == null:
		return
	if not _is_defending or not _can_defend_in_current_mode() or stamina <= 0.0:
		_shield_block_debug_mi.visible = false
		return
	var total_angle_radians := deg_to_rad(clampf(block_arc_degrees, 0.0, 360.0))
	if total_angle_radians <= 0.0:
		_shield_block_debug_mi.visible = false
		return
	var facing2 := _facing_planar
	if facing2.length_squared() <= 1e-6:
		facing2 = Vector2(0.0, -1.0)
	else:
		facing2 = facing2.normalized()
	var radius := _get_player_body_radius() + 2.25
	var segments := maxi(6, int(ceil(clampf(block_arc_degrees, 0.0, 360.0) / 12.0)))
	var imm := ImmediateMesh.new()
	_append_sector_fan_xz(
		imm,
		_shield_block_debug_mat,
		global_position,
		facing2,
		radius,
		hitbox_debug_ground_y + 0.006,
		total_angle_radians,
		segments
	)
	_shield_block_debug_mi.visible = true
	_shield_block_debug_mi.material_override = _shield_block_debug_mat
	_shield_block_debug_mi.mesh = imm


func _rebuild_player_hitbox_debug() -> void:
	if _player_hitbox_mi == null:
		return
	if not show_player_hitbox_debug:
		_player_hitbox_mi.visible = false
		return
	_player_hitbox_mi.visible = true
	var radius := 0.7605869
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
	_flow_decay_step(delta)
	var cd_sp := InfusionFlowRef.cooldown_tick_multiplier(
		_flow_aggression_remaining, _flow_overdrive_remaining, _infusion_flow_threshold()
	)
	_melee_attack_cooldown_remaining = maxf(0.0, _melee_attack_cooldown_remaining - delta * cd_sp)
	_ranged_cooldown_remaining = maxf(0.0, _ranged_cooldown_remaining - delta * cd_sp)
	_bomb_cooldown_remaining = maxf(0.0, _bomb_cooldown_remaining - delta * cd_sp)
	if is_damage_authority():
		_surge_authoritative_tick(delta)
		_phase_dash_trail_cooldown_remaining = maxf(0.0, _phase_dash_trail_cooldown_remaining - delta)
		_phase_contact_chip_cooldown_remaining = maxf(0.0, _phase_contact_chip_cooldown_remaining - delta)
		_phase_slip_body_physics_tick(delta)

	var use_wasd_sp := _is_wasd_mouse_scheme_enabled()
	if _menu_input_blocked:
		_clear_pending_rmb_attack()
		_rmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		_lmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	elif Input.is_action_just_pressed(&"weapon_switch"):
		_clear_pending_rmb_attack()
		_cycle_weapon()
	if not _menu_input_blocked and Input.is_action_just_pressed(&"bomb_throw"):
		_clear_pending_rmb_attack()
		_face_toward_mouse_planar()
		if _try_throw_bomb():
			_play_attack_animation_presentation(&"bomb")

	var defend_down := (
		not _menu_input_blocked
		and Input.is_action_pressed(&"defend")
		and _can_defend_in_current_mode()
	)
	_set_defending_state(defend_down)
	_tick_stamina_regen(delta)

	var ui_blocks_attack := _ui_blocks_attack_this_physics_frame()
	_process_local_melee_charge_input(
		delta, use_wasd_sp, ui_blocks_attack, defend_down, not _menu_input_blocked
	)

	var direction := Vector2.ZERO
	var aim_planar_sp := Vector2.ZERO
	var move_active := false
	if not _menu_input_blocked:
		var intent := _local_move_steering_intent()
		move_active = bool(intent.get("move_active", false))
		if move_active:
			var tw: Variant = intent.get("target_world", global_position)
			var target_world: Vector2 = tw as Vector2 if tw is Vector2 else global_position
			var to_target := target_world - global_position
			if to_target.length_squared() > 0.01:
				direction = to_target.normalized()
		var av: Variant = intent.get("aim_planar", Vector2.ZERO)
		aim_planar_sp = av as Vector2 if av is Vector2 else Vector2.ZERO
	var rooted_by_enemy := _external_movement_rooted
	var dash_blocked := _external_dash_blocked
	var dodge_pressed := not _menu_input_blocked and Input.is_action_just_pressed(&"dodge")
	if rooted_by_enemy:
		move_active = false
		direction = Vector2.ZERO
		if dodge_pressed:
			if is_damage_authority():
				_enemy_control_consume_root_pull_attempt()
			dodge_pressed = false
	if dash_blocked and dodge_pressed:
		enemy_control_register_latch_break_input()
		dodge_pressed = false

	_update_facing_planar(
		direction, true, _resolve_facing_aim_for_move_step(aim_planar_sp, direction, defend_down)
	)
	if not _menu_input_blocked:
		_execute_pending_rmb_attack_if_any()
	else:
		velocity = Vector2.ZERO

	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	if rooted_by_enemy:
		_dodge_time_remaining = 0.0
	if _dodge_time_remaining > 0.0:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
	elif dodge_pressed and _dodge_cooldown_remaining <= 0.0 and not _is_defending:
		_dodge_direction = _facing_planar.normalized()
		if _dodge_direction.length_squared() <= 1e-6:
			_dodge_direction = Vector2(0.0, -1.0)
		_dodge_time_remaining = dodge_duration
		_dodge_cooldown_remaining = dodge_cooldown
		if is_damage_authority():
			_phase_try_dash_trail_burst(global_position, _dodge_direction)

	var planar_speed := 0.0
	if _dodge_time_remaining > 0.0:
		velocity = _dodge_direction * dodge_speed
		planar_speed = dodge_speed
	elif direction != Vector2.ZERO:
		var resolved_speed := speed
		resolved_speed *= InfusionFlowRef.overdrive_move_speed_multiplier(
			_flow_overdrive_remaining, _infusion_flow_threshold()
		)
		if _surge_overdrive_active and InfusionSurgeRef.is_surge_attuned(_infusion_surge_threshold()):
			resolved_speed *= InfusionSurgeRef.overdrive_player_move_speed_mult()
		if _is_defending:
			resolved_speed *= clampf(defend_move_speed_multiplier, 0.0, 1.0)
		resolved_speed *= _external_move_speed_factor()
		velocity = direction * resolved_speed
		planar_speed = resolved_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	if _visual:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)
		var visual_facing := _resolve_visual_facing_planar()
		_visual.rotation.y = atan2(visual_facing.x, visual_facing.y)
		if _visual.has_method(&"set_locomotion_from_planar_speed"):
			_visual.set_locomotion_from_planar_speed(planar_speed, speed)

	_attack_hitbox_visual_time_remaining = maxf(0.0, _attack_hitbox_visual_time_remaining - delta)
	_refresh_debug_visuals(delta)

	if _health_component != null:
		_invuln_time_remaining = _health_component.get_invulnerability_remaining()
	if _invuln_time_remaining > 0.0:
		_update_invulnerability_flash_visual()


func _ui_blocks_attack_this_physics_frame() -> bool:
	var physics_frame := Engine.get_physics_frames()
	if _cached_ui_hovered_physics_frame == physics_frame:
		return _cached_ui_blocks_attack
	var viewport := get_viewport()
	_cached_ui_blocks_attack = viewport != null and viewport.gui_get_hovered_control() != null
	_cached_ui_hovered_physics_frame = physics_frame
	return _cached_ui_blocks_attack


func _exit_tree() -> void:
	_free_world_debug_meshes()
	_remote_ranged_projectiles_by_event_id.clear()
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.queue_free()

	_set_downed_state(true, true)


func reset_for_retry(world_pos: Vector2) -> void:
	_set_downed_state(false)
	_set_defending_state(false)
	clear_all_external_move_speed_multipliers()
	_clear_pending_rmb_attack()
	weapon_mode = WeaponMode.SWORD
	_coerce_weapon_mode_to_available(true)
	heal_to_full()
	global_position = world_pos
	velocity = Vector2.ZERO
	height = 0.0
	_invuln_time_remaining = 0.0
	_stamina_regen_cooldown_remaining = 0.0
	_dodge_time_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_facing_lock_time_remaining = 0.0
	_rmb_down = false
	_lmb_down = false
	_bomb_cooldown_remaining = 0.0
	if _body_shape != null:
		_body_shape.disabled = false
	if _player_hurtbox != null:
		_player_hurtbox.set_active(is_damage_authority())
	_reset_player_visual_transparency()
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)


func revive(health_after_revive: int = -1) -> void:
	if _multiplayer_active() and not _is_server_peer():
		return
	if not _is_dead:
		return
	clear_all_external_move_speed_multipliers()
	var resolved_health := health_after_revive
	if resolved_health <= 0:
		resolved_health = REVIVE_HEALTH
	health = clampi(resolved_health, 1, max_health)
	_sync_health_component_state()
	_restore_stamina_to_full()
	_set_downed_state(false)
	_set_defending_state(false)


func revive_to_full() -> void:
	revive(max_health)


func heal_to_full() -> void:
	health = max_health
	_sync_health_component_state()
	_restore_stamina_to_full()


func _free_world_debug_meshes() -> void:
	for mi in [_melee_debug_mi, _player_hitbox_mi, _mob_hitboxes_mi, _shield_block_debug_mi]:
		if mi != null and is_instance_valid(mi):
			mi.queue_free()
	_melee_debug_mi = null
	_player_hitbox_mi = null
	_mob_hitboxes_mi = null
	_shield_block_debug_mi = null
	_cached_visual_mesh_instances.clear()
	_debug_visual_refresh_time_remaining = 0.0
	_last_invulnerability_flash_state = -1


func get_shadow_visual_root() -> Node3D:
	return _visual
