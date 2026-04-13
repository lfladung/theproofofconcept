extends Node
class_name NetworkSessionService

signal state_changed(previous_state: int, current_state: int)
signal role_changed(previous_role: int, current_role: int)
signal peer_slot_map_changed(slot_map: Dictionary)
signal transport_error(message: String)
signal registry_lookup_result(success: bool, message: String)
signal session_code_changed(session_code: String)
signal lobby_ready_changed(ready_map: Dictionary)
signal mission_state_changed(snapshot: Dictionary)
signal party_state_changed(snapshot: Dictionary)

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

enum MissionFlowPhase {
	NONE,
	HUB,
	SELECT,
	STAGING,
}

const DEFAULT_PORT := 7000
const HUB_MAX_PLAYERS := 6
const RUN_MAX_PLAYERS := 4
const DEFAULT_MAX_PLAYERS := RUN_MAX_PLAYERS
const LOBBY_CODE_LENGTH := 6
const DEFAULT_REGISTRY_URL := "http://127.0.0.1:8787"
const LOBBY_SCENE_PATH := "res://scenes/ui/lobby_menu.tscn"
const HUB_SCENE_PATH := "res://scenes/hub/hub_world.tscn"
const RUN_SCENE_PATH := "res://dungeon/game/dungeon_orchestrator.tscn"
const MissionRegistryRef = preload("res://scripts/missions/mission_registry.gd")
const MissionLaunchResolverRef = preload("res://scripts/missions/mission_launch_resolver.gd")

var session_state: int = SessionState.OFFLINE
var session_role: int = SessionRole.NONE
var host_peer_id := 1
var max_players := DEFAULT_MAX_PLAYERS
var dedicated_server_mode := false

var _peer_slots: Dictionary = {}
var _intended_disconnect := false
var _queued_scene_path := ""
var _scene_transfer_in_progress := false
var _scene_transfer_token := 0
var _include_host_in_slots := true
var _runtime_ready_peers: Dictionary = {}
var _lobby_ready_peers: Dictionary = {}
var _selected_mission_id: StringName = &""
var _mission_flow_phase: int = MissionFlowPhase.NONE

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
var _party_request: HTTPRequest = null
var _party_request_in_flight := false
var _party_request_context := ""
var _party_code := ""
var _party_member_id := ""
var _party_snapshot: Dictionary = {}
var _party_selected_mission_id: StringName = &""
var _party_ready := false
var _instance_kind := "hub"
var _fallback_to_hub_scene_on_registry_failure := false

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
	if _scene_transfer_in_progress:
		return false
	if session_state == SessionState.CONNECTING or session_state == SessionState.OFFLINE:
		return false
	if session_role == SessionRole.CLIENT:
		return (
			(session_state == SessionState.LOBBY or session_state == SessionState.IN_RUN)
			and _peer_slots.has(get_local_peer_id())
		)
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return true
	for key in _peer_slots.keys():
		var peer_id := int(key)
		if peer_id == host_peer_id:
			continue
		if not bool(_runtime_ready_peers.get(peer_id, false)):
			return false
	if session_state != SessionState.IN_RUN:
		return (
			session_state == SessionState.LOBBY
			and _mission_flow_phase in [
				MissionFlowPhase.HUB,
				MissionFlowPhase.SELECT,
				MissionFlowPhase.STAGING,
			]
		)
	return true


func mark_runtime_scene_ready_local() -> void:
	if session_role != SessionRole.CLIENT:
		return
	if not has_active_peer():
		return
	_rpc_client_runtime_ready.rpc_id(host_peer_id)


func mark_runtime_scene_leaving_local() -> void:
	_begin_scene_transfer()
	if session_role != SessionRole.CLIENT:
		return
	if not has_active_peer():
		return
	_rpc_client_runtime_leaving.rpc_id(host_peer_id)

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


func get_mission_flow_phase_name() -> String:
	match _mission_flow_phase:
		MissionFlowPhase.HUB:
			return "HUB"
		MissionFlowPhase.SELECT:
			return "SELECT"
		MissionFlowPhase.STAGING:
			return "STAGING"
		_:
			return "NONE"


func get_session_code() -> String:
	return _session_code


func get_selected_mission_id() -> StringName:
	return _selected_mission_id


func has_selected_mission() -> bool:
	return _selected_mission_id != &"" and MissionRegistryRef.has_mission(_selected_mission_id)


func get_selected_mission_payload() -> Dictionary:
	return MissionRegistryRef.mission_payload(_selected_mission_id)


func get_mission_state_snapshot() -> Dictionary:
	return {
		"mission_id": String(_selected_mission_id),
		"mission": get_selected_mission_payload(),
		"phase": _mission_flow_phase,
		"phase_name": get_mission_flow_phase_name(),
	}


func get_lobby_ready_map() -> Dictionary:
	return _lobby_ready_peers.duplicate(true)


func get_party_snapshot() -> Dictionary:
	return _party_snapshot.duplicate(true)


func get_party_code() -> String:
	return _party_code


func get_party_member_id() -> String:
	return _ensure_party_member_id()


func has_active_party() -> bool:
	return not _party_code.is_empty()


func is_party_request_in_progress() -> bool:
	return _party_request_in_flight


func is_local_party_owner() -> bool:
	return not _party_member_id.is_empty() and _party_member_id == String(_party_snapshot.get("owner_member_id", ""))


func is_local_party_ready() -> bool:
	return _party_ready


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


func request_hub_from_registry(registry_url: String = "") -> bool:
	if has_active_peer():
		_emit_transport_error("Already connected to a hub.")
		return false
	if _lookup_in_flight or _create_lobby_in_flight:
		_emit_transport_error("A session directory request is already in progress.")
		return false
	var base_url := _registry_base_url(registry_url)
	_ensure_create_lobby_request_node()
	var endpoint := "%s/v1/hubs/join" % [base_url.trim_suffix("/")]
	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := {
		"max_players": HUB_MAX_PLAYERS,
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
	_emit_registry_lookup_result(true, "Finding a hub...")
	return true


func request_lobby_from_registry(registry_url: String = "") -> bool:
	return request_hub_from_registry(registry_url)


func request_legacy_lobby_from_registry(registry_url: String = "") -> bool:
	if has_active_peer():
		_emit_transport_error("Disconnect first before creating a lobby.")
		return false
	if _lookup_in_flight or _create_lobby_in_flight:
		_emit_transport_error("A session directory request is already in progress.")
		return false
	var base_url := _registry_base_url(registry_url)
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
	_set_mission_state(&"", MissionFlowPhase.HUB, false)
	_broadcast_slot_map_if_host()
	_broadcast_session_code_if_host()
	_broadcast_lobby_ready_if_host()
	_broadcast_mission_state_if_host()
	if as_dedicated_server:
		_public_port = port
		_enable_dedicated_diagnostics(port)
	else:
		_registry_configure_for_player_host(port, wanted_max_players)
		_registry_register_instance()
		_queue_scene_change(HUB_SCENE_PATH)
	return true


func join_lobby(address: String, port: int = DEFAULT_PORT) -> bool:
	_begin_scene_transfer()
	_disconnect_local_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_end_scene_transfer()
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
	_set_mission_state(&"", MissionFlowPhase.NONE, false)
	_session_code = ""
	_clear_party_state()
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


func create_party_for_mission(mission_id: StringName, registry_url: String = "") -> bool:
	var normalized_id := StringName(String(mission_id))
	if not MissionRegistryRef.has_mission(normalized_id):
		_emit_transport_error("Unknown mission '%s'." % [String(normalized_id)])
		return false
	_party_selected_mission_id = normalized_id
	_party_ready = false
	return _send_party_request(
		"/v1/parties/create",
		{
			"mission_id": String(normalized_id),
			"member_id": _ensure_party_member_id(),
		},
		"create",
		registry_url
	)


func join_party_by_code(party_code: String, registry_url: String = "") -> bool:
	var code := party_code.strip_edges().to_upper()
	if code.is_empty():
		_emit_transport_error("Enter a party code first.")
		return false
	return _send_party_request(
		"/v1/parties/join",
		{
			"party_code": code,
			"member_id": _ensure_party_member_id(),
		},
		"join",
		registry_url
	)


func set_local_party_ready(is_ready: bool, registry_url: String = "") -> bool:
	if _party_code.is_empty():
		_emit_transport_error("Join a party first.")
		return false
	_party_ready = is_ready
	var payload := {
		"party_code": _party_code,
		"member_id": _ensure_party_member_id(),
		"ready": is_ready,
	}
	if is_local_party_owner() and _party_selected_mission_id != &"":
		payload["mission_id"] = String(_party_selected_mission_id)
	return _send_party_request("/v1/parties/update", payload, "update", registry_url)


func toggle_local_party_ready() -> bool:
	return set_local_party_ready(not _party_ready)


func leave_party(registry_url: String = "") -> bool:
	if _party_code.is_empty():
		_clear_party_state()
		return true
	var sent := _send_party_request(
		"/v1/parties/leave",
		{
			"party_code": _party_code,
			"member_id": _ensure_party_member_id(),
		},
		"leave",
		registry_url
	)
	if sent:
		_clear_party_state()
	return sent


func poll_party(registry_url: String = "") -> bool:
	if _party_code.is_empty() or _party_request_in_flight:
		return false
	var base_url := _registry_base_url(registry_url)
	_ensure_party_request_node()
	_party_request_context = "poll"
	var endpoint := "%s/v1/parties/snapshot?code=%s&member_id=%s" % [
		base_url.trim_suffix("/"),
		_party_code.uri_encode(),
		_ensure_party_member_id().uri_encode(),
	]
	var err := _party_request.request(endpoint, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		_party_request_context = ""
		_emit_transport_error("Failed to query party state (error %s)." % [err])
		return false
	_party_request_in_flight = true
	return true


func start_party_run(registry_url: String = "") -> bool:
	if _party_code.is_empty():
		_emit_transport_error("Join a party first.")
		return false
	if not is_local_party_owner():
		_emit_transport_error("Only the party owner can start the mission.")
		return false
	return _send_party_request(
		"/v1/parties/start",
		{
			"party_code": _party_code,
			"member_id": _ensure_party_member_id(),
		},
		"start",
		registry_url
	)


func disconnect_from_session(change_scene: bool = true) -> void:
	_registry_unregister_best_effort()
	_registry_enabled = false
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	_set_mission_state(&"", MissionFlowPhase.NONE, false)
	_session_code = ""
	_emit_session_code_changed()
	_emit_lobby_ready_changed()
	_emit_slot_map_changed()
	if change_scene:
		_queue_scene_change(LOBBY_SCENE_PATH)


func close_lobby_from_host() -> void:
	if session_role != SessionRole.HOST:
		disconnect_from_session()
		return
	if not has_active_peer():
		disconnect_from_session()
		return
	_registry_unregister_best_effort()
	_rpc_lobby_closed_by_host.rpc("Host closed the lobby.")
	call_deferred("_finish_lobby_shutdown_to_menu")


func request_select_mission_from_local_peer(mission_id: StringName) -> void:
	var normalized_id := StringName(String(mission_id))
	if session_state != SessionState.LOBBY:
		return
	if session_role == SessionRole.HOST or session_role == SessionRole.DEDICATED_SERVER:
		select_mission(normalized_id)
		return
	if session_role == SessionRole.CLIENT and has_active_peer():
		_rpc_request_select_mission.rpc_id(host_peer_id, normalized_id)


func select_mission(mission_id: StringName) -> bool:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		_emit_transport_error("Only the server can select a mission.")
		return false
	if session_state != SessionState.LOBBY:
		_emit_transport_error("Mission can only be selected from hub/lobby state.")
		return false
	var normalized_id := StringName(String(mission_id))
	if not MissionRegistryRef.has_mission(normalized_id):
		_emit_transport_error("Unknown mission '%s'." % [String(normalized_id)])
		return false
	_set_mission_state(normalized_id, MissionFlowPhase.SELECT, true)
	return true


func request_mission_staging_from_local_peer() -> void:
	if session_state != SessionState.LOBBY:
		return
	if session_role == SessionRole.HOST or session_role == SessionRole.DEDICATED_SERVER:
		proceed_to_mission_staging()
		return
	if session_role == SessionRole.CLIENT and has_active_peer():
		_rpc_request_mission_staging.rpc_id(host_peer_id)


func proceed_to_mission_staging() -> bool:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		_emit_transport_error("Only the server can open mission staging.")
		return false
	if session_state != SessionState.LOBBY:
		_emit_transport_error("Mission staging can only open from hub/lobby state.")
		return false
	if not has_selected_mission():
		_emit_transport_error("Select a mission before opening staging.")
		return false
	_set_mission_state(_selected_mission_id, MissionFlowPhase.STAGING, true)
	return true


func request_cancel_mission_staging_from_local_peer() -> void:
	if session_state != SessionState.LOBBY:
		return
	if session_role == SessionRole.HOST or session_role == SessionRole.DEDICATED_SERVER:
		cancel_mission_staging()
		return
	if session_role == SessionRole.CLIENT and has_active_peer():
		_rpc_request_cancel_mission_staging.rpc_id(host_peer_id)


func cancel_mission_staging() -> bool:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		_emit_transport_error("Only the server can close mission staging.")
		return false
	if session_state != SessionState.LOBBY:
		return false
	var fallback_phase := MissionFlowPhase.SELECT if has_selected_mission() else MissionFlowPhase.HUB
	_set_mission_state(_selected_mission_id, fallback_phase, true)
	return true


func start_run() -> bool:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		_emit_transport_error("Only the host/server can start a run.")
		return false
	if session_state != SessionState.LOBBY:
		_emit_transport_error("Run can only start from lobby state.")
		return false
	if not has_selected_mission():
		_emit_transport_error("Select a mission before starting a run.")
		return false
	if not are_all_lobby_players_ready():
		_emit_transport_error("All players must be ready before the run begins.")
		return false
	var run_scene_path := MissionLaunchResolverRef.resolve_scene_path(_selected_mission_id)
	if run_scene_path.is_empty():
		_emit_transport_error("Selected mission has no launch target.")
		return false
	_mark_all_remote_runtime_not_ready_for_run()
	_rpc_set_session_state.rpc(SessionState.IN_RUN)
	_rpc_change_scene.rpc(run_scene_path)
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
	return return_to_hub()


func return_to_hub() -> bool:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		_emit_transport_error("Only the host/server can return everyone to hub.")
		return false
	if session_state != SessionState.IN_RUN:
		return false
	_rpc_set_session_state.rpc(SessionState.LOBBY)
	_set_mission_state(&"", MissionFlowPhase.HUB, true)
	_rpc_change_scene.rpc(HUB_SCENE_PATH)
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
		return_to_hub()
	elif session_role == SessionRole.DEDICATED_SERVER:
		return
	elif session_role == SessionRole.CLIENT and has_active_peer():
		mark_runtime_scene_leaving_local()
		await get_tree().process_frame
		await get_tree().process_frame
		disconnect_from_session(false)
		_fallback_to_hub_scene_on_registry_failure = true
		if not request_hub_from_registry():
			_fallback_to_hub_scene_on_registry_failure = false
			_queue_scene_change(HUB_SCENE_PATH)
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


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_closed_by_host(message: String = "") -> void:
	_finish_lobby_shutdown_to_menu()
	if not message.is_empty():
		_emit_registry_lookup_result(false, message)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_session_code(session_code: String) -> void:
	_session_code = session_code.strip_edges().to_upper()
	_emit_session_code_changed()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby_ready(ready_map: Dictionary) -> void:
	_lobby_ready_peers = _normalize_ready_map(ready_map)
	_reconcile_lobby_ready_with_slot_map()
	_emit_lobby_ready_changed()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_mission_state(mission_id: StringName, mission_flow_phase: int) -> void:
	_set_mission_state(mission_id, mission_flow_phase, false)


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
func _rpc_request_select_mission(mission_id: StringName) -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if session_state != SessionState.LOBBY:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if not _is_known_request_peer(sender_peer):
		return
	select_mission(mission_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_mission_staging() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if session_state != SessionState.LOBBY:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if not _is_known_request_peer(sender_peer):
		return
	proceed_to_mission_staging()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_cancel_mission_staging() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if session_state != SessionState.LOBBY:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if not _is_known_request_peer(sender_peer):
		return
	cancel_mission_staging()


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
func _rpc_request_return_to_hub() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	if session_state != SessionState.IN_RUN:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if not _is_known_request_peer(sender_peer):
		return
	return_to_hub()


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


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_runtime_leaving() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer <= 0:
		return
	_runtime_ready_peers[sender_peer] = false
	if dedicated_server_mode:
		_dedicated_log("peer_runtime_leaving peer=%s slots=%s" % [sender_peer, _slot_map_debug_string()])


func _on_connected_to_server() -> void:
	if session_role == SessionRole.CLIENT:
		host_peer_id = 1
		_lobby_ready_peers.clear()
		_set_mission_state(&"", MissionFlowPhase.HUB, false)
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
	_set_mission_state(&"", MissionFlowPhase.NONE, false)
	_session_code = ""
	_emit_session_code_changed()
	_emit_lobby_ready_changed()
	_emit_slot_map_changed()
	if _fallback_to_hub_scene_on_registry_failure:
		_fallback_to_hub_scene_on_registry_failure = false
		_queue_scene_change(HUB_SCENE_PATH)
	else:
		_end_scene_transfer()
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
	_set_mission_state(&"", MissionFlowPhase.NONE, false)
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
	if session_state == SessionState.LOBBY and _mission_flow_phase == MissionFlowPhase.NONE:
		_set_mission_state(&"", MissionFlowPhase.HUB, false)
	_broadcast_mission_state_if_host()
	if session_state == SessionState.IN_RUN:
		_rpc_set_session_state.rpc_id(peer_id, SessionState.IN_RUN)
		var run_scene_path := (
			MissionLaunchResolverRef.resolve_scene_path(_selected_mission_id)
			if has_selected_mission()
			else RUN_SCENE_PATH
		)
		_rpc_change_scene.rpc_id(peer_id, run_scene_path)
	else:
		_rpc_set_session_state.rpc_id(peer_id, SessionState.LOBBY)
		_rpc_change_scene.rpc_id(peer_id, HUB_SCENE_PATH)
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


func _set_mission_state(mission_id: StringName, mission_flow_phase: int, broadcast_if_host: bool) -> void:
	var normalized_id := StringName(String(mission_id))
	if normalized_id != &"" and not MissionRegistryRef.has_mission(normalized_id):
		normalized_id = &""
	var normalized_phase := clampi(mission_flow_phase, MissionFlowPhase.NONE, MissionFlowPhase.STAGING)
	if normalized_id == &"" and normalized_phase != MissionFlowPhase.HUB:
		normalized_phase = MissionFlowPhase.NONE
	var changed := normalized_id != _selected_mission_id or normalized_phase != _mission_flow_phase
	_selected_mission_id = normalized_id
	_mission_flow_phase = normalized_phase
	if broadcast_if_host and (session_role == SessionRole.HOST or session_role == SessionRole.DEDICATED_SERVER):
		_rpc_sync_mission_state.rpc(_selected_mission_id, _mission_flow_phase)
	if changed:
		_emit_mission_state_changed()


func _emit_mission_state_changed() -> void:
	mission_state_changed.emit(get_mission_state_snapshot())


func _broadcast_mission_state_if_host() -> void:
	if session_role != SessionRole.HOST and session_role != SessionRole.DEDICATED_SERVER:
		return
	_rpc_sync_mission_state.rpc(_selected_mission_id, _mission_flow_phase)
	_emit_mission_state_changed()


func _is_known_request_peer(peer_id: int) -> bool:
	return peer_id > 0 and (peer_id == host_peer_id or _peer_slots.has(peer_id))


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
	for key in _peer_slots.keys():
		var peer_id := int(key)
		_runtime_ready_peers[peer_id] = peer_id == host_peer_id
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


func _finish_lobby_shutdown_to_menu() -> void:
	_registry_enabled = false
	_disconnect_local_peer()
	_set_role(SessionRole.NONE)
	_set_state(SessionState.OFFLINE)
	_peer_slots.clear()
	_runtime_ready_peers.clear()
	_lobby_ready_peers.clear()
	_set_mission_state(&"", MissionFlowPhase.NONE, false)
	_session_code = ""
	_emit_session_code_changed()
	_emit_lobby_ready_changed()
	_emit_slot_map_changed()
	_queue_scene_change(LOBBY_SCENE_PATH)


func _clear_intended_disconnect() -> void:
	_intended_disconnect = false


func _begin_scene_transfer() -> void:
	_scene_transfer_token += 1
	_scene_transfer_in_progress = true


func _end_scene_transfer() -> void:
	_scene_transfer_token += 1
	_scene_transfer_in_progress = false


func _queue_scene_change(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	_begin_scene_transfer()
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
		call_deferred("_clear_scene_transfer_after_scene_ready", _scene_transfer_token)
		return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		_end_scene_transfer()
		_emit_transport_error("Failed to change scene to '%s' (error %s)." % [scene_path, err])
		return
	call_deferred("_clear_scene_transfer_after_scene_ready", _scene_transfer_token)


func _clear_scene_transfer_after_scene_ready(token: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if token == _scene_transfer_token:
		_scene_transfer_in_progress = false


func _fallback_to_hub_scene_after_run_leave_if_needed() -> void:
	if not _fallback_to_hub_scene_on_registry_failure:
		return
	_fallback_to_hub_scene_on_registry_failure = false
	_queue_scene_change(HUB_SCENE_PATH)


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


func _emit_party_state_changed() -> void:
	party_state_changed.emit(_party_snapshot.duplicate(true))


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
	_selected_mission_id = &""
	_mission_flow_phase = MissionFlowPhase.NONE
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
	_party_request_in_flight = false
	_party_request_context = ""
	_fallback_to_hub_scene_on_registry_failure = false
	_clear_party_state()


func _try_bootstrap_dedicated_server() -> void:
	if not _is_dedicated_cmdline():
		return
	var port := _cmdline_int_value("--port=", DEFAULT_PORT)
	var wanted_max_players := _cmdline_int_value("--max_players=", DEFAULT_MAX_PLAYERS)
	var auto_start_run := _cmdline_bool_value("--start_in_run=", false)
	var mission_id := StringName(_cmdline_string_value("--mission_id=", ""))
	_instance_kind = _cmdline_string_value("--instance_kind=", "hub").strip_edges().to_lower()
	_dedicated_idle_shutdown_seconds = maxf(5.0, float(_cmdline_int_value("--empty_shutdown_seconds=", 20)))
	var requested_log_path := _cmdline_string_value("--dedicated_log_file=", "").strip_edges()
	if not requested_log_path.is_empty():
		_dedicated_log_override_path = ProjectSettings.globalize_path(requested_log_path)
	if not host_lobby(port, wanted_max_players, false, true):
		return
	_registry_configure_for_dedicated(port, wanted_max_players)
	if auto_start_run:
		_bootstrap_dedicated_run(mission_id)
	else:
		_instance_kind = "hub"
		_queue_scene_change(HUB_SCENE_PATH)
	_registry_register_instance()



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


func _bootstrap_dedicated_run(mission_id: StringName) -> void:
	var normalized_id := StringName(String(mission_id))
	if normalized_id == &"" or not MissionRegistryRef.has_mission(normalized_id):
		normalized_id = MissionRegistryRef.default_mission_id()
	_selected_mission_id = normalized_id
	_mission_flow_phase = MissionFlowPhase.STAGING
	_instance_kind = "run"
	_set_state(SessionState.IN_RUN)
	var run_scene_path := MissionLaunchResolverRef.resolve_scene_path(_selected_mission_id)
	if run_scene_path.is_empty():
		run_scene_path = RUN_SCENE_PATH
	_queue_scene_change(run_scene_path)
	_dedicated_log("boot_run mission_id=%s max_players=%s" % [String(_selected_mission_id), max_players])


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
	_instance_kind = _cmdline_string_value("--instance_kind=", _instance_kind).strip_edges().to_lower()
	if _instance_kind.is_empty():
		_instance_kind = "hub"
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


func _ensure_party_request_node() -> void:
	if _party_request != null:
		return
	_party_request = HTTPRequest.new()
	_party_request.name = "PartyRequest"
	add_child(_party_request)
	_party_request.request_completed.connect(_on_party_request_completed)


func _send_party_request(path: String, payload: Dictionary, context: String, registry_url: String = "") -> bool:
	if _party_request_in_flight:
		_emit_transport_error("A party request is already in progress.")
		return false
	var base_url := _registry_base_url(registry_url)
	_ensure_party_request_node()
	_party_request_context = context
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _party_request.request(
		"%s%s" % [base_url.trim_suffix("/"), path],
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		_party_request_context = ""
		_emit_transport_error("Failed to query party service (error %s)." % [err])
		return false
	_party_request_in_flight = true
	return true


func _registry_base_url(registry_url: String = "") -> String:
	var base_url := registry_url.strip_edges()
	if base_url.is_empty():
		base_url = _cmdline_string_value("--registry_url=", DEFAULT_REGISTRY_URL)
	if base_url.is_empty():
		base_url = DEFAULT_REGISTRY_URL
	return base_url


func _ensure_party_member_id() -> String:
	if _party_member_id.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_party_member_id = "member_%s_%s" % [Time.get_unix_time_from_system(), rng.randi()]
	return _party_member_id


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
			"kind": _instance_kind,
			"mission_id": String(_selected_mission_id),
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
			"kind": _instance_kind,
			"mission_id": String(_selected_mission_id),
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
		_fallback_to_hub_scene_after_run_leave_if_needed()
		return
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if parsed is not Dictionary:
		var parse_error := "Session directory returned invalid JSON payload."
		_emit_transport_error(parse_error)
		_emit_registry_lookup_result(false, parse_error)
		_fallback_to_hub_scene_after_run_leave_if_needed()
		return
	var payload := parsed as Dictionary
	if not bool(payload.get("ok", false)):
		var payload_error := "Session directory did not return a valid lobby list."
		if payload.has("error"):
			payload_error = "Session directory error: %s" % [String(payload.get("error", "unknown"))]
		_emit_transport_error(payload_error)
		_emit_registry_lookup_result(false, payload_error)
		_fallback_to_hub_scene_after_run_leave_if_needed()
		return
	var join_variant: Variant = payload.get("join", {})
	if join_variant is not Dictionary:
		var join_error := "Session directory response is missing join endpoint info."
		_emit_transport_error(join_error)
		_emit_registry_lookup_result(false, join_error)
		_fallback_to_hub_scene_after_run_leave_if_needed()
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
		_fallback_to_hub_scene_after_run_leave_if_needed()
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
		_fallback_to_hub_scene_after_run_leave_if_needed()
		return
	_fallback_to_hub_scene_on_registry_failure = false


func _on_party_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var context := _party_request_context
	_party_request_context = ""
	_party_request_in_flight = false
	var response_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(response_text)
	if response_code < 200 or response_code >= 300:
		var message := _party_error_message(response_code, parsed)
		_emit_transport_error(message)
		_emit_party_state_changed()
		return
	if parsed is not Dictionary:
		_emit_transport_error("Party service returned invalid JSON payload.")
		_emit_party_state_changed()
		return
	var payload := parsed as Dictionary
	if not bool(payload.get("ok", false)):
		_emit_transport_error(_party_error_text(String(payload.get("error", "party_request_failed"))))
		_emit_party_state_changed()
		return
	if context == "leave":
		_clear_party_state()
		return
	_apply_party_payload(payload)
	var launch := payload.get("launch", {}) as Dictionary
	if launch.is_empty() and _party_snapshot.has("launch"):
		launch = _party_snapshot.get("launch", {}) as Dictionary
	if not launch.is_empty():
		_connect_to_party_launch(launch)
	_emit_party_state_changed()


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


func _apply_party_payload(payload: Dictionary) -> void:
	var party := payload.get("party", {}) as Dictionary
	if party.is_empty():
		return
	_party_snapshot = party.duplicate(true)
	_party_code = String(party.get("party_code", "")).strip_edges().to_upper()
	_party_selected_mission_id = StringName(String(party.get("mission_id", "")))
	_party_ready = false
	var members := party.get("members", []) as Array
	for member_v in members:
		if member_v is not Dictionary:
			continue
		var member := member_v as Dictionary
		if String(member.get("member_id", "")) == _ensure_party_member_id():
			_party_ready = bool(member.get("ready", false))
			break
	_emit_party_state_changed()


func _clear_party_state() -> void:
	_party_code = ""
	_party_snapshot.clear()
	_party_selected_mission_id = &""
	_party_ready = false
	_emit_party_state_changed()


func _connect_to_party_launch(launch: Dictionary) -> void:
	var join := launch.get("join", {}) as Dictionary
	var host := String(join.get("host", "")).strip_edges()
	var port := int(join.get("port", DEFAULT_PORT))
	if host.is_empty() or port <= 0:
		_emit_transport_error("Party launch returned an invalid endpoint.")
		return
	_clear_party_state()
	_join_lobby_after_runtime_scene_exit(host, port)


func _join_lobby_after_runtime_scene_exit(host: String, port: int) -> void:
	if session_role == SessionRole.CLIENT and has_active_peer():
		mark_runtime_scene_leaving_local()
		await get_tree().process_frame
		await get_tree().process_frame
	if not join_lobby(host, port):
		_emit_transport_error("Party launch endpoint was valid, but connection failed.")


func _party_error_message(response_code: int, parsed: Variant) -> String:
	if parsed is Dictionary:
		var payload := parsed as Dictionary
		if payload.has("error"):
			return _party_error_text(String(payload.get("error", "")))
	return "Party request failed (HTTP %s)." % [response_code]


func _party_error_text(error: String) -> String:
	match error:
		"party_full":
			return "Party is full."
		"party_not_found":
			return "Party code was not found."
		"not_party_owner":
			return "Only the party owner can start the mission."
		"party_not_ready":
			return "All party members must be ready before the mission starts."
		"mission_required":
			return "Select a mission before starting."
		"allocator_unavailable":
			return "Mission allocator is unavailable."
		_:
			return "Party request failed: %s" % [error]


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
