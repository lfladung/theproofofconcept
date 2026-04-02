@tool
extends SceneTree

const SerializerScript = preload("res://addons/dungeon_room_editor/core/serializer.gd")

const AUTHORED_ROOM_ROOT := "res://dungeon/rooms/authored"
const ROOM_BASE_SCENE_PATH := "res://dungeon/rooms/base/room_base.tscn"
const FLOOR_MASK_SMALL: StringName = &"floor_mask_small"
const FLOOR_MASK_LARGE: StringName = &"floor_mask_large"
const FLOOR_MASK_EXTRA_LARGE: StringName = &"floor_mask_extra_large"


func _initialize() -> void:
	var serializer = SerializerScript.new()
	var room_paths := _collect_room_scene_paths(AUTHORED_ROOM_ROOT)
	if room_paths.is_empty():
		push_error("RUNTIME_FLOOR_MASK_CHECK: no authored rooms found under %s" % AUTHORED_ROOM_ROOT)
		quit(1)
		return
	var summarized: Array[String] = []
	var rooms_with_large := 0
	var rooms_with_extra_large := 0
	for room_path in room_paths:
		var packed := load(room_path) as PackedScene
		if packed == null:
			push_warning("RUNTIME_FLOOR_MASK_CHECK: could not load room %s" % room_path)
			continue
		var room = packed.instantiate()
		if room == null:
			push_warning("RUNTIME_FLOOR_MASK_CHECK: could not instantiate room %s" % room_path)
			continue
		if not room is RoomBase:
			room.free()
			continue
		var ensured := serializer.ensure_layout_for_room(room as RoomBase)
		var layout = ensured.get("layout", null)
		var counts := _count_runtime_floor_masks(layout)
		var small := int(counts.get("small", 0))
		var large := int(counts.get("large", 0))
		var extra_large := int(counts.get("extra_large", 0))
		if large > 0:
			rooms_with_large += 1
		if extra_large > 0:
			rooms_with_extra_large += 1
		summarized.append(
			"%s :: small=%d large=%d extra_large=%d" % [
				room_path,
				small,
				large,
				extra_large,
			]
		)
		room.free()
	summarized.sort()
	for line in summarized:
		print(line)
	print(
		"RUNTIME_FLOOR_MASK_SUMMARY rooms=%d rooms_with_large=%d rooms_with_extra_large=%d" % [
			summarized.size(),
			rooms_with_large,
			rooms_with_extra_large,
		]
	)
	quit()


func _collect_room_scene_paths(root_path: String) -> Array[String]:
	var collected: Array[String] = []
	_collect_room_scene_paths_recursive(root_path, collected)
	return collected


func _collect_room_scene_paths_recursive(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var child_path := "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_collect_room_scene_paths_recursive(child_path, out)
			continue
		if not name.ends_with(".tscn"):
			continue
		if child_path == ROOM_BASE_SCENE_PATH:
			continue
		out.append(child_path)
	dir.list_dir_end()


func _count_runtime_floor_masks(layout) -> Dictionary:
	var counts := {
		"small": 0,
		"large": 0,
		"extra_large": 0,
	}
	if layout == null:
		return counts
	for item in layout.items:
		if item == null:
			continue
		match StringName(item.piece_id):
			FLOOR_MASK_SMALL:
				counts["small"] = int(counts["small"]) + 1
			FLOOR_MASK_LARGE:
				counts["large"] = int(counts["large"]) + 1
			FLOOR_MASK_EXTRA_LARGE:
				counts["extra_large"] = int(counts["extra_large"]) + 1
	return counts
