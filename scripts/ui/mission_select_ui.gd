extends Control
class_name MissionSelectUI

signal close_requested

const MissionRegistryRef = preload("res://scripts/missions/mission_registry.gd")

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
var _party_poll_timer: Timer


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
	if session != null and session.has_signal("party_state_changed"):
		session.party_state_changed.connect(_on_party_state_changed)
	if session != null and session.has_signal("registry_lookup_result"):
		session.registry_lookup_result.connect(_on_registry_lookup_result)
	if session != null and session.has_signal("transport_error"):
		session.transport_error.connect(_on_transport_error)
	_build_mission_list()
	_party_poll_timer = Timer.new()
	_party_poll_timer.name = "PartyPollTimer"
	_party_poll_timer.wait_time = 1.0
	_party_poll_timer.one_shot = false
	add_child(_party_poll_timer)
	_party_poll_timer.timeout.connect(_on_party_poll_timer_timeout)
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
		and _session().has_signal("party_state_changed")
		and _session().party_state_changed.is_connected(_on_party_state_changed)
	):
		_session().party_state_changed.disconnect(_on_party_state_changed)
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
	var local_mission = MissionRegistryRef.get_mission(_selected_local_mission_id)
	if local_mission == null:
		_current_label.text = "Selected mission: none"
	else:
		_current_label.text = "Selected mission: %s (%s)" % [
			local_mission.display_name,
			String(local_mission.mission_id),
		]
	if session != null and session.has_method("has_active_party") and bool(session.call("has_active_party")):
		_showing_lobby_stage = true

	_title_label.text = "Party Lobby" if _showing_lobby_stage else "Mission Select"
	_current_label.visible = not _showing_lobby_stage
	_lobby_code_row.visible = not _showing_lobby_stage
	_content.visible = not _showing_lobby_stage
	_lobby_stage_vbox.visible = _showing_lobby_stage
	_proceed_button.visible = not _showing_lobby_stage
	_start_run_button.visible = _showing_lobby_stage
	_ready_button.visible = _showing_lobby_stage
	_close_button.text = "Back" if _showing_lobby_stage else "Close"

	_proceed_button.disabled = _selected_local_mission_id == &""
	var pending := (
		session != null
		and (
			(session.has_method("is_registry_lookup_in_progress") and bool(session.call("is_registry_lookup_in_progress")))
			or (session.has_method("is_lobby_create_in_progress") and bool(session.call("is_lobby_create_in_progress")))
			or (session.has_method("is_party_request_in_progress") and bool(session.call("is_party_request_in_progress")))
		)
	)
	_join_lobby_button.disabled = pending
	_lobby_code_input.editable = not pending
	_refresh_lobby_stage_state()
	_refresh_party_polling()


func _on_mission_state_changed(snapshot: Dictionary) -> void:
	_refresh_network_state()


func _on_session_state_changed(_previous_state: int, _current_state: int) -> void:
	_refresh_network_state()


func _on_peer_slot_map_changed(_slot_map: Dictionary) -> void:
	_refresh_network_state()


func _on_lobby_ready_changed(_ready_map: Dictionary) -> void:
	_refresh_network_state()


func _on_party_state_changed(_snapshot: Dictionary) -> void:
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
	if session == null or not session.has_method("join_party_by_code"):
		return
	var code := _lobby_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_current_label.text = "Enter a party code first."
		return
	if not bool(session.call("join_party_by_code", code)):
		_refresh_network_state()


func _on_ready_pressed() -> void:
	var session := _session()
	if session != null and session.has_method("toggle_local_party_ready"):
		session.call("toggle_local_party_ready")


func _on_start_run_pressed() -> void:
	var session := _session()
	if session != null and session.has_method("start_party_run"):
		session.call("start_party_run")


func _on_proceed_pressed() -> void:
	var session := _session()
	if session == null:
		return
	if _selected_local_mission_id == &"":
		return
	if session.has_method("create_party_for_mission"):
		session.call("create_party_for_mission", _selected_local_mission_id)


func _on_close_pressed() -> void:
	if _showing_lobby_stage:
		var session := _session()
		if session != null and session.has_method("leave_party"):
			session.call("leave_party")
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
	var party_snapshot := (
		session.call("get_party_snapshot") as Dictionary
		if session.has_method("get_party_snapshot")
		else {}
	)
	var mission_id := StringName(String(party_snapshot.get("mission_id", String(_selected_local_mission_id))))
	var mission = MissionRegistryRef.get_mission(mission_id)
	if mission == null:
		_mission_context_label.text = "Mission: none selected"
	else:
		_mission_context_label.text = "Mission: %s (%s)" % [
			mission.display_name,
			String(mission.mission_id),
		]
	var party_code := (
		String(session.call("get_party_code")).strip_edges().to_upper()
		if session.has_method("get_party_code")
		else ""
	)
	_lobby_code_display_label.text = party_code if not party_code.is_empty() else "-"

	var members := party_snapshot.get("members", []) as Array
	var local_ready := (
		bool(session.call("is_local_party_ready"))
		if session.has_method("is_local_party_ready")
		else false
	)
	var ready_total := members.size()
	var ready_count := 0
	for member_v in members:
		if member_v is Dictionary and bool((member_v as Dictionary).get("ready", false)):
			ready_count += 1

	var status := "Party: %s" % [party_code if not party_code.is_empty() else "pending"]
	if ready_total > 0:
		status += " | Ready: %s/%s" % [ready_count, ready_total]
	_status_label.text = status

	var is_owner := session.has_method("is_local_party_owner") and bool(session.call("is_local_party_owner"))
	_start_run_button.disabled = not (is_owner and mission != null)
	_start_run_button.text = "Start Mission" if is_owner else "Waiting For Owner"
	_ready_button.disabled = party_code.is_empty()
	_ready_button.text = "Unready" if local_ready else "Ready"
	_rebuild_party_list(party_snapshot)


func _rebuild_party_list(party_snapshot: Dictionary) -> void:
	_peers_list.clear()
	var session := _session()
	if session == null:
		_peers_list.add_item("No party.")
		return
	var members := party_snapshot.get("members", []) as Array
	if members.is_empty():
		_peers_list.add_item("Waiting for party...")
		return
	var owner_id := String(party_snapshot.get("owner_member_id", ""))
	var local_member_id := (
		String(session.call("get_party_member_id"))
		if session.has_method("get_party_member_id")
		else ""
	)
	for index in range(members.size()):
		var member := members[index] as Dictionary
		if member == null:
			continue
		var member_id := String(member.get("member_id", ""))
		var tag := ""
		if member_id == owner_id:
			tag += " host"
		if member_id == local_member_id:
			tag += " (you)"
		var ready_text := "READY" if bool(member.get("ready", false)) else "NOT READY"
		_peers_list.add_item("Player %s | %s%s" % [index + 1, ready_text, tag])


func _refresh_party_polling() -> void:
	if _party_poll_timer == null:
		return
	if _showing_lobby_stage:
		if _party_poll_timer.is_stopped():
			_party_poll_timer.start()
	else:
		_party_poll_timer.stop()


func _on_party_poll_timer_timeout() -> void:
	var session := _session()
	if session != null and session.has_method("poll_party"):
		session.call("poll_party")


func _session() -> Node:
	return get_node_or_null("/root/NetworkSession")
