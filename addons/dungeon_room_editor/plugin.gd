@tool
extends EditorPlugin

const SessionScript = preload("res://addons/dungeon_room_editor/core/editor_session.gd")
const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const PlacementControllerScript = preload("res://addons/dungeon_room_editor/core/placement_controller.gd")
const SelectionControllerScript = preload("res://addons/dungeon_room_editor/core/selection_controller.gd")
const SceneSyncScript = preload("res://addons/dungeon_room_editor/core/scene_sync.gd")
const SerializerScript = preload("res://addons/dungeon_room_editor/core/serializer.gd")
const PlaytestLauncherScript = preload("res://addons/dungeon_room_editor/core/playtest_launcher.gd")
const ItemDataScript = preload("res://addons/dungeon_room_editor/resources/room_placed_item_data.gd")

const MainPanelScene = preload("res://addons/dungeon_room_editor/main_screen/room_editor_main_panel.tscn")
const PreviewDockScene = preload("res://addons/dungeon_room_editor/docks/preview_dock.tscn")
const DefaultCatalog = preload("res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres")
const ToolMode = SessionScript.ToolMode
const _NO_CELL := Vector2i(9_999_999, 9_999_999)
const _AUTO_FLOOR_EXIT_ITEM_ID := "floor_exit_marker_auto"
const _FLOOR_EXIT_PIECE_ID: StringName = &"floor_exit_marker"
const _FLOOR_EXIT_BOUNDARY_INSET_TILES := 0

var _session = SessionScript.new()
var _placement_controller = PlacementControllerScript.new()
var _selection_controller = SelectionControllerScript.new()
var _scene_sync = SceneSyncScript.new()
var _serializer = SerializerScript.new()
var _playtest_launcher = PlaytestLauncherScript.new()

var _main_panel: Control
var _palette_dock: Control
var _properties_dock: ScrollContainer
var _preview_dock: Control
var _preview_popout_window: Window
var _preview_popout_dock: Control
var _room_canvas: Control
var _last_edited_room_ref: WeakRef
var _last_edited_room: RoomBase:
	get:
		if _last_edited_room_ref == null:
			return null
		var resolved := _last_edited_room_ref.get_ref()
		return resolved as RoomBase
	set(value):
		_last_edited_room_ref = weakref(value) if value != null else null
var _drag_item_id := ""
var _last_drag_cell := _NO_CELL


func _enter_tree() -> void:
	set_process(true)


func _exit_tree() -> void:
	set_process(false)
	if _session != null and _session.room != null and is_instance_valid(_session.room):
		_restore_visual_3d_proxy_after_room_editor(_session.room)
	if is_instance_valid(_main_panel):
		_main_panel.queue_free()
	if is_instance_valid(_preview_popout_window):
		_preview_popout_window.queue_free()
	_main_panel = null
	_palette_dock = null
	_properties_dock = null
	_preview_dock = null
	_preview_popout_window = null
	_preview_popout_dock = null
	_room_canvas = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Room Editor"


func _get_plugin_icon() -> Texture2D:
	var base_control := get_editor_interface().get_base_control()
	if base_control == null:
		return null
	return base_control.get_theme_icon(&"Node2D", &"EditorIcons")


func _process(_delta: float) -> void:
	_refresh_edited_room(false)


func _handles(object: Object) -> bool:
	return object is RoomBase


func _edit(object: Object) -> void:
	if object is RoomBase:
		_refresh_edited_room(true)
		return
	_last_edited_room = null
	_session.clear()
	_sync_empty_state()
	_redirect_to_default_editor_if_needed()


func _make_visible(visible: bool) -> void:
	if visible:
		_ensure_ui()
	if _main_panel != null:
		_main_panel.visible = visible
	_prune_freed_room_references()
	_apply_visual_3d_proxy_room_editor_policy()
	if not visible:
		_reset_drag_state()
		return
	_refresh_edited_room(false)
	if _session.room == null or not is_instance_valid(_session.room):
		_sync_empty_state()
		_redirect_to_default_editor_if_needed()
		return
	_room_canvas.call(&"center_view", true)
	_room_canvas.grab_focus()


func _connect_ui() -> void:
	_main_panel.connect("mode_requested", _on_mode_requested)
	_main_panel.connect("box_paint_toggled", _on_box_paint_toggled)
	_main_panel.connect("placement_rotation_selected", _on_placement_rotation_selected)
	_main_panel.connect("visible_layer_requested", _on_visible_layer_requested)
	_main_panel.connect("center_view_requested", _on_center_view_requested)
	_main_panel.connect("popout_preview_toggled", _on_popout_preview_toggled)
	_main_panel.connect("playtest_requested", _playtest_current_room)
	_palette_dock.connect("piece_selected", _on_piece_selected)
	_properties_dock.connect("room_properties_changed", _on_room_properties_changed)
	_properties_dock.connect("selected_item_changed", _on_selected_item_changed)
	_properties_dock.connect("export_json_requested", _on_export_json_requested)
	_properties_dock.connect("import_json_requested", _on_import_json_requested)
	_room_canvas.connect("hover_grid_changed", _on_canvas_hover_grid_changed)
	_room_canvas.connect("primary_pressed", _on_canvas_primary_pressed)
	_room_canvas.connect("primary_dragged", _on_canvas_primary_dragged)
	_room_canvas.connect("primary_released", _on_canvas_primary_released)
	_room_canvas.connect("rotate_shortcut_requested", _on_canvas_rotate_shortcut_requested)
	_room_canvas.connect("delete_shortcut_requested", _on_canvas_delete_shortcut_requested)
	_session.mode_changed.connect(_on_mode_changed)
	_session.active_piece_changed.connect(_on_active_piece_changed)
	_session.placement_rotation_changed.connect(_on_placement_rotation_changed)
	_session.visible_layer_changed.connect(_on_visible_layer_changed)


func _ensure_ui() -> void:
	if _main_panel != null:
		return
	_main_panel = MainPanelScene.instantiate() as Control
	_main_panel.name = "DungeonRoomEditorMainPanel"
	_main_panel.visible = false
	var main_screen := get_editor_interface().get_editor_main_screen()
	main_screen.add_child(_main_panel)
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_dock = _main_panel.get_node("VBox/BodySplit/PalettePanel/PaletteDock") as Control
	_properties_dock = _main_panel.get_node(
		"VBox/BodySplit/WorkspaceSplit/InspectorSplit/PropertiesDock"
	) as ScrollContainer
	_preview_dock = _main_panel.get_node(
		"VBox/BodySplit/WorkspaceSplit/InspectorSplit/PreviewDock"
	) as Control
	_room_canvas = _main_panel.get_node(
		"VBox/BodySplit/WorkspaceSplit/CanvasPanel/RoomCanvas"
	) as Control
	_connect_ui()
	_palette_dock.call(&"set_catalog", DefaultCatalog)
	_room_canvas.call(&"set_session", _session)
	_sync_empty_state()


func _prune_freed_room_references() -> void:
	if _last_edited_room != null and not is_instance_valid(_last_edited_room):
		_last_edited_room = null
	if _session != null and _session.room != null and not is_instance_valid(_session.room):
		_session.clear()
		if is_instance_valid(_main_panel):
			_sync_empty_state()


func _refresh_edited_room(force_refresh: bool) -> void:
	_prune_freed_room_references()
	var root := get_editor_interface().get_edited_scene_root()
	if root is not RoomBase:
		var prev_room: Object = _last_edited_room
		if prev_room == null and _session != null:
			prev_room = _session.room
		if is_instance_valid(prev_room):
			_restore_visual_3d_proxy_after_room_editor(prev_room)
		if _last_edited_room != null or (_session != null and _session.room != null):
			_last_edited_room = null
			_session.clear()
			_sync_empty_state()
		_redirect_to_default_editor_if_needed()
		return
	var room := root as RoomBase
	if not force_refresh and room == _last_edited_room and _session.layout != null:
		return
	if _last_edited_room != null and is_instance_valid(_last_edited_room) and _last_edited_room != room:
		_restore_visual_3d_proxy_after_room_editor(_last_edited_room)
	_last_edited_room = room
	var ensured = _serializer.ensure_layout_for_room(room)
	_session.bind_room(
		room,
		ensured.get("layout", null),
		String(ensured.get("layout_path", "")),
		DefaultCatalog
	)
	_sync_ui_state("Room editor ready.")
	if _room_canvas != null:
		_room_canvas.call(&"center_view", true)


func _sync_empty_state(status_message: String = "Open a RoomBase scene to author it here.") -> void:
	if _room_canvas != null:
		_room_canvas.call(&"set_session", _session)
		_room_canvas.call(&"queue_redraw")
	if _properties_dock != null:
		_properties_dock.call(&"refresh", null)
		_properties_dock.call(&"set_status", status_message)
	if _preview_dock != null:
		_preview_dock.call(&"refresh_preview", null, null, DefaultCatalog, _session.visible_layer_filter)
	if _preview_popout_dock != null:
		_preview_popout_dock.call(
			&"refresh_preview",
			null,
			null,
			DefaultCatalog,
			_session.visible_layer_filter
		)
	if _main_panel != null:
		_main_panel.call(&"set_mode", _session.tool_mode)
		_main_panel.call(&"set_box_paint_enabled", _session.box_paint_enabled)
		_main_panel.call(&"set_placement_rotation_option_steps", _session.placement_rotation_steps)
		_main_panel.call(
			&"set_popout_preview_open",
			is_instance_valid(_preview_popout_window) and _preview_popout_window.visible
		)
		_main_panel.call(&"set_visible_layer_filter", _session.visible_layer_filter)


func _sync_ui_state(status_message: String = "") -> void:
	_prune_freed_room_references()
	if _session.room == null or not is_instance_valid(_session.room) or _session.layout == null:
		_sync_empty_state(status_message)
		return
	_scene_sync.sync_room(_session.room, _session.layout, DefaultCatalog)
	var auto_floor_exit_changed := _apply_auto_floor_exit_marker()
	if auto_floor_exit_changed:
		_scene_sync.sync_room(_session.room, _session.layout, DefaultCatalog)
	var visual_root: Node3D = _session.room.get_generated_visual_root()
	_scene_sync.apply_placement_layer_visibility(visual_root, _session.visible_layer_filter)
	if _session.layout_path != "":
		_serializer.save_layout(_session.room, _session.layout, _session.layout_path)
	if _properties_dock != null:
		_properties_dock.call(&"refresh", _session)
		if status_message != "":
			_properties_dock.call(&"set_status", status_message)
		else:
			_properties_dock.call(&"set_status", _session.hover_reason)
	if _preview_dock != null:
		_preview_dock.call(&"refresh_preview", _session.room, _session.layout, DefaultCatalog, _session.visible_layer_filter)
	if _preview_popout_dock != null:
		_preview_popout_dock.call(
			&"refresh_preview",
			_session.room,
			_session.layout,
			DefaultCatalog,
			_session.visible_layer_filter
		)
	if _room_canvas != null:
		_room_canvas.call(&"set_session", _session)
		_room_canvas.call(&"queue_redraw")
	if _main_panel != null:
		_main_panel.call(&"set_mode", _session.tool_mode)
		_main_panel.call(&"set_box_paint_enabled", _session.box_paint_enabled)
		_main_panel.call(&"set_placement_rotation_option_steps", _session.placement_rotation_steps)
		_main_panel.call(
			&"set_popout_preview_open",
			is_instance_valid(_preview_popout_window) and _preview_popout_window.visible
		)
		_main_panel.call(&"set_visible_layer_filter", _session.visible_layer_filter)
	_apply_visual_3d_proxy_room_editor_policy()


func _apply_auto_floor_exit_marker() -> bool:
	if _session == null or _session.room == null or _session.layout == null or _session.catalog == null:
		return false
	var room: RoomBase = _session.room
	var layout = _session.layout
	if room.room_type != "boss":
		return _remove_auto_floor_exit_marker(layout)
	var piece = _session.catalog.find_piece(_FLOOR_EXIT_PIECE_ID)
	if piece == null:
		return false
	var entrance_markers := room.get_connection_markers_by_kind("entrance")
	if entrance_markers.size() != 1:
		return _remove_auto_floor_exit_marker(layout)
	var anchor := _derive_floor_exit_anchor(room, entrance_markers[0], piece.footprint)
	if anchor == _NO_CELL:
		return _remove_auto_floor_exit_marker(layout)
	var existing_floor_exit_items := _find_floor_exit_items(layout)
	var managed_item = layout.find_item(_AUTO_FLOOR_EXIT_ITEM_ID)
	if managed_item == null and not existing_floor_exit_items.is_empty():
		managed_item = existing_floor_exit_items[0]
	if managed_item == null:
		managed_item = ItemDataScript.new()
		managed_item.item_id = _AUTO_FLOOR_EXIT_ITEM_ID
		layout.items.append(managed_item)
	var changed := false
	changed = _set_if_different(managed_item, &"item_id", _AUTO_FLOOR_EXIT_ITEM_ID) or changed
	changed = _set_if_different(managed_item, &"piece_id", piece.piece_id) or changed
	changed = _set_if_different(managed_item, &"category", piece.category) or changed
	changed = _set_if_different(managed_item, &"grid_position", anchor) or changed
	changed = _set_if_different(managed_item, &"rotation_steps", 0) or changed
	changed = _set_if_different(managed_item, &"tags", piece.default_tags.duplicate()) or changed
	changed = _set_if_different(managed_item, &"encounter_group_id", StringName()) or changed
	changed = _set_if_different(managed_item, &"enemy_id", StringName()) or changed
	changed = _set_if_different(
		managed_item,
		&"placement_layer",
		piece.default_placement_layer()
	) or changed
	changed = _set_if_different(managed_item, &"blocks_movement", piece.blocks_movement) or changed
	changed = _set_if_different(
		managed_item,
		&"blocks_projectiles",
		piece.blocks_projectiles
	) or changed
	for index in range(layout.items.size() - 1, -1, -1):
		var item = layout.items[index]
		if item == null or item == managed_item:
			continue
		if not _is_floor_exit_item(item):
			continue
		layout.items.remove_at(index)
		changed = true
	if changed:
		layout.emit_changed()
	return changed


func _remove_auto_floor_exit_marker(layout) -> bool:
	if layout == null:
		return false
	var changed := false
	for index in range(layout.items.size()):
		var item = layout.items[index]
		if item != null and item.item_id == _AUTO_FLOOR_EXIT_ITEM_ID:
			layout.items.remove_at(index)
			changed = true
			break
	if changed:
		layout.emit_changed()
	return changed


func _derive_floor_exit_anchor(
	room: RoomBase,
	entrance_marker: ConnectorMarker2D,
	footprint: Vector2i
) -> Vector2i:
	if room == null or entrance_marker == null:
		return _NO_CELL
	var occupancy := _build_floor_exit_occupancy()
	var floor_lookup: Dictionary = occupancy.get("floor", {})
	var blocked_lookup: Dictionary = occupancy.get("blocked", {})
	if floor_lookup.is_empty():
		return _NO_CELL
	var room_rect: Rect2i = room.get_room_rect_tiles()
	var size_tiles := Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))
	var min_x := room_rect.position.x + _FLOOR_EXIT_BOUNDARY_INSET_TILES
	var min_y := room_rect.position.y + _FLOOR_EXIT_BOUNDARY_INSET_TILES
	var max_x := room_rect.position.x + room_rect.size.x - size_tiles.x - _FLOOR_EXIT_BOUNDARY_INSET_TILES
	var max_y := room_rect.position.y + room_rect.size.y - size_tiles.y - _FLOOR_EXIT_BOUNDARY_INSET_TILES
	if max_x < min_x or max_y < min_y:
		return _NO_CELL
	var room_center_local := room.get_room_rect_world().get_center()
	var preferred := _NO_CELL
	match entrance_marker.direction:
		"west":
			preferred = Vector2i(
				max_x,
				max_y if entrance_marker.position.y <= room_center_local.y else min_y
			)
		"east":
			preferred = Vector2i(
				min_x,
				max_y if entrance_marker.position.y <= room_center_local.y else min_y
			)
		"north":
			preferred = Vector2i(
				max_x if entrance_marker.position.x <= room_center_local.x else min_x,
				max_y
			)
		"south":
			preferred = Vector2i(
				max_x if entrance_marker.position.x <= room_center_local.x else min_x,
				min_y
			)
		_:
			return _NO_CELL
	return _nearest_valid_floor_exit_anchor(preferred, size_tiles, floor_lookup, blocked_lookup)


func _find_floor_exit_items(layout) -> Array:
	var out: Array = []
	if layout == null:
		return out
	for item in layout.items:
		if _is_floor_exit_item(item):
			out.append(item)
	return out


func _is_floor_exit_item(item) -> bool:
	if item == null:
		return false
	if item.piece_id == _FLOOR_EXIT_PIECE_ID:
		return true
	return item.tags is PackedStringArray and item.tags.has("floor_exit")


func _build_floor_exit_occupancy() -> Dictionary:
	var floor_lookup: Dictionary = {}
	var blocked_lookup: Dictionary = {}
	for item in _session.layout.items:
		if item == null or _is_floor_exit_item(item):
			continue
		var piece = _session.catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		var footprint := GridMath.rotated_footprint(piece.footprint, item.rotation_steps)
		var placement_layer: StringName = item.resolved_placement_layer(piece)
		for x in range(footprint.x):
			for y in range(footprint.y):
				var cell: Vector2i = item.grid_position + Vector2i(x, y)
				if piece.category == &"floor" or item.category == &"floor" or placement_layer == &"ground":
					floor_lookup[cell] = true
				if (
					placement_layer == &"overlay"
					and (
						piece.category == &"wall"
						or item.category == &"wall"
						or piece.blocks_movement
						or item.blocks_movement
					)
				):
					blocked_lookup[cell] = true
	return {
		"floor": floor_lookup,
		"blocked": blocked_lookup,
	}


func _nearest_valid_floor_exit_anchor(
	preferred: Vector2i,
	footprint: Vector2i,
	floor_lookup: Dictionary,
	blocked_lookup: Dictionary
) -> Vector2i:
	var best := _NO_CELL
	var best_dist := INF
	for candidate_variant in floor_lookup.keys():
		var candidate := candidate_variant as Vector2i
		if not _floor_exit_footprint_fits(candidate, footprint, floor_lookup, blocked_lookup):
			continue
		var dist := preferred.distance_squared_to(candidate)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	if best != _NO_CELL:
		return best
	return _NO_CELL


func _floor_exit_footprint_fits(
	anchor: Vector2i,
	footprint: Vector2i,
	floor_lookup: Dictionary,
	blocked_lookup: Dictionary
) -> bool:
	for x in range(footprint.x):
		for y in range(footprint.y):
			var cell := anchor + Vector2i(x, y)
			if not floor_lookup.has(cell):
				return false
			if blocked_lookup.has(cell):
				return false
	return true


func _set_if_different(target: Object, property_name: StringName, next_value: Variant) -> bool:
	var current_value = target.get(property_name)
	if current_value == next_value:
		return false
	target.set(property_name, next_value)
	return true


func _restore_visual_3d_proxy_after_room_editor(room: Object) -> void:
	if room == null or not is_instance_valid(room) or not (room is RoomBase):
		return
	var rb := room as RoomBase
	var proxy := rb.get_node_or_null(^"Visual3DProxy") as Node3D
	if proxy == null:
		return
	if proxy.has_meta(&"_room_editor_suppressed_proxy_visible"):
		proxy.visible = bool(proxy.get_meta(&"_room_editor_suppressed_proxy_visible", true))
		proxy.remove_meta(&"_room_editor_suppressed_proxy_visible")


func _apply_visual_3d_proxy_room_editor_policy() -> void:
	if _session == null:
		return
	if _session.room == null or not is_instance_valid(_session.room):
		return
	var room := _session.room as RoomBase
	var proxy := room.get_node_or_null(^"Visual3DProxy") as Node3D
	if proxy == null:
		return
	var suppress := _main_panel != null and _main_panel.visible
	if suppress:
		if not proxy.has_meta(&"_room_editor_suppressed_proxy_visible"):
			proxy.set_meta(&"_room_editor_suppressed_proxy_visible", proxy.visible)
		proxy.visible = false
	else:
		if proxy.has_meta(&"_room_editor_suppressed_proxy_visible"):
			proxy.visible = bool(proxy.get_meta(&"_room_editor_suppressed_proxy_visible", true))
			proxy.remove_meta(&"_room_editor_suppressed_proxy_visible")


func _set_status(message: String) -> void:
	if _properties_dock != null:
		_properties_dock.call(&"set_status", message)


func _redirect_to_default_editor_if_needed() -> void:
	if _main_panel == null or not _main_panel.visible:
		return
	get_editor_interface().call_deferred(&"set_main_screen_editor", "2D")


func _create_preview_popout_window() -> void:
	if is_instance_valid(_preview_popout_window):
		return
	_preview_popout_window = Window.new()
	_preview_popout_window.visible = false
	_preview_popout_window.title = "Room Editor 3D Preview"
	_preview_popout_window.name = "DungeonRoomEditorPreviewWindow"
	_preview_popout_window.force_native = true
	_preview_popout_window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_PRIMARY_SCREEN
	_preview_popout_window.unresizable = false
	_preview_popout_window.borderless = false
	_preview_popout_window.transient = false
	_preview_popout_window.min_size = Vector2i(420, 320)
	_preview_popout_window.size = Vector2i(900, 620)
	_preview_popout_window.wrap_controls = true
	_preview_popout_window.close_requested.connect(_on_preview_popout_close_requested)
	get_editor_interface().get_base_control().add_child(_preview_popout_window)
	_preview_popout_dock = PreviewDockScene.instantiate() as Control
	if _preview_popout_dock != null:
		_preview_popout_window.add_child(_preview_popout_dock)
		_preview_popout_dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _reset_drag_state() -> void:
	_drag_item_id = ""
	_last_drag_cell = _NO_CELL
	_session.clear_box_paint()
	if _room_canvas != null:
		_room_canvas.call(&"queue_redraw")


func _is_grid_inside_room(grid: Vector2i) -> bool:
	return (
		_session.room != null
		and _session.layout != null
		and GridMath.grid_is_inside_room(grid, _session.layout, _session.room)
	)


func _clear_hover(message: String = "") -> void:
	_session.set_hover_state(_NO_CELL, false, message)
	_set_status(message)
	if _room_canvas != null:
		_room_canvas.call(&"queue_redraw")


func _on_mode_requested(mode: int) -> void:
	_session.set_tool_mode(mode)


func _on_box_paint_toggled(enabled: bool) -> void:
	_session.set_box_paint_enabled(enabled)
	if _session.box_drag_active:
		_session.clear_box_paint()
	if _room_canvas != null:
		_room_canvas.call(&"queue_redraw")
	var message := "Box paint enabled." if enabled else "Box paint disabled."
	if _session.room != null:
		_update_hover(_session.hover_cell)
	else:
		_set_status(message)


func _on_center_view_requested() -> void:
	if _room_canvas != null:
		_room_canvas.call(&"center_view", true)
		_room_canvas.grab_focus()


func _on_popout_preview_toggled(open_requested: bool) -> void:
	if open_requested:
		_open_preview_popout()
		return
	_close_preview_popout()


func _on_placement_rotation_selected(rotation_steps: int) -> void:
	_session.set_placement_rotation_steps(rotation_steps)
	if _session.room != null:
		_update_hover(_session.hover_cell)


func _open_preview_popout() -> void:
	if not is_instance_valid(_preview_popout_window):
		_create_preview_popout_window()
	if not is_instance_valid(_preview_popout_window):
		return
	_preview_popout_window.show()
	_preview_popout_window.grab_focus()
	if _preview_popout_dock != null:
		_preview_popout_dock.call(
			&"refresh_preview",
			_session.room,
			_session.layout,
			DefaultCatalog,
			_session.visible_layer_filter
		)
	if _main_panel != null:
		_main_panel.call(&"set_popout_preview_open", true)


func _close_preview_popout() -> void:
	if not is_instance_valid(_preview_popout_window):
		return
	_preview_popout_window.hide()
	if _main_panel != null:
		_main_panel.call(&"set_popout_preview_open", false)


func _on_preview_popout_close_requested() -> void:
	_close_preview_popout()


func _on_visible_layer_requested(layer_filter: StringName) -> void:
	_session.set_visible_layer_filter(layer_filter)


func _on_mode_changed(_mode: int) -> void:
	_reset_drag_state()
	if _main_panel != null:
		_main_panel.call(&"set_mode", _session.tool_mode)
	if _room_canvas != null:
		_room_canvas.grab_focus()
	if _session.room != null:
		_update_hover(_session.hover_cell)


func _on_active_piece_changed(piece_id: StringName) -> void:
	if _palette_dock != null and piece_id != &"":
		_palette_dock.call(&"set_active_piece", piece_id)
	if _session.room != null:
		_update_hover(_session.hover_cell)
	if _room_canvas != null:
		_room_canvas.call(&"queue_redraw")


func _on_visible_layer_changed(_layer_filter: StringName) -> void:
	var selected_item = _session.selected_item()
	var selected_piece = _session.selected_piece()
	if selected_item != null and selected_piece != null and not _session.is_item_visible(selected_item, selected_piece):
		_session.set_selected_item_id("")
	_sync_ui_state("Viewing %s layer." % _display_layer_name(_session.visible_layer_filter))


func _on_placement_rotation_changed(rotation_steps: int) -> void:
	if _main_panel != null:
		_main_panel.call(&"set_placement_rotation_option_steps", rotation_steps)
	if _session.room != null:
		_update_hover(_session.hover_cell)


func _on_canvas_hover_grid_changed(grid: Vector2i) -> void:
	if _is_box_paint_mode() and _session.box_drag_active:
		if not _is_grid_inside_room(grid):
			_set_status("Placement is outside the room bounds.")
			return
		_session.set_hover_state(grid, true, "")
		_set_status(_box_paint_status(grid))
		if _room_canvas != null:
			_room_canvas.call(&"queue_redraw")
		return
	if not _is_grid_inside_room(grid):
		_clear_hover("Placement is outside the room bounds.")
		return
	_update_hover(grid)


func _on_canvas_primary_pressed(grid: Vector2i) -> void:
	if _session.room == null or _session.layout == null:
		return
	if not _is_grid_inside_room(grid):
		_reset_drag_state()
		_clear_hover("Placement is outside the room bounds.")
		return
	_last_drag_cell = grid
	match _session.tool_mode:
		ToolMode.PLACE:
			if _is_box_paint_mode():
				_begin_box_paint(grid)
			else:
				_try_place_at(grid)
		ToolMode.ERASE:
			_try_erase_at(grid)
		ToolMode.SELECT:
			_begin_selection_drag(grid)
		ToolMode.ROTATE:
			_rotate_item_at(grid)


func _on_canvas_primary_dragged(grid: Vector2i) -> void:
	if _session.room == null or _session.layout == null or grid == _last_drag_cell:
		return
	if not _is_grid_inside_room(grid):
		if _is_box_paint_mode() and _session.box_drag_active:
			_set_status("Placement is outside the room bounds.")
		else:
			_clear_hover("Placement is outside the room bounds.")
		return
	var previous_grid := _last_drag_cell
	_last_drag_cell = grid
	match _session.tool_mode:
		ToolMode.PLACE:
			if _is_box_paint_mode():
				_update_box_paint(grid)
			else:
				_paint_path(previous_grid, grid)
		ToolMode.ERASE:
			_erase_path(previous_grid, grid)
		ToolMode.SELECT:
			if _drag_item_id != "":
				_try_move_selected_to(grid)


func _on_canvas_primary_released() -> void:
	if _is_box_paint_mode() and _session.box_drag_active:
		_commit_box_paint()
	_reset_drag_state()

func _on_canvas_rotate_shortcut_requested() -> void:
	if _session.room == null or _session.layout == null:
		return
	if _session.selected_item() != null:
		_rotate_selected_item()
		return
	if _session.tool_mode == ToolMode.PLACE:
		_session.cycle_placement_rotation()
		_update_hover(_session.hover_cell)
		_sync_ui_state("Rotated active piece preview (Place rot dropdown).")








func _on_canvas_delete_shortcut_requested() -> void:
	if _session.selected_item() != null:
		_try_erase_item(_session.selected_item().item_id)


func _on_piece_selected(piece_id: StringName) -> void:
	_session.set_active_piece_id(piece_id)
	_set_status("Selected '%s'." % [String(piece_id)])


func _on_room_properties_changed(
	room_id: String, room_tags: PackedStringArray, enemy_groups: PackedStringArray, room_size_tiles: Vector2i
) -> void:
	if _session.layout == null or _session.room == null:
		return
	_session.layout.room_id = room_id
	_session.layout.room_tags = room_tags.duplicate()
	_session.layout.recommended_enemy_groups = enemy_groups.duplicate()
	_session.room.room_id = room_id
	_session.room.room_tags = room_tags.duplicate()
	_session.room.origin_mode = _properties_dock.call(&"selected_origin_mode")
	_session.room.room_size_tiles = Vector2i(maxi(1, room_size_tiles.x), maxi(1, room_size_tiles.y))
	_session.layout.emit_changed()
	_sync_ui_state("Updated room properties.")


func _on_selected_item_changed(payload: Dictionary) -> void:
	var item = _session.layout.find_item(String(payload.get("item_id", ""))) if _session.layout != null else null
	var piece = _session.catalog.find_piece(item.piece_id) if item != null and _session.catalog != null else null
	if item == null or piece == null:
		return
	var next_grid = payload.get("grid_position", item.grid_position)
	var next_rotation = int(payload.get("rotation_steps", item.rotation_steps))
	var result := _placement_controller.can_place(
		_session.room,
		_session.layout,
		_session.catalog,
		piece,
		next_grid,
		next_rotation,
		item.item_id,
		StringName(payload.get("placement_layer", item.resolved_placement_layer(piece)))
	)
	if not bool(result.get("valid", false)):
		_sync_ui_state(String(result.get("reason", "Invalid placement.")))
		return
	var resolved_grid = result.get("resolved_grid", next_grid)
	item.grid_position = resolved_grid if resolved_grid is Vector2i else next_grid
	item.rotation_steps = int(result.get("resolved_rotation_steps", next_rotation))
	item.placement_layer = StringName(payload.get("placement_layer", item.resolved_placement_layer(piece)))
	item.tags = (payload.get("tags", item.tags) as PackedStringArray).duplicate()
	item.encounter_group_id = payload.get("encounter_group_id", item.encounter_group_id)
	item.enemy_id = StringName(String(payload.get("enemy_id", item.resolved_enemy_id(piece))))
	item.blocks_movement = bool(payload.get("blocks_movement", item.blocks_movement))
	item.blocks_projectiles = bool(payload.get("blocks_projectiles", item.blocks_projectiles))
	_session.layout.emit_changed()
	_sync_ui_state("Updated selected item.")


func _on_export_json_requested(path: String) -> void:
	if _serializer.export_layout_json(_session.layout, path):
		_sync_ui_state("Exported room layout JSON.")
	else:
		_sync_ui_state("Failed to export room layout JSON.")


func _on_import_json_requested(path: String) -> void:
	var imported = _serializer.import_layout_json(path)
	if imported == null:
		_sync_ui_state("Failed to import room layout JSON.")
		return
	_session.bind_room(_session.room, imported, _session.layout_path, DefaultCatalog)
	_session.room.authored_layout = imported
	_sync_ui_state("Imported room layout JSON.")


func _playtest_current_room() -> void:
	if _playtest_launcher.launch(get_editor_interface(), _session.room, _session.layout, _serializer):
		_sync_ui_state("Launching room playtest.")
	else:
		_sync_ui_state("Save the room scene before running playtest.")


func _update_hover(grid: Vector2i) -> void:
	if _session.room == null or _session.layout == null:
		return
	if not _is_grid_inside_room(grid):
		_clear_hover("Placement is outside the room bounds.")
		return
	var reason := ""
	var valid := true
	var preview_anchor := _NO_CELL
	var preview_rotation_steps := -1
	var piece = _session.active_piece()
	if piece != null and _session.tool_mode == ToolMode.PLACE:
		var result = _placement_controller.can_place(
			_session.room,
			_session.layout,
			_session.catalog,
			piece,
			grid,
			_session.placement_rotation_steps
		)
		valid = bool(result.get("valid", false))
		reason = String(result.get("reason", ""))
		if valid:
			var rg = result.get("resolved_grid", null)
			if rg is Vector2i:
				preview_anchor = rg
			preview_rotation_steps = int(
				result.get("resolved_rotation_steps", _session.placement_rotation_steps)
			)
	elif _drag_item_id != "" and _session.tool_mode == ToolMode.SELECT:
		var item = _session.selected_item()
		var selected_piece = _session.selected_piece()
		if item != null and selected_piece != null:
			var result = _placement_controller.can_place(
				_session.room,
				_session.layout,
				_session.catalog,
				selected_piece,
				grid,
				item.rotation_steps,
				item.item_id
			)
			valid = bool(result.get("valid", false))
			reason = String(result.get("reason", ""))
			if valid:
				var rg2 = result.get("resolved_grid", null)
				if rg2 is Vector2i:
					preview_anchor = rg2
				preview_rotation_steps = int(result.get("resolved_rotation_steps", item.rotation_steps))
	_session.set_hover_state(grid, valid, reason, preview_anchor, preview_rotation_steps)
	_set_status(reason)
	if _room_canvas != null:
		_room_canvas.call(&"queue_redraw")


func _try_place_at(grid: Vector2i) -> bool:
	if not _is_grid_inside_room(grid):
		_clear_hover("Placement is outside the room bounds.")
		return true
	var result := _place_item_at(grid, true)
	var reason := String(result.get("reason", ""))
	if reason != "":
		_set_status(reason)
	return bool(result.get("handled", false))


func _place_item_at(grid: Vector2i, sync_after: bool) -> Dictionary:
	var piece = _session.active_piece()
	if piece == null:
		return {"handled": false, "changed": false}
	var pre_place := _placement_controller.can_place(
		_session.room,
		_session.layout,
		_session.catalog,
		piece,
		grid,
		_session.placement_rotation_steps
	)
	if not bool(pre_place.get("valid", false)):
		return {
			"handled": true,
			"changed": false,
			"reason": String(pre_place.get("reason", "Invalid placement.")),
		}
	var resolved_grid = pre_place.get("resolved_grid", grid)
	if not resolved_grid is Vector2i:
		resolved_grid = grid
	var resolved_rotation_steps := int(
		pre_place.get("resolved_rotation_steps", _session.placement_rotation_steps)
	)
	for existing in _session.layout.items:
		if existing == null:
			continue
		if (
			existing.piece_id == piece.piece_id
			and existing.grid_position == resolved_grid
			and existing.rotation_steps == resolved_rotation_steps
			and existing.resolved_placement_layer(piece) == piece.default_placement_layer()
		):
			return {"handled": true, "changed": false}
	var result = _placement_controller.place_item(_session, piece, grid)
	if not bool(result.get("valid", false)):
		return {
			"handled": true,
			"changed": false,
			"reason": String(result.get("reason", "Invalid placement.")),
		}
	var item = result.get("item", null)
	if item != null:
		_session.set_selected_item_id(item.item_id)
	if sync_after:
		_sync_ui_state("Placed '%s'." % [
			piece.display_name if piece.display_name != "" else String(piece.piece_id)
		])
	return {"handled": true, "changed": item != null, "item": item}


func _begin_selection_drag(grid: Vector2i) -> bool:
	var item = _selection_controller.item_at_grid(
		_session.layout,
		_session.catalog,
		_session.room,
		grid,
		_session.visible_layer_filter
	)
	_session.set_selected_item_id(item.item_id if item != null else "")
	_drag_item_id = item.item_id if item != null else ""
	_sync_ui_state("Selected item." if item != null else "Selection cleared.")
	return true


func _try_move_selected_to(grid: Vector2i) -> bool:
	var item = _session.selected_item()
	var piece = _session.selected_piece()
	if item == null or piece == null or item.grid_position == grid:
		return false
	var result = _placement_controller.can_place(
		_session.room,
		_session.layout,
		_session.catalog,
		piece,
		grid,
		item.rotation_steps,
		item.item_id,
		item.resolved_placement_layer(piece)
	)
	if not bool(result.get("valid", false)):
		_set_status(String(result.get("reason", "Invalid move.")))
		return true
	var resolved_move = result.get("resolved_grid", grid)
	item.grid_position = resolved_move if resolved_move is Vector2i else grid
	item.rotation_steps = int(result.get("resolved_rotation_steps", item.rotation_steps))
	_session.layout.emit_changed()
	_sync_ui_state("Moved selected item.")
	return true


func _rotate_selected_item() -> bool:
	var item = _session.selected_item()
	return _rotate_item(item) if item != null else false


func _rotate_item_at(grid: Vector2i) -> bool:
	var item = _selection_controller.item_at_grid(
		_session.layout,
		_session.catalog,
		_session.room,
		grid,
		_session.visible_layer_filter
	)
	return _rotate_item(item) if item != null else false


func _rotate_item(item) -> bool:
	var piece = _session.catalog.find_piece(item.piece_id) if _session.catalog != null else null
	if item == null or piece == null or not piece.supports_rotation:
		return false
	var next_rotation = item.normalized_rotation_steps() + 1
	var result = _placement_controller.can_place(
		_session.room,
		_session.layout,
		_session.catalog,
		piece,
		item.grid_position,
		next_rotation,
		item.item_id,
		item.resolved_placement_layer(piece)
	)
	if not bool(result.get("valid", false)):
		_sync_ui_state(String(result.get("reason", "Invalid rotation.")))
		return true
	item.rotation_steps = next_rotation
	_session.layout.emit_changed()
	_session.set_selected_item_id(item.item_id)
	_sync_ui_state("Rotated selected item.")
	return true


func _try_erase_at(grid: Vector2i) -> bool:
	if not _is_grid_inside_room(grid):
		_clear_hover("Placement is outside the room bounds.")
		return true
	var result := _erase_item_at(grid, true)
	return bool(result.get("handled", false))


func _erase_item_at(grid: Vector2i, sync_after: bool) -> Dictionary:
	var item = _selection_controller.item_at_grid(
		_session.layout,
		_session.catalog,
		_session.room,
		grid,
		_session.visible_layer_filter
	)
	if item == null:
		return {"handled": false, "changed": false}
	if not _placement_controller.remove_item(_session, item.item_id):
		return {"handled": false, "changed": false}
	if _session.selected_item_id == item.item_id:
		_session.set_selected_item_id("")
	if sync_after:
		_sync_ui_state("Erased item.")
	return {"handled": true, "changed": true, "item_id": item.item_id}


func _try_erase_item(item_id: String) -> bool:
	if not _placement_controller.remove_item(_session, item_id):
		return false
	if _session.selected_item_id == item_id:
		_session.set_selected_item_id("")
	_sync_ui_state("Erased item.")
	return true


func _paint_path(from_grid: Vector2i, to_grid: Vector2i) -> bool:
	var changed_count := 0
	var last_reason := ""
	for grid in _grid_line_cells(from_grid, to_grid):
		var result := _place_item_at(grid, false)
		if bool(result.get("changed", false)):
			changed_count += 1
		var reason := String(result.get("reason", ""))
		if reason != "":
			last_reason = reason
	if changed_count > 0:
		_sync_ui_state("Painted %d cells." % changed_count)
		return true
	if last_reason != "":
		_set_status(last_reason)
		return true
	return false


func _paint_rectangle(from_grid: Vector2i, to_grid: Vector2i) -> bool:
	var changed_count := 0
	var last_reason := ""
	for grid in _grid_rect_cells(from_grid, to_grid):
		var result := _place_item_at(grid, false)
		if bool(result.get("changed", false)):
			changed_count += 1
		var reason := String(result.get("reason", ""))
		if reason != "":
			last_reason = reason
	if changed_count > 0:
		_sync_ui_state("Painted %d cells." % changed_count)
		return true
	if last_reason != "":
		_set_status(last_reason)
		return true
	return false


func _erase_path(from_grid: Vector2i, to_grid: Vector2i) -> bool:
	var changed_count := 0
	for grid in _grid_line_cells(from_grid, to_grid):
		var result := _erase_item_at(grid, false)
		if bool(result.get("changed", false)):
			changed_count += 1
	if changed_count > 0:
		_sync_ui_state("Erased %d cells." % changed_count)
		return true
	return false


func _grid_line_cells(from_grid: Vector2i, to_grid: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x0 := from_grid.x
	var y0 := from_grid.y
	var x1 := to_grid.x
	var y1 := to_grid.y
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var err2 := err * 2
		if err2 > -dy:
			err -= dy
			x0 += sx
		if err2 < dx:
			err += dx
			y0 += sy
	return cells


func _grid_rect_cells(from_grid: Vector2i, to_grid: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var min_x := mini(from_grid.x, to_grid.x)
	var max_x := maxi(from_grid.x, to_grid.x)
	var min_y := mini(from_grid.y, to_grid.y)
	var max_y := maxi(from_grid.y, to_grid.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			cells.append(Vector2i(x, y))
	return cells


func _is_box_paint_mode() -> bool:
	return _session.tool_mode == ToolMode.PLACE and _session.box_paint_enabled


func _begin_box_paint(grid: Vector2i) -> void:
	_session.begin_box_paint(grid)
	_session.set_hover_state(grid, true, "")
	_set_status(_box_paint_status(grid))
	if _room_canvas != null:
		_room_canvas.call(&"queue_redraw")


func _update_box_paint(grid: Vector2i) -> void:
	_session.update_box_paint(grid)
	_session.set_hover_state(grid, true, "")
	_set_status(_box_paint_status(grid))
	if _room_canvas != null:
		_room_canvas.call(&"queue_redraw")


func _commit_box_paint() -> void:
	if not GridMath.is_defined_grid(_session.box_drag_start) or not GridMath.is_defined_grid(_session.box_drag_end):
		return
	_paint_rectangle(_session.box_drag_start, _session.box_drag_end)


func _box_paint_status(current_grid: Vector2i) -> String:
	var start: Vector2i = _session.box_drag_start if GridMath.is_defined_grid(_session.box_drag_start) else current_grid
	var width := absi(current_grid.x - start.x) + 1
	var height := absi(current_grid.y - start.y) + 1
	return "Box paint: %d x %d (%d cells)" % [width, height, width * height]


func _display_layer_name(layer_filter: StringName) -> String:
	match String(layer_filter):
		"ground":
			return "ground"
		"overlay":
			return "overlay"
		_:
			return "all"
