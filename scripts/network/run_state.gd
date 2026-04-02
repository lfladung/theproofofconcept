extends Node
class_name RunStateStore

signal run_started(snapshot: Dictionary)
signal run_ended(previous_snapshot: Dictionary)
signal snapshot_changed(snapshot: Dictionary)

var run_id := ""
var seed := 0
var floor_index := 1
var in_run := false
var started_at_unix := 0
var revision := 0
var extra: Dictionary = {}


func _ready() -> void:
	var session := _session()
	if session != null:
		session.state_changed.connect(_on_session_state_changed)


func begin_new_run(optional_seed: int = 0) -> void:
	var chosen_seed := optional_seed
	if chosen_seed == 0:
		chosen_seed = int(Time.get_unix_time_from_system())
	seed = chosen_seed
	floor_index = 1
	started_at_unix = int(Time.get_unix_time_from_system())
	run_id = "run_%s_%s" % [started_at_unix, seed]
	in_run = true
	revision += 1
	var snap := snapshot()
	run_started.emit(snap)
	snapshot_changed.emit(snap)


func clear_run() -> void:
	var prev := snapshot()
	run_id = ""
	seed = 0
	floor_index = 1
	in_run = false
	started_at_unix = 0
	extra.clear()
	revision += 1
	run_ended.emit(prev)
	snapshot_changed.emit(snapshot())


func set_floor(new_floor_index: int) -> void:
	floor_index = max(1, new_floor_index)
	revision += 1
	snapshot_changed.emit(snapshot())


func set_extra_value(key: StringName, value: Variant) -> void:
	extra[key] = value
	revision += 1
	snapshot_changed.emit(snapshot())


func apply_snapshot(data: Dictionary) -> void:
	run_id = String(data.get("run_id", ""))
	seed = int(data.get("seed", 0))
	floor_index = max(1, int(data.get("floor_index", 1)))
	in_run = bool(data.get("in_run", false))
	started_at_unix = int(data.get("started_at_unix", 0))
	extra = data.get("extra", {}).duplicate(true)
	revision = int(data.get("revision", revision + 1))
	snapshot_changed.emit(snapshot())


func snapshot() -> Dictionary:
	return {
		"run_id": run_id,
		"seed": seed,
		"floor_index": floor_index,
		"in_run": in_run,
		"started_at_unix": started_at_unix,
		"revision": revision,
		"extra": extra.duplicate(true),
	}


func _on_session_state_changed(_previous_state: int, current_state: int) -> void:
	if current_state == NetworkSession.SessionState.IN_RUN:
		if not in_run:
			begin_new_run(seed)
		return
	if in_run:
		clear_run()


func _session() -> NetworkSessionService:
	return get_node_or_null("/root/NetworkSession") as NetworkSessionService
