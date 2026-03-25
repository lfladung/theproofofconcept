extends Node
class_name NetworkSessionService

signal state_changed(previous_state: int, current_state: int)
signal role_changed(previous_role: int, current_role: int)
signal peer_slot_map_changed(slot_map: Dictionary)
signal transport_error(message: String)

enum SessionState {
	OFFLINE,
	CONNECTING,
	LOBBY,
	IN_RUN,
}

enum SessionRole {
	NONE,
	HOST,
	CLIENT,
}

const DEFAULT_PORT := 7000
const DEFAULT_MAX_PLAYERS := 4
const LOBBY_SCENE_PATH := "res://scenes/ui/lobby_menu.tscn"
const RUN_SCENE_PATH := "res://dungeon/game/small_dungeon.tscn"

var session_state: int = SessionState.OFFLINE
var session_role: int = SessionRole.NONE
var host_peer_id := 1
var max_players := DEFAULT_MAX_PLAYERS

var _peer_slots: Dictionary = {}
var _intended_disconnect := false
var _queued_scene_path := ""


func _ready() -> void:
	_hard_reset_offline_boot_state()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func has_active_peer() -> bool:
	return multiplayer.multiplayer_peer != null


func get_peer_slot_map() -> Dictionary:
	return _peer_slots.duplicate(true)


func get_slot_for_peer(peer_id: int) -> int:
	return int(_peer_slots.get(peer_id, -1))


func get_local_peer_id() -> int:
	if not has_active_peer():
		return 1
	return multiplayer.get_unique_id()


func get_state_name() -> String:
	match session_state:
		SessionState.CONNECTING:
			return "CONNECTING"
		SessionState.LOBBY:
			return "LOBBY"
		SessionState.IN_RUN:
			return "IN_RUN"
		_:
			return "OFFLINE"


func get_role_name() -> String:
	match session_role:
		SessionRole.HOST:
			return "HOST"
		SessionRole.CLIENT:
			return "CLIENT"
		_:
			return "NONE"


func host_lobby(port: int = DEFAULT_PORT, wanted_max_players: int = DEFAULT_MAX_PLAYERS) -> bool:
	_disconnect_local_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, wanted_max_players)
	if err != OK:
		_emit_transport_error(_host_error_message(err, port))
		return false
	multiplayer.multiplayer_peer = peer
	max_players = max(1, wanted_max_players)
	host_peer_id = multiplayer.get_unique_id()
	_set_role(SessionRole.HOST)
	_set_state(SessionState.LOBBY)
	_peer_slots.clear()
	_peer_slots[host_peer_id] = 0
	_broadcast_slot_map_if_host()
	return true


func join_lobby(address: String, port: int = DEFAULT_PORT) -> bool:
	_disconnect_local_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_emit_transport_error(
			"Failed to join lobby at %s:%s (error %s)." % [address, port, err]
		)
		return false
	multiplayer.multiplayer_peer = peer
	_set_role(SessionRole.CLIENT)
	_set_state(SessionState.CONNECTING)
	_peer_slots.clear()
	return true


func disconnect_from_session() -> void:
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_emit_slot_map_changed()
	_queue_scene_change(LOBBY_SCENE_PATH)


func start_run() -> bool:
	if session_role != SessionRole.HOST:
		_emit_transport_error("Only the host can start a run.")
		return false
	if session_state != SessionState.LOBBY:
		_emit_transport_error("Run can only start from lobby state.")
		return false
	_rpc_set_session_state.rpc(SessionState.IN_RUN)
	_rpc_change_scene.rpc(RUN_SCENE_PATH)
	return true



func start_offline_run() -> bool:
	if has_active_peer():
		_emit_transport_error("Disconnect from multiplayer before starting offline.")
		return false
	_set_role(SessionRole.NONE)
	_set_state(SessionState.IN_RUN)
	_peer_slots.clear()
	_emit_slot_map_changed()
	_queue_scene_change(RUN_SCENE_PATH)
	return true

func return_to_lobby() -> bool:
	if session_role != SessionRole.HOST:
		_emit_transport_error("Only the host can return everyone to lobby.")
		return false
	if session_state != SessionState.IN_RUN:
		return false
	_rpc_set_session_state.rpc(SessionState.LOBBY)
	_rpc_change_scene.rpc(LOBBY_SCENE_PATH)
	return true


func request_leave_run_from_local_peer() -> void:
	if session_state != SessionState.IN_RUN:
		return
	if session_role == SessionRole.HOST:
		return_to_lobby()
	else:
		disconnect_from_session()


@rpc("authority", "call_local", "reliable")
func _rpc_set_session_state(new_state: int) -> void:
	_set_state(new_state)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_peer_slots(slot_map: Dictionary) -> void:
	_peer_slots = _normalize_slot_map(slot_map)
	_emit_slot_map_changed()


@rpc("authority", "call_local", "reliable")
func _rpc_change_scene(scene_path: String) -> void:
	_queue_scene_change(scene_path)


func _on_connected_to_server() -> void:
	if session_role == SessionRole.CLIENT:
		host_peer_id = 1
		_set_state(SessionState.LOBBY)


func _on_connection_failed() -> void:
	var message := "Connection to host failed."
	if not _intended_disconnect:
		_emit_transport_error(message)
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_emit_slot_map_changed()


func _on_server_disconnected() -> void:
	if _intended_disconnect:
		return
	_emit_transport_error("Disconnected from host.")
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_emit_slot_map_changed()
	_queue_scene_change(LOBBY_SCENE_PATH)


func _on_peer_connected(peer_id: int) -> void:
	if session_role != SessionRole.HOST:
		return
	if peer_id == host_peer_id:
		return
	_peer_slots[peer_id] = _next_available_slot()
	_broadcast_slot_map_if_host()
	if session_state == SessionState.IN_RUN:
		_rpc_set_session_state.rpc_id(peer_id, SessionState.IN_RUN)
		_rpc_change_scene.rpc_id(peer_id, RUN_SCENE_PATH)
	else:
		_rpc_set_session_state.rpc_id(peer_id, SessionState.LOBBY)
		_rpc_change_scene.rpc_id(peer_id, LOBBY_SCENE_PATH)


func _on_peer_disconnected(peer_id: int) -> void:
	if _peer_slots.has(peer_id):
		_peer_slots.erase(peer_id)
	if session_role == SessionRole.HOST:
		_broadcast_slot_map_if_host()
	else:
		_emit_slot_map_changed()


func _next_available_slot() -> int:
	var used := {}
	for slot in _peer_slots.values():
		used[int(slot)] = true
	for i in range(max_players):
		if not used.has(i):
			return i
	return max_players + _peer_slots.size()


func _broadcast_slot_map_if_host() -> void:
	if session_role != SessionRole.HOST:
		return
	_rpc_sync_peer_slots.rpc(_peer_slots)


func _normalize_slot_map(slot_map: Dictionary) -> Dictionary:
	var out := {}
	for key in slot_map.keys():
		out[int(key)] = int(slot_map[key])
	return out


func _disconnect_local_peer() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_intended_disconnect = true
	multiplayer.multiplayer_peer = null
	call_deferred("_clear_intended_disconnect")


func _clear_intended_disconnect() -> void:
	_intended_disconnect = false


func _queue_scene_change(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	_queued_scene_path = scene_path
	call_deferred("_deferred_change_scene")


func _deferred_change_scene() -> void:
	if _queued_scene_path.is_empty():
		return
	var scene_path := _queued_scene_path
	_queued_scene_path = ""
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == scene_path:
		return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		_emit_transport_error("Failed to change scene to '%s' (error %s)." % [scene_path, err])


func _set_state(new_state: int) -> void:
	if session_state == new_state:
		return
	var previous := session_state
	session_state = new_state
	state_changed.emit(previous, session_state)


func _set_role(new_role: int) -> void:
	if session_role == new_role:
		return
	var previous := session_role
	session_role = new_role
	role_changed.emit(previous, session_role)


func _emit_slot_map_changed() -> void:
	peer_slot_map_changed.emit(_peer_slots.duplicate(true))


func _emit_transport_error(message: String) -> void:
	transport_error.emit(message)




func _hard_reset_offline_boot_state() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_intended_disconnect = false
	_peer_slots.clear()
	session_state = SessionState.OFFLINE
	session_role = SessionRole.NONE
	host_peer_id = 1
	max_players = DEFAULT_MAX_PLAYERS

func _host_error_message(err: int, port: int) -> String:
	match err:
		ERR_ALREADY_IN_USE:
			return (
				"Failed to host on port %s: port already in use. "
				+ "Host in one instance only, and use Join in the other (or pick another port)."
			) % [port]
		ERR_CANT_CREATE:
			return (
				"Failed to host on port %s: ENet host creation failed. "
				+ "Another process may be using the port, or firewall/AV may be blocking it."
			) % [port]
		_:
			return "Failed to host lobby on port %s (error %s)." % [port, err]




