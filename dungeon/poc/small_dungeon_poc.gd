extends Node

const WALL_THICKNESS := 1.0
const ROOM_HEIGHT := 0.4
const WALL_VISUAL_HEIGHT := 3.0
const WALL_VISUAL_BASE_Y := -0.5
const LABEL_SCALE := 0.2
const CAMERA_LERP_SPEED := 8.0
## ARPG-style diagonal view (yaw) + look-down pitch; applied in _ready().
const CAMERA_DIAG_PITCH_DEG := -44.0
const CAMERA_DIAG_YAW_DEG := 40.0
const WALL_PIECE_SCENE := preload("res://dungeon/modules/structure/wall_segment_2d.tscn")
const DOOR_STANDARD_SCENE := preload("res://dungeon/modules/connectivity/door_standard_2d.tscn")
const ENTRANCE_MARKER_SCENE := preload("res://dungeon/modules/connectivity/entrance_marker_2d.tscn")
const EXIT_MARKER_SCENE := preload("res://dungeon/modules/connectivity/exit_marker_2d.tscn")
const MOB_SCENE := preload("res://mob.tscn")
const SPAWN_POINT_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_point_2d.tscn")
const SPAWN_VOLUME_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_volume_2d.tscn")
const ROOM_TRIGGER_SCENE := preload("res://dungeon/modules/encounter/room_encounter_trigger_2d.tscn")
const DUNGEON_CELL_DOOR_SCENE := preload("res://dungeon/visuals/dungeon_cell_door_3d.tscn")
const STYLIZED_WALL_3D_SCENE := preload("res://art/Meshy_AI_stylized_wall_0322224805_texture.glb")
const FLOOR_WALL_ALBEDO_TEXTURE := preload("res://art/Meshy_AI_stylized_wall_0322224805_texture_0.jpg")
## World units per texture repeat on floors (matches 3×3 room tiles).
const FLOOR_TEXTURE_TILE_WORLD := 3.0
## Matches DoorBlockers / door sockets: slab half-width 1.5, centers on X as placed in the POC scene.
const _DOOR_SLAB_HALF := 1.5
const _COMBAT_DOOR_X_W := 67.5
const _COMBAT_DOOR_X_E := 139.5
const _BOSS_DOOR_X_W := 184.5
## Only clamp bodies in the vertical doorway strip (opening is 6 units tall, ±3).
const _DOOR_CLAMP_Y_EXT := 3.51
const _PLAYER_CLAMP_R := 1.2676448
const _MOB_CLAMP_R := 1.15
## Do not pull actors far outside the door (other rooms).
const _W_EXT_X := 65.0
const _E_EXT_X := 143.0
const _BOSS_W_EXT_X := 182.0

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
@onready var _info_label: Label = $CanvasLayer/InfoLabel
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


func _ready() -> void:
	_camera_pivot.rotation_degrees = Vector3(CAMERA_DIAG_PITCH_DEG, CAMERA_DIAG_YAW_DEG, 0.0)
	_configure_room_metadata()
	_build_world_bounds()
	_build_room_debug_visuals()
	_spawn_encounter_modules()
	_spawn_entrance_exit_markers()
	_set_combat_doors_locked(false, false)
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
	_refresh_encounter_state()


func _physics_process(_delta: float) -> void:
	_apply_hard_door_clamps()


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
	for child in _encounter_modules_root.get_children():
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
	var desired_x := maxf(0.01, size_2d.x)
	var desired_y := maxf(0.01, size_2d.y)
	wall_piece.footprint_tiles = Vector2i(
		maxi(1, int(roundf(desired_x))),
		maxi(1, int(roundf(desired_y)))
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
		var root_to_mesh := root.global_transform.affine_inverse() * mi.global_transform
		var aabb := _transform_aabb_to_space(root_to_mesh, mi.mesh.get_aabb())
		if not any:
			merged = aabb
			any = true
		else:
			merged = merged.merge(aabb)
	return merged if any else AABB()


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
			var combat_visuals := r.name == &"CombatRoom" and (dir_key == "west" or dir_key == "east")
			var key := "%s:%s" % [int(roundf(world_pos.x * 100.0)), int(roundf(world_pos.y * 100.0))]
			if not door_specs_by_key.has(key):
				door_specs_by_key[key] = {
					"world_pos": world_pos,
					"wall_direction": dir_key,
					"use_combat_lock_visuals": combat_visuals,
					"width_tiles": socket.width_tiles,
				}
			elif combat_visuals and not bool((door_specs_by_key[key] as Dictionary).get("use_combat_lock_visuals", false)):
				# Shared openings are discovered from both adjacent rooms; prefer combat-room metadata.
				var existing := door_specs_by_key[key] as Dictionary
				existing["world_pos"] = world_pos
				existing["wall_direction"] = dir_key
				existing["use_combat_lock_visuals"] = true
				existing["width_tiles"] = socket.width_tiles
				door_specs_by_key[key] = existing

	for key in door_specs_by_key.keys():
		var spec := door_specs_by_key[key] as Dictionary
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
		if d == "west":
			west_world = sp
			has_w = true
		elif d == "east":
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
	mesh.position = Vector3(rect.position.x + rect.size.x * 0.5, ROOM_HEIGHT * 0.5 - 0.5, rect.position.y + rect.size.y * 0.5)
	_room_visuals.add_child(mesh)

	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.BLACK
	label.position = Vector3(mesh.position.x, 1.4, mesh.position.z)
	label.scale = Vector3.ONE * LABEL_SCALE
	_room_visuals.add_child(label)


func _add_cell_door_3d(world_pos: Vector2, wall_direction: String, use_combat_lock_visuals: bool) -> DungeonCellDoor3D:
	var door := DUNGEON_CELL_DOOR_SCENE.instantiate() as DungeonCellDoor3D
	door.use_combat_lock_visuals = use_combat_lock_visuals
	door.configure_for_socket(wall_direction)
	door.position = Vector3(world_pos.x, 0.0, world_pos.y)
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
	# Boss west blocking uses _apply_hard_door_clamps while the boss encounter is active.
	pass


func _apply_hard_door_clamps() -> void:
	if bool(_encounter_active.get(&"combat", false)):
		_clamp_combat_doors(_player, _PLAYER_CLAMP_R)
		for n in get_tree().get_nodes_in_group(&"mob"):
			if n is CharacterBody2D:
				_clamp_combat_doors(n as CharacterBody2D, _MOB_CLAMP_R)
	if bool(_encounter_active.get(&"boss", false)):
		_clamp_boss_west_door(_player, _PLAYER_CLAMP_R)
		for n in get_tree().get_nodes_in_group(&"mob"):
			if n is CharacterBody2D:
				_clamp_boss_west_door(n as CharacterBody2D, _MOB_CLAMP_R)


func _clamp_combat_doors(body: CharacterBody2D, radius: float) -> void:
	if body == null:
		return
	var p := body.global_position
	var v := body.velocity
	var changed := false
	if absf(p.y) <= _DOOR_CLAMP_Y_EXT:
		var w_lim := _COMBAT_DOOR_X_W + _DOOR_SLAB_HALF + radius
		if p.x < w_lim and p.x > _W_EXT_X:
			p.x = w_lim
			v.x = maxf(0.0, v.x)
			changed = true
		var e_lim := _COMBAT_DOOR_X_E - _DOOR_SLAB_HALF - radius
		if p.x > e_lim and p.x < _E_EXT_X:
			p.x = e_lim
			v.x = minf(0.0, v.x)
			changed = true
	if changed:
		body.global_position = p
		body.velocity = v


func _clamp_boss_west_door(body: CharacterBody2D, radius: float) -> void:
	if body == null:
		return
	var p := body.global_position
	if absf(p.y) > _DOOR_CLAMP_Y_EXT:
		return
	var inner_lim := _BOSS_DOOR_X_W + _DOOR_SLAB_HALF + radius
	if p.x < inner_lim and p.x > _BOSS_W_EXT_X:
		body.global_position = Vector2(inner_lim, p.y)
		var v := body.velocity
		v.x = maxf(0.0, v.x)
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


func _spawn_encounter_modules() -> void:
	_spawn_points_by_encounter.clear()
	_spawn_volumes_by_encounter.clear()
	_encounter_active = {&"combat": false, &"boss": false}
	_encounter_completed = {&"combat": false, &"boss": false}
	_encounter_mobs = {&"combat": [], &"boss": []}

	_spawn_encounter_trigger(Vector2(103.5, 0), &"combat", "CombatEncounterTrigger")
	_spawn_encounter_trigger(Vector2(238.5, 0), &"boss", "BossEncounterTrigger")

	# Combat room center is (103.5, 0) with half extents ~36x36; bias points toward corners.
	for point_pos in [
		Vector2(73.5, -30),
		Vector2(73.5, 30),
		Vector2(133.5, -30),
		Vector2(133.5, 30),
	]:
		_spawn_enemy_spawn_point(point_pos, &"combat")
	# Keep spawn-volume support, but place volumes near corners to preserve corner-biased spawns.
	_spawn_enemy_spawn_volume(Vector2(78, -27), Vector2(18, 14), &"combat")
	_spawn_enemy_spawn_volume(Vector2(129, 27), Vector2(18, 14), &"combat")

	# Boss room center is (238.5, 0) with half extents ~54x54; spawn near opposite corners.
	_spawn_enemy_spawn_point(Vector2(196.5, -42), &"boss")
	_spawn_enemy_spawn_point(Vector2(280.5, 42), &"boss")
	_spawn_enemy_spawn_volume(Vector2(196.5, 42), Vector2(20, 16), &"boss")


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
			_start_combat_encounter()
		"boss":
			_start_boss_encounter()


func _start_combat_encounter() -> void:
	_combat_started = true
	_encounter_active[&"combat"] = true
	_set_combat_doors_locked(true)
	_info_label.text = "Combat started. Clear all enemies to unlock."
	_spawn_encounter_wave(&"combat", 6, 1.0)


func _start_boss_encounter() -> void:
	_boss_started = true
	_encounter_active[&"boss"] = true
	_set_boss_entry_locked(true)
	_info_label.text = "Boss encounter started. Defeat all enemies."
	_spawn_encounter_wave(&"boss", 2, 1.25)


func _spawn_encounter_wave(encounter_id: StringName, total_count: int, speed_multiplier: float) -> void:
	var spawned := 0
	var points: Array = _spawn_points_by_encounter.get(encounter_id, []) as Array
	var volumes: Array = _spawn_volumes_by_encounter.get(encounter_id, []) as Array
	var player_pos := _player.global_position
	for point_node in points:
		if spawned >= total_count:
			break
		if point_node is EnemySpawnPoint2D:
			var point := point_node as EnemySpawnPoint2D
			_spawn_encounter_mob(encounter_id, point.get_spawn_position(), player_pos, speed_multiplier)
			spawned += 1
	while spawned < total_count:
		if volumes.is_empty():
			break
		var volume_idx := randi() % volumes.size()
		var volume := volumes[volume_idx] as EnemySpawnVolume2D
		_spawn_encounter_mob(encounter_id, volume.sample_spawn_position(), player_pos, speed_multiplier)
		spawned += 1


func _spawn_encounter_mob(
	encounter_id: StringName, spawn_position: Vector2, target_position: Vector2, speed_multiplier: float
) -> void:
	var mob := MOB_SCENE.instantiate() as CreepMob
	if mob == null:
		return
	mob.min_speed *= speed_multiplier
	mob.max_speed *= speed_multiplier
	mob.configure_spawn(spawn_position, target_position)
	$GameWorld2D.add_child(mob)
	if not _encounter_mobs.has(encounter_id):
		_encounter_mobs[encounter_id] = []
	var mobs: Array = _encounter_mobs[encounter_id] as Array
	mobs.append(mob)
	_encounter_mobs[encounter_id] = mobs
	mob.tree_exited.connect(func() -> void: _on_encounter_mob_removed(encounter_id, mob), CONNECT_ONE_SHOT)


func _on_encounter_mob_removed(encounter_id: StringName, mob: CreepMob) -> void:
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
	_info_label.text = "Dungeon complete! POC flow validated."
