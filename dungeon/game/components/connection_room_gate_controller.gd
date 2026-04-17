extends Node
class_name ConnectionRoomGateController

const LOCK_PREFIX := "progression_gate/"
const STATE_WAITING_FOR_CLEAR := "waiting_for_clear"
const STATE_WAITING_FOR_PARTY := "waiting_for_party"
const STATE_ADVANCED := "advanced"

signal gate_status_changed(text: String)

var room_queries: RoomQueryService
var door_lock_controller: DoorLockController
var required_peer_ids_fn: Callable = Callable()
var player_for_peer_id_fn: Callable = Callable()
var encounter_cleared_fn: Callable = Callable()

var _gates: Array[Dictionary] = []
var _last_status_text := ""


func clear_runtime_state() -> void:
	_gates.clear()
	_last_status_text = ""
	if door_lock_controller != null:
		door_lock_controller.clear_named_locks_by_prefix(LOCK_PREFIX)


func setup_gates(layout: Dictionary) -> void:
	clear_runtime_state()
	var gate_values := layout.get("progression_gates", []) as Array
	for gate_value in gate_values:
		if gate_value is not Dictionary:
			continue
		var gate := (gate_value as Dictionary).duplicate(true)
		gate["state"] = STATE_WAITING_FOR_CLEAR
		_gates.append(gate)
	_sync_all_gate_locks()


func refresh() -> void:
	if _gates.is_empty():
		return
	var changed := false
	for i in range(_gates.size()):
		var gate := _gates[i]
		var old_state := String(gate.get("state", ""))
		var next_state := _resolve_gate_state(gate)
		if next_state != old_state:
			gate["state"] = next_state
			_gates[i] = gate
			changed = true
	if changed:
		_sync_all_gate_locks()
	_emit_status_if_changed()


func _resolve_gate_state(gate: Dictionary) -> String:
	if String(gate.get("state", "")) == STATE_ADVANCED:
		return STATE_ADVANCED
	var previous_encounter_id := String(gate.get("previous_encounter_id", ""))
	if not previous_encounter_id.is_empty() and not _encounter_is_cleared(previous_encounter_id):
		return STATE_WAITING_FOR_CLEAR
	if _required_players_reached_checkpoint(gate):
		return STATE_ADVANCED
	return STATE_WAITING_FOR_PARTY


func _sync_all_gate_locks() -> void:
	if door_lock_controller == null:
		return
	door_lock_controller.clear_named_locks_by_prefix(LOCK_PREFIX)
	for gate in _gates:
		_sync_gate_locks(gate)


func _sync_gate_locks(gate: Dictionary) -> void:
	var state := String(gate.get("state", ""))
	var gate_id := String(gate.get("id", "gate"))
	match state:
		STATE_WAITING_FOR_CLEAR:
			_set_gate_lock(
				"%s%s/previous_to_connector" % [LOCK_PREFIX, gate_id],
				StringName(String(gate.get("previous_room", ""))),
				String(gate.get("previous_room_dir", "")),
				true
			)
			_set_gate_lock(
				"%s%s/connector_to_next" % [LOCK_PREFIX, gate_id],
				StringName(String(gate.get("connector_room", ""))),
				String(gate.get("connector_exit_dir", "")),
				true
			)
		STATE_WAITING_FOR_PARTY:
			_set_gate_lock(
				"%s%s/connector_to_next" % [LOCK_PREFIX, gate_id],
				StringName(String(gate.get("connector_room", ""))),
				String(gate.get("connector_exit_dir", "")),
				true
			)
		STATE_ADVANCED:
			_set_gate_lock(
				"%s%s/connector_to_previous" % [LOCK_PREFIX, gate_id],
				StringName(String(gate.get("connector_room", ""))),
				String(gate.get("connector_entry_dir", "")),
				true
			)
			_set_gate_lock(
				"%s%s/previous_to_connector" % [LOCK_PREFIX, gate_id],
				StringName(String(gate.get("previous_room", ""))),
				String(gate.get("previous_room_dir", "")),
				true
			)


func _set_gate_lock(lock_id_text: String, room_name: StringName, direction: String, locked: bool) -> void:
	if door_lock_controller == null:
		return
	var socket_pos := Vector2.ZERO
	if room_queries != null and String(room_name) != "" and not direction.is_empty():
		socket_pos = room_queries.connection_marker_world_position(room_name, direction)
	door_lock_controller.set_named_room_socket_lock(StringName(lock_id_text), room_name, socket_pos, direction, locked)


func _required_players_in_connector(connector_room: StringName) -> bool:
	if String(connector_room).is_empty():
		return false
	return _required_players_in_rooms([connector_room])


func _required_players_reached_checkpoint(gate: Dictionary) -> bool:
	var allowed_rooms: Array[StringName] = []
	for room_value in gate.get("advance_room_names", []) as Array:
		var room_name := StringName(String(room_value))
		if room_name != &"" and not allowed_rooms.has(room_name):
			allowed_rooms.append(room_name)
	var connector_room := StringName(String(gate.get("connector_room", "")))
	if connector_room != &"" and not allowed_rooms.has(connector_room):
		allowed_rooms.append(connector_room)
	if allowed_rooms.is_empty():
		return false
	return _required_players_in_rooms(allowed_rooms)


func _required_players_in_rooms(room_names: Array[StringName]) -> bool:
	if room_names.is_empty():
		return false
	var peer_ids := _required_peer_ids()
	if peer_ids.is_empty():
		return false
	for peer_id in peer_ids:
		var player := _player_for_peer(peer_id)
		if player == null or not is_instance_valid(player):
			return false
		if room_queries == null:
			return false
		if not room_names.has(StringName(room_queries.room_name_at(player.global_position, 1.25))):
			return false
	return true


func _required_peer_ids() -> Array[int]:
	if required_peer_ids_fn.is_valid():
		var value: Variant = required_peer_ids_fn.call()
		if value is Array[int]:
			return value as Array[int]
		if value is Array:
			var out: Array[int] = []
			for peer_value in value as Array:
				out.append(int(peer_value))
			return out
	return []


func _player_for_peer(peer_id: int) -> CharacterBody2D:
	if not player_for_peer_id_fn.is_valid():
		return null
	var value: Variant = player_for_peer_id_fn.call(peer_id)
	if value is CharacterBody2D:
		return value as CharacterBody2D
	return null


func _encounter_is_cleared(encounter_id: String) -> bool:
	if encounter_id.is_empty():
		return true
	if not encounter_cleared_fn.is_valid():
		return false
	return bool(encounter_cleared_fn.call(StringName(encounter_id)))


func _emit_status_if_changed() -> void:
	var text := _status_text()
	if text == _last_status_text:
		return
	_last_status_text = text
	if not text.is_empty():
		gate_status_changed.emit(text)


func _status_text() -> String:
	for gate in _gates:
		match String(gate.get("state", "")):
			STATE_WAITING_FOR_CLEAR:
				pass
			STATE_WAITING_FOR_PARTY:
				var connector_room := StringName(String(gate.get("connector_room", "")))
				var peer_ids := _required_peer_ids()
				var in_count := 0
				for peer_id in peer_ids:
					var player := _player_for_peer(peer_id)
					if player != null and is_instance_valid(player) and room_queries != null:
						if StringName(room_queries.room_name_at(player.global_position, 1.25)) == connector_room:
							in_count += 1
				return "Connection room checkpoint: %s/%s players." % [in_count, peer_ids.size()]
			_:
				pass
	return ""
