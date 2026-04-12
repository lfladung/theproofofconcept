extends Control
class_name MissionSelectUI

signal close_requested

const MissionRegistryRef = preload("res://scripts/missions/mission_registry.gd")
const MISSION_FLOW_PHASE_STAGING := 3

@onready var _title_label: Label = $Panel/Margin/Rows/TitleLabel
@onready var _lobby_code_row: HBoxContainer = $Panel/Margin/Rows/LobbyCodeRow
@onready var _content: HBoxContainer = $Panel/Margin/Rows/Content
@onready var _mission_list: VBoxContainer = $Panel/Margin/Rows/Content/MissionList
@onready var _details_label: Label = $Panel/Margin/Rows/Content/DetailsLabel
@onready var _current_label: Label = $Panel/Margin/Rows/CurrentMissionLabel
@onready var _lobby_code_input: LineEdit = $Panel/Margin/Rows/LobbyCodeRow/LobbyCodeInput
@onready var _join_lobby_button: Button = $Panel/Margin/Rows/LobbyCodeRow/JoinLobbyButton
@onready var _lobby_stage_vbox: VBoxContainer = $Panel/Margin/Rows/LobbyStageVBox
@onready var _mission_context_label: Label = $Panel/Margin/Rows/LobbyStageVBox/MissionContextLabel
@onready var _lobby_code_display_label: LineEdit = $Panel/Margin/Rows/LobbyStageVBox/LobbyCodeDisplayLabel
@onready var _status_label: Label = $Panel/Margin/Rows/LobbyStageVBox/StatusLabel
@onready var _peers_list: ItemList = $Panel/Margin/Rows/LobbyStageVBox/PeersList
@onready var _proceed_button: Button = $Panel/Margin/Rows/ButtonRow/ProceedButton
@onready var _start_run_button: Button = $Panel/Margin/Rows/ButtonRow/StartRunButton
@onready var _ready_button: Button = $Panel/Margin/Rows/ButtonRow/ReadyButton
@onready var _close_button: Button = $Panel/Margin/Rows/ButtonRow/CloseButton

var _selected_local_mission_id: StringName = &""
var _showing_lobby_stage := false


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_proceed_button.pressed.connect(_on_proceed_pressed)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_run_button.pressed.connect(_on_start_run_pressed)
	_join_lobby_button.pressed.connect(_on_join_lobby_pressed)
	_lobby_code_input.text_submitted.connect(_on_lobby_code_submitted)
	var session := _session()
	if session != null and session.has_signal("mission_state_changed"):
		session.mission_state_changed.connect(_on_mission_state_changed)
	if session != null and session.has_signal("state_changed"):
		session.state_changed.connect(_on_session_state_changed)
	if session != null and session.has_signal("peer_slot_map_changed"):
		session.peer_slot_map_changed.connect(_on_peer_slot_map_changed)
	if session != null and session.has_signal("lobby_ready_changed"):
		session.lobby_ready_changed.connect(_on_lobby_ready_changed)
	if session != null and session.has_signal("registry_lookup_result"):
		session.registry_lookup_result.connect(_on_registry_lookup_result)
	if session != null and session.has_signal("transport_error"):
		session.transport_error.connect(_on_transport_error)
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
	if (
		_session() != null
		and _session().has_signal("state_changed")
		and _session().state_changed.is_connected(_on_session_state_changed)
	):
		_session().state_changed.disconnect(_on_session_state_changed)
	if (
		_session() != null
		and _session().has_signal("peer_slot_map_changed")
		and _session().peer_slot_map_changed.is_connected(_on_peer_slot_map_changed)
	):
		_session().peer_slot_map_changed.disconnect(_on_peer_slot_map_changed)
	if (
		_session() != null
		and _session().has_signal("lobby_ready_changed")
		and _session().lobby_ready_changed.is_connected(_on_lobby_ready_changed)
	):
		_session().lobby_ready_changed.disconnect(_on_lobby_ready_changed)
	if (
		_session() != null
		and _session().has_signal("registry_lookup_result")
		and _session().registry_lookup_result.is_connected(_on_registry_lookup_result)
	):
		_session().registry_lookup_result.disconnect(_on_registry_lookup_result)
	if (
		_session() != null
		and _session().has_signal("transport_error")
		and _session().transport_error.is_connected(_on_transport_error)
	):
		_session().transport_error.disconnect(_on_transport_error)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()


func open_multiplayer_lobby_stage() -> void:
	_showing_lobby_stage = true
	_refresh_network_state()


func open_mission_select_stage() -> void:
	_showing_lobby_stage = false
	_refresh_network_state()


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
	if session != null and session.has_method("get_mission_state_snapshot"):
		var snapshot := session.call("get_mission_state_snapshot") as Dictionary
		_showing_lobby_stage = int(snapshot.get("phase", 0)) == MISSION_FLOW_PHASE_STAGING

	_title_label.text = "Multiplayer Lobby" if _showing_lobby_stage else "Mission Select"
	_current_label.visible = not _showing_lobby_stage
	_lobby_code_row.visible = not _showing_lobby_stage
	_content.visible = not _showing_lobby_stage
	_lobby_stage_vbox.visible = _showing_lobby_stage
	_proceed_button.visible = not _showing_lobby_stage
	_start_run_button.visible = _showing_lobby_stage
	_ready_button.visible = _showing_lobby_stage
	_close_button.text = "Back" if _showing_lobby_stage else "Close"

	_proceed_button.disabled = not (
		session != null and session.has_method("has_selected_mission") and bool(session.call("has_selected_mission"))
	)
	var pending := (
		session != null
		and (
			(session.has_method("is_registry_lookup_in_progress") and bool(session.call("is_registry_lookup_in_progress")))
			or (session.has_method("is_lobby_create_in_progress") and bool(session.call("is_lobby_create_in_progress")))
		)
	)
	_join_lobby_button.disabled = pending
	_lobby_code_input.editable = not pending
	_refresh_lobby_stage_state()


func _on_mission_state_changed(snapshot: Dictionary) -> void:
	_showing_lobby_stage = int(snapshot.get("phase", 0)) == MISSION_FLOW_PHASE_STAGING
	_refresh_network_state()


func _on_session_state_changed(_previous_state: int, _current_state: int) -> void:
	_refresh_network_state()


func _on_peer_slot_map_changed(_slot_map: Dictionary) -> void:
	_refresh_network_state()


func _on_lobby_ready_changed(_ready_map: Dictionary) -> void:
	_refresh_network_state()


func _on_registry_lookup_result(success: bool, message: String) -> void:
	_refresh_network_state()
	if success:
		if message.begins_with("Resolving"):
			_details_label.text = "Joining lobby..."
	else:
		_details_label.text = message if not message.is_empty() else "Lobby join failed."


func _on_transport_error(message: String) -> void:
	_refresh_network_state()
	if not message.is_empty():
		_details_label.text = message


func _on_lobby_code_submitted(_text: String) -> void:
	_on_join_lobby_pressed()


func _on_join_lobby_pressed() -> void:
	var session := _session()
	if session == null or not session.has_method("join_lobby_via_session_code"):
		return
	var code := _lobby_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_current_label.text = "Enter a lobby code first."
		return
	if session.has_method("has_active_peer") and bool(session.call("has_active_peer")):
		session.call("disconnect_from_session", false)
	if not bool(session.call("join_lobby_via_session_code", code)):
		_refresh_network_state()


func _on_ready_pressed() -> void:
	var session := _session()
	if session != null and session.has_method("toggle_local_peer_ready"):
		session.call("toggle_local_peer_ready")


func _on_start_run_pressed() -> void:
	var session := _session()
	if session != null and session.has_method("request_start_run_from_local_peer"):
		session.call("request_start_run_from_local_peer")


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
	if _showing_lobby_stage:
		var session := _session()
		if session != null and session.has_method("request_cancel_mission_staging_from_local_peer"):
			session.call("request_cancel_mission_staging_from_local_peer")
		open_mission_select_stage()
		return
	close_requested.emit()


func _refresh_lobby_stage_state() -> void:
	if not _showing_lobby_stage:
		return
	var session := _session()
	if session == null:
		_status_label.text = "State: OFFLINE | Role: NONE"
		_mission_context_label.text = "Mission: none selected"
		_lobby_code_display_label.text = "-"
		_peers_list.clear()
		_peers_list.add_item("Offline.")
		return
	var has_selected_mission := session.has_method("has_selected_mission") and bool(session.call("has_selected_mission"))
	var payload := (
		session.call("get_selected_mission_payload") as Dictionary
		if has_selected_mission and session.has_method("get_selected_mission_payload")
		else {}
	)
	if payload.is_empty():
		_mission_context_label.text = "Mission: none selected"
	else:
		_mission_context_label.text = "Mission: %s (%s)" % [
			String(payload.get("display_name", "")),
			String(payload.get("mission_id", "")),
		]
	var session_code := (
		String(session.call("get_session_code")).strip_edges().to_upper()
		if session.has_method("get_session_code")
		else ""
	)
	_lobby_code_display_label.text = session_code if not session_code.is_empty() else "-"

	var slot_map := (
		session.call("get_peer_slot_map") as Dictionary
		if session.has_method("get_peer_slot_map")
		else {}
	)
	var ready_map := (
		session.call("get_lobby_ready_map") as Dictionary
		if session.has_method("get_lobby_ready_map")
		else {}
	)
	var in_lobby := int(session.get("session_state")) == 2
	var is_dedicated := int(session.get("session_role")) == 3
	var local_ready := (
		bool(session.call("is_local_peer_ready"))
		if session.has_method("is_local_peer_ready")
		else false
	)
	var ready_total := slot_map.size()
	var ready_count := 0
	for key in slot_map.keys():
		if bool(ready_map.get(int(key), false)):
			ready_count += 1

	var status := "State: %s | Role: %s" % [
		String(session.call("get_state_name")) if session.has_method("get_state_name") else "UNKNOWN",
		String(session.call("get_role_name")) if session.has_method("get_role_name") else "UNKNOWN",
	]
	if in_lobby and ready_total > 0:
		status += " | Ready: %s/%s" % [ready_count, ready_total]
	_status_label.text = status

	_start_run_button.disabled = not (in_lobby and not is_dedicated and has_selected_mission)
	_start_run_button.text = "Start Selected Mission" if has_selected_mission else "Select Mission First"
	_ready_button.disabled = not (in_lobby and not is_dedicated)
	_ready_button.text = "Unready" if local_ready else "Ready"
	_rebuild_peer_list(slot_map, ready_map)


func _rebuild_peer_list(slot_map: Dictionary, ready_map: Dictionary) -> void:
	_peers_list.clear()
	var session := _session()
	if session == null or not (session.has_method("has_active_peer") and bool(session.call("has_active_peer"))):
		_peers_list.add_item("Offline.")
		return
	if slot_map.is_empty():
		_peers_list.add_item("Connected. Waiting for peers...")
		return
	var local_peer := int(session.call("get_local_peer_id")) if session.has_method("get_local_peer_id") else 1
	var peer_ids := slot_map.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var peer_id_int := int(peer_id)
		var slot := int(slot_map[peer_id])
		var tag := " (you)" if peer_id_int == local_peer else ""
		var ready_text := "READY" if bool(ready_map.get(peer_id_int, false)) else "NOT READY"
		_peers_list.add_item("Player %s | %s%s" % [slot + 1, ready_text, tag])


func _session() -> Node:
	return get_node_or_null("/root/NetworkSession")
