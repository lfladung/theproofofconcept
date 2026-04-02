extends SceneTree

const SMALL_DUNGEON_SCENE := preload("res://dungeon/game/small_dungeon.tscn")
const OUTPUT_PATH := "res://logs/live_fight_profile_latest.json"
const WINDOW_SIZE := Vector2i(1600, 900)
const BOOT_TIMEOUT_SECONDS := 20.0
const TELEPORT_SETTLE_SECONDS := 1.0
const COMBAT_ROOM_IDLE_SECONDS := 2.0
const ENCOUNTER_START_SECONDS := 3.0
const ENCOUNTER_SUSTAIN_SECONDS := 5.0

var _dungeon: Node
var _bucket_samples_ms: Dictionary = {}
var _bucket_enemy_counts: Dictionary = {}


func _init() -> void:
	await process_frame
	var window := root.get_window()
	if window != null:
		window.size = WINDOW_SIZE
		window.mode = Window.MODE_WINDOWED
		window.title = "Live Fight Profiler"

	_dungeon = SMALL_DUNGEON_SCENE.instantiate()
	root.add_child(_dungeon)
	print("[fight-profile] instantiated small_dungeon")

	var floor_ready := await _wait_for_floor_generated(BOOT_TIMEOUT_SECONDS)
	if not floor_ready:
		_finish_with_error("Timed out waiting for small_dungeon floor generation.")
		return
	print("[fight-profile] floor generated")

	if not _move_player_to_combat_room():
		_finish_with_error("Failed to move player to combat room.")
		return
	print("[fight-profile] player moved to combat room")

	await _wait_seconds(TELEPORT_SETTLE_SECONDS)
	await _sample_bucket("combat_room_idle", COMBAT_ROOM_IDLE_SECONDS)

	var encounter_id := _combat_encounter_id()
	if String(encounter_id) == "":
		_finish_with_error("No combat encounter id was available.")
		return
	print("[fight-profile] starting encounter %s" % [String(encounter_id)])
	_dungeon.call("_start_arena_encounter", encounter_id)

	await _sample_bucket("encounter_start", ENCOUNTER_START_SECONDS)
	await _sample_bucket("encounter_sustain", ENCOUNTER_SUSTAIN_SECONDS)

	var summary := _build_summary()
	_write_summary(summary)
	_print_summary(summary)
	quit(0)


func _wait_for_floor_generated(timeout_seconds: float) -> bool:
	var deadline_usec := Time.get_ticks_usec() + int(timeout_seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline_usec:
		await process_frame
		if _dungeon != null and bool(_dungeon.get("_has_generated_floor")):
			return true
	return false


func _wait_seconds(seconds: float) -> void:
	var end_usec := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < end_usec:
		await process_frame


func _move_player_to_combat_room() -> bool:
	if _dungeon == null:
		return false
	var player_v: Variant = _dungeon.get("_player")
	if player_v is not CharacterBody2D or not is_instance_valid(player_v):
		return false
	var player := player_v as CharacterBody2D
	var room_name := _dungeon.call("_layout_room_name", "combat_room") as StringName
	if String(room_name) == "":
		return false
	var room_center := _dungeon.call("_room_center_2d", room_name) as Vector2
	player.global_position = room_center
	player.velocity = Vector2.ZERO
	return true


func _combat_encounter_id() -> StringName:
	if _dungeon == null:
		return &""
	return _dungeon.get("_combat_encounter_id") as StringName


func _sample_bucket(bucket_name: String, seconds: float) -> void:
	var samples: Array[float] = []
	var enemy_counts: Array[int] = []
	_bucket_samples_ms[bucket_name] = samples
	_bucket_enemy_counts[bucket_name] = enemy_counts
	var end_usec := Time.get_ticks_usec() + int(seconds * 1000000.0)
	var last_usec := Time.get_ticks_usec()
	while Time.get_ticks_usec() < end_usec:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		samples.append(float(now_usec - last_usec) / 1000.0)
		enemy_counts.append(_mob_count())
		last_usec = now_usec


func _mob_count() -> int:
	if _dungeon == null:
		return 0
	var tree := _dungeon.get_tree()
	if tree == null:
		return 0
	return tree.get_nodes_in_group(&"mob").size()


func _build_summary() -> Dictionary:
	var buckets := {}
	for key in _bucket_samples_ms.keys():
		var bucket_name := String(key)
		var samples := _bucket_samples_ms[bucket_name] as Array[float]
		var enemy_counts := _bucket_enemy_counts.get(bucket_name, []) as Array[int]
		buckets[bucket_name] = _bucket_stats(samples, enemy_counts)
	return {
		"scene": "res://dungeon/game/small_dungeon.tscn",
		"window_size": {"x": WINDOW_SIZE.x, "y": WINDOW_SIZE.y},
		"timestamp_unix": Time.get_unix_time_from_system(),
		"buckets": buckets,
	}


func _bucket_stats(samples_ms: Array[float], enemy_counts: Array[int]) -> Dictionary:
	if samples_ms.is_empty():
		return {
			"frames": 0,
			"avg_ms": 0.0,
			"avg_fps": 0.0,
			"p95_ms": 0.0,
			"max_ms": 0.0,
			"frames_over_16_7ms": 0,
			"frames_over_33_3ms": 0,
			"frames_over_50ms": 0,
			"avg_enemy_count": 0.0,
			"max_enemy_count": 0,
		}
	var total_ms := 0.0
	var max_ms := 0.0
	var over_16 := 0
	var over_33 := 0
	var over_50 := 0
	for sample in samples_ms:
		total_ms += sample
		max_ms = maxf(max_ms, sample)
		if sample > 16.7:
			over_16 += 1
		if sample > 33.3:
			over_33 += 1
		if sample > 50.0:
			over_50 += 1
	var sorted_samples := samples_ms.duplicate()
	sorted_samples.sort()
	var p95_index := clampi(int(floor(float(sorted_samples.size() - 1) * 0.95)), 0, sorted_samples.size() - 1)
	var avg_ms := total_ms / float(samples_ms.size())
	var enemy_total := 0
	var enemy_max := 0
	for count in enemy_counts:
		enemy_total += count
		enemy_max = maxi(enemy_max, count)
	var avg_enemy_count := float(enemy_total) / float(maxi(1, enemy_counts.size()))
	return {
		"frames": samples_ms.size(),
		"avg_ms": snapped(avg_ms, 0.01),
		"avg_fps": snapped(1000.0 / avg_ms if avg_ms > 0.001 else 0.0, 0.01),
		"p95_ms": snapped(float(sorted_samples[p95_index]), 0.01),
		"max_ms": snapped(max_ms, 0.01),
		"frames_over_16_7ms": over_16,
		"frames_over_33_3ms": over_33,
		"frames_over_50ms": over_50,
		"avg_enemy_count": snapped(avg_enemy_count, 0.01),
		"max_enemy_count": enemy_max,
	}


func _write_summary(summary: Dictionary) -> void:
	var abs_dir := ProjectSettings.globalize_path("res://logs")
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[fight-profile] Failed to write summary to %s" % OUTPUT_PATH)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print("[fight-profile] wrote %s" % ProjectSettings.globalize_path(OUTPUT_PATH))


func _print_summary(summary: Dictionary) -> void:
	print("[fight-profile] summary begin")
	var buckets := summary.get("buckets", {}) as Dictionary
	for bucket_name in ["combat_room_idle", "encounter_start", "encounter_sustain"]:
		var bucket := buckets.get(bucket_name, {}) as Dictionary
		print(
			"[fight-profile] %s frames=%s avg_ms=%s avg_fps=%s p95_ms=%s max_ms=%s >33ms=%s >50ms=%s avg_enemies=%s max_enemies=%s"
			% [
				bucket_name,
				int(bucket.get("frames", 0)),
				float(bucket.get("avg_ms", 0.0)),
				float(bucket.get("avg_fps", 0.0)),
				float(bucket.get("p95_ms", 0.0)),
				float(bucket.get("max_ms", 0.0)),
				int(bucket.get("frames_over_33_3ms", 0)),
				int(bucket.get("frames_over_50ms", 0)),
				float(bucket.get("avg_enemy_count", 0.0)),
				int(bucket.get("max_enemy_count", 0)),
			]
		)
	print("[fight-profile] summary end")


func _finish_with_error(message: String) -> void:
	push_error("[fight-profile] %s" % message)
	quit(1)
