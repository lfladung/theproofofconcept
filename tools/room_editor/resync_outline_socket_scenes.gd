@tool
extends SceneTree

## Headless: reload outline RoomBase scenes, run scene sync so DoorSocket2D nodes match layouts
## (positions use footprint center — see DungeonRoomSceneSync._sync_socket_item).

const CATALOG_PATH := "res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres"
const SceneSync := preload("res://addons/dungeon_room_editor/core/scene_sync.gd")

const SCENE_PATHS: Array[String] = [
	"res://dungeon/rooms/authored/outlines/v1/room_combat_skirmish_small_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_combat_tactical_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_arena_wave_large_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_connector_narrow_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_connector_turn_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_connector_junction_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_treasure_reward_small_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_chokepoint_gate_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_boss_approach_large_a.tscn",
]


func _initialize() -> void:
	var catalog = load(CATALOG_PATH)
	if catalog == null:
		push_error("Failed to load catalog")
		quit(1)
		return
	var sync := SceneSync.new()
	for scene_path in SCENE_PATHS:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("Failed to load %s" % scene_path)
			quit(1)
			return
		var room = packed.instantiate() as RoomBase
		if room == null:
			push_error("Not RoomBase: %s" % scene_path)
			quit(1)
			return
		# Reload sidecar layout from disk so .tres edits are picked up.
		if room.authored_layout != null:
			var lp := ResourceLoader.load(room.authored_layout.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if lp != null:
				room.authored_layout = lp
		sync.sync_room(room, room.authored_layout, catalog)
		var out := PackedScene.new()
		var err := out.pack(room)
		if err != OK:
			room.free()
			push_error("pack failed %s err=%s" % [scene_path, err])
			quit(1)
			return
		err = ResourceSaver.save(out, scene_path)
		room.free()
		if err != OK:
			push_error("save failed %s err=%s" % [scene_path, err])
			quit(1)
			return
		print("Resynced %s" % scene_path)
	print("RESYNC_OUTLINE_SOCKET_SCENES_OK")
	quit()
