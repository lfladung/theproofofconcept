@tool
extends SceneTree

const ROOM_PATHS := [
	"res://dungeon/rooms/authored/outlines/v1/room_combat_skirmish_small_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_combat_tactical_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_arena_wave_large_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_connector_narrow_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_connector_turn_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_connector_junction_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_treasure_reward_small_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_chokepoint_gate_medium_a.tscn",
	"res://dungeon/rooms/authored/outlines/v1/room_boss_approach_large_a.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_combat_skirmish_small_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_combat_tactical_medium_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_arena_wave_large_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_connector_narrow_medium_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_connector_turn_medium_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_connector_junction_medium_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_treasure_reward_small_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_chokepoint_gate_medium_b.tscn",
	"res://dungeon/rooms/authored/outlines/v2/room_boss_approach_large_b.tscn",
]


func _count_layout_structural_markers(room: RoomBase) -> int:
	var layout = room.authored_layout
	if layout == null:
		return 0
	var n := 0
	for item in layout.items:
		if item == null:
			continue
		match item.piece_id:
			&"encounter_entry_marker", &"prop_placement_marker", &"nav_boundary_marker":
				n += 1
			_:
				pass
	return n


func _initialize() -> void:
	call_deferred("_validate_all")


func _validate_all() -> void:
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
		var zone_nodes := generated_zones.get_child_count() if generated_zones else 0
		var layout_zone_markers := _count_layout_structural_markers(room)
		if zone_nodes < 3 and layout_zone_markers < 3:
			push_error(
				"Room %s is missing structural zone markers (need 3+ in scene or layout)" % room_path
			)
			quit(1)
			return
		if generated_sockets == null:
			push_error("Room %s is missing generated sockets root" % room_path)
			quit(1)
			return
		print(
			"Validated %s | items=%s | sockets=%s | zones=%s | layout_structural=%s" % [
				room_path,
				(layout_items as Array).size(),
				generated_sockets.get_child_count(),
				zone_nodes,
				layout_zone_markers,
			]
		)
		room.queue_free()
		await process_frame
	print("VALIDATED_OUTLINE_ROOMS_OK")
	quit()
