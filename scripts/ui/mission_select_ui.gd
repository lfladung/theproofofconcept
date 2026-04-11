extends Control
class_name MissionSelectUI

signal close_requested

const MissionRegistryRef = preload("res://scripts/missions/mission_registry.gd")

@onready var _mission_list: VBoxContainer = $Panel/Margin/Rows/Content/MissionList
@onready var _details_label: Label = $Panel/Margin/Rows/Content/DetailsLabel
@onready var _current_label: Label = $Panel/Margin/Rows/CurrentMissionLabel
@onready var _proceed_button: Button = $Panel/Margin/Rows/ButtonRow/ProceedButton
@onready var _close_button: Button = $Panel/Margin/Rows/ButtonRow/CloseButton

var _selected_local_mission_id: StringName = &""


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_proceed_button.pressed.connect(_on_proceed_pressed)
	var session := _session()
	if session != null and session.has_signal("mission_state_changed"):
		session.mission_state_changed.connect(_on_mission_state_changed)
	_build_mission_list()
	_select_local_mission(MissionRegistryRef.default_mission_id())
	_refresh_network_state()


func _exit_tree() -> void:
	if (
		_session() != null
		and _session().has_signal("mission_state_changed")
		and _session().mission_state_changed.is_connected(_on_mission_state_changed)
	):
		_session().mission_state_changed.disconnect(_on_mission_state_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()


func _build_mission_list() -> void:
	for child in _mission_list.get_children():
		child.queue_free()
	for mission in MissionRegistryRef.all_missions():
		if mission == null:
			continue
		var button := Button.new()
		button.text = "%s  |  %s" % [mission.display_name, mission.difficulty]
		button.custom_minimum_size = Vector2(240, 42)
		button.pressed.connect(_on_mission_button_pressed.bind(mission.mission_id))
		_mission_list.add_child(button)


func _on_mission_button_pressed(mission_id: StringName) -> void:
	_select_local_mission(mission_id)
	var session := _session()
	if session != null and session.has_method("request_select_mission_from_local_peer"):
		session.call("request_select_mission_from_local_peer", mission_id)


func _select_local_mission(mission_id: StringName) -> void:
	_selected_local_mission_id = mission_id
	var mission = MissionRegistryRef.get_mission(mission_id)
	if mission == null:
		_details_label.text = "Choose a mission."
		return
	_details_label.text = (
		"Mission ID: %s\nName: %s\nDifficulty: %s\nFloors: %s\nEnemy Theme: %s\nRewards: %s"
		% [
			String(mission.mission_id),
			mission.display_name,
			mission.difficulty,
			mission.floor_count,
			mission.enemy_theme,
			", ".join(mission.rewards),
		]
	)


func _refresh_network_state() -> void:
	var session := _session()
	var payload := (
		session.call("get_selected_mission_payload") as Dictionary
		if session != null and session.has_method("get_selected_mission_payload")
		else {}
	)
	if payload.is_empty():
		_current_label.text = "Authoritative mission: none selected"
	else:
		_current_label.text = "Authoritative mission: %s (%s)" % [
			String(payload.get("display_name", "")),
			String(payload.get("mission_id", "")),
		]
	_proceed_button.disabled = not (
		session != null and session.has_method("has_selected_mission") and bool(session.call("has_selected_mission"))
	)


func _on_mission_state_changed(_snapshot: Dictionary) -> void:
	_refresh_network_state()


func _on_proceed_pressed() -> void:
	var session := _session()
	if session == null:
		return
	var has_mission := session.has_method("has_selected_mission") and bool(session.call("has_selected_mission"))
	if not has_mission and _selected_local_mission_id != &"":
		session.call("request_select_mission_from_local_peer", _selected_local_mission_id)
	if session.has_method("request_mission_staging_from_local_peer"):
		session.call("request_mission_staging_from_local_peer")


func _on_close_pressed() -> void:
	close_requested.emit()


func _session() -> Node:
	return get_node_or_null("/root/NetworkSession")
