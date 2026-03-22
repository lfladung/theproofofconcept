extends Node

const WALL_THICKNESS := 1.0
const ROOM_HEIGHT := 0.4
const WALL_VISUAL_HEIGHT := 3.0
const WALL_VISUAL_BASE_Y := -0.5
const LABEL_SCALE := 0.2
const CAMERA_LERP_SPEED := 8.0
const WALL_PIECE_SCENE := preload("res://dungeon/modules/structure/wall_segment_2d.tscn")
const DOOR_STANDARD_SCENE := preload("res://dungeon/modules/connectivity/door_standard_2d.tscn")
const DOOR_LOCKED_SCENE := preload("res://dungeon/modules/connectivity/door_locked_2d.tscn")
const ENTRANCE_MARKER_SCENE := preload("res://dungeon/modules/connectivity/entrance_marker_2d.tscn")
const EXIT_MARKER_SCENE := preload("res://dungeon/modules/connectivity/exit_marker_2d.tscn")

@onready var _world_bounds: StaticBody2D = $GameWorld2D/WorldBounds
@onready var _rooms_root: Node2D = $GameWorld2D/Rooms
@onready var _piece_instances_root: Node2D = $GameWorld2D/PieceInstances
@onready var _visual_world: Node3D = $VisualWorld3D
@onready var _room_visuals: Node3D = $VisualWorld3D/RoomVisuals
@onready var _wall_visuals: Node3D = $VisualWorld3D/WallVisuals
@onready var _door_visuals: Node3D = $VisualWorld3D/DoorVisuals
@onready var _camera_pivot: Marker3D = $VisualWorld3D/CameraPivot
@onready var _player: CharacterBody2D = $GameWorld2D/Player
@onready var _combat_clear_timer: Timer = $CombatClearTimer
@onready var _boss_clear_timer: Timer = $BossClearTimer
@onready var _info_label: Label = $CanvasLayer/InfoLabel
@onready var _combat_trigger: Area2D = $GameWorld2D/Triggers/CombatRoomTrigger
@onready var _boss_trigger: Area2D = $GameWorld2D/Triggers/BossRoomTrigger
@onready var _boss_exit_portal: Area2D = $GameWorld2D/Triggers/BossExitPortal

var _combat_started := false
var _combat_cleared := false
var _boss_started := false
var _boss_cleared := false
var _combat_door_west: LockedDoorPiece2D
var _combat_door_east: LockedDoorPiece2D
var _boss_door_west: LockedDoorPiece2D


func _ready() -> void:
	_configure_room_metadata()
	_build_world_bounds()
	_build_room_debug_visuals()
	_spawn_runtime_lock_doors()
	_spawn_entrance_exit_markers()
	_set_combat_doors_locked(false)
	_set_boss_entry_locked(false)
	_boss_exit_portal.monitoring = false
	_boss_exit_portal.monitorable = false
	($VisualWorld3D/BossPortalMarker as MeshInstance3D).visible = false
	_info_label.text = "Explore: Entrance -> Transition -> Combat -> Transition -> Boss. Branch north for Treasure."


func _process(delta: float) -> void:
	if _player == null or _camera_pivot == null:
		return
	var target := Vector3(_player.global_position.x, _camera_pivot.global_position.y, _player.global_position.y)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(target, clampf(delta * CAMERA_LERP_SPEED, 0.0, 1.0))


func _configure_room_metadata() -> void:
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		r.tile_size = Vector2i(3, 3)
		r.standard_room_sizes = PackedInt32Array([9, 15, 24, 36])
		_set_room_sockets_for_layout(r)


func _set_room_sockets_for_layout(room: RoomBase) -> void:
	var openings_by_room: Dictionary = {
		"EntranceRoom": {"east": 2},
		"TransitionRoomA": {"west": 2, "east": 2},
		"CombatRoom": {"west": 2, "east": 2},
		"TransitionRoomB": {"west": 2, "east": 2, "north": 2},
		"BossRoom": {"west": 2},
		"BranchTransitionRoom": {"south": 2, "north": 2},
		"TreasureRoom": {"south": 2},
	}
	var configured: Dictionary = openings_by_room.get(room.name, {}) as Dictionary
	for socket in room.get_all_sockets():
		var width_tiles := int(configured.get(socket.direction, 0))
		if width_tiles <= 0:
			socket.connector_type = &"inactive"
			continue
		socket.connector_type = &"standard"
		socket.width_tiles = width_tiles
		var half_w := room.room_size_tiles.x * room.tile_size.x * 0.5
		var half_h := room.room_size_tiles.y * room.tile_size.y * 0.5
		match socket.direction:
			"north":
				socket.position = Vector2(0, -half_h)
			"south":
				socket.position = Vector2(0, half_h)
			"west":
				socket.position = Vector2(-half_w, 0)
			"east":
				socket.position = Vector2(half_w, 0)
			_:
				pass


func _build_world_bounds() -> void:
	for child in _world_bounds.get_children():
		child.queue_free()
	for child in _piece_instances_root.get_children():
		child.queue_free()
	for child in _wall_visuals.get_children():
		child.queue_free()
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		_add_room_boundary(room as RoomBase)


func _add_room_boundary(room: RoomBase) -> void:
	var rect_local := room.get_room_rect_world()
	var half_w := rect_local.size.x * 0.5
	var half_h := rect_local.size.y * 0.5
	var center := room.global_position
	var openings: Dictionary = {
		"north": [],
		"south": [],
		"east": [],
		"west": [],
	}
	for socket in room.get_all_sockets():
		if socket.connector_type == &"inactive":
			continue
		var width_world := float(socket.width_tiles * room.tile_size.x)
		match socket.direction:
			"north", "south":
				openings[socket.direction].append({"offset": socket.position.x, "width": width_world})
			"east", "west":
				openings[socket.direction].append({"offset": socket.position.y, "width": width_world})
			_:
				pass
	_add_horizontal_wall_segments(center, -half_h, half_w, openings["north"] as Array)
	_add_horizontal_wall_segments(center, half_h, half_w, openings["south"] as Array)
	_add_vertical_wall_segments(center, -half_w, half_h, openings["west"] as Array)
	_add_vertical_wall_segments(center, half_w, half_h, openings["east"] as Array)


func _add_horizontal_wall_segments(
	center: Vector2, local_y: float, half_width: float, openings: Array
) -> void:
	var segments := _segments_from_openings(-half_width, half_width, openings)
	for seg in segments:
		var seg_start: float = seg.x
		var seg_end: float = seg.y
		var width := seg_end - seg_start
		if width <= 0.01:
			continue
		_add_wall_shape(
			Vector2(center.x + (seg_start + seg_end) * 0.5, center.y + local_y),
			Vector2(width, WALL_THICKNESS)
		)


func _add_vertical_wall_segments(center: Vector2, local_x: float, half_height: float, openings: Array) -> void:
	var segments := _segments_from_openings(-half_height, half_height, openings)
	for seg in segments:
		var seg_start: float = seg.x
		var seg_end: float = seg.y
		var height := seg_end - seg_start
		if height <= 0.01:
			continue
		_add_wall_shape(
			Vector2(center.x + local_x, center.y + (seg_start + seg_end) * 0.5),
			Vector2(WALL_THICKNESS, height)
		)


func _segments_from_openings(min_value: float, max_value: float, openings: Array) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	for opening in openings:
		var center_offset := float(opening.get("offset", 0.0))
		var width := maxf(0.0, float(opening.get("width", 0.0)))
		var half_open := width * 0.5
		intervals.append(Vector2(center_offset - half_open, center_offset + half_open))
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var segments: Array[Vector2] = []
	var cursor := min_value
	for interval in intervals:
		var a := clampf(interval.x, min_value, max_value)
		var b := clampf(interval.y, min_value, max_value)
		if a > cursor:
			segments.append(Vector2(cursor, a))
		cursor = maxf(cursor, b)
	if cursor < max_value:
		segments.append(Vector2(cursor, max_value))
	return segments


func _add_wall_shape(position_2d: Vector2, size_2d: Vector2) -> void:
	_add_wall_piece(position_2d, size_2d)
	_add_wall_visual(position_2d, size_2d)


func _add_wall_piece(position_2d: Vector2, size_2d: Vector2) -> void:
	var wall_piece := WALL_PIECE_SCENE.instantiate() as DungeonPiece2D
	if wall_piece == null:
		return
	wall_piece.name = "WallPiece_%s_%s" % [position_2d.x, position_2d.y]
	wall_piece.tile_size = Vector2i(1, 1)
	wall_piece.footprint_tiles = Vector2i(
		maxi(1, int(roundf(size_2d.x))),
		maxi(1, int(roundf(size_2d.y)))
	)
	wall_piece.blocks_movement = true
	wall_piece.walkable = false
	wall_piece.position = position_2d
	_piece_instances_root.add_child(wall_piece)


func _add_wall_visual(position_2d: Vector2, size_2d: Vector2) -> void:
	var wall_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size_2d.x, WALL_VISUAL_HEIGHT, size_2d.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.47, 0.31, 0.20, 1.0)
	box.material = mat
	wall_mesh.mesh = box
	wall_mesh.position = Vector3(
		position_2d.x,
		WALL_VISUAL_BASE_Y + WALL_VISUAL_HEIGHT * 0.5,
		position_2d.y
	)
	_wall_visuals.add_child(wall_mesh)


func _build_room_debug_visuals() -> void:
	for child in _room_visuals.get_children():
		child.queue_free()
	for child in _door_visuals.get_children():
		child.queue_free()
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var rect_local := r.get_room_rect_world()
		var rect := Rect2(rect_local.position + r.global_position, rect_local.size)
		var color := _color_for_room_type(r.room_type)
		_add_room_floor_visual(rect, color, r.name + " (" + r.room_type.to_upper() + ")")
		for socket in r.get_all_sockets():
			if socket.connector_type == &"inactive":
				continue
			_spawn_standard_door_piece(r.global_position + socket.position, socket.width_tiles)
			_add_door_visual(r.global_position + socket.position)


func _add_room_floor_visual(rect: Rect2, color: Color, label_text: String) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(rect.size.x, ROOM_HEIGHT, rect.size.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mesh.mesh = bm
	mesh.position = Vector3(rect.position.x + rect.size.x * 0.5, ROOM_HEIGHT * 0.5 - 0.5, rect.position.y + rect.size.y * 0.5)
	_room_visuals.add_child(mesh)

	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.BLACK
	label.position = Vector3(mesh.position.x, 1.4, mesh.position.z)
	label.scale = Vector3.ONE * LABEL_SCALE
	_room_visuals.add_child(label)


func _add_door_visual(world_pos: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 0.6, 3.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.26, 0.86, 1.0)
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(world_pos.x, -0.15, world_pos.y)
	_door_visuals.add_child(mi)


func _color_for_room_type(room_type: String) -> Color:
	match room_type:
		"corridor", "connector":
			return Color(0.92, 0.92, 0.92, 1.0)
		"treasure":
			return Color(1.0, 0.97, 0.84, 1.0)
		"boss":
			return Color(0.95, 0.88, 0.88, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)


func _set_combat_doors_locked(locked: bool) -> void:
	if _combat_door_west:
		_combat_door_west.set_locked(locked)
	if _combat_door_east:
		_combat_door_east.set_locked(locked)


func _set_boss_entry_locked(locked: bool) -> void:
	if _boss_door_west:
		_boss_door_west.set_locked(locked)


func _spawn_standard_door_piece(world_pos: Vector2, width_tiles: int) -> void:
	var door_piece := DOOR_STANDARD_SCENE.instantiate() as DungeonPiece2D
	if door_piece == null:
		return
	door_piece.tile_size = Vector2i(3, 3)
	door_piece.footprint_tiles = Vector2i(maxi(1, width_tiles), 1)
	door_piece.blocks_movement = false
	door_piece.walkable = true
	door_piece.position = world_pos
	_piece_instances_root.add_child(door_piece)


func _spawn_runtime_lock_doors() -> void:
	_combat_door_west = _spawn_locked_door_piece(Vector2(67.5, 0), 2, "CombatDoorWestPiece")
	_combat_door_east = _spawn_locked_door_piece(Vector2(139.5, 0), 2, "CombatDoorEastPiece")
	_boss_door_west = _spawn_locked_door_piece(Vector2(184.5, 0), 2, "BossDoorWestPiece")


func _spawn_locked_door_piece(world_pos: Vector2, width_tiles: int, node_name: String) -> LockedDoorPiece2D:
	var locked_piece := DOOR_LOCKED_SCENE.instantiate() as LockedDoorPiece2D
	if locked_piece == null:
		return null
	locked_piece.name = node_name
	locked_piece.tile_size = Vector2i(3, 3)
	locked_piece.footprint_tiles = Vector2i(maxi(1, width_tiles), 1)
	locked_piece.position = world_pos
	_piece_instances_root.add_child(locked_piece)
	return locked_piece


func _spawn_entrance_exit_markers() -> void:
	var entrance_pos := ($GameWorld2D/Markers/PlayerSpawnMarker as Marker2D).position
	var exit_pos := ($GameWorld2D/Triggers/BossExitPortal as Area2D).position
	var entrance_marker := ENTRANCE_MARKER_SCENE.instantiate() as ConnectorMarker2D
	if entrance_marker:
		entrance_marker.name = "EntranceMarkerPiece"
		entrance_marker.position = entrance_pos
		_piece_instances_root.add_child(entrance_marker)
	var exit_marker := EXIT_MARKER_SCENE.instantiate() as ConnectorMarker2D
	if exit_marker:
		exit_marker.name = "ExitMarkerPiece"
		exit_marker.position = exit_pos
		_piece_instances_root.add_child(exit_marker)


func _on_combat_room_trigger_body_entered(body: Node2D) -> void:
	if _combat_started or not body.is_in_group(&"player"):
		return
	_combat_started = true
	_set_combat_doors_locked(true)
	_info_label.text = "Combat room locked. Simulating clear trigger..."
	_combat_clear_timer.start()


func _on_combat_clear_timer_timeout() -> void:
	_combat_cleared = true
	_set_combat_doors_locked(false)
	_info_label.text = "Combat room cleared. Doors unlocked."


func _on_boss_room_trigger_body_entered(body: Node2D) -> void:
	if _boss_started or not body.is_in_group(&"player"):
		return
	_boss_started = true
	_set_boss_entry_locked(true)
	_info_label.text = "Boss room engaged. Simulating boss completion..."
	_boss_clear_timer.start()


func _on_boss_clear_timer_timeout() -> void:
	_boss_cleared = true
	_set_boss_entry_locked(false)
	_boss_exit_portal.monitoring = true
	_boss_exit_portal.monitorable = true
	($VisualWorld3D/BossPortalMarker as MeshInstance3D).visible = true
	_info_label.text = "Boss defeated. Exit portal is active."


func _on_boss_exit_portal_body_entered(body: Node2D) -> void:
	if not _boss_cleared or not body.is_in_group(&"player"):
		return
	_info_label.text = "Dungeon complete! POC flow validated."
