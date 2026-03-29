@tool
extends SceneTree

const ROOM_PATHS := [
	"res://dungeon/rooms/authored/outlines/room_combat_skirmish_small_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_combat_tactical_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_arena_wave_large_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_connector_narrow_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_connector_turn_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_connector_junction_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_treasure_reward_small_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_chokepoint_gate_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/room_boss_approach_large_a.tscn",
]


func _initialize() -> void:
	var root := Node.new()
	get_root().add_child(root)
	for room_path in ROOM_PATHS:
		var scene := load(room_path) as PackedScene
		if scene == null:
			push_error("Failed to load %s" % room_path)
			quit(1)
			return
		var room = scene.instantiate()
		if room == null or not (room is RoomBase):
			push_error("Scene %s did not instantiate as RoomBase" % room_path)
			quit(1)
			return
		root.add_child(room)
		await process_frame
		if room.authored_layout == null:
			push_error("Room %s is missing authored_layout" % room_path)
			quit(1)
			return
		var layout_items = room.authored_layout.get("items")
		if not (layout_items is Array) or (layout_items as Array).is_empty():
			push_error("Room %s has empty authored layout items" % room_path)
			quit(1)
			return
		var generated_zones: Node2D = room.get_generated_zones_root()
		var generated_sockets: Node2D = room.get_generated_sockets_root()
		if generated_zones == null or generated_zones.get_child_count() < 3:
			push_error("Room %s is missing generated structural zone markers" % room_path)
			quit(1)
			return
		if generated_sockets == null:
			push_error("Room %s is missing generated sockets root" % room_path)
			quit(1)
			return
		print(
			"Validated %s | items=%s | sockets=%s | zones=%s" % [
				room_path,
				(layout_items as Array).size(),
				generated_sockets.get_child_count(),
				generated_zones.get_child_count(),
			]
		)
		room.queue_free()
		await process_frame
	print("VALIDATED_OUTLINE_ROOMS_OK")
	quit()
