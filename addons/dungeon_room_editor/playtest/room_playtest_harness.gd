extends Node

const PLAYER_SCENE := preload("res://scenes/entities/player.tscn")
const DASHER_SCENE := preload("res://scenes/entities/dasher.tscn")
const ARROW_TOWER_SCENE := preload("res://scenes/entities/arrow_tower.tscn")
const IRON_SENTINEL_SCENE := preload("res://scenes/entities/iron_sentinel.tscn")
const ROBOT_MOB_SCENE := preload("res://scenes/entities/robot_mob.tscn")
const CAMERA_FOLLOW_SCRIPT := preload("res://dungeon/game/components/camera_follow.gd")
const SERIALIZER_SCRIPT := preload("res://addons/dungeon_room_editor/core/serializer.gd")
const SCENE_SYNC_SCRIPT := preload("res://addons/dungeon_room_editor/core/scene_sync.gd")
const PREVIEW_BUILDER_SCRIPT := preload("res://addons/dungeon_room_editor/preview/preview_builder.gd")
const CATALOG_PATH := "res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres"
const MANIFEST_PATH := "user://dungeon_room_editor_playtest.json"
const CAMERA_LERP_SPEED := 8.0
const CAMERA_DIAG_PITCH_DEG := -38.0
const CAMERA_DIAG_YAW_DEG := 180.0
const CAMERA_LOCAL_OFFSET := Vector3(0.0, 0.0, 150.0)
const CAMERA_ORTHO_SIZE := 50.0
const CAMERA_FAR := 500.0
const ROOM_BOUNDARY_LAYER := 4
const ROOM_WALL_COLLIDER_THICKNESS := 3.0
const ENEMY_ID_DASHER := &"dasher"
const ENEMY_ID_ARROW_TOWER := &"arrow_tower"
const ENEMY_ID_IRON_SENTINEL := &"iron_sentinel"
const ENEMY_ID_ROBOT_MOB := &"robot_mob"

@onready var _game_world_2d: Node2D = $GameWorld2D
@onready var _visual_world_3d: Node3D = $VisualWorld3D
@onready var _room_visuals: Node3D = $VisualWorld3D/RoomVisuals
@onready var _camera_pivot: Marker3D = $VisualWorld3D/CameraPivot
@onready var _camera: Camera3D = $VisualWorld3D/CameraPivot/Camera

var _serializer = SERIALIZER_SCRIPT.new()
var _scene_sync = SCENE_SYNC_SCRIPT.new()
var _preview_builder = PREVIEW_BUILDER_SCRIPT.new()
var _camera_follow
var _player: CharacterBody2D
var _room: RoomBase


func _ready() -> void:
	_configure_camera_from_main_game()
	var scene_path := _load_manifest_room_path()
	if scene_path.is_empty():
		push_warning("Playtest manifest is missing room_scene_path.")
		return
	var room_scene := load(scene_path) as PackedScene
	if room_scene == null:
		push_warning("Cannot load playtest room scene: %s" % scene_path)
		return
	_room = room_scene.instantiate() as RoomBase
	if _room == null:
		push_warning("Selected playtest scene is not a RoomBase: %s" % scene_path)
		return
	_game_world_2d.add_child(_room)
	var catalog = load(CATALOG_PATH)
	var layout = _room.get(&"authored_layout")
	if layout == null:
		var layout_path := _serializer.layout_path_for_scene(scene_path)
		if ResourceLoader.exists(layout_path):
			layout = load(layout_path)
	if layout != null and catalog != null:
		_scene_sync.sync_room(_room, layout, catalog)
		_remove_generated_room_visuals()
		_room_visuals.position = Vector3.ZERO
		_preview_builder.rebuild_preview(_room_visuals, _room, layout, catalog)
		_align_room_visuals_to_room()
	_build_room_collision_shell()
	_spawn_player()
	_spawn_authored_enemies()
	_initialize_camera_follow()


func _process(delta: float) -> void:
	if _camera_follow == null:
		return
	_camera_follow.tick(delta)


func _spawn_player() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	if player == null:
		return
	_game_world_2d.add_child(player)
	player.global_position = _resolve_player_spawn()
	_player = player
	_snap_camera_to_player()


func _resolve_player_spawn() -> Vector2:
	if _room == null:
		return Vector2.ZERO
	var room_rect := _room.get_room_rect_world()
	return _room.global_position + room_rect.get_center()


func _load_manifest_room_path() -> String:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return ""
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return ""
	var parsed := JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return ""
	return String((parsed as Dictionary).get("room_scene_path", ""))


func _spawn_authored_enemies() -> void:
	if _room == null:
		return
	var player_position := _player.global_position if _player != null and is_instance_valid(_player) else Vector2.ZERO
	for zone in _room.get_zone_markers():
		if zone == null or not is_instance_valid(zone):
			continue
		if zone.zone_type != "enemy_spawn":
			continue
		var enemy_scene := _enemy_scene_for_zone(zone)
		if enemy_scene == null:
			continue
		var enemy := enemy_scene.instantiate() as Node2D
		if enemy == null:
			continue
		_game_world_2d.add_child(enemy)
		if enemy.has_method(&"configure_spawn"):
			enemy.call(&"configure_spawn", zone.global_position, player_position)
		else:
			enemy.global_position = zone.global_position


func _enemy_scene_for_zone(zone: ZoneMarker2D) -> PackedScene:
	if zone == null:
		return null
	var resolved_enemy_id := zone.enemy_id
	if resolved_enemy_id == &"":
		resolved_enemy_id = StringName(String(zone.zone_role))
	match resolved_enemy_id:
		ENEMY_ID_ARROW_TOWER:
			return ARROW_TOWER_SCENE
		ENEMY_ID_IRON_SENTINEL:
			return IRON_SENTINEL_SCENE
		ENEMY_ID_ROBOT_MOB:
			return ROBOT_MOB_SCENE
		ENEMY_ID_DASHER:
			return DASHER_SCENE
		&"melee":
			return DASHER_SCENE
		&"ranged":
			return ARROW_TOWER_SCENE
		_:
			return null


func _remove_generated_room_visuals() -> void:
	if _room == null:
		return
	var generated_visuals := _room.get_node_or_null(^"Visual3DProxy/GeneratedByRoomEditor")
	if generated_visuals != null:
		generated_visuals.free()


func _configure_camera_from_main_game() -> void:
	_camera_pivot.rotation_degrees = Vector3(CAMERA_DIAG_PITCH_DEG, CAMERA_DIAG_YAW_DEG, 0.0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = CAMERA_LOCAL_OFFSET
	_camera.size = CAMERA_ORTHO_SIZE
	_camera.far = CAMERA_FAR
	_camera.current = true


func _initialize_camera_follow() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_camera_follow = CAMERA_FOLLOW_SCRIPT.new()
	_camera_follow.camera_pivot = _camera_pivot
	_camera_follow.player = _player
	_camera_follow.lerp_speed = CAMERA_LERP_SPEED
	add_child(_camera_follow)


func _snap_camera_to_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_camera_pivot.global_position = Vector3(
		_player.global_position.x,
		_camera_pivot.global_position.y,
		_player.global_position.y
	)


func _build_room_collision_shell() -> void:
	if _room == null:
		return
	var existing := _game_world_2d.get_node_or_null(^"GeneratedRoomBounds")
	if existing != null:
		existing.queue_free()
	var container := Node2D.new()
	container.name = "GeneratedRoomBounds"
	_game_world_2d.add_child(container)
	var rect := _room.get_room_rect_world()
	var origin := _room.global_position
	container.add_child(
		_create_wall_body(
			Vector2(origin.x + rect.get_center().x, origin.y + rect.position.y - ROOM_WALL_COLLIDER_THICKNESS * 0.5),
			Vector2(rect.size.x + ROOM_WALL_COLLIDER_THICKNESS * 2.0, ROOM_WALL_COLLIDER_THICKNESS),
			"NorthWall"
		)
	)
	container.add_child(
		_create_wall_body(
			Vector2(origin.x + rect.get_center().x, origin.y + rect.end.y + ROOM_WALL_COLLIDER_THICKNESS * 0.5),
			Vector2(rect.size.x + ROOM_WALL_COLLIDER_THICKNESS * 2.0, ROOM_WALL_COLLIDER_THICKNESS),
			"SouthWall"
		)
	)
	container.add_child(
		_create_wall_body(
			Vector2(origin.x + rect.position.x - ROOM_WALL_COLLIDER_THICKNESS * 0.5, origin.y + rect.get_center().y),
			Vector2(ROOM_WALL_COLLIDER_THICKNESS, rect.size.y),
			"WestWall"
		)
	)
	container.add_child(
		_create_wall_body(
			Vector2(origin.x + rect.end.x + ROOM_WALL_COLLIDER_THICKNESS * 0.5, origin.y + rect.get_center().y),
			Vector2(ROOM_WALL_COLLIDER_THICKNESS, rect.size.y),
			"EastWall"
		)
	)


func _create_wall_body(position: Vector2, size: Vector2, body_name: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = position
	body.collision_layer = ROOM_BOUNDARY_LAYER
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = size
	shape.shape = rect_shape
	body.add_child(shape)
	return body


func _align_room_visuals_to_room() -> void:
	if _room == null or _room_visuals == null:
		return
	var bounds := _compute_room_visual_bounds()
	if bounds.size == Vector3.ZERO:
		return
	var room_rect := _room.get_room_rect_world()
	var visual_center := bounds.get_center()
	var logical_center := room_rect.get_center()
	_room_visuals.position += Vector3(
		logical_center.x - visual_center.x,
		0.0,
		logical_center.y - visual_center.z
	)


func _compute_room_visual_bounds() -> AABB:
	var has_bounds := false
	var bounds := AABB()
	var inverse_root := _room_visuals.global_transform.affine_inverse()
	for child in _room_visuals.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_aabb := _transform_aabb(
			inverse_root * mesh_instance.global_transform,
			mesh_instance.get_aabb()
		)
		if not has_bounds:
			bounds = local_aabb
			has_bounds = true
		else:
			bounds = bounds.merge(local_aabb)
	return bounds if has_bounds else AABB()


func _transform_aabb(transform: Transform3D, aabb: AABB) -> AABB:
	var corners := [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]
	var transformed_position: Vector3 = transform * corners[0]
	var result := AABB(transformed_position, Vector3.ZERO)
	for index in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result
