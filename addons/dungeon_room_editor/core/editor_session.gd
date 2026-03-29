@tool
extends RefCounted
class_name DungeonRoomEditorSession

const NO_CELL := Vector2i(9_999_999, 9_999_999)

signal room_changed(room)
signal layout_changed()
signal selection_changed(item_id: String)
signal active_piece_changed(piece_id: StringName)
signal mode_changed(mode: int)
signal hover_changed(cell: Vector2i, is_valid: bool, reason: String)
signal placement_rotation_changed(rotation_steps: int)
signal visible_layer_changed(layer_filter: StringName)

enum ToolMode { PLACE, SELECT, ERASE, ROTATE }

var room: RoomBase
var layout
var layout_path := ""
var catalog
var selected_item_id := ""
var active_piece_id: StringName = &""
var tool_mode := ToolMode.PLACE
var hover_cell := Vector2i.ZERO
var hover_valid := false
var hover_reason := ""
var placement_rotation_steps := 0
var visible_layer_filter: StringName = &"all"
var box_paint_enabled := false
var box_drag_active := false
var box_drag_start := NO_CELL
var box_drag_end := NO_CELL


func bind_room(next_room: RoomBase, next_layout, next_layout_path: String, next_catalog) -> void:
	room = next_room
	layout = next_layout
	layout_path = next_layout_path
	catalog = next_catalog
	selected_item_id = ""
	if active_piece_id == &"" and catalog != null and not catalog.pieces.is_empty():
		active_piece_id = catalog.pieces[0].piece_id
	clear_box_paint()
	room_changed.emit(room)
	layout_changed.emit()
	selection_changed.emit(selected_item_id)
	active_piece_changed.emit(active_piece_id)
	mode_changed.emit(tool_mode)
	placement_rotation_changed.emit(placement_rotation_steps)
	visible_layer_changed.emit(visible_layer_filter)


func clear() -> void:
	room = null
	layout = null
	layout_path = ""
	selected_item_id = ""
	hover_cell = Vector2i.ZERO
	hover_valid = false
	hover_reason = ""
	clear_box_paint()
	room_changed.emit(null)
	layout_changed.emit()
	selection_changed.emit("")


func active_piece():
	return catalog.find_piece(active_piece_id) if catalog != null else null


func selected_item():
	return layout.find_item(selected_item_id) if layout != null and selected_item_id != "" else null


func selected_piece():
	var item = selected_item()
	if item == null or catalog == null:
		return null
	return catalog.find_piece(item.piece_id)


func set_selected_item_id(item_id: String) -> void:
	if selected_item_id == item_id:
		return
	selected_item_id = item_id
	selection_changed.emit(selected_item_id)


func set_active_piece_id(piece_id: StringName) -> void:
	if active_piece_id == piece_id:
		return
	active_piece_id = piece_id
	active_piece_changed.emit(active_piece_id)


func set_tool_mode(next_mode: int) -> void:
	next_mode = clampi(next_mode, ToolMode.PLACE, ToolMode.ROTATE)
	if tool_mode == next_mode:
		return
	tool_mode = next_mode
	mode_changed.emit(tool_mode)


func set_hover_state(cell: Vector2i, is_valid: bool, reason: String = "") -> void:
	if hover_cell == cell and hover_valid == is_valid and hover_reason == reason:
		return
	hover_cell = cell
	hover_valid = is_valid
	hover_reason = reason
	hover_changed.emit(hover_cell, hover_valid, hover_reason)


func set_placement_rotation_steps(steps: int) -> void:
	steps = posmod(steps, 4)
	if placement_rotation_steps == steps:
		return
	placement_rotation_steps = steps
	placement_rotation_changed.emit(placement_rotation_steps)


func cycle_placement_rotation() -> void:
	set_placement_rotation_steps(placement_rotation_steps + 1)


func set_box_paint_enabled(enabled: bool) -> void:
	box_paint_enabled = enabled


func set_visible_layer_filter(layer_filter: StringName) -> void:
	if layer_filter == &"":
		layer_filter = &"all"
	if visible_layer_filter == layer_filter:
		return
	visible_layer_filter = layer_filter
	visible_layer_changed.emit(visible_layer_filter)


func is_item_visible(item, piece = null) -> bool:
	if item == null:
		return false
	var resolved_layer: StringName = item.resolved_placement_layer(piece)
	return visible_layer_filter == &"all" or resolved_layer == visible_layer_filter


func begin_box_paint(cell: Vector2i) -> void:
	box_drag_active = true
	box_drag_start = cell
	box_drag_end = cell


func update_box_paint(cell: Vector2i) -> void:
	if not box_drag_active:
		return
	box_drag_end = cell


func clear_box_paint() -> void:
	box_drag_active = false
	box_drag_start = NO_CELL
	box_drag_end = NO_CELL


func next_item_id(piece) -> String:
	var prefix := String(piece.piece_id if piece != null else &"item")
	var counter := 1
	while true:
		var candidate := "%s_%03d" % [prefix, counter]
		if layout == null or layout.find_item(candidate) == null:
			return candidate
		counter += 1
	return ""
