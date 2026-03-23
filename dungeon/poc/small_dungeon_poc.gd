extends Node

const WALL_THICKNESS := 1.0
const ROOM_HEIGHT := 0.4
const WALL_VISUAL_HEIGHT := 3.0
## Top surface of the textured floor slabs (everything below world y=0 so the walk plane at y=0 stays clear).
const FLOOR_SLAB_TOP_Y := -0.5
const WALL_VISUAL_BASE_Y := FLOOR_SLAB_TOP_Y
const LABEL_SCALE := 0.2
const CAMERA_LERP_SPEED := 8.0
## ARPG-style diagonal view (yaw) + look-down pitch; applied in _ready().
const CAMERA_DIAG_PITCH_DEG := -44.0
const CAMERA_DIAG_YAW_DEG := 40.0
const WALL_PIECE_SCENE := preload("res://dungeon/modules/structure/wall_segment_2d.tscn")
const DOOR_STANDARD_SCENE := preload("res://dungeon/modules/connectivity/door_standard_2d.tscn")
const ENTRANCE_MARKER_SCENE := preload("res://dungeon/modules/connectivity/entrance_marker_2d.tscn")
const EXIT_MARKER_SCENE := preload("res://dungeon/modules/connectivity/exit_marker_2d.tscn")
const DASHER_SCENE := preload("res://dasher.tscn")
const ARROW_TOWER_SCENE := preload("res://arrow_tower.tscn")
const SPAWN_POINT_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_point_2d.tscn")
const SPAWN_VOLUME_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_volume_2d.tscn")
const ROOM_TRIGGER_SCENE := preload("res://dungeon/modules/encounter/room_encounter_trigger_2d.tscn")
const TREASURE_CHEST_SCENE := preload("res://dungeon/modules/gameplay/treasure_chest_2d.tscn")
const TRAP_TILE_SCENE := preload("res://dungeon/modules/gameplay/trap_tile_2d.tscn")
const DUNGEON_CELL_DOOR_SCENE := preload("res://dungeon/visuals/dungeon_cell_door_3d.tscn")
const STYLIZED_WALL_3D_SCENE := preload("res://art/stylized_wall_texture.glb")
const FLOOR_WALL_ALBEDO_TEXTURE := preload("res://art/stylized_wall_texture_0.jpg")
## World units per texture repeat on floors (matches 3×3 room tiles).
const FLOOR_TEXTURE_TILE_WORLD := 3.0
const _COMBAT_TRAP_OFFSETS: Array[Vector2] = [
	Vector2(-15.5, -20.0),
	Vector2(16.5, 18.0),
]
## Matches DoorBlockers / door sockets: slab half-width (blocker X size * 0.5), centers on X as placed in the POC scene.
const _DOOR_SLAB_HALF := 3.0
const _COMBAT_DOOR_X_W := 67.5
const _COMBAT_DOOR_X_E := 139.5
const _BOSS_DOOR_X_W := 184.5
## Only clamp bodies in the vertical doorway strip (opening is 12 units tall, ±6).
const _DOOR_CLAMP_Y_EXT := 7.02
const _PLAYER_CLAMP_R := 1.2676448
const _MOB_CLAMP_R := 1.15
## Do not pull actors far outside the door (other rooms).
const _W_EXT_X := 65.0
const _E_EXT_X := 143.0
const _BOSS_W_EXT_X := 182.0
const _BOSS_PORTAL_INSET := 1.5
const _SIZE_9_15: PackedInt32Array = [9, 15]
const _SIZE_24_36: PackedInt32Array = [24, 36]

@onready var _world_bounds: StaticBody2D = $GameWorld2D/WorldBounds
@onready var _rooms_root: Node2D = $GameWorld2D/Rooms
@onready var _piece_instances_root: Node2D = $GameWorld2D/PieceInstances
@onready var _encounter_modules_root: Node2D = $GameWorld2D/EncounterModules
@onready var _visual_world: Node3D = $VisualWorld3D
@onready var _room_visuals: Node3D = $VisualWorld3D/RoomVisuals
@onready var _wall_visuals: Node3D = $VisualWorld3D/WallVisuals
@onready var _door_visuals: Node3D = $VisualWorld3D/DoorVisuals
@onready var _camera_pivot: Marker3D = $VisualWorld3D/CameraPivot
@onready var _player: CharacterBody2D = $GameWorld2D/Player
@onready var _info_label: Label = $CanvasLayer/UI/InfoLabel
@onready var _boss_exit_portal: Area2D = $GameWorld2D/Triggers/BossExitPortal

var _combat_started := false
var _combat_cleared := false
var _boss_started := false
var _boss_cleared := false
var _combat_door_visual_west: DungeonCellDoor3D
var _combat_door_visual_east: DungeonCellDoor3D
var _encounter_active: Dictionary = {}
var _encounter_completed: Dictionary = {}
var _encounter_mobs: Dictionary = {}
var _spawn_points_by_encounter: Dictionary = {}
var _spawn_volumes_by_encounter: Dictionary = {}
var _wall_visual_prefab_ready := false
var _wall_visual_prefab_has_mesh := false
var _wall_visual_prefab_aabb := AABB()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _floor_index := 1
var _main_dir := "east"
var _prev_main_dir := ""
var _branch_dir := "north"
var _combat_entry_dir := "west"
var _combat_exit_dir := "east"
var _combat_entry_socket := Vector2.ZERO
var _combat_exit_socket := Vector2.ZERO
var _boss_entry_dir := "west"
var _boss_entry_socket := Vector2.ZERO
var _combat_door_x_w := _COMBAT_DOOR_X_W
var _combat_door_x_e := _COMBAT_DOOR_X_E
var _boss_door_x_w := _BOSS_DOOR_X_W
var _w_ext_x := _W_EXT_X
var _e_ext_x := _E_EXT_X
var _boss_w_ext_x := _BOSS_W_EXT_X
var _retry_pending := false
var _prev_player_pos := Vector2.ZERO
var _prev_player_inside := true
var _prev_room_name := ""
var _floor_transition_pending := false
var _last_assembly_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_rng.randomize()
	_camera_pivot.rotation_degrees = Vector3(CAMERA_DIAG_PITCH_DEG, CAMERA_DIAG_YAW_DEG, 0.0)
	_regenerate_level(true)
	if _player != null and _player.has_signal(&"hit") and not _player.hit.is_connected(_on_player_hit):
		_player.hit.connect(_on_player_hit)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _camera_pivot == null:
		return
	var target := Vector3(_player.global_position.x, _camera_pivot.global_position.y, _player.global_position.y)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(target, clampf(delta * CAMERA_LERP_SPEED, 0.0, 1.0))
	_refresh_encounter_state()


func _physics_process(_delta: float) -> void:
	if _retry_pending:
		return
	if _player != null and is_instance_valid(_player):
		var inside_now := _is_point_inside_any_room(_player.global_position, 1.25)
		var room_now := _room_name_at(_player.global_position, 1.25)
		if not inside_now and _prev_player_inside:
			# Prevent one-frame dash tunneling through thin boundary colliders.
			_player.global_position = _prev_player_pos
			_player.velocity = Vector2.ZERO
			if _player.has_method("set"):
				_player.set("_dodge_time_remaining", 0.0)
			inside_now = true
			room_now = _room_name_at(_player.global_position, 1.25)
		_prev_player_pos = _player.global_position
		_prev_player_inside = inside_now
		_prev_room_name = room_now
	_apply_hard_door_clamps()


func _build_room_graph_links() -> Array[Dictionary]:
	var back_dir := _opposite_direction(_main_dir)
	var links: Array[Dictionary] = [
		{"from": "EntranceRoom", "to": "TransitionRoomA", "from_dir": _main_dir},
		{"from": "TransitionRoomA", "to": "CombatRoom", "from_dir": _main_dir},
		{"from": "CombatRoom", "to": "TransitionRoomB", "from_dir": _main_dir},
		{"from": "TransitionRoomB", "to": "BossRoom", "from_dir": _main_dir, "to_dir": back_dir},
	]
	links.append({"from": "TransitionRoomB", "to": "BranchTransitionRoom", "from_dir": _branch_dir})
	links.append({"from": "BranchTransitionRoom", "to": "TreasureRoom", "from_dir": _branch_dir})
	return links


func _regenerate_level(randomize_layout: bool) -> void:
	_floor_transition_pending = false
	_combat_started = false
	_combat_cleared = false
	_boss_started = false
	_boss_cleared = false
	_retry_pending = false
	_clear_floor_loot()
	for n in get_tree().get_nodes_in_group(&"mob"):
		if n is Node:
			(n as Node).queue_free()
	var assembled_ok := false
	var max_tries := 8 if randomize_layout else 1
	for attempt in range(max_tries):
		_configure_room_metadata(randomize_layout)
		assembled_ok = _assemble_rooms_procedurally()
		if assembled_ok:
			break
	if not assembled_ok and randomize_layout:
		# Guaranteed-safe fallback if randomized attempts fail validation.
		_configure_room_metadata(false)
		assembled_ok = _assemble_rooms_procedurally()
	if not assembled_ok:
		push_warning(
			"Milestone 5 assembly failed after retries (%s validation issues); skipping floor build." % [
				_last_assembly_errors.size()
			]
		)
		return
	_prev_main_dir = _main_dir
	_cache_runtime_door_positions()
	_position_runtime_markers()
	_build_world_bounds()
	_build_room_debug_visuals()
	_spawn_gameplay_objects()
	_spawn_encounter_modules()
	_spawn_entrance_exit_markers()
	_set_combat_doors_locked(false, false)
	_set_boss_entry_locked(false)
	_boss_exit_portal.monitoring = false
	_boss_exit_portal.monitorable = false
	($VisualWorld3D/BossPortalMarker as MeshInstance3D).visible = false
	var entrance_spawn := _room_center_2d(&"EntranceRoom")
	_player.global_position = entrance_spawn
	_player.velocity = Vector2.ZERO
	_prev_player_pos = _player.global_position
	_prev_player_inside = _is_point_inside_any_room(_prev_player_pos, 1.25)
	_prev_room_name = _room_name_at(_prev_player_pos, 1.25)
	_info_label.text = (
		"Floor %s generated. Spawn exit goes %s; treasure branch goes %s." % [
			_floor_index,
			_main_dir,
			_branch_dir,
		]
	)


func _configure_room_metadata(randomize_layout: bool = false) -> void:
	if randomize_layout:
		var options := PackedStringArray(["north", "east", "south", "west"])
		if _prev_main_dir != "":
			options.remove_at(options.find(_prev_main_dir))
		_main_dir = options[_rng.randi() % options.size()]
		var branch_options := _perpendicular_directions(_main_dir)
		_branch_dir = branch_options[_rng.randi() % branch_options.size()]
	else:
		_main_dir = "east"
		_branch_dir = "north"
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		r.tile_size = Vector2i(3, 3)
		r.standard_room_sizes = PackedInt32Array([9, 15, 24, 36])
		if randomize_layout:
			match String(r.name):
				"TransitionRoomA":
					r.room_size_tiles = Vector2i(_pick_from_sizes(_SIZE_9_15), 9)
				"CombatRoom":
					r.room_size_tiles = Vector2i(_pick_from_sizes(_SIZE_24_36), _pick_from_sizes(_SIZE_24_36))
				"TransitionRoomB":
					r.room_size_tiles = Vector2i(_pick_from_sizes(_SIZE_9_15), 9)
				"BossRoom":
					r.room_size_tiles = Vector2i(36, 36)
				"BranchTransitionRoom":
					r.room_size_tiles = Vector2i(9, _pick_from_sizes(_SIZE_9_15))
				"TreasureRoom":
					r.room_size_tiles = Vector2i(_pick_from_sizes(_SIZE_9_15), _pick_from_sizes(_SIZE_9_15))
				_:
					pass
		_set_room_sockets_for_layout(r)


func _pick_from_sizes(options: PackedInt32Array) -> int:
	if options.is_empty():
		return 9
	return int(options[_rng.randi() % options.size()])


func _opposite_direction(direction: String) -> String:
	match direction:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		"west":
			return "east"
		_:
			return ""


func _perpendicular_directions(direction: String) -> PackedStringArray:
	match direction:
		"north", "south":
			return PackedStringArray(["east", "west"])
		"east", "west":
			return PackedStringArray(["north", "south"])
		_:
			return PackedStringArray(["north", "south"])


func _clear_floor_loot() -> void:
	for child in _piece_instances_root.get_children():
		if child is DroppedCoin:
			(child as Node).queue_free()
	# Safety net for any orphaned visual meshes from old floor coins.
	for n in _visual_world.find_children("DroppedCoinMesh", "MeshInstance3D", true, false):
		if n is Node:
			(n as Node).queue_free()


func _assemble_rooms_procedurally() -> bool:
	var assembler: ProceduralAssemblyV1 = ProceduralAssemblyV1.new()
	var links: Array[Dictionary] = _build_room_graph_links()
	var result: Dictionary = assembler.assemble_from_socket_graph(_rooms_root, &"EntranceRoom", links)
	_last_assembly_errors = PackedStringArray()
	if bool(result.get("ok", false)):
		var placed: int = int(result.get("placed_count", 0))
		var total: int = int(result.get("total_rooms", 0))
		print("Milestone 5: procedural assembly ready (%s/%s rooms connected)." % [placed, total])
		return true
	_last_assembly_errors = result.get("errors", PackedStringArray()) as PackedStringArray
	return false


func _room_by_name(room_name: StringName) -> RoomBase:
	var room := _rooms_root.get_node_or_null(String(room_name))
	if room is RoomBase:
		return room as RoomBase
	return null


func _room_half_extents(room: RoomBase) -> Vector2:
	return Vector2(
		float(room.room_size_tiles.x * room.tile_size.x) * 0.5,
		float(room.room_size_tiles.y * room.tile_size.y) * 0.5
	)


func _room_center_2d(room_name: StringName) -> Vector2:
	var room := _room_by_name(room_name)
	return room.global_position if room != null else Vector2.ZERO


func _socket_world_position(room_name: StringName, direction: String) -> Vector2:
	var room := _room_by_name(room_name)
	if room == null:
		return Vector2.ZERO
	for socket in room.get_socket_by_direction(direction):
		if socket.connector_type != &"inactive":
			return room.global_position + socket.position
	return room.global_position


func _cache_runtime_door_positions() -> void:
	_combat_entry_dir = _opposite_direction(_main_dir)
	_combat_exit_dir = _main_dir
	_boss_entry_dir = _opposite_direction(_main_dir)
	_combat_entry_socket = _socket_world_position(&"CombatRoom", _combat_entry_dir)
	_combat_exit_socket = _socket_world_position(&"CombatRoom", _combat_exit_dir)
	_boss_entry_socket = _socket_world_position(&"BossRoom", _boss_entry_dir)
	_combat_door_x_w = _combat_entry_socket.x
	_combat_door_x_e = _combat_exit_socket.x
	_boss_door_x_w = _boss_entry_socket.x
	_w_ext_x = _combat_door_x_w - 2.5
	_e_ext_x = _combat_door_x_e + 3.5
	_boss_w_ext_x = _boss_door_x_w - 2.5


func _position_runtime_markers() -> void:
	var boss_room := _room_by_name(&"BossRoom")
	if boss_room == null:
		return
	var half := _room_half_extents(boss_room)
	var outward := _direction_vector(_main_dir)
	var inset_x := maxf(0.0, half.x - _BOSS_PORTAL_INSET)
	var inset_y := maxf(0.0, half.y - _BOSS_PORTAL_INSET)
	var offset := Vector2(outward.x * inset_x, outward.y * inset_y)
	_boss_exit_portal.position = boss_room.global_position + offset
	var portal_marker := $VisualWorld3D/BossPortalMarker as MeshInstance3D
	if portal_marker != null:
		portal_marker.position = Vector3(_boss_exit_portal.position.x, 0.45, _boss_exit_portal.position.y)


func _direction_vector(direction: String) -> Vector2:
	match direction:
		"north":
			return Vector2(0.0, -1.0)
		"south":
			return Vector2(0.0, 1.0)
		"east":
			return Vector2(1.0, 0.0)
		"west":
			return Vector2(-1.0, 0.0)
		_:
			return Vector2(1.0, 0.0)


func _set_room_sockets_for_layout(room: RoomBase) -> void:
	var back_main: String = _opposite_direction(_main_dir)
	var back_branch: String = _opposite_direction(_branch_dir)
	var trans_b_branch: Dictionary = {_branch_dir: 4}
	var branch_openings: Dictionary = (
		{back_branch: 4, _branch_dir: 4}
	)
	var treasure_openings: Dictionary = {back_branch: 4}
	var openings_by_room: Dictionary = {
		"EntranceRoom": {_main_dir: 4},
		"TransitionRoomA": {back_main: 4, _main_dir: 4},
		"CombatRoom": {back_main: 4, _main_dir: 4},
		"TransitionRoomB": {back_main: 4, _main_dir: 4}.merged(trans_b_branch),
		"BossRoom": {back_main: 4},
		"BranchTransitionRoom": branch_openings,
		"TreasureRoom": treasure_openings,
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
	_free_children_immediate(_world_bounds)
	_free_children_immediate(_piece_instances_root)
	_free_children_immediate(_encounter_modules_root)
	_free_children_immediate(_wall_visuals)
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		_add_room_boundary(room as RoomBase)


func _free_children_immediate(parent: Node) -> void:
	if parent == null:
		return
	var kids := parent.get_children()
	for child in kids:
		if child is Node:
			(child as Node).free()


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
	var desired_x := maxf(0.01, size_2d.x)
	var desired_y := maxf(0.01, size_2d.y)
	var qx := float(maxi(1, int(roundf(desired_x))))
	var qy := float(maxi(1, int(roundf(desired_y))))
	wall_piece.footprint_tiles = Vector2i(
		int(qx),
		int(qy)
	)
	wall_piece.blocks_movement = true
	wall_piece.walkable = false
	wall_piece.position = position_2d
	_piece_instances_root.add_child(wall_piece)


func _add_wall_visual(position_2d: Vector2, size_2d: Vector2) -> void:
	_ensure_wall_visual_prefab_metrics()
	if _wall_visual_prefab_has_mesh:
		var src := _wall_visual_prefab_aabb
		var tiles_x := maxi(1, int(roundf(size_2d.x)))
		var tiles_z := maxi(1, int(roundf(size_2d.y)))
		var module_x := size_2d.x / float(tiles_x)
		var module_z := size_2d.y / float(tiles_z)
		var sx := module_x / maxf(0.01, src.size.x)
		var sy := WALL_VISUAL_HEIGHT / maxf(0.01, src.size.y)
		var sz := module_z / maxf(0.01, src.size.z)
		var src_center := src.get_center()
		var base_x := position_2d.x - size_2d.x * 0.5 + module_x * 0.5
		var base_z := position_2d.y - size_2d.y * 0.5 + module_z * 0.5
		var world_y := WALL_VISUAL_BASE_Y - src.position.y * sy
		for ix in range(tiles_x):
			for iz in range(tiles_z):
				var wall_node := STYLIZED_WALL_3D_SCENE.instantiate() as Node3D
				if wall_node == null:
					continue
				wall_node.scale = Vector3(sx, sy, sz)
				wall_node.position = Vector3(
					base_x + float(ix) * module_x - src_center.x * sx,
					world_y,
					base_z + float(iz) * module_z - src_center.z * sz
				)
				_wall_visuals.add_child(wall_node)
		return

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


func _ensure_wall_visual_prefab_metrics() -> void:
	if _wall_visual_prefab_ready:
		return
	_wall_visual_prefab_ready = true
	var sample := STYLIZED_WALL_3D_SCENE.instantiate() as Node3D
	if sample == null:
		return
	var aabb := _merged_mesh_aabb_in_root_space(sample)
	if aabb.size.length_squared() > 1e-8:
		_wall_visual_prefab_aabb = aabb
		_wall_visual_prefab_has_mesh = true
	sample.free()


func _merged_mesh_aabb_in_root_space(root: Node3D) -> AABB:
	var merged := AABB()
	var any := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor_space(mi, root)
		var aabb := _transform_aabb_to_space(root_to_mesh, mi.mesh.get_aabb())
		if not any:
			merged = aabb
			any = true
		else:
			merged = merged.merge(aabb)
	return merged if any else AABB()


static func _transform_to_ancestor_space(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _transform_aabb_to_space(xf: Transform3D, aabb: AABB) -> AABB:
	var p := aabb.position
	var s := aabb.size
	var corners: Array[Vector3] = [
		Vector3(p.x, p.y, p.z),
		Vector3(p.x + s.x, p.y, p.z),
		Vector3(p.x, p.y + s.y, p.z),
		Vector3(p.x, p.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z),
		Vector3(p.x + s.x, p.y, p.z + s.z),
		Vector3(p.x, p.y + s.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z + s.z),
	]
	var out := AABB()
	var first := true
	for c in corners:
		var wc := xf * c
		if first:
			out = AABB(wc, Vector3.ZERO)
			first = false
		else:
			out = out.expand(wc)
	return out


func _build_room_debug_visuals() -> void:
	for child in _room_visuals.get_children():
		child.queue_free()
	for child in _door_visuals.get_children():
		child.queue_free()
	var door_specs_by_key: Dictionary = {}
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var rect_local := r.get_room_rect_world()
		# Match _add_room_boundary: walls are centered on global_position with half-extents size*0.5.
		# Using rect_local.position + global would offset floors for odd tile counts (asymmetric tile rect).
		var half := rect_local.size * 0.5
		var rect := Rect2(r.global_position - half, rect_local.size)
		var color := _color_for_room_type(r.room_type)
		_add_room_floor_visual(rect, color, r.name + " (" + r.room_type.to_upper() + ")")
		for socket in r.get_all_sockets():
			if socket.connector_type == &"inactive":
				continue
			var world_pos := r.global_position + socket.position
			var dir_key := String(socket.direction)
			var combat_visuals := (
				r.name == &"CombatRoom"
				and (dir_key == _combat_entry_dir or dir_key == _combat_exit_dir)
			)
			var dk := "%s:%s" % [int(roundf(world_pos.x * 100.0)), int(roundf(world_pos.y * 100.0))]
			if not door_specs_by_key.has(dk):
				door_specs_by_key[dk] = {
					"world_pos": world_pos,
					"wall_direction": dir_key,
					"use_combat_lock_visuals": combat_visuals,
					"width_tiles": socket.width_tiles,
				}
			else:
				var existing := door_specs_by_key[dk] as Dictionary
				if combat_visuals and not bool(existing.get("use_combat_lock_visuals", false)):
					# Shared openings are discovered from both adjacent rooms; prefer combat-room metadata.
					existing["world_pos"] = world_pos
					existing["wall_direction"] = dir_key
					existing["use_combat_lock_visuals"] = true
					existing["width_tiles"] = socket.width_tiles
				door_specs_by_key[dk] = existing

	for dk in door_specs_by_key.keys():
		var spec := door_specs_by_key[dk] as Dictionary
		var door_pos := spec["world_pos"] as Vector2
		_spawn_standard_door_piece(door_pos, int(spec.get("width_tiles", 1)))
		_add_cell_door_3d(
			door_pos,
			String(spec.get("wall_direction", "west")),
			bool(spec.get("use_combat_lock_visuals", false))
		)

	_assign_combat_door_visual_refs()


func _assign_combat_door_visual_refs() -> void:
	_combat_door_visual_west = null
	_combat_door_visual_east = null
	var cr := _rooms_root.get_node_or_null("CombatRoom") as RoomBase
	if cr == null:
		return
	var west_world := Vector2.ZERO
	var east_world := Vector2.ZERO
	var has_w := false
	var has_e := false
	for s in cr.get_all_sockets():
		if s.connector_type == &"inactive":
			continue
		var d := String(s.direction)
		var sp := cr.global_position + s.position
		if d == _combat_entry_dir:
			west_world = sp
			has_w = true
		elif d == _combat_exit_dir:
			east_world = sp
			has_e = true
	var best_w: DungeonCellDoor3D = null
	var best_e: DungeonCellDoor3D = null
	var best_dw := 1.0e12
	var best_de := 1.0e12
	for child in _door_visuals.get_children():
		if not child is DungeonCellDoor3D:
			continue
		var asm := child as DungeonCellDoor3D
		if not asm.use_combat_lock_visuals:
			continue
		var flat := Vector2(asm.global_position.x, asm.global_position.z)
		if has_w:
			var dw := flat.distance_to(west_world)
			if dw < best_dw:
				best_dw = dw
				best_w = asm
		if has_e:
			var de := flat.distance_to(east_world)
			if de < best_de:
				best_de = de
				best_e = asm
	const _MAX_SOCK_MATCH := 2.0
	if has_w and best_w != null and best_dw < _MAX_SOCK_MATCH:
		_combat_door_visual_west = best_w
	if has_e and best_e != null and best_de < _MAX_SOCK_MATCH:
		_combat_door_visual_east = best_e


func _add_room_floor_visual(rect: Rect2, color: Color, label_text: String) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(rect.size.x, ROOM_HEIGHT, rect.size.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = FLOOR_WALL_ALBEDO_TEXTURE
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tile := maxf(0.01, FLOOR_TEXTURE_TILE_WORLD)
	mat.uv1_scale = Vector3(rect.size.x / tile, rect.size.y / tile, 1.0)
	mesh.material_override = mat
	mesh.mesh = bm
	var floor_center_y := FLOOR_SLAB_TOP_Y - ROOM_HEIGHT * 0.5
	mesh.position = Vector3(rect.position.x + rect.size.x * 0.5, floor_center_y, rect.position.y + rect.size.y * 0.5)
	_room_visuals.add_child(mesh)

	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.BLACK
	label.position = Vector3(mesh.position.x, FLOOR_SLAB_TOP_Y + 1.85, mesh.position.z)
	label.scale = Vector3.ONE * LABEL_SCALE
	_room_visuals.add_child(label)


func _add_cell_door_3d(world_pos: Vector2, wall_direction: String, use_combat_lock_visuals: bool) -> DungeonCellDoor3D:
	var door := DUNGEON_CELL_DOOR_SCENE.instantiate() as DungeonCellDoor3D
	door.use_combat_lock_visuals = use_combat_lock_visuals
	door.configure_for_socket(wall_direction)
	door.position = Vector3(world_pos.x, FLOOR_SLAB_TOP_Y, world_pos.y)
	_door_visuals.add_child(door)
	return door


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


func _set_combat_doors_locked(locked: bool, animate: bool = true) -> void:
	for asm in [_combat_door_visual_west, _combat_door_visual_east]:
		if asm != null:
			asm.set_combat_locked(locked, animate)


func _set_boss_entry_locked(_locked: bool) -> void:
	# Boss entry blocking uses _apply_hard_door_clamps while the boss encounter is active.
	pass


func _apply_hard_door_clamps() -> void:
	if bool(_encounter_active.get(&"combat", false)):
		_clamp_combat_doors(_player, _PLAYER_CLAMP_R)
		for n in get_tree().get_nodes_in_group(&"mob"):
			if n is CharacterBody2D:
				_clamp_combat_doors(n as CharacterBody2D, _MOB_CLAMP_R)
	if bool(_encounter_active.get(&"boss", false)):
		_clamp_boss_entry_door(_player, _PLAYER_CLAMP_R)
		for n in get_tree().get_nodes_in_group(&"mob"):
			if n is CharacterBody2D:
				_clamp_boss_entry_door(n as CharacterBody2D, _MOB_CLAMP_R)


func _clamp_combat_doors(body: CharacterBody2D, radius: float) -> void:
	if body == null:
		return
	_clamp_to_locked_socket(body, radius, _combat_entry_socket, _combat_entry_dir)
	_clamp_to_locked_socket(body, radius, _combat_exit_socket, _combat_exit_dir)


func _clamp_boss_entry_door(body: CharacterBody2D, radius: float) -> void:
	if body == null:
		return
	_clamp_to_locked_socket(body, radius, _boss_entry_socket, _boss_entry_dir)


func _clamp_to_locked_socket(
	body: CharacterBody2D, radius: float, socket_pos: Vector2, door_direction: String
) -> void:
	if body == null:
		return
	var p := body.global_position
	var v := body.velocity
	var changed := false
	match door_direction:
		"west":
			if absf(p.y - socket_pos.y) <= _DOOR_CLAMP_Y_EXT:
				var lim := socket_pos.x + _DOOR_SLAB_HALF + radius
				if p.x < lim:
					p.x = lim
					v.x = maxf(0.0, v.x)
					changed = true
		"east":
			if absf(p.y - socket_pos.y) <= _DOOR_CLAMP_Y_EXT:
				var lim := socket_pos.x - _DOOR_SLAB_HALF - radius
				if p.x > lim:
					p.x = lim
					v.x = minf(0.0, v.x)
					changed = true
		"north":
			if absf(p.x - socket_pos.x) <= _DOOR_CLAMP_Y_EXT:
				var lim := socket_pos.y + _DOOR_SLAB_HALF + radius
				if p.y < lim:
					p.y = lim
					v.y = maxf(0.0, v.y)
					changed = true
		"south":
			if absf(p.x - socket_pos.x) <= _DOOR_CLAMP_Y_EXT:
				var lim := socket_pos.y - _DOOR_SLAB_HALF - radius
				if p.y > lim:
					p.y = lim
					v.y = minf(0.0, v.y)
					changed = true
		_:
			pass
	if changed:
		body.global_position = p
		body.velocity = v


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


func _spawn_gameplay_objects() -> void:
	var treasure_center := _room_center_2d(&"TreasureRoom")
	var chest := TREASURE_CHEST_SCENE.instantiate() as TreasureChest2D
	if chest:
		chest.name = "TreasureChestPOC"
		chest.coin_count = 10
		# Chest GLB pivot sits low — lift well above sunken floor.
		chest.mesh_ground_y = maxf(1.2, FLOOR_SLAB_TOP_Y + 1.7)
		chest.position = treasure_center
		_piece_instances_root.add_child(chest)
	var combat_center := _room_center_2d(&"CombatRoom")
	for off in _COMBAT_TRAP_OFFSETS:
		_spawn_trap_tile_at(combat_center + off)


func _spawn_trap_tile_at(world_pos: Vector2) -> void:
	var trap := TRAP_TILE_SCENE.instantiate() as TrapTile2D
	if trap == null:
		return
	trap.name = "TrapTile_%s_%s" % [int(world_pos.x), int(world_pos.y)]
	trap.mesh_ground_y = FLOOR_SLAB_TOP_Y + 0.22
	trap.position = world_pos
	_piece_instances_root.add_child(trap)


func _spawn_entrance_exit_markers() -> void:
	var entrance_pos := _room_center_2d(&"EntranceRoom")
	var exit_pos := _boss_exit_portal.position
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


func _spawn_encounter_modules() -> void:
	_spawn_points_by_encounter.clear()
	_spawn_volumes_by_encounter.clear()
	_encounter_active = {&"combat": false, &"boss": false}
	_encounter_completed = {&"combat": false, &"boss": false}
	_encounter_mobs = {&"combat": [], &"boss": []}

	var combat_room := _room_by_name(&"CombatRoom")
	var boss_room := _room_by_name(&"BossRoom")
	if combat_room == null or boss_room == null:
		return
	var combat_center := combat_room.global_position
	var boss_center := boss_room.global_position
	_spawn_encounter_trigger(combat_center, &"combat", "CombatEncounterTrigger")
	_spawn_encounter_trigger(boss_center, &"boss", "BossEncounterTrigger")

	var combat_half := _room_half_extents(combat_room)
	var combat_margin := Vector2(minf(6.0, combat_half.x * 0.35), minf(6.0, combat_half.y * 0.35))
	var cpx := maxf(3.0, combat_half.x - combat_margin.x)
	var cpy := maxf(3.0, combat_half.y - combat_margin.y)
	for point_pos in [
		combat_center + Vector2(-cpx, -cpy),
		combat_center + Vector2(-cpx, cpy),
		combat_center + Vector2(cpx, -cpy),
		combat_center + Vector2(cpx, cpy),
	]:
		_spawn_enemy_spawn_point(point_pos, &"combat")
	var combat_vol_size := Vector2(maxf(12.0, combat_half.x * 0.5), maxf(10.0, combat_half.y * 0.4))
	_spawn_enemy_spawn_volume(combat_center + Vector2(-cpx * 0.78, -cpy * 0.72), combat_vol_size, &"combat")
	_spawn_enemy_spawn_volume(combat_center + Vector2(cpx * 0.78, cpy * 0.72), combat_vol_size, &"combat")

	var boss_half := _room_half_extents(boss_room)
	var bpx := maxf(5.0, boss_half.x - 12.0)
	var bpy := maxf(5.0, boss_half.y - 12.0)
	_spawn_enemy_spawn_point(boss_center + Vector2(-bpx, -bpy), &"boss")
	_spawn_enemy_spawn_point(boss_center + Vector2(bpx, bpy), &"boss")
	var boss_vol_size := Vector2(maxf(16.0, boss_half.x * 0.4), maxf(12.0, boss_half.y * 0.35))
	_spawn_enemy_spawn_volume(boss_center + Vector2(-bpx, bpy), boss_vol_size, &"boss")


func _spawn_encounter_trigger(position_2d: Vector2, encounter_id: StringName, node_name: String) -> void:
	var trigger := ROOM_TRIGGER_SCENE.instantiate() as RoomEncounterTrigger2D
	if trigger == null:
		return
	trigger.name = node_name
	trigger.encounter_id = encounter_id
	trigger.position = position_2d
	trigger.encounter_triggered.connect(_on_encounter_triggered)
	_encounter_modules_root.add_child(trigger)


func _spawn_enemy_spawn_point(position_2d: Vector2, encounter_id: StringName) -> void:
	var point := SPAWN_POINT_SCENE.instantiate() as EnemySpawnPoint2D
	if point == null:
		return
	point.encounter_id = encounter_id
	point.position = position_2d
	_encounter_modules_root.add_child(point)
	if not _spawn_points_by_encounter.has(encounter_id):
		_spawn_points_by_encounter[encounter_id] = []
	var points: Array = _spawn_points_by_encounter[encounter_id] as Array
	points.append(point)
	_spawn_points_by_encounter[encounter_id] = points


func _spawn_enemy_spawn_volume(position_2d: Vector2, size_2d: Vector2, encounter_id: StringName) -> void:
	var volume := SPAWN_VOLUME_SCENE.instantiate() as EnemySpawnVolume2D
	if volume == null:
		return
	volume.encounter_id = encounter_id
	volume.position = position_2d
	volume.size = size_2d
	_encounter_modules_root.add_child(volume)
	if not _spawn_volumes_by_encounter.has(encounter_id):
		_spawn_volumes_by_encounter[encounter_id] = []
	var volumes: Array = _spawn_volumes_by_encounter[encounter_id] as Array
	volumes.append(volume)
	_spawn_volumes_by_encounter[encounter_id] = volumes


func _on_encounter_triggered(encounter_id: StringName) -> void:
	if bool(_encounter_active.get(encounter_id, false)) or bool(_encounter_completed.get(encounter_id, false)):
		return
	match String(encounter_id):
		"combat":
			call_deferred("_start_combat_encounter")
		"boss":
			call_deferred("_start_boss_encounter")


func _start_combat_encounter() -> void:
	_combat_started = true
	_encounter_active[&"combat"] = true
	_set_combat_doors_locked(true)
	_info_label.text = "Combat started. Clear all enemies to unlock."
	var raw_count := 6 + maxi(0, _floor_index - 1)
	var adjusted_count := maxi(1, int(ceili(float(raw_count) * 0.5)))
	_spawn_encounter_wave(&"combat", adjusted_count, 1.0 + float(_floor_index - 1) * 0.08)


func _start_boss_encounter() -> void:
	_boss_started = true
	_encounter_active[&"boss"] = true
	_set_boss_entry_locked(true)
	_info_label.text = "Boss encounter started. Defeat all enemies."
	var raw_count := 2 + int(floor(float(_floor_index - 1) / 2.0))
	var adjusted_count := maxi(1, int(ceili(float(raw_count) * 0.5)))
	_spawn_encounter_wave(
		&"boss",
		adjusted_count,
		1.25 + float(_floor_index - 1) * 0.05
	)


func _spawn_encounter_wave(encounter_id: StringName, total_count: int, speed_multiplier: float) -> void:
	var spawned := 0
	var points: Array = _spawn_points_by_encounter.get(encounter_id, []) as Array
	var volumes: Array = _spawn_volumes_by_encounter.get(encounter_id, []) as Array
	var player_pos := _player.global_position
	var planned_scenes: Array[PackedScene] = []
	if total_count >= 2:
		# Guarantee mixed waves: at least one dasher + one tower when possible.
		planned_scenes.append(DASHER_SCENE)
		planned_scenes.append(ARROW_TOWER_SCENE)
	for i in range(planned_scenes.size(), total_count):
		planned_scenes.append(_pick_enemy_scene(encounter_id))
	for point_node in points:
		if spawned >= total_count:
			break
		if point_node is EnemySpawnPoint2D:
			var point := point_node as EnemySpawnPoint2D
			var scene_for_spawn := planned_scenes[spawned] if spawned < planned_scenes.size() else null
			_spawn_encounter_mob(
				encounter_id,
				point.get_spawn_position(),
				player_pos,
				speed_multiplier,
				scene_for_spawn
			)
			spawned += 1
	while spawned < total_count:
		if volumes.is_empty():
			break
		var volume_idx := randi() % volumes.size()
		var volume := volumes[volume_idx] as EnemySpawnVolume2D
		var scene_for_spawn := planned_scenes[spawned] if spawned < planned_scenes.size() else null
		_spawn_encounter_mob(
			encounter_id,
			volume.sample_spawn_position(),
			player_pos,
			speed_multiplier,
			scene_for_spawn
		)
		spawned += 1


func _spawn_encounter_mob(
	encounter_id: StringName,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	enemy_scene: PackedScene = null
) -> void:
	call_deferred(
		"_spawn_encounter_mob_deferred",
		encounter_id,
		spawn_position,
		target_position,
		speed_multiplier,
		enemy_scene
	)


func _spawn_encounter_mob_deferred(
	encounter_id: StringName,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	enemy_scene: PackedScene = null
) -> void:
	var scene_to_spawn := enemy_scene if enemy_scene != null else _pick_enemy_scene(encounter_id)
	var enemy := scene_to_spawn.instantiate() as EnemyBase
	if enemy == null:
		return
	enemy.apply_speed_multiplier(speed_multiplier)
	enemy.configure_spawn(spawn_position, target_position)
	$GameWorld2D.add_child(enemy)
	if not _encounter_mobs.has(encounter_id):
		_encounter_mobs[encounter_id] = []
	var mobs: Array = _encounter_mobs[encounter_id] as Array
	mobs.append(enemy)
	_encounter_mobs[encounter_id] = mobs
	enemy.tree_exited.connect(func() -> void: _on_encounter_mob_removed(encounter_id, enemy), CONNECT_ONE_SHOT)


func _pick_enemy_scene(encounter_id: StringName) -> PackedScene:
	# Combat rooms mix in towers; boss rooms keep dashers plus occasional tower support.
	var tower_weight := 0.35 if String(encounter_id) == "combat" else 0.25
	return ARROW_TOWER_SCENE if randf() < tower_weight else DASHER_SCENE


func _on_encounter_mob_removed(encounter_id: StringName, mob: EnemyBase) -> void:
	if not _encounter_mobs.has(encounter_id):
		return
	var mobs: Array = _encounter_mobs[encounter_id] as Array
	mobs.erase(mob)
	_encounter_mobs[encounter_id] = mobs


func _refresh_encounter_state() -> void:
	for encounter_key in _encounter_active.keys():
		var encounter_id := encounter_key as StringName
		if not bool(_encounter_active[encounter_id]):
			continue
		var mobs: Array = _encounter_mobs.get(encounter_id, []) as Array
		var alive: Array = []
		for mob in mobs:
			if is_instance_valid(mob):
				alive.append(mob)
		_encounter_mobs[encounter_id] = alive
		if alive.is_empty():
			_complete_encounter(encounter_id)


func _complete_encounter(encounter_id: StringName) -> void:
	_encounter_active[encounter_id] = false
	_encounter_completed[encounter_id] = true
	match String(encounter_id):
		"combat":
			_combat_cleared = true
			_set_combat_doors_locked(false)
			_info_label.text = "Combat room cleared. Doors unlocked."
		"boss":
			_boss_cleared = true
			_set_boss_entry_locked(false)
			_boss_exit_portal.monitoring = true
			_boss_exit_portal.monitorable = true
			($VisualWorld3D/BossPortalMarker as MeshInstance3D).visible = true
			_info_label.text = "Boss defeated. Exit portal is active."


func _on_boss_exit_portal_body_entered(body: Node2D) -> void:
	if not _boss_cleared or not body.is_in_group(&"player"):
		return
	if _floor_transition_pending:
		return
	_floor_transition_pending = true
	_boss_exit_portal.set_deferred("monitoring", false)
	_boss_exit_portal.set_deferred("monitorable", false)
	call_deferred("_deferred_advance_floor_after_portal")


func _deferred_advance_floor_after_portal() -> void:
	if _player != null and _player.has_method(&"heal_to_full"):
		_player.call(&"heal_to_full")
	_floor_index += 1
	_regenerate_level(true)


func _on_player_hit() -> void:
	_retry_pending = true
	_encounter_active[&"combat"] = false
	_encounter_active[&"boss"] = false
	for n in get_tree().get_nodes_in_group(&"mob"):
		if n is Node:
			(n as Node).queue_free()
	_info_label.text = "You died. Press Enter to Retry."


func _unhandled_input(event: InputEvent) -> void:
	if not _retry_pending:
		return
	if event.is_action_pressed("ui_accept"):
		_floor_index = 1
		_prev_main_dir = ""
		_reset_score_ui()
		_regenerate_level(true)
		var spawn := _room_center_2d(&"EntranceRoom")
		if _player != null and _player.has_method(&"reset_for_retry"):
			_player.call(&"reset_for_retry", spawn)


func _reset_score_ui() -> void:
	for n in get_tree().get_nodes_in_group(&"score_ui"):
		if n.has_method(&"reset_score"):
			n.call(&"reset_score")


func _is_point_inside_any_room(world_pos: Vector2, margin: float = 0.0) -> bool:
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var local_rect := r.get_room_rect_world()
		var rect := Rect2(r.global_position - local_rect.size * 0.5, local_rect.size).grow(margin)
		if rect.has_point(world_pos):
			return true
	return false


func _room_name_at(world_pos: Vector2, margin: float = 0.0) -> String:
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var local_rect := r.get_room_rect_world()
		var rect := Rect2(r.global_position - local_rect.size * 0.5, local_rect.size).grow(margin)
		if rect.has_point(world_pos):
			return String(r.name)
	return ""
