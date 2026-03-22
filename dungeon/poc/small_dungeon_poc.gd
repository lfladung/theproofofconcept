extends Node

const WALL_THICKNESS := 1.0
const ROOM_HEIGHT := 0.4
const LABEL_SCALE := 0.2

@onready var _world_bounds: StaticBody2D = $GameWorld2D/WorldBounds
@onready var _rooms_root: Node2D = $GameWorld2D/Rooms
@onready var _visual_world: Node3D = $VisualWorld3D
@onready var _room_visuals: Node3D = $VisualWorld3D/RoomVisuals
@onready var _door_visuals: Node3D = $VisualWorld3D/DoorVisuals
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


func _ready() -> void:
	_configure_room_metadata()
	_build_world_bounds()
	_build_room_debug_visuals()
	_set_combat_doors_locked(false)
	_set_boss_entry_locked(false)
	_boss_exit_portal.monitoring = false
	_boss_exit_portal.monitorable = false
	($VisualWorld3D/BossPortalMarker as MeshInstance3D).visible = false
	_info_label.text = "Explore: Entrance -> Transition -> Combat -> Transition -> Boss. Branch north for Treasure."


func _configure_room_metadata() -> void:
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		r.tile_size = Vector2i(3, 3)
		r.standard_room_sizes = PackedInt32Array([6, 10, 16, 24, 32])
		_set_room_sockets_for_layout(r)


func _set_room_sockets_for_layout(room: RoomBase) -> void:
	var openings_by_room := {
		"EntranceRoom": {"east": 2},
		"TransitionRoomA": {"west": 2, "east": 2},
		"CombatRoom": {"west": 2, "east": 2},
		"TransitionRoomB": {"west": 2, "east": 2, "north": 2},
		"BossRoom": {"west": 2},
		"BranchTransitionRoom": {"south": 2, "north": 2},
		"TreasureRoom": {"south": 2},
	}
	var configured := openings_by_room.get(room.name, {})
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
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		_add_room_boundary(room as RoomBase)


func _add_room_boundary(room: RoomBase) -> void:
	var rect_local := room.get_room_rect_world()
	var half_w := rect_local.size.x * 0.5
	var half_h := rect_local.size.y * 0.5
	var center := room.global_position
	var openings := {
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
	_add_horizontal_wall_segments(center, -half_h, half_w, openings["north"])
	_add_horizontal_wall_segments(center, half_h, half_w, openings["south"])
	_add_vertical_wall_segments(center, -half_w, half_h, openings["west"])
	_add_vertical_wall_segments(center, half_w, half_h, openings["east"])


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
	var cs := CollisionShape2D.new()
	cs.position = position_2d
	var shape := RectangleShape2D.new()
	shape.size = size_2d
	cs.shape = shape
	_world_bounds.add_child(cs)


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
	($GameWorld2D/DoorBlockers/CombatDoorWest/CollisionShape2D as CollisionShape2D).disabled = not locked
	($GameWorld2D/DoorBlockers/CombatDoorEast/CollisionShape2D as CollisionShape2D).disabled = not locked


func _set_boss_entry_locked(locked: bool) -> void:
	($GameWorld2D/DoorBlockers/BossDoorWest/CollisionShape2D as CollisionShape2D).disabled = not locked


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
