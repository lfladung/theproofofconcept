extends Control
class_name LobbyMenu

@onready var _address_input: LineEdit = $Center/Margin/VBox/AddressRow/AddressInput
@onready var _port_input: SpinBox = $Center/Margin/VBox/AddressRow/PortInput
@onready var _host_button: Button = $Center/Margin/VBox/ButtonRow/HostButton
@onready var _join_button: Button = $Center/Margin/VBox/ButtonRow/JoinButton
@onready var _start_run_button: Button = $Center/Margin/VBox/ButtonRow/StartRunButton
@onready var _play_offline_button: Button = $Center/Margin/VBox/ButtonRow/PlayOfflineButton
@onready var _disconnect_button: Button = $Center/Margin/VBox/ButtonRow/DisconnectButton
@onready var _status_label: Label = $Center/Margin/VBox/StatusLabel
@onready var _error_label: Label = $Center/Margin/VBox/ErrorLabel
@onready var _peers_list: ItemList = $Center/Margin/VBox/PeersList


func _ready() -> void:
	if _address_input.text.strip_edges().is_empty():
		_address_input.text = "127.0.0.1"
	_port_input.min_value = 1
	_port_input.max_value = 65535
	_port_input.value = NetworkSession.DEFAULT_PORT
	_error_label.text = ""
	
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_start_run_button.pressed.connect(_on_start_run_pressed)
	_play_offline_button.pressed.connect(_on_play_offline_pressed)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)
	
	NetworkSession.state_changed.connect(_on_session_state_changed)
	NetworkSession.role_changed.connect(_on_session_role_changed)
	NetworkSession.peer_slot_map_changed.connect(_on_peer_slot_map_changed)
	NetworkSession.transport_error.connect(_on_transport_error)
	
	_refresh_ui()
	_rebuild_peer_list(NetworkSession.get_peer_slot_map())


func _on_host_pressed() -> void:
	_error_label.text = ""
	var port := int(_port_input.value)
	if not NetworkSession.host_lobby(port, NetworkSession.DEFAULT_MAX_PLAYERS):
		_refresh_ui()


func _on_join_pressed() -> void:
	_error_label.text = ""
	var addr := _address_input.text.strip_edges()
	if addr.is_empty():
		_error_label.text = "Enter a host address first."
		return
	var port := int(_port_input.value)
	if not NetworkSession.join_lobby(addr, port):
		_refresh_ui()


func _on_start_run_pressed() -> void:
	_error_label.text = ""
	NetworkSession.start_run()



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


func _on_session_state_changed(_previous_state: int, _current_state: int) -> void:
	_refresh_ui()


func _on_session_role_changed(_previous_role: int, _current_role: int) -> void:
	_refresh_ui()


func _on_peer_slot_map_changed(slot_map: Dictionary) -> void:
	_rebuild_peer_list(slot_map)
	_refresh_ui()


func _refresh_ui() -> void:
	var has_peer: bool = NetworkSession.has_active_peer()
	var is_host: bool = NetworkSession.session_role == NetworkSession.SessionRole.HOST
	var in_lobby: bool = NetworkSession.session_state == NetworkSession.SessionState.LOBBY
	var is_connecting: bool = NetworkSession.session_state == NetworkSession.SessionState.CONNECTING
	
	_host_button.disabled = has_peer
	_join_button.disabled = has_peer
	_start_run_button.disabled = not (is_host and in_lobby)
	_play_offline_button.disabled = has_peer
	_disconnect_button.disabled = not has_peer
	
	var status := "State: %s | Role: %s" % [NetworkSession.get_state_name(), NetworkSession.get_role_name()]
	if has_peer:
		status += " | Local Peer: %s" % NetworkSession.get_local_peer_id()
	if is_connecting:
		status += " (connecting...)"
	_status_label.text = status


func _rebuild_peer_list(slot_map: Dictionary) -> void:
	_peers_list.clear()
	if not NetworkSession.has_active_peer():
		_peers_list.add_item("Offline. Click Host or Join to enter a lobby.")
		return
	if slot_map.is_empty():
		_peers_list.add_item("Connected. Waiting for peers...")
		return
	var peer_ids := slot_map.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var slot := int(slot_map[peer_id])
		var tag := ""
		if int(peer_id) == NetworkSession.get_local_peer_id():
			tag = " (you)"
		_peers_list.add_item("Peer %s -> Slot %s%s" % [peer_id, slot, tag])




