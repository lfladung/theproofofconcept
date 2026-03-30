extends Node

enum ControlScheme {
	MOUSE = 0,
	WASD_MOUSE = 1,
}

signal control_scheme_changed(scheme: ControlScheme)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_CONTROLS := "controls"
const KEY_SCHEME := "scheme"

const ACTION_MELEE := &"melee_attack"
const ACTION_DEFEND := &"defend"
const ACTION_BOMB := &"bomb_throw"

var control_scheme: ControlScheme = ControlScheme.MOUSE

var _default_melee_events: Array[InputEvent] = []
var _default_defend_events: Array[InputEvent] = []
var _default_bomb_events: Array[InputEvent] = []
var _defaults_captured := false


func _ready() -> void:
	_capture_defaults_if_needed()
	_load_from_disk()
	apply_scheme_to_input_map()


func is_wasd_mouse_scheme() -> bool:
	return control_scheme == ControlScheme.WASD_MOUSE


func set_control_scheme(scheme: ControlScheme) -> void:
	if control_scheme == scheme:
		return
	control_scheme = scheme
	_save_to_disk()
	apply_scheme_to_input_map()
	control_scheme_changed.emit(control_scheme)


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
	if not cfg.has_section_key(SECTION_CONTROLS, KEY_SCHEME):
		return
	var raw := int(cfg.get_value(SECTION_CONTROLS, KEY_SCHEME))
	if raw == int(ControlScheme.WASD_MOUSE):
		control_scheme = ControlScheme.WASD_MOUSE
	else:
		control_scheme = ControlScheme.MOUSE


func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION_CONTROLS, KEY_SCHEME, int(control_scheme))
	cfg.save(SETTINGS_PATH)
