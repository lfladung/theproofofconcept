extends Node

enum ControlScheme {
	MOUSE = 0,
	WASD_MOUSE = 1,
}

enum WindowMode {
	WINDOWED = 0,
	BORDERED_FULLSCREEN = 1,
	FULLSCREEN = 2,
}

signal control_scheme_changed(scheme: ControlScheme)
signal display_settings_apply_started
signal display_settings_changed(resolution: Vector2i, window_mode: WindowMode)
signal display_settings_apply_finished

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_CONTROLS := "controls"
const KEY_SCHEME := "scheme"
const SECTION_DISPLAY := "display"
const KEY_RESOLUTION_WIDTH := "resolution_width"
const KEY_RESOLUTION_HEIGHT := "resolution_height"
const KEY_WINDOW_MODE := "window_mode"

const RESOLUTION_OPTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const ACTION_MELEE := &"melee_attack"
const ACTION_DEFEND := &"defend"
const ACTION_BOMB := &"bomb_throw"

var control_scheme: ControlScheme = ControlScheme.MOUSE
var resolution: Vector2i = RESOLUTION_OPTIONS[0]
var window_mode: WindowMode = WindowMode.WINDOWED

var _default_melee_events: Array[InputEvent] = []
var _default_defend_events: Array[InputEvent] = []
var _default_bomb_events: Array[InputEvent] = []
var _defaults_captured := false
var _display_apply_revision := 0


func _ready() -> void:
	_capture_defaults_if_needed()
	_load_from_disk()
	apply_scheme_to_input_map()
	apply_display_settings()


func is_wasd_mouse_scheme() -> bool:
	return control_scheme == ControlScheme.WASD_MOUSE


func set_control_scheme(scheme: ControlScheme) -> void:
	if control_scheme == scheme:
		return
	control_scheme = scheme
	_save_to_disk()
	apply_scheme_to_input_map()
	control_scheme_changed.emit(control_scheme)


func set_resolution(next_resolution: Vector2i) -> void:
	var validated := _validated_resolution(next_resolution)
	if resolution == validated:
		return
	resolution = validated
	_save_to_disk()
	apply_display_settings()
	display_settings_changed.emit(resolution, window_mode)


func set_window_mode(next_window_mode: WindowMode) -> void:
	var validated := _validated_window_mode(next_window_mode)
	if window_mode == validated:
		return
	window_mode = validated
	_save_to_disk()
	apply_display_settings()
	display_settings_changed.emit(resolution, window_mode)


func set_display_settings(next_resolution: Vector2i, next_window_mode: WindowMode) -> void:
	var validated_resolution := _validated_resolution(next_resolution)
	var validated_window_mode := _validated_window_mode(next_window_mode)
	if resolution == validated_resolution and window_mode == validated_window_mode:
		return
	resolution = validated_resolution
	window_mode = validated_window_mode
	_save_to_disk()
	apply_display_settings()
	display_settings_changed.emit(resolution, window_mode)


func get_resolution_options() -> Array[Vector2i]:
	return RESOLUTION_OPTIONS.duplicate()


func get_resolution_index() -> int:
	return RESOLUTION_OPTIONS.find(resolution)


func get_window_mode_index() -> int:
	return int(window_mode)


func resolution_display_name(next_resolution: Vector2i) -> String:
	return "%sx%s" % [next_resolution.x, next_resolution.y]


func window_mode_display_name(next_window_mode: WindowMode) -> String:
	match next_window_mode:
		WindowMode.BORDERED_FULLSCREEN:
			return "Bordered fullscreen"
		WindowMode.FULLSCREEN:
			return "Fullscreen"
		_:
			return "Windowed"


func apply_display_settings() -> void:
	_display_apply_revision += 1
	var apply_revision := _display_apply_revision
	display_settings_apply_started.emit()
	_apply_display_settings_after_curtain.call_deferred(apply_revision)


func _apply_display_settings_after_curtain(apply_revision: int) -> void:
	await get_tree().process_frame
	if apply_revision != _display_apply_revision:
		return
	var window := get_window()
	if window == null:
		return
	window.borderless = false
	window.unresizable = true
	match window_mode:
		WindowMode.BORDERED_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED
			window.size = resolution
			window.mode = Window.MODE_MAXIMIZED
		WindowMode.FULLSCREEN:
			window.mode = Window.MODE_FULLSCREEN
		_:
			window.mode = Window.MODE_WINDOWED
			window.size = resolution
			_center_window(window)
	_finish_display_settings_apply.call_deferred(apply_revision)


func apply_scheme_to_input_map() -> void:
	_capture_defaults_if_needed()
	match control_scheme:
		ControlScheme.MOUSE:
			_restore_action_events(ACTION_MELEE, _default_melee_events)
			_restore_action_events(ACTION_DEFEND, _default_defend_events)
			_restore_action_events(ACTION_BOMB, _default_bomb_events)
		ControlScheme.WASD_MOUSE:
			_apply_wasd_melee()
			_apply_wasd_defend()
			_apply_wasd_bomb()


func _capture_defaults_if_needed() -> void:
	if _defaults_captured:
		return
	_default_melee_events = _duplicate_event_array(InputMap.action_get_events(ACTION_MELEE))
	_default_defend_events = _duplicate_event_array(InputMap.action_get_events(ACTION_DEFEND))
	_default_bomb_events = _duplicate_event_array(InputMap.action_get_events(ACTION_BOMB))
	_defaults_captured = true


func _duplicate_event_array(src: Array) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for ev in src:
		if ev is InputEvent:
			out.append((ev as InputEvent).duplicate(true) as InputEvent)
	return out


func _restore_action_events(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for ev in events:
		InputMap.action_add_event(action, ev.duplicate(true))


func _is_keyboard_event(ev: InputEvent) -> bool:
	return ev is InputEventKey


func _strip_keyboard_events(events: Array[InputEvent]) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for ev in events:
		if not _is_keyboard_event(ev):
			out.append(ev.duplicate(true) as InputEvent)
	return out


func _has_right_mouse_button(events: Array[InputEvent]) -> bool:
	for ev in events:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				return true
	return false


func _apply_wasd_melee() -> void:
	var next := _strip_keyboard_events(_default_melee_events)
	_restore_action_events(ACTION_MELEE, next)


func _apply_wasd_defend() -> void:
	var next := _strip_keyboard_events(_default_defend_events)
	if not _has_right_mouse_button(next):
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		next.append(rmb)
	_restore_action_events(ACTION_DEFEND, next)


func _apply_wasd_bomb() -> void:
	var next := _strip_keyboard_events(_default_bomb_events)
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	next.append(q)
	_restore_action_events(ACTION_BOMB, next)


func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if cfg.has_section_key(SECTION_CONTROLS, KEY_SCHEME):
		var raw := int(cfg.get_value(SECTION_CONTROLS, KEY_SCHEME))
		if raw == int(ControlScheme.WASD_MOUSE):
			control_scheme = ControlScheme.WASD_MOUSE
		else:
			control_scheme = ControlScheme.MOUSE

	if cfg.has_section_key(SECTION_DISPLAY, KEY_RESOLUTION_WIDTH) and cfg.has_section_key(
		SECTION_DISPLAY, KEY_RESOLUTION_HEIGHT
	):
		var loaded_resolution := Vector2i(
			int(cfg.get_value(SECTION_DISPLAY, KEY_RESOLUTION_WIDTH)),
			int(cfg.get_value(SECTION_DISPLAY, KEY_RESOLUTION_HEIGHT))
		)
		resolution = _validated_resolution(loaded_resolution)
	if cfg.has_section_key(SECTION_DISPLAY, KEY_WINDOW_MODE):
		window_mode = _validated_window_mode(int(cfg.get_value(SECTION_DISPLAY, KEY_WINDOW_MODE)))


func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION_CONTROLS, KEY_SCHEME, int(control_scheme))
	cfg.set_value(SECTION_DISPLAY, KEY_RESOLUTION_WIDTH, resolution.x)
	cfg.set_value(SECTION_DISPLAY, KEY_RESOLUTION_HEIGHT, resolution.y)
	cfg.set_value(SECTION_DISPLAY, KEY_WINDOW_MODE, int(window_mode))
	cfg.save(SETTINGS_PATH)


func _validated_resolution(candidate: Vector2i) -> Vector2i:
	if RESOLUTION_OPTIONS.has(candidate):
		return candidate
	return RESOLUTION_OPTIONS[0]


func _validated_window_mode(candidate: int) -> WindowMode:
	match candidate:
		WindowMode.BORDERED_FULLSCREEN, WindowMode.FULLSCREEN:
			return candidate
		_:
			return WindowMode.WINDOWED


func _center_window(window: Window) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	window.position = usable_rect.position + ((usable_rect.size - window.size) / 2)


func _finish_display_settings_apply(apply_revision: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if apply_revision != _display_apply_revision:
		return
	display_settings_apply_finished.emit()
