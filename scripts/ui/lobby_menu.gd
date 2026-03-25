extends Control
class_name LobbyMenu

@onready var _session_code_input: LineEdit = $Center/Margin/VBox/CodeRow/SessionCodeInput
@onready var _join_code_button: Button = $Center/Margin/VBox/CodeRow/JoinCodeButton
@onready var _host_button: Button = $Center/Margin/VBox/ButtonRow/HostButton
@onready var _start_run_button: Button = $Center/Margin/VBox/ButtonRow/StartRunButton
@onready var _ready_button: Button = $Center/Margin/VBox/ButtonRow/ReadyButton
@onready var _play_offline_button: Button = $Center/Margin/VBox/ButtonRow/PlayOfflineButton
@onready var _disconnect_button: Button = $Center/Margin/VBox/ButtonRow/DisconnectButton
@onready var _status_label: Label = $Center/Margin/VBox/StatusLabel
@onready var _lobby_code_label: LineEdit = $Center/Margin/VBox/LobbyCodeLabel
@onready var _error_label: Label = $Center/Margin/VBox/ErrorLabel
@onready var _peers_list: ItemList = $Center/Margin/VBox/PeersList


func _ready() -> void:
	_error_label.text = ""

	_host_button.pressed.connect(_on_host_pressed)
	_join_code_button.pressed.connect(_on_join_code_pressed)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_run_button.pressed.connect(_on_start_run_pressed)
	_play_offline_button.pressed.connect(_on_play_offline_pressed)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)

	NetworkSession.state_changed.connect(_on_session_state_changed)
	NetworkSession.role_changed.connect(_on_session_role_changed)
	NetworkSession.peer_slot_map_changed.connect(_on_peer_slot_map_changed)
	NetworkSession.transport_error.connect(_on_transport_error)
	NetworkSession.registry_lookup_result.connect(_on_registry_lookup_result)
	NetworkSession.session_code_changed.connect(_on_session_code_changed)
	NetworkSession.lobby_ready_changed.connect(_on_lobby_ready_changed)

	_refresh_ui()
	_rebuild_peer_list(NetworkSession.get_peer_slot_map())


func _on_host_pressed() -> void:
	_error_label.text = ""
	if not NetworkSession.request_lobby_from_registry():
		_refresh_ui()
	_refresh_ui()


func _on_join_code_pressed() -> void:
	_error_label.text = ""
	var code := _session_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_error_label.text = "Enter a session code first."
		return
	if not NetworkSession.join_lobby_via_session_code(code):
		_refresh_ui()


func _on_ready_pressed() -> void:
	_error_label.text = ""
	NetworkSession.toggle_local_peer_ready()


func _on_start_run_pressed() -> void:
	_error_label.text = ""
	NetworkSession.request_start_run_from_local_peer()


func _on_play_offline_pressed() -> void:
	_error_label.text = ""
	if not NetworkSession.start_offline_run():
		_refresh_ui()


func _on_disconnect_pressed() -> void:
	_error_label.text = ""
	NetworkSession.disconnect_from_session()


func _on_transport_error(message: String) -> void:
	_error_label.text = message
	_refresh_ui()


func _on_registry_lookup_result(success: bool, message: String) -> void:
	if not success and not message.is_empty():
		_error_label.text = message
	elif success and (
		message.begins_with("Resolving")
		or message.begins_with("Finding")
		or message.begins_with("Found")
		or message.begins_with("Creating")
		or message.begins_with("Created")
	):
		_error_label.text = ""
	_refresh_ui()


func _on_session_state_changed(_previous_state: int, _current_state: int) -> void:
	_refresh_ui()


func _on_session_role_changed(_previous_role: int, _current_role: int) -> void:
	_refresh_ui()


func _on_peer_slot_map_changed(slot_map: Dictionary) -> void:
	_rebuild_peer_list(slot_map)
	_refresh_ui()


func _on_session_code_changed(_session_code: String) -> void:
	_refresh_ui()


func _on_lobby_ready_changed(_ready_map: Dictionary) -> void:
	_rebuild_peer_list(NetworkSession.get_peer_slot_map())
	_refresh_ui()


func _refresh_ui() -> void:
	var has_peer: bool = NetworkSession.has_active_peer()
	var is_lookup_pending: bool = NetworkSession.is_registry_lookup_in_progress()
	var is_create_pending: bool = NetworkSession.is_lobby_create_in_progress()
	var has_pending_request: bool = is_lookup_pending or is_create_pending
	var is_host: bool = (
		NetworkSession.session_role == NetworkSession.SessionRole.HOST
		or NetworkSession.session_role == NetworkSession.SessionRole.DEDICATED_SERVER
	)
	var is_dedicated: bool = NetworkSession.session_role == NetworkSession.SessionRole.DEDICATED_SERVER
	var in_lobby: bool = NetworkSession.session_state == NetworkSession.SessionState.LOBBY
	var is_connecting: bool = NetworkSession.session_state == NetworkSession.SessionState.CONNECTING
	var local_ready := NetworkSession.is_local_peer_ready()
	var ready_map: Dictionary = NetworkSession.get_lobby_ready_map()
	var slot_map: Dictionary = NetworkSession.get_peer_slot_map()
	var ready_total := slot_map.size()
	var ready_count := 0
	for key in slot_map.keys():
		if bool(ready_map.get(int(key), false)):
			ready_count += 1

	_host_button.disabled = has_peer or has_pending_request
	_join_code_button.disabled = has_peer or has_pending_request
	_start_run_button.visible = has_peer and in_lobby and not is_dedicated
	_start_run_button.disabled = not (has_peer and in_lobby and not is_dedicated)
	_ready_button.visible = has_peer and in_lobby and not is_dedicated
	_ready_button.disabled = not (has_peer and in_lobby and not is_dedicated)
	_ready_button.text = "Unready" if local_ready else "Ready"
	_play_offline_button.disabled = has_peer or has_pending_request
	_disconnect_button.disabled = not has_peer
	_session_code_input.editable = not (has_peer or has_pending_request)

	var session_code := NetworkSession.get_session_code().strip_edges().to_upper()
	_lobby_code_label.text = session_code if not session_code.is_empty() else "-"
	if is_host and not session_code.is_empty():
		_session_code_input.text = session_code

	var status := "State: %s | Role: %s" % [NetworkSession.get_state_name(), NetworkSession.get_role_name()]
	if has_peer:
		status += " | Local Peer: %s" % NetworkSession.get_local_peer_id()
	if in_lobby and ready_total > 0:
		status += " | Ready: %s/%s" % [ready_count, ready_total]
	if is_connecting:
		status += " (connecting...)"
	elif is_create_pending:
		status += " (creating lobby...)"
	elif is_lookup_pending:
		status += " (resolving session code...)"
	_status_label.text = status


func _rebuild_peer_list(slot_map: Dictionary) -> void:
	_peers_list.clear()
	var ready_map: Dictionary = NetworkSession.get_lobby_ready_map()
	if not NetworkSession.has_active_peer():
		_peers_list.add_item("Offline. Create a lobby or join by session code.")
		return
	if slot_map.is_empty():
		_peers_list.add_item("Connected. Waiting for peers...")
		return
	var peer_ids := slot_map.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var peer_id_int := int(peer_id)
		var slot := int(slot_map[peer_id])
		var tag := ""
		if peer_id_int == NetworkSession.get_local_peer_id():
			tag = " (you)"
		var ready_text := "READY" if bool(ready_map.get(peer_id_int, false)) else "NOT READY"
		_peers_list.add_item("Peer %s -> Slot %s | %s%s" % [peer_id_int, slot, ready_text, tag])
