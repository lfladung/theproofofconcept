@tool
extends RefCounted
class_name DungeonRoomPlaytestLauncher

const MANIFEST_PATH := "user://dungeon_room_editor_playtest.json"
const HARNESS_SCENE_PATH := "res://addons/dungeon_room_editor/playtest/room_playtest_harness.tscn"
const SCENE_SYNC_SCRIPT := preload("res://addons/dungeon_room_editor/core/scene_sync.gd")
const DEFAULT_CATALOG := preload("res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres")

var _scene_sync = SCENE_SYNC_SCRIPT.new()


func launch(editor_interface: Object, room: RoomBase, layout, serializer) -> bool:
	if room == null or layout == null:
		return false
	if room.scene_file_path.is_empty():
		return false
	# Regenerate plugin-owned nodes without scene ownership so save_scene strips stale generated content.
	_scene_sync.sync_room(room, layout, DEFAULT_CATALOG)
	if editor_interface != null and editor_interface.has_method("save_scene"):
		editor_interface.call("save_scene")
	serializer.save_layout(room, layout)
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"room_scene_path": room.scene_file_path}, "\t"))
	if editor_interface != null and editor_interface.has_method("play_custom_scene"):
		editor_interface.call("play_custom_scene", HARNESS_SCENE_PATH)
		return true
	return false
