extends "res://dungeon/game/dungeon_orchestrator_internals.gd"

## Camera tick, debug overlays, FPS label, combat debug HUD, physics clamps.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"infusion_guide_toggle"):
		_ensure_infusion_guide_overlay()
		if _infusion_guide_overlay == null:
			return
		if _infusion_guide_overlay.has_method(&"request_toggle_from_world"):
			_infusion_guide_overlay.call(&"request_toggle_from_world")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			if _should_defer_escape_menu_to_existing_overlay():
				return
			_ensure_escape_menu()
			if _escape_menu != null and _escape_menu.has_method(&"handle_escape") and bool(_escape_menu.call(&"handle_escape")):
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _camera_follow != null:
		_camera_follow.tick(delta)
	_tick_authored_room_visual_streaming(delta)
	_tick_info_label_refresh(delta)
	_refresh_combat_debug_overlay(delta)
	_refresh_fps_counter(delta)
	if _is_authoritative_world():
		if _encounter_spawn_controller != null:
			_encounter_spawn_controller.flush_spawn_queue(delta)
		_tick_authoritative_maintenance(delta)
	_update_backdrop_parallax()
	_update_backdrop_quad_transform()


func _ensure_combat_debug_overlay() -> void:
	var ui_root := get_node_or_null("CanvasLayer/UI") as Control
	if ui_root == null:
		return
	var existing := ui_root.get_node_or_null("CombatDebugLabel") as Label
	if existing != null:
		_combat_debug_label = existing
	else:
		var lbl := Label.new()
		lbl.name = "CombatDebugLabel"
		lbl.layout_mode = 1
		lbl.offset_left = 10.0
		lbl.offset_top = 82.0
		lbl.offset_right = 860.0
		lbl.offset_bottom = 246.0
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = "CombatDebug: pending"
		ui_root.add_child(lbl)
		_combat_debug_label = lbl
	_combat_debug_label.offset_bottom = maxf(_combat_debug_label.offset_bottom, 246.0)
	_combat_debug_label.visible = show_combat_debug_overlay
	_refresh_combat_debug_overlay(0.0, true)


func _ensure_fps_counter() -> void:
	var ui_root := get_node_or_null("CanvasLayer/UI") as Control
	if ui_root == null:
		return
	var existing := ui_root.get_node_or_null("FpsCounterLabel") as Label
	if existing != null:
		_fps_counter_label = existing
	else:
		var lbl := Label.new()
		lbl.name = "FpsCounterLabel"
		lbl.layout_mode = 1
		lbl.anchors_preset = 1
		lbl.anchor_left = 1.0
		lbl.anchor_right = 1.0
		lbl.offset_left = -188.0
		lbl.offset_top = 244.0
		lbl.offset_right = -14.0
		lbl.offset_bottom = 270.0
		lbl.grow_horizontal = 0
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
		lbl.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.85))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.text = "FPS: --"
		ui_root.add_child(lbl)
		_fps_counter_label = lbl
	_fps_counter_label.visible = show_fps_counter
	_refresh_fps_counter(0.0)


func _refresh_fps_counter(delta: float) -> void:
	if _fps_counter_label == null:
		return
	_fps_counter_label.visible = show_fps_counter
	if not show_fps_counter:
		return
	_fps_counter_refresh_time_remaining = maxf(0.0, _fps_counter_refresh_time_remaining - delta)
	if _fps_counter_refresh_time_remaining > 0.0:
		return
	_fps_counter_refresh_time_remaining = maxf(0.05, fps_counter_update_interval)
	var fps := Engine.get_frames_per_second()
	var ms := 1000.0 / float(fps) if fps > 0 else 0.0
	var text := "FPS: %d  |  %.1f ms" % [fps, ms]
	if "--autostart-singleplayer" in OS.get_cmdline_user_args():
		var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var rooms_loaded := _authored_room_visual_nodes.size()
		var room_names := ",".join(_authored_room_visual_nodes.keys())
		print("FPS_LOG t=%.1f fps=%d ms=%.1f dc=%d obj=%d prim=%d rooms=%d [%s]" % [
			Time.get_ticks_msec() / 1000.0, fps, ms, draw_calls, objects, primitives, rooms_loaded, room_names
		])
	if text == _fps_counter_last_text:
		return
	_fps_counter_last_text = text
	_fps_counter_label.text = text


func _set_combat_debug_overlay_text(text: String) -> void:
	if _combat_debug_label == null:
		return
	if _combat_debug_last_text == text:
		return
	_combat_debug_last_text = text
	_combat_debug_label.text = text


func _refresh_combat_debug_overlay(delta: float = 0.0, force: bool = false) -> void:
	if _combat_debug_label == null:
		return
	_combat_debug_label.visible = show_combat_debug_overlay
	if not show_combat_debug_overlay:
		_combat_debug_refresh_time_remaining = 0.0
		return
	_combat_debug_refresh_time_remaining = maxf(0.0, _combat_debug_refresh_time_remaining - delta)
	if not force and _combat_debug_refresh_time_remaining > 0.0:
		return
	_combat_debug_refresh_time_remaining = maxf(0.05, combat_debug_update_interval)
	var ordered_peer_ids: Array[int] = _overlay_sorted_player_peer_ids()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("CombatDebug players=%s" % [ordered_peer_ids.size()])
	if ordered_peer_ids.is_empty():
		lines.append("player roster empty")
	else:
		for idx in range(ordered_peer_ids.size()):
			var peer_id := ordered_peer_ids[idx]
			var player_label := "P%s" % [idx + 1]
			var player_v: Variant = _players_by_peer.get(peer_id, null)
			if player_v is not CharacterBody2D:
				lines.append("%s missing player node" % [player_label])
				continue
			var player_node: CharacterBody2D = player_v as CharacterBody2D
			if player_node == null or not is_instance_valid(player_node):
				lines.append("%s invalid player node" % [player_label])
				continue
			if not player_node.has_method(&"get_combat_debug_snapshot"):
				lines.append("%s debug snapshot missing" % [player_label])
				continue
			var snapshot_v: Variant = player_node.call(&"get_combat_debug_snapshot")
			if snapshot_v is not Dictionary:
				lines.append("%s debug snapshot invalid" % [player_label])
				continue
			var snapshot: Dictionary = snapshot_v as Dictionary
			var local_weapon := String(snapshot.get("weapon_mode", "?"))
			var weapon := String(snapshot.get("authoritative_weapon_mode", local_weapon))
			var local_melee_cd := float(snapshot.get("melee_cooldown", 0.0))
			var local_ranged_cd := float(snapshot.get("ranged_cooldown", 0.0))
			var local_bomb_cd := float(snapshot.get("bomb_cooldown", 0.0))
			var melee_cd := float(snapshot.get("authoritative_melee_cooldown", local_melee_cd))
			var ranged_cd := float(snapshot.get("authoritative_ranged_cooldown", local_ranged_cd))
			var bomb_cd := float(snapshot.get("authoritative_bomb_cooldown", local_bomb_cd))
			var local_stamina := float(snapshot.get("stamina", 0.0))
			var stamina := float(snapshot.get("authoritative_stamina", local_stamina))
			var local_guard_broken := bool(snapshot.get("stamina_broken", false))
			var guard_broken := bool(snapshot.get("authoritative_stamina_broken", local_guard_broken))
			var local_defending := bool(snapshot.get("is_defending", false))
			var defending := bool(snapshot.get("authoritative_is_defending", local_defending))
			var is_downed := bool(snapshot.get("is_downed", false))
			var row := "%s %s ST=%.1f guard=%s defend=%s down=%s CD[m/r/b]=%.2f/%.2f/%.2f" % [
				player_label,
				weapon,
				stamina,
				"broken" if guard_broken else "ready",
				defending,
				is_downed,
				melee_cd,
				ranged_cd,
				bomb_cd,
			]
			lines.append(row)
	_set_combat_debug_overlay_text("\n".join(lines))


func _physics_process(_delta: float) -> void:
	if _player != null and is_instance_valid(_player):
		var inside_now := _is_point_inside_any_room(_player.global_position, 1.25)
		var room_now := _room_name_at(_player.global_position, 1.25)
		if not inside_now and _prev_player_inside:
			# Prevent one-frame dash tunneling through thin boundary colliders.
			_player.global_position = _prev_player_pos
			_player.velocity = Vector2.ZERO
			if _player.has_method("set"):
				_player.set("_dodge_time_remaining", 0.0)
			inside_now = true
			room_now = _room_name_at(_player.global_position, 1.25)
		_prev_player_pos = _player.global_position
		_prev_player_inside = inside_now
		_prev_room_name = room_now
	_apply_hard_door_clamps()
	if _is_authoritative_world():
		_flush_enemy_transform_batch()

