extends Node

const PLAYER_SCENE := preload("res://scenes/entities/player.tscn")
const EnemySpawnByEnemyId = preload("res://dungeon/game/enemy_spawn_by_id.gd")
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
		if enemy.has_method(&"configure_spawn"):
			enemy.call(&"configure_spawn", zone.global_position, player_position)
		else:
			enemy.global_position = zone.global_position
		_game_world_2d.add_child(enemy)


## Spawns used by runtime enemies (Triad echo units, Splitter splinters, etc.). `current_scene` in playtest
## is this harness, not `DungeonOrchestrator`, so those mobs call here via the same method name/signature as
## `dungeon_orchestrator_internals.gd` `spawn_runtime_enemy_by_kind`.
func spawn_runtime_enemy_by_kind(
	encounter_id: StringName,
	scene_kind: int,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float = 1.0,
	start_aggro: bool = true
) -> EnemyBase:
	var scene_to_spawn := _playtest_enemy_scene_from_kind(scene_kind)
	if scene_to_spawn == null:
		return null
	var enemy := scene_to_spawn.instantiate() as EnemyBase
	if enemy == null:
		return null
	enemy.apply_speed_multiplier(speed_multiplier)
	enemy.configure_spawn(spawn_position, target_position)
	_game_world_2d.add_child(enemy)
	enemy.set_aggro_enabled(start_aggro)
	if not encounter_id.is_empty():
		enemy.set_meta(&"encounter_id", encounter_id)
	return enemy


## Integer kinds must stay aligned with `dungeon_orchestrator_internals.gd` `ENEMY_SCENE_KIND_*`.
func _playtest_enemy_scene_from_kind(kind: int) -> PackedScene:
	match kind:
		1:
			return EnemySpawnByEnemyId.DASHER_SCENE
		2:
			return EnemySpawnByEnemyId.ARROW_TOWER_SCENE
		3:
			return EnemySpawnByEnemyId.IRON_SENTINEL_SCENE
		4:
			return EnemySpawnByEnemyId.ROBOT_MOB_SCENE
		5:
			return EnemySpawnByEnemyId.SKEWER_SCENE
		6:
			return EnemySpawnByEnemyId.GLAIVER_SCENE
		7:
			return EnemySpawnByEnemyId.RAZORFORM_SCENE
		8:
			return EnemySpawnByEnemyId.SCRAMBLER_SCENE
		9:
			return EnemySpawnByEnemyId.FLOW_DASHER_SCENE
		10:
			return EnemySpawnByEnemyId.FLOWFORM_SCENE
		11:
			return EnemySpawnByEnemyId.STUMBLER_SCENE
		12:
			return EnemySpawnByEnemyId.SHIELDWALL_SCENE
		13:
			return EnemySpawnByEnemyId.WARDEN_SCENE
		14:
			return EnemySpawnByEnemyId.SPLITTER_SCENE
		15:
			return EnemySpawnByEnemyId.ECHOFORM_SCENE
		16:
			return EnemySpawnByEnemyId.TRIAD_SCENE
		17:
			return EnemySpawnByEnemyId.LURKER_SCENE
		18:
			return EnemySpawnByEnemyId.LEECHER_SCENE
		19:
			return EnemySpawnByEnemyId.BINDER_SCENE
		20:
			return EnemySpawnByEnemyId.FIZZLER_SCENE
		21:
			return EnemySpawnByEnemyId.BURSTER_SCENE
		22:
			return EnemySpawnByEnemyId.DETONATOR_SCENE
		23:
			return EnemySpawnByEnemyId.ECHO_SPLINTER_SCENE
		24:
			return EnemySpawnByEnemyId.ECHO_UNIT_SCENE
		_:
			return EnemySpawnByEnemyId.FLOW_DASHER_SCENE


func _enemy_scene_for_zone(zone: ZoneMarker2D) -> PackedScene:
	if zone == null:
		return null
	var resolved_enemy_id := zone.enemy_id
	if resolved_enemy_id == &"":
		resolved_enemy_id = StringName(String(zone.zone_role))
	var from_catalog := EnemySpawnByEnemyId.scene_for_enemy_id(resolved_enemy_id)
	if from_catalog != null:
		return from_catalog
	match resolved_enemy_id:
		&"melee":
			return EnemySpawnByEnemyId.STUMBLER_SCENE
		&"ranged":
			return EnemySpawnByEnemyId.SHIELDWALL_SCENE
		_:
			var pool: Array[PackedScene] = [
				EnemySpawnByEnemyId.STUMBLER_SCENE,
				EnemySpawnByEnemyId.SHIELDWALL_SCENE,
				EnemySpawnByEnemyId.WARDEN_SCENE,
			]
			return pool[randi() % pool.size()]


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
