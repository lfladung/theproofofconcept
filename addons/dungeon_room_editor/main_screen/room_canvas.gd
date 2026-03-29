@tool
extends Control

signal hover_grid_changed(grid: Vector2i)
signal primary_pressed(grid: Vector2i)
signal primary_dragged(grid: Vector2i)
signal primary_released()
signal rotate_shortcut_requested()
signal delete_shortcut_requested()

const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const CanvasOverlayScript = preload("res://addons/dungeon_room_editor/overlays/canvas_overlay.gd")

var _session
var _overlay = CanvasOverlayScript.new()
var _zoom := 1.0
var _world_offset := Vector2.ZERO
var _is_primary_down := false
var _is_panning := false
var _has_centered_current_room := false


func _ready() -> void:
	focus_mode = FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_session(session) -> void:
	var current_room = session.room if session != null else null
	var previous_room = _session.room if _session != null else null
	_session = session
	if current_room != previous_room:
		_has_centered_current_room = false
	queue_redraw()


func center_view(force: bool = false) -> void:
	if _session == null or _session.room == null:
		_zoom = 1.0
		_world_offset = Vector2.ZERO
		queue_redraw()
		return
	if size.x <= 1.0 or size.y <= 1.0:
		return
	if _has_centered_current_room and not force:
		return
	var room_rect := GridMath.room_local_rect(_session.room)
	var available := size - Vector2(96.0, 96.0)
	if available.x <= 1.0 or available.y <= 1.0:
		return
	var fit_scale := min(
		available.x / maxf(room_rect.size.x, 1.0),
		available.y / maxf(room_rect.size.y, 1.0)
	)
	_zoom = clampf(fit_scale, 0.25, 24.0)
	_world_offset = -room_rect.get_center()
	_has_centered_current_room = true
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				grab_focus()
				var grid := _canvas_to_grid(button.position)
				if button.pressed:
					_is_primary_down = true
					hover_grid_changed.emit(grid)
					primary_pressed.emit(grid)
				else:
					_is_primary_down = false
					primary_released.emit()
				accept_event()
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_is_panning = button.pressed
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				_apply_zoom(1.1, button.position)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom(1.0 / 1.1, button.position)
				accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _is_panning:
			_world_offset += motion.relative / maxf(_zoom, 0.001)
			queue_redraw()
			accept_event()
			return
		var grid := _canvas_to_grid(motion.position)
		hover_grid_changed.emit(grid)
		if _is_primary_down:
			primary_dragged.emit(grid)
		accept_event()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.keycode:
			KEY_R:
				rotate_shortcut_requested.emit()
				accept_event()
			KEY_DELETE, KEY_BACKSPACE:
				delete_shortcut_requested.emit()
				accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.10, 0.11), true)
	if _session == null or _session.room == null or _session.layout == null:
		_draw_centered_message("Open a RoomBase scene to author it here.")
		return
	center_view()
	_overlay.draw(self, _session, Callable(self, "_project_local_to_canvas"))


func _draw_centered_message(message: String) -> void:
	var font := get_theme_font(&"font", &"Label")
	if font == null:
		return
	var font_size := get_theme_font_size(&"font_size", &"Label")
	var text_size := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var position := (size - text_size) * 0.5 + Vector2(0.0, text_size.y)
	draw_string(font, position, message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.86, 0.89, 0.93, 0.86))


func _apply_zoom(factor: float, pivot: Vector2) -> void:
	var before := _canvas_to_room_local(pivot)
	_zoom = clampf(_zoom * factor, 0.1, 64.0)
	var after := _canvas_to_room_local(pivot)
	_world_offset += before - after
	queue_redraw()


func _project_local_to_canvas(local_position: Vector2) -> Vector2:
	return size * 0.5 + (local_position + _world_offset) * _zoom


func _canvas_to_room_local(canvas_position: Vector2) -> Vector2:
	return ((canvas_position - size * 0.5) / maxf(_zoom, 0.001)) - _world_offset


func _canvas_to_grid(canvas_position: Vector2) -> Vector2i:
	if _session == null or _session.room == null:
		return Vector2i.ZERO
	return GridMath.local_to_grid(_canvas_to_room_local(canvas_position), _session.layout, _session.room)
