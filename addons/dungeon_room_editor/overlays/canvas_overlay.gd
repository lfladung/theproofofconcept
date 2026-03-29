@tool
extends RefCounted
class_name DungeonRoomCanvasOverlay

const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")

var grid_color := Color(0.25, 0.65, 0.95, 0.26)
var boundary_color := Color(0.75, 0.75, 0.82, 0.65)
var hover_valid_color := Color(0.18, 0.82, 0.45, 0.32)
var hover_invalid_color := Color(0.93, 0.22, 0.22, 0.32)
var selected_color := Color(0.98, 0.82, 0.20, 0.34)
var item_outline_color := Color(0.96, 0.96, 0.98, 0.42)


func draw(overlay: Control, session, projector: Callable = Callable()) -> void:
	if overlay == null or session == null or session.room == null or session.layout == null or session.catalog == null:
		return
	var room = session.room
	var layout = session.layout
	var room_rect := GridMath.room_local_rect(room)
	var top_left := _project(room, room_rect.position, projector)
	var top_right := _project(room, room_rect.position + Vector2(room_rect.size.x, 0.0), projector)
	var bottom_right := _project(room, room_rect.position + room_rect.size, projector)
	var bottom_left := _project(room, room_rect.position + Vector2(0.0, room_rect.size.y), projector)
	overlay.draw_polyline(
		PackedVector2Array([top_left, top_right, bottom_right, bottom_left, top_left]),
		boundary_color,
		2.0
	)

	var step := GridMath.grid_step(layout, room)
	var x = room_rect.position.x
	while x <= room_rect.end.x + 0.001:
		var from := _project(room, Vector2(x, room_rect.position.y), projector)
		var to := _project(room, Vector2(x, room_rect.end.y), projector)
		overlay.draw_line(from, to, grid_color, 1.0)
		x += step.x
	var y = room_rect.position.y
	while y <= room_rect.end.y + 0.001:
		var from := _project(room, Vector2(room_rect.position.x, y), projector)
		var to := _project(room, Vector2(room_rect.end.x, y), projector)
		overlay.draw_line(from, to, grid_color, 1.0)
		y += step.y

	for item in layout.items:
		if item == null:
			continue
		var piece = session.catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		if not session.is_item_visible(item, piece):
			continue
		_draw_rect_outline(overlay, room, GridMath.item_rect(item, piece, layout, room), item_outline_color, 1.0, projector)

	var selected_item = session.selected_item()
	var selected_piece = session.selected_piece()
	if selected_item != null and selected_piece != null and session.is_item_visible(selected_item, selected_piece):
		var selected_rect := GridMath.item_rect(selected_item, selected_piece, layout, room)
		_draw_rect_fill(overlay, room, selected_rect, selected_color, projector)
		_draw_rect_outline(overlay, room, selected_rect, selected_color.lightened(0.18), 2.0, projector)

	var preview_piece = session.active_piece()
	if (
		preview_piece != null
		and session.box_paint_enabled
		and session.box_drag_active
		and GridMath.is_defined_grid(session.box_drag_start)
		and GridMath.is_defined_grid(session.box_drag_end)
	):
		for grid in _grid_rect_cells(session.box_drag_start, session.box_drag_end):
			if not GridMath.grid_is_inside_room(grid, layout, room):
				continue
			var box_rect := GridMath.anchor_rect(
				grid,
				preview_piece.footprint,
				session.placement_rotation_steps,
				layout,
				room
			)
			_draw_rect_fill(overlay, room, box_rect, hover_valid_color.darkened(0.1), projector)
			_draw_rect_outline(overlay, room, box_rect, hover_valid_color.lightened(0.12), 1.5, projector)

	if (
		preview_piece != null
		and not session.box_drag_active
		and GridMath.is_defined_grid(session.hover_cell)
		and GridMath.grid_is_inside_room(session.hover_cell, layout, room)
	):
		var hover_rect := GridMath.anchor_rect(
			session.hover_cell,
			preview_piece.footprint,
			session.placement_rotation_steps,
			layout,
			room
		)
		_draw_rect_fill(
			overlay,
			room,
			hover_rect,
			hover_valid_color if session.hover_valid else hover_invalid_color,
			projector
		)
		_draw_rect_outline(
			overlay,
			room,
			hover_rect,
			hover_valid_color.darkened(0.25) if session.hover_valid else hover_invalid_color.darkened(0.1),
			2.0,
			projector
		)


func _draw_rect_fill(overlay: Control, room: RoomBase, rect: Rect2, color: Color, projector: Callable) -> void:
	var corners := PackedVector2Array([
		_project(room, rect.position, projector),
		_project(room, rect.position + Vector2(rect.size.x, 0.0), projector),
		_project(room, rect.position + rect.size, projector),
		_project(room, rect.position + Vector2(0.0, rect.size.y), projector),
	])
	overlay.draw_colored_polygon(corners, color)


func _draw_rect_outline(overlay: Control, room: RoomBase, rect: Rect2, color: Color, width: float, projector: Callable) -> void:
	var corners := PackedVector2Array([
		_project(room, rect.position, projector),
		_project(room, rect.position + Vector2(rect.size.x, 0.0), projector),
		_project(room, rect.position + rect.size, projector),
		_project(room, rect.position + Vector2(0.0, rect.size.y), projector),
		_project(room, rect.position, projector),
	])
	overlay.draw_polyline(corners, color, width)


func _project(room: RoomBase, local_position: Vector2, projector: Callable) -> Vector2:
	if projector.is_valid():
		return projector.call(local_position)
	return GridMath.local_to_canvas(room, local_position)


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
