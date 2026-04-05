extends Node
class_name NetworkSessionService

signal state_changed(previous_state: int, current_state: int)
signal role_changed(previous_role: int, current_role: int)
signal peer_slot_map_changed(slot_map: Dictionary)
signal transport_error(message: String)
signal registry_lookup_result(success: bool, message: String)
signal session_code_changed(session_code: String)
signal lobby_ready_changed(ready_map: Dictionary)

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
	DEDICATED_SERVER,
}

const DEFAULT_PORT := 7000
const DEFAULT_MAX_PLAYERS := 4
const LOBBY_CODE_LENGTH := 6
const DEFAULT_REGISTRY_URL := "http://127.0.0.1:8787"
const LOBBY_SCENE_PATH := "res://scenes/ui/lobby_menu.tscn"
const RUN_SCENE_PATH := "res://dungeon/game/dungeon_orchestrator.tscn"

var session_state: int = SessionState.OFFLINE
var session_role: int = SessionRole.NONE
var host_peer_id := 1
var max_players := DEFAULT_MAX_PLAYERS
var dedicated_server_mode := false

var _peer_slots: Dictionary = {}
var _intended_disconnect := false
var _queued_scene_path := ""
var _include_host_in_slots := true
var _runtime_ready_peers: Dictionary = {}
var _lobby_ready_peers: Dictionary = {}

# Dedicated registry/session-directory support (optional).
var _registry_enabled := false
var _registry_url := ""
var _public_host := "127.0.0.1"
var _public_port := DEFAULT_PORT
var _instance_id := ""
var _session_code := ""
var _registry_heartbeat_seconds := 5.0
var _registry_started_unix := 0
var _registry_request: HTTPRequest = null
var _registry_timer: Timer = null
var _registry_request_in_flight := false
var _registry_retry_heartbeat := false

# Client-side session code resolve -> host/port join.
var _lookup_request: HTTPRequest = null
var _lookup_in_flight := false
var _lookup_code := ""
var _create_lobby_request: HTTPRequest = null
var _create_lobby_in_flight := false

# Dedicated runtime diagnostics (console logging).
var _server_diag_timer: Timer = null
var _server_diag_enabled := false
var _server_diag_interval_seconds := 5.0
var _dedicated_log_override_path := ""
var _dedicated_idle_shutdown_timer: Timer = null
var _dedicated_idle_shutdown_seconds := 20.0
var _dedicated_shutdown_pending := false
var _dedicated_unregister_sent := false
var _dedicated_had_player := false


func _ready() -> void:
	_hard_reset_offline_boot_state()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_try_bootstrap_dedicated_server()


func _exit_tree() -> void:
	if not _dedicated_shutdown_pending:
		_registry_unregister_best_effort()
	if _server_diag_timer != null:
		_server_diag_timer.stop()
	if _dedicated_idle_shutdown_timer != null:
		_dedicated_idle_shutdown_timer.stop()


func has_active_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return false
	return peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func get_peer_slot_map() -> Dictionary:
	return _peer_slots.duplicate(true)


func get_slot_for_peer(peer_id: int) -> int:
	return int(_peer_slots.get(peer_id, -1))



func can_broadcast_world_replication() -> bool:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return true
	if session_state != SessionState.IN_RUN:
		return false
	for key in _peer_slots.keys():
		var peer_id := int(key)
		if peer_id == host_peer_id:
			continue
		if not bool(_runtime_ready_peers.get(peer_id, false)):
			return false
	return true


func mark_runtime_scene_ready_local() -> void:
	if session_role != SessionRole.CLIENT:
		return
	if not has_active_peer():
		return
	_rpc_client_runtime_ready.rpc_id(host_peer_id)

func get_local_peer_id() -> int:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return 1
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
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
		SessionRole.DEDICATED_SERVER:
			return "DEDICATED_SERVER"
		_:
			return "NONE"


func get_session_code() -> String:
	return _session_code


func get_lobby_ready_map() -> Dictionary:
	return _lobby_ready_peers.duplicate(true)


func is_local_peer_ready() -> bool:
	return bool(_lobby_ready_peers.get(get_local_peer_id(), false))


func set_local_peer_ready(is_ready: bool) -> void:
	if session_state != SessionState.LOBBY:
		return
	if session_role == SessionRole.HOST or session_role == SessionRole.DEDICATED_SERVER:
		var local_peer := get_local_peer_id()
		if not _peer_slots.has(local_peer):
			return
		_lobby_ready_peers[local_peer] = is_ready
		_broadcast_lobby_ready_if_host()
		return
	if session_role != SessionRole.CLIENT or not has_active_peer():
		return
	_rpc_request_set_lobby_ready.rpc_id(host_peer_id, is_ready)


func toggle_local_peer_ready() -> void:
	set_local_peer_ready(not is_local_peer_ready())


func are_all_lobby_players_ready() -> bool:
	if _peer_slots.is_empty():
		return false
	for key in _peer_slots.keys():
		var peer_id := int(key)
		if not bool(_lobby_ready_peers.get(peer_id, false)):
			return false
	return true


func is_registry_lookup_in_progress() -> bool:
	return _lookup_in_flight


func is_lobby_create_in_progress() -> bool:
	return _create_lobby_in_flight


func request_lobby_from_registry(registry_url: String = "") -> bool:
	if has_active_peer():
		_emit_transport_error("Disconnect first before creating a lobby.")
		return false
	if _lookup_in_flight or _create_lobby_in_flight:
		_emit_transport_error("A session directory request is already in progress.")
		return false
	var base_url := registry_url.strip_edges()
	if base_url.is_empty():
		base_url = _cmdline_string_value("--registry_url=", DEFAULT_REGISTRY_URL)
	if base_url.is_empty():
		base_url = DEFAULT_REGISTRY_URL
	_ensure_create_lobby_request_node()
	var endpoint := "%s/v1/lobbies/create" % [base_url.trim_suffix("/")]
	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := {
		"max_players": max_players,
	}
	var err := _create_lobby_request.request(
		endpoint,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		_emit_transport_error("Failed to query session directory (error %s)." % [err])
		return false
	_create_lobby_in_flight = true
	_emit_registry_lookup_result(true, "Creating a lobby...")
	return true


func host_lobby(
	port: int = DEFAULT_PORT,
	wanted_max_players: int = DEFAULT_MAX_PLAYERS,
	include_host_in_slots: bool = true,
	as_dedicated_server: bool = false
) -> bool:
	_disconnect_local_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, wanted_max_players)
	if err != OK:
		_emit_transport_error(_host_error_message(err, port))
		return false
	multiplayer.multiplayer_peer = peer
	max_players = max(1, wanted_max_players)
	host_peer_id = multiplayer.get_unique_id()
	_include_host_in_slots = include_host_in_slots
	dedicated_server_mode = as_dedicated_server
	_set_role(SessionRole.DEDICATED_SERVER if as_dedicated_server else SessionRole.HOST)
	_set_state(SessionState.LOBBY)
	_session_code = _random_session_code()
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	if _include_host_in_slots:
		_peer_slots[host_peer_id] = 0
		_runtime_ready_peers[host_peer_id] = true
		_lobby_ready_peers[host_peer_id] = false
	_broadcast_slot_map_if_host()
	_broadcast_session_code_if_host()
	_broadcast_lobby_ready_if_host()
	if as_dedicated_server:
		_public_port = port
		_enable_dedicated_diagnostics(port)
	else:
		_registry_configure_for_player_host(port, wanted_max_players)
		_registry_register_instance()
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
	dedicated_server_mode = false
	_include_host_in_slots = true
	_set_role(SessionRole.CLIENT)
	_set_state(SessionState.CONNECTING)
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	_session_code = ""
	_emit_session_code_changed()
	_emit_lobby_ready_changed()
	return true


func join_lobby_via_session_code(session_code: String, registry_url: String = "") -> bool:
	if has_active_peer():
		_emit_transport_error("Disconnect first before joining by session code.")
		return false
	if _lookup_in_flight:
		_emit_transport_error("Session code lookup already in progress.")
		return false
	var code := session_code.strip_edges().to_upper()
	if code.is_empty():
		_emit_transport_error("Enter a session code first.")
		return false
	var base_url := registry_url.strip_edges()
	if base_url.is_empty():
		base_url = _cmdline_string_value("--registry_url=", DEFAULT_REGISTRY_URL)
	if base_url.is_empty():
		base_url = DEFAULT_REGISTRY_URL
	_ensure_lookup_request_node()
	var endpoint := "%s/v1/instances/resolve?code=%s" % [base_url.trim_suffix("/"), code.uri_encode()]
	var err := _lookup_request.request(endpoint, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		_emit_transport_error("Failed to query session directory (error %s)." % [err])
		return false
	_lookup_in_flight = true
	_lookup_code = code
	_emit_registry_lookup_result(true, "Resolving session code %s..." % [code])
	return true


func disconnect_from_session() -> void:
	_registry_unregister_best_effort()
	_registry_enabled = false
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	_session_code = ""
	_emit_session_code_changed()
	_emit_lobby_ready_changed()
	_emit_slot_map_changed()
	_queue_scene_change(LOBBY_SCENE_PATH)


func start_run() -> bool:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		_emit_transport_error("Only the host/server can start a run.")
		return false
	if session_state != SessionState.LOBBY:
		_emit_transport_error("Run can only start from lobby state.")
		return false
	if not are_all_lobby_players_ready():
		_emit_transport_error("All players must be ready before the run begins.")
		return false
	_mark_all_remote_runtime_not_ready_for_run()
	_rpc_set_session_state.rpc(SessionState.IN_RUN)
	_rpc_change_scene.rpc(RUN_SCENE_PATH)
	_registry_send_heartbeat()
	return true


func request_start_run_from_local_peer() -> void:
	if session_state != SessionState.LOBBY:
		return
	if session_role == SessionRole.HOST or session_role == SessionRole.DEDICATED_SERVER:
		start_run()
		return
	if session_role == SessionRole.CLIENT and has_active_peer():
		_rpc_request_start_run.rpc_id(host_peer_id)


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
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		_emit_transport_error("Only the host/server can return everyone to lobby.")
		return false
	if session_state != SessionState.IN_RUN:
		return false
	_rpc_set_session_state.rpc(SessionState.LOBBY)
	_rpc_change_scene.rpc(LOBBY_SCENE_PATH)
	_runtime_ready_peers.clear()
	if _include_host_in_slots:
		_runtime_ready_peers[host_peer_id] = true
	for key in _peer_slots.keys():
		_lobby_ready_peers[int(key)] = false
	_broadcast_lobby_ready_if_host()
	_registry_send_heartbeat()
	return true


func request_leave_run_from_local_peer() -> void:
	if session_state != SessionState.IN_RUN:
		return
	if session_role == SessionRole.HOST:
		return_to_lobby()
	elif session_role == SessionRole.DEDICATED_SERVER:
		return
	else:
		disconnect_from_session()


func is_dedicated_server() -> bool:
	return dedicated_server_mode and session_role == SessionRole.DEDICATED_SERVER


@rpc("authority", "call_local", "reliable")
func _rpc_set_session_state(new_state: int) -> void:
	_set_state(new_state)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_peer_slots(slot_map: Dictionary) -> void:
	_peer_slots = _normalize_slot_map(slot_map)
	_reconcile_lobby_ready_with_slot_map()
	_emit_lobby_ready_changed()
	_emit_slot_map_changed()


@rpc("authority", "call_local", "reliable")
func _rpc_change_scene(scene_path: String) -> void:
	_queue_scene_change(scene_path)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_session_code(session_code: String) -> void:
	_session_code = session_code.strip_edges().to_upper()
	_emit_session_code_changed()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby_ready(ready_map: Dictionary) -> void:
	_lobby_ready_peers = _normalize_ready_map(ready_map)
	_reconcile_lobby_ready_with_slot_map()
	_emit_lobby_ready_changed()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_set_lobby_ready(is_ready: bool) -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if session_state != SessionState.LOBBY:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer <= 0 or not _peer_slots.has(sender_peer):
		return
	_lobby_ready_peers[sender_peer] = is_ready
	_broadcast_lobby_ready_if_host()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_start_run() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if session_state != SessionState.LOBBY:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer <= 0 or not _peer_slots.has(sender_peer):
		return
	start_run()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_runtime_ready() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer <= 0:
		return
	_runtime_ready_peers[sender_peer] = true
	if dedicated_server_mode:
		_dedicated_log("peer_runtime_ready peer=%s slots=%s" % [sender_peer, _slot_map_debug_string()])


func _on_connected_to_server() -> void:
	if session_role == SessionRole.CLIENT:
		host_peer_id = 1
		_lobby_ready_peers.clear()
		_emit_lobby_ready_changed()
		_set_state(SessionState.LOBBY)


func _on_connection_failed() -> void:
	var message := "Connection to host failed."
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	_session_code = ""
	_emit_session_code_changed()
	_emit_lobby_ready_changed()
	_emit_slot_map_changed()
	if not _intended_disconnect:
		_emit_transport_error(message)


func _on_server_disconnected() -> void:
	if _intended_disconnect:
		return
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	_session_code = ""
	_emit_session_code_changed()
	_emit_lobby_ready_changed()
	_emit_slot_map_changed()
	_queue_scene_change(LOBBY_SCENE_PATH)
	_emit_transport_error("Disconnected from host.")


func _on_peer_connected(peer_id: int) -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if _include_host_in_slots and peer_id == host_peer_id:
		_runtime_ready_peers[peer_id] = true
		return
	_peer_slots[peer_id] = _next_available_slot()
	_runtime_ready_peers[peer_id] = false
	_lobby_ready_peers[peer_id] = false
	_broadcast_slot_map_if_host()
	_broadcast_session_code_if_host()
	_broadcast_lobby_ready_if_host()
	if session_state == SessionState.IN_RUN:
		_rpc_set_session_state.rpc_id(peer_id, SessionState.IN_RUN)
		_rpc_change_scene.rpc_id(peer_id, RUN_SCENE_PATH)
	else:
		_rpc_set_session_state.rpc_id(peer_id, SessionState.LOBBY)
		_rpc_change_scene.rpc_id(peer_id, LOBBY_SCENE_PATH)
	if dedicated_server_mode:
		_dedicated_had_player = true
		_cancel_dedicated_idle_shutdown("peer_connected=%s" % [peer_id])
		_dedicated_log("peer_connected peer=%s slot=%s slots=%s" % [peer_id, int(_peer_slots.get(peer_id, -1)), _slot_map_debug_string()])
	_registry_send_heartbeat()


func _on_peer_disconnected(peer_id: int) -> void:
	_runtime_ready_peers.erase(peer_id)
	_lobby_ready_peers.erase(peer_id)
	if _peer_slots.has(peer_id):
		_peer_slots.erase(peer_id)
	if session_role == SessionRole.HOST or session_role == SessionRole.DEDICATED_SERVER:
		_broadcast_slot_map_if_host()
		_broadcast_lobby_ready_if_host()
	else:
		_emit_slot_map_changed()
	if dedicated_server_mode:
		_dedicated_log("peer_disconnected peer=%s slots=%s" % [peer_id, _slot_map_debug_string()])
		if _peer_slots.is_empty():
			_schedule_dedicated_idle_shutdown("all_players_left")
	_registry_send_heartbeat()


func _next_available_slot() -> int:
	var used := {}
	for slot in _peer_slots.values():
		used[int(slot)] = true
	for i in range(max_players):
		if not used.has(i):
			return i
	return max_players + _peer_slots.size()



func _mark_all_remote_runtime_not_ready_for_run() -> void:
	for key in _peer_slots.keys():
		var peer_id := int(key)
		if peer_id == host_peer_id:
			_runtime_ready_peers[peer_id] = true
		else:
			_runtime_ready_peers[peer_id] = false


func _normalize_ready_map(ready_map: Dictionary) -> Dictionary:
	var out := {}
	for key in ready_map.keys():
		out[int(key)] = bool(ready_map[key])
	return out


func _reconcile_lobby_ready_with_slot_map() -> void:
	var normalized := {}
	for key in _peer_slots.keys():
		var peer_id := int(key)
		normalized[peer_id] = bool(_lobby_ready_peers.get(peer_id, false))
	_lobby_ready_peers = normalized


func _broadcast_lobby_ready_if_host() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	_reconcile_lobby_ready_with_slot_map()
	_rpc_sync_lobby_ready.rpc(_lobby_ready_peers)
	_emit_lobby_ready_changed()


func _broadcast_session_code_if_host() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	_rpc_sync_session_code.rpc(_session_code)
	_emit_session_code_changed()


func _try_auto_start_when_all_ready() -> void:
	if session_state != SessionState.LOBBY:
		return
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if not are_all_lobby_players_ready():
		return
	start_run()


func _registry_configure_for_player_host(port: int, wanted_max_players: int) -> void:
	_registry_enabled = true
	_registry_url = _cmdline_string_value("--registry_url=", DEFAULT_REGISTRY_URL).strip_edges()
	if _registry_url.is_empty():
		_registry_url = DEFAULT_REGISTRY_URL
	_public_host = _cmdline_string_value("--public_host=", _best_registry_public_host())
	_public_port = port
	_instance_id = "host_%s_%s" % [host_peer_id, Time.get_unix_time_from_system()]
	_registry_heartbeat_seconds = maxf(1.0, float(_cmdline_int_value("--registry_heartbeat_ms=", 5000)) / 1000.0)
	_registry_started_unix = int(Time.get_unix_time_from_system())
	max_players = max(1, wanted_max_players)
	_ensure_registry_nodes()
	_registry_timer.wait_time = _registry_heartbeat_seconds
	_registry_timer.start()


func _best_registry_public_host() -> String:
	for raw in IP.get_local_addresses():
		var host := String(raw)
		if host.is_empty() or host == "127.0.0.1" or host == "::1":
			continue
		if host.contains(":"):
			continue
		return host
	return "127.0.0.1"
func _broadcast_slot_map_if_host() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
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
	if scene_path == RUN_SCENE_PATH:
		var overlay := get_node_or_null("/root/LoadingOverlay")
		if overlay != null and overlay.has_method("show_loading"):
			overlay.call("show_loading")
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


func _emit_session_code_changed() -> void:
	session_code_changed.emit(_session_code)


func _emit_lobby_ready_changed() -> void:
	lobby_ready_changed.emit(_lobby_ready_peers.duplicate(true))

func _emit_transport_error(message: String) -> void:
	if dedicated_server_mode or _is_dedicated_cmdline():
		var line := "[DedicatedServer][transport_error] %s" % [message]
		print(line)
		_append_dedicated_log_file(line)
	else:
		push_warning("[NetworkSession] %s" % [message])
	transport_error.emit(message)


func _emit_registry_lookup_result(success: bool, message: String) -> void:
	registry_lookup_result.emit(success, message)


func _hard_reset_offline_boot_state() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_intended_disconnect = false
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	dedicated_server_mode = false
	_include_host_in_slots = true
	session_state = SessionState.OFFLINE
	session_role = SessionRole.NONE
	host_peer_id = 1
	max_players = DEFAULT_MAX_PLAYERS
	_registry_enabled = false
	_registry_url = ""
	_public_host = "127.0.0.1"
	_public_port = DEFAULT_PORT
	_instance_id = ""
	_session_code = ""
	_registry_heartbeat_seconds = 5.0
	_registry_started_unix = 0
	_registry_request_in_flight = false
	_registry_retry_heartbeat = false
	if _registry_timer != null:
		_registry_timer.stop()
	if _server_diag_timer != null:
		_server_diag_timer.stop()
	if _dedicated_idle_shutdown_timer != null:
		_dedicated_idle_shutdown_timer.stop()
	_server_diag_enabled = false
	_server_diag_interval_seconds = 5.0
	_dedicated_log_override_path = ""
	_dedicated_idle_shutdown_seconds = 20.0
	_dedicated_shutdown_pending = false
	_dedicated_unregister_sent = false
	_dedicated_had_player = false
	_lookup_in_flight = false
	_lookup_code = ""
	_create_lobby_in_flight = false


func _try_bootstrap_dedicated_server() -> void:
	if not _is_dedicated_cmdline():
		return
	var port := _cmdline_int_value("--port=", DEFAULT_PORT)
	var wanted_max_players := _cmdline_int_value("--max_players=", DEFAULT_MAX_PLAYERS)
	var auto_start_run := _cmdline_bool_value("--start_in_run=", false)
	_dedicated_idle_shutdown_seconds = maxf(5.0, float(_cmdline_int_value("--empty_shutdown_seconds=", 20)))
	var requested_log_path := _cmdline_string_value("--dedicated_log_file=", "").strip_edges()
	if not requested_log_path.is_empty():
		_dedicated_log_override_path = ProjectSettings.globalize_path(requested_log_path)
	if not host_lobby(port, wanted_max_players, false, true):
		return
	_registry_configure_for_dedicated(port, wanted_max_players)
	_registry_register_instance()
	if auto_start_run:
		start_run()



func _all_cmdline_args() -> Array[String]:
	var merged: Array[String] = []
	for raw in OS.get_cmdline_args():
		merged.append(String(raw))
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		if not merged.has(arg):
			merged.append(arg)
	return merged


func _is_dedicated_cmdline() -> bool:
	var args := _all_cmdline_args()
	for raw in args:
		var arg := String(raw)
		if arg == "--dedicated_server" or arg == "--server" or arg == "--dedicated":
			return true
	return OS.has_feature("dedicated_server")


func _cmdline_int_value(prefix: String, fallback: int) -> int:
	var args := _all_cmdline_args()
	for raw in args:
		var arg := String(raw)
		if arg.begins_with(prefix):
			var tail := arg.trim_prefix(prefix)
			if tail.is_valid_int():
				return int(tail)
	return fallback


func _cmdline_bool_value(prefix: String, fallback: bool) -> bool:
	var args := _all_cmdline_args()
	for raw in args:
		var arg := String(raw)
		if not arg.begins_with(prefix):
			continue
		var tail := arg.trim_prefix(prefix).to_lower()
		if tail in ["1", "true", "yes", "on"]:
			return true
		if tail in ["0", "false", "no", "off"]:
			return false
	return fallback


func _cmdline_string_value(prefix: String, fallback: String) -> String:
	var args := _all_cmdline_args()
	for raw in args:
		var arg := String(raw)
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


func _registry_configure_for_dedicated(port: int, wanted_max_players: int) -> void:
	var configured_registry := _cmdline_string_value("--registry_url=", "")
	if configured_registry.is_empty():
		return
	_registry_enabled = true
	_registry_url = configured_registry if not configured_registry.is_empty() else DEFAULT_REGISTRY_URL
	_public_host = _cmdline_string_value("--public_host=", "127.0.0.1")
	_public_port = port
	_instance_id = _cmdline_string_value("--instance_id=", "inst_%s" % [Time.get_unix_time_from_system()])
	_session_code = _cmdline_string_value("--session_code=", _random_session_code())
	_registry_heartbeat_seconds = maxf(
		1.0,
		float(_cmdline_int_value("--registry_heartbeat_ms=", 5000)) / 1000.0
	)
	_registry_started_unix = int(Time.get_unix_time_from_system())
	max_players = max(1, wanted_max_players)
	_ensure_registry_nodes()
	_registry_timer.wait_time = _registry_heartbeat_seconds
	_registry_timer.start()
	print(
		"[DedicatedRegistry] enabled url=%s code=%s host=%s port=%s" % [
			_registry_url,
			_session_code,
			_public_host,
			_public_port,
		]
	)


func _ensure_registry_nodes() -> void:
	if _registry_request == null:
		_registry_request = HTTPRequest.new()
		_registry_request.name = "RegistryRequest"
		add_child(_registry_request)
		_registry_request.request_completed.connect(_on_registry_request_completed)
	if _registry_timer == null:
		_registry_timer = Timer.new()
		_registry_timer.name = "RegistryHeartbeatTimer"
		_registry_timer.one_shot = false
		add_child(_registry_timer)
		_registry_timer.timeout.connect(_on_registry_heartbeat_timer_timeout)


func _ensure_lookup_request_node() -> void:
	if _lookup_request != null:
		return
	_lookup_request = HTTPRequest.new()
	_lookup_request.name = "SessionLookupRequest"
	add_child(_lookup_request)
	_lookup_request.request_completed.connect(_on_lookup_request_completed)


func _ensure_create_lobby_request_node() -> void:
	if _create_lobby_request != null:
		return
	_create_lobby_request = HTTPRequest.new()
	_create_lobby_request.name = "SessionCreateRequest"
	add_child(_create_lobby_request)
	_create_lobby_request.request_completed.connect(_on_create_lobby_request_completed)


func _random_session_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in range(LOBBY_CODE_LENGTH):
		out += chars[rng.randi_range(0, chars.length() - 1)]
	return out


func _registry_register_instance() -> void:
	if not _registry_enabled:
		return
	_registry_post(
		"/v1/instances/register",
		{
			"instance_id": _instance_id,
			"session_code": _session_code,
			"host": _public_host,
			"port": _public_port,
			"max_players": max_players,
			"current_players": _peer_slots.size(),
			"state": get_state_name(),
			"started_unix": _registry_started_unix,
		}
	)


func _registry_send_heartbeat() -> void:
	if not _registry_enabled:
		return
	if _registry_request_in_flight:
		_registry_retry_heartbeat = true
		return
	_registry_post(
		"/v1/instances/heartbeat",
		{
			"instance_id": _instance_id,
			"session_code": _session_code,
			"current_players": _peer_slots.size(),
			"max_players": max_players,
			"state": get_state_name(),
		}
	)


func _registry_unregister_best_effort() -> void:
	if not _registry_enabled or _instance_id.is_empty():
		return
	if _registry_request_in_flight:
		return
	_registry_post(
		"/v1/instances/unregister",
		{
			"instance_id": _instance_id,
			"session_code": _session_code,
		}
	)


func _registry_post(path: String, payload: Dictionary) -> void:
	if not _registry_enabled:
		return
	if not is_inside_tree():
		return
	_ensure_registry_nodes()
	if _registry_request_in_flight:
		return
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := "%s%s" % [_registry_url.trim_suffix("/"), path]
	var body := JSON.stringify(payload)
	var err := _registry_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("[DedicatedRegistry] request failed (%s): %s" % [err, url])
		return
	_registry_request_in_flight = true


func _on_registry_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	_registry_request_in_flight = false
	if response_code < 200 or response_code >= 300:
		push_warning("[DedicatedRegistry] HTTP %s from registry." % [response_code])
	if _dedicated_shutdown_pending:
		_try_unregister_then_quit_dedicated()
		return
	if _registry_retry_heartbeat:
		_registry_retry_heartbeat = false
		_registry_send_heartbeat()


func _on_registry_heartbeat_timer_timeout() -> void:
	_registry_send_heartbeat()


func _on_lookup_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_lookup_in_flight = false
	if response_code < 200 or response_code >= 300:
		var lookup_error := "Session code %s was not found." % [_lookup_code]
		if response_code != 404:
			lookup_error = "Session directory request failed (HTTP %s)." % [response_code]
		_emit_transport_error(lookup_error)
		_emit_registry_lookup_result(false, lookup_error)
		return
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if parsed is not Dictionary:
		var parse_error := "Session directory returned invalid JSON payload."
		_emit_transport_error(parse_error)
		_emit_registry_lookup_result(false, parse_error)
		return
	var payload := parsed as Dictionary
	if not bool(payload.get("ok", false)):
		var payload_error := "Session code %s was not found." % [_lookup_code]
		if payload.has("error"):
			payload_error = "Session directory error: %s" % [String(payload.get("error", "unknown"))]
		_emit_transport_error(payload_error)
		_emit_registry_lookup_result(false, payload_error)
		return
	var join_variant: Variant = payload.get("join", {})
	if join_variant is not Dictionary:
		var join_error := "Session directory response is missing join endpoint info."
		_emit_transport_error(join_error)
		_emit_registry_lookup_result(false, join_error)
		return
	var join_data := join_variant as Dictionary
	var host := String(join_data.get("host", "")).strip_edges()
	var port := int(join_data.get("port", DEFAULT_PORT))
	if host.is_empty() or port <= 0:
		var endpoint_error := "Session directory returned an invalid endpoint."
		_emit_transport_error(endpoint_error)
		_emit_registry_lookup_result(false, endpoint_error)
		return
	_emit_registry_lookup_result(true, "Resolved %s -> %s:%s" % [_lookup_code, host, port])
	if not join_lobby(host, port):
		_emit_registry_lookup_result(false, "Resolved endpoint, but failed to join lobby.")




func _on_create_lobby_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_create_lobby_in_flight = false
	if response_code < 200 or response_code >= 300:
		var create_error := "Session directory request failed (HTTP %s)." % [response_code]
		_emit_transport_error(create_error)
		_emit_registry_lookup_result(false, create_error)
		return
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if parsed is not Dictionary:
		var parse_error := "Session directory returned invalid JSON payload."
		_emit_transport_error(parse_error)
		_emit_registry_lookup_result(false, parse_error)
		return
	var payload := parsed as Dictionary
	if not bool(payload.get("ok", false)):
		var payload_error := "Session directory did not return a valid lobby list."
		if payload.has("error"):
			payload_error = "Session directory error: %s" % [String(payload.get("error", "unknown"))]
		_emit_transport_error(payload_error)
		_emit_registry_lookup_result(false, payload_error)
		return
	var join_variant: Variant = payload.get("join", {})
	if join_variant is not Dictionary:
		var join_error := "Session directory response is missing join endpoint info."
		_emit_transport_error(join_error)
		_emit_registry_lookup_result(false, join_error)
		return
	var join_data := join_variant as Dictionary
	var host := String(join_data.get("host", "")).strip_edges()
	var port := int(join_data.get("port", DEFAULT_PORT))
	var code := String(payload.get("session_code", "")).strip_edges().to_upper()
	if code.is_empty():
		var instance_variant: Variant = payload.get("instance", {})
		if instance_variant is Dictionary:
			code = String((instance_variant as Dictionary).get("session_code", "")).strip_edges().to_upper()
	if host.is_empty() or port <= 0:
		var endpoint_error := "Session directory returned an invalid lobby endpoint."
		_emit_transport_error(endpoint_error)
		_emit_registry_lookup_result(false, endpoint_error)
		return
	if not code.is_empty():
		_session_code = code
		_emit_session_code_changed()
	_emit_registry_lookup_result(
		true,
		"Created lobby %s. Joining..." % [code if not code.is_empty() else "(code pending)"]
	)
	if not join_lobby(host, port):
		_emit_registry_lookup_result(false, "Found lobby, but failed to join.")


func _pick_registry_lobby_candidate(instances: Array) -> Dictionary:
	var chosen: Dictionary = {}
	var has_choice := false
	var chosen_players := 0
	var chosen_is_empty := false
	for entry in instances:
		if entry is not Dictionary:
			continue
		var row := entry as Dictionary
		var state := String(row.get("state", "")).strip_edges().to_upper()
		var current_players := int(row.get("current_players", 0))
		var row_max_players := int(row.get("max_players", 0))
		if state != "LOBBY":
			continue
		if row_max_players <= 0:
			continue
		if current_players >= row_max_players:
			continue
		var row_is_empty := current_players <= 0
		if not has_choice:
			chosen = row
			has_choice = true
			chosen_players = current_players
			chosen_is_empty = row_is_empty
			continue
		if row_is_empty and not chosen_is_empty:
			chosen = row
			chosen_players = current_players
			chosen_is_empty = true
			continue
		if row_is_empty == chosen_is_empty and current_players < chosen_players:
			chosen = row
			chosen_players = current_players
	return chosen


func _enable_dedicated_diagnostics(port: int) -> void:
	_server_diag_enabled = true
	_server_diag_interval_seconds = maxf(
		1.0,
		float(_cmdline_int_value("--server_log_interval_ms=", 5000)) / 1000.0
	)
	_ensure_server_diag_timer()
	_server_diag_timer.wait_time = _server_diag_interval_seconds
	_server_diag_timer.start()
	_dedicated_log(
		"boot state=%s port=%s max_players=%s session_code=%s registry=%s log=%s idle_shutdown=%ss" % [
			get_state_name(),
			port,
			max_players,
			_session_code if not _session_code.is_empty() else "(pending)",
			_registry_enabled,
			_dedicated_log_file_path(),
			_dedicated_idle_shutdown_seconds,
		]
	)
	if _peer_slots.is_empty():
		_schedule_dedicated_idle_shutdown("boot_empty")


func _ensure_server_diag_timer() -> void:
	if _server_diag_timer != null:
		return
	_server_diag_timer = Timer.new()
	_server_diag_timer.name = "DedicatedDiagTimer"
	_server_diag_timer.one_shot = false
	add_child(_server_diag_timer)
	_server_diag_timer.timeout.connect(_on_server_diag_timer_timeout)


func _on_server_diag_timer_timeout() -> void:
	if not _server_diag_enabled:
		return
	var peer := multiplayer.multiplayer_peer
	var status_text := "no_peer"
	if peer != null:
		status_text = str(peer.get_connection_status())
	_dedicated_log(
		"alive state=%s peers=%s slots=%s conn_status=%s" % [
			get_state_name(),
			_peer_slots.size(),
			_slot_map_debug_string(),
			status_text,
		]
	)


func _ensure_dedicated_idle_shutdown_timer() -> void:
	if _dedicated_idle_shutdown_timer != null:
		return
	_dedicated_idle_shutdown_timer = Timer.new()
	_dedicated_idle_shutdown_timer.name = "DedicatedIdleShutdownTimer"
	_dedicated_idle_shutdown_timer.one_shot = true
	add_child(_dedicated_idle_shutdown_timer)
	_dedicated_idle_shutdown_timer.timeout.connect(_on_dedicated_idle_shutdown_timeout)


func _cancel_dedicated_idle_shutdown(reason: String = "") -> void:
	if _dedicated_idle_shutdown_timer == null:
		return
	if _dedicated_idle_shutdown_timer.is_stopped():
		return
	_dedicated_idle_shutdown_timer.stop()
	if not reason.is_empty():
		_dedicated_log("idle_shutdown_cancelled reason=%s" % [reason])


func _schedule_dedicated_idle_shutdown(reason: String) -> void:
	if not dedicated_server_mode:
		return
	if not _peer_slots.is_empty():
		return
	if _dedicated_shutdown_pending:
		return
	_ensure_dedicated_idle_shutdown_timer()
	_dedicated_idle_shutdown_timer.wait_time = _dedicated_idle_shutdown_seconds
	_dedicated_idle_shutdown_timer.start()
	_dedicated_log(
		"idle_shutdown_scheduled in=%ss reason=%s had_player=%s" % [
			_dedicated_idle_shutdown_seconds,
			reason,
			_dedicated_had_player,
		]
	)


func _on_dedicated_idle_shutdown_timeout() -> void:
	if not dedicated_server_mode:
		return
	if not _peer_slots.is_empty():
		return
	_dedicated_shutdown_pending = true
	_dedicated_unregister_sent = false
	_dedicated_log(
		"idle_shutdown_triggered peers=0 had_player=%s state=%s" % [
			_dedicated_had_player,
			get_state_name(),
		]
	)
	_try_unregister_then_quit_dedicated()


func _try_unregister_then_quit_dedicated() -> void:
	if not _dedicated_shutdown_pending:
		return
	if _registry_enabled and not _instance_id.is_empty():
		if _registry_request_in_flight:
			return
		if not _dedicated_unregister_sent:
			_dedicated_unregister_sent = true
			_registry_post(
				"/v1/instances/unregister",
				{
					"instance_id": _instance_id,
					"session_code": _session_code,
				}
			)
			if _registry_request_in_flight:
				return
	_dedicated_log("shutdown_exit")
	get_tree().quit()


func _slot_map_debug_string() -> String:
	if _peer_slots.is_empty():
		return "{}"
	var keys: Array = _peer_slots.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key in keys:
		var peer_id := int(key)
		var slot := int(_peer_slots[key])
		parts.append("%s:%s" % [peer_id, slot])
	return "{%s}" % ",".join(parts)


func _dedicated_log(message: String) -> void:
	if not dedicated_server_mode and not _server_diag_enabled:
		return
	var stamp := str(Time.get_unix_time_from_system())
	var line := "[DedicatedServer][%s] %s" % [stamp, message]
	print(line)
	_append_dedicated_log_file(line)


func _dedicated_log_file_path() -> String:
	if not _dedicated_log_override_path.is_empty():
		return _dedicated_log_override_path
	var user_dir := OS.get_user_data_dir()
	if user_dir.is_empty():
		return "user://dedicated_server.log"
	return user_dir.path_join("dedicated_server.log")


func _append_dedicated_log_file(line: String) -> void:
	var log_path := _dedicated_log_file_path()
	var base_dir := log_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		var create_file := FileAccess.open(log_path, FileAccess.WRITE)
		if create_file == null:
			return
		create_file.close()
		file = FileAccess.open(log_path, FileAccess.READ_WRITE)
		if file == null:
			return
	file.seek_end()
	file.store_line(line)
	file.close()


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
