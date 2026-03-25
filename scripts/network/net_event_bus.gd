extends Node
class_name NetEventHub

signal session_state_changed(previous_state: int, current_state: int)
signal session_role_changed(previous_role: int, current_role: int)
signal lobby_peer_joined(peer_id: int, slot: int)
signal lobby_peer_left(peer_id: int, previous_slot: int)
signal lobby_slot_map_changed(slot_map: Dictionary)
signal network_error(message: String)

var _last_slot_map: Dictionary = {}


func _ready() -> void:
	var session := _session()
	if session == null:
		push_warning("NetEventBus could not find /root/NetworkSession.")
		return
	session.state_changed.connect(_on_session_state_changed)
	session.role_changed.connect(_on_session_role_changed)
	session.peer_slot_map_changed.connect(_on_slot_map_changed)
	session.transport_error.connect(_on_transport_error)


func request_host_lobby(port: int = 7000, max_players: int = 4) -> bool:
	var session := _session()
	return session.host_lobby(port, max_players) if session != null else false


func request_join_lobby(address: String, port: int = 7000) -> bool:
	var session := _session()
	return session.join_lobby(address, port) if session != null else false


func request_start_run() -> bool:
	var session := _session()
	return session.start_run() if session != null else false


func request_return_to_lobby() -> bool:
	var session := _session()
	return session.return_to_lobby() if session != null else false


func request_disconnect() -> void:
	var session := _session()
	if session != null:
		session.disconnect_from_session()


func _on_session_state_changed(previous_state: int, current_state: int) -> void:
	session_state_changed.emit(previous_state, current_state)


func _on_session_role_changed(previous_role: int, current_role: int) -> void:
	session_role_changed.emit(previous_role, current_role)


func _on_transport_error(message: String) -> void:
	network_error.emit(message)


func _on_slot_map_changed(slot_map: Dictionary) -> void:
	var normalized := _normalize_slot_map(slot_map)
	var prev := _last_slot_map
	for peer_id in normalized.keys():
		if not prev.has(peer_id):
			lobby_peer_joined.emit(peer_id, int(normalized[peer_id]))
	for peer_id in prev.keys():
		if not normalized.has(peer_id):
			lobby_peer_left.emit(peer_id, int(prev[peer_id]))
	_last_slot_map = normalized
	lobby_slot_map_changed.emit(_last_slot_map.duplicate(true))


func _normalize_slot_map(slot_map: Dictionary) -> Dictionary:
	var out := {}
	for key in slot_map.keys():
		out[int(key)] = int(slot_map[key])
	return out


func _session() -> NetworkSessionService:
	return get_node_or_null("/root/NetworkSession") as NetworkSessionService
