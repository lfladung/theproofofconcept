extends Node

const WALL_THICKNESS := 1.0
const ROOM_HEIGHT := 0.4
const WALL_VISUAL_HEIGHT := 3.0
## Top surface of the textured floor slabs (everything below world y=0 so the walk plane at y=0 stays clear).
const FLOOR_SLAB_TOP_Y := -0.5
const WALL_VISUAL_BASE_Y := FLOOR_SLAB_TOP_Y
const LABEL_SCALE := 0.2
const CAMERA_LERP_SPEED := 8.0
## Spiral Knights-inspired framing: south-side view with a slight diagonal.
const CAMERA_DIAG_PITCH_DEG := -38.0
const CAMERA_DIAG_YAW_DEG := 180.0
const WALL_PIECE_SCENE := preload("res://dungeon/modules/structure/wall_segment_2d.tscn")
## Stone wall GLB tiles boundary segments (same asset as stone ground tier).
const STONE_WALL_GLB := preload("res://art/environment/walls/stone_wall_texture.glb")
## Ground GLBs tile per room; cycle with dungeon depth (`_floor_index`): metal → grass → dirt → stone.
const GROUND_GLB_METAL := preload("res://art/environment/floors/metal_tile_floor_texture.glb")
const GROUND_GLB_GRASS := preload("res://art/environment/floors/grass_ground_texture.glb")
const GROUND_GLB_DIRT := preload("res://art/environment/floors/dirt_brick_ground_texture.glb")
const GROUND_GLB_STONE := STONE_WALL_GLB
## 2D backdrop PNGs; one is chosen at random when each floor builds.
const BACKDROP_IMAGE_DIR := "res://art/backdrops"
## Full-screen quad along camera -Z (inside Camera3D far plane).
const BACKDROP_QUAD_DISTANCE := 420.0
## Slightly larger than ortho frustum so edges are not visible.
const BACKDROP_QUAD_MARGIN := 1.12
## Far backdrop moves only as a fraction of camera/pivot motion (camera is truth; background nearly static).
const BACKDROP_PARALLAX_CAMERA_FRACTION := 0.02
## Cap accumulated quad shift in camera space so margins can hide edges (0 = no cap).
const BACKDROP_PARALLAX_MAX_OFFSET := 40.0
const LAYOUT_KEY_BACKDROP_TEXTURE_PATH := "backdrop_texture_path"
const DOOR_STANDARD_SCENE := preload("res://dungeon/modules/connectivity/door_standard_2d.tscn")
const ENTRANCE_MARKER_SCENE := preload("res://dungeon/modules/connectivity/entrance_marker_2d.tscn")
const EXIT_MARKER_SCENE := preload("res://dungeon/modules/connectivity/exit_marker_2d.tscn")
const DASHER_SCENE := preload("res://scenes/entities/dasher.tscn")
const ARROW_TOWER_SCENE := preload("res://scenes/entities/arrow_tower.tscn")
const SPAWN_POINT_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_point_2d.tscn")
const SPAWN_VOLUME_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_volume_2d.tscn")
const ROOM_TRIGGER_SCENE := preload("res://dungeon/modules/encounter/room_encounter_trigger_2d.tscn")
const TREASURE_CHEST_SCENE := preload("res://dungeon/modules/gameplay/treasure_chest_2d.tscn")
const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")
const PUZZLE_FLOOR_BUTTON_SCENE := preload("res://dungeon/modules/gameplay/puzzle_floor_button_2d.tscn")
const ROOM_BASE_SCENE := preload("res://dungeon/rooms/base/room_base.tscn")
const TRAP_TILE_SCENE := preload("res://dungeon/modules/gameplay/trap_tile_2d.tscn")
const DUNGEON_CELL_DOOR_SCENE := preload("res://dungeon/visuals/dungeon_cell_door_3d.tscn")
const PLAYER_SCENE := preload("res://scenes/entities/player.tscn")
const LOADOUT_OVERLAY_SCENE := preload("res://scenes/ui/loadout/loadout_overlay.tscn")
const LoadoutRepositoryScript = preload("res://scripts/loadout/loadout_repository.gd")
const ELEVATOR_VISUAL_SCENE := preload("res://art/props/interactables/elevator_texture.glb")
const ENEMY_SCENE_KIND_DASHER := 1
const ENEMY_SCENE_KIND_ARROW_TOWER := 2
## World units per texture repeat on floors (4x4 gameplay tiles at 3 units per tile).
const FLOOR_TEXTURE_TILE_WORLD := 12.0
## Match floor tile size so wall stone pattern lines up at room corners.
const WALL_TEXTURE_TILE_WORLD := FLOOR_TEXTURE_TILE_WORLD
const _COMBAT_TRAP_OFFSETS: Array[Vector2] = [
	Vector2(-7.75, -10.0),
	Vector2(8.25, 9.0),
]
const _TRAP_ROOM_OFFSETS: Array[Vector2] = [
	Vector2(-3.5, -3.5),
	Vector2(3.5, 3.5),
]
## Matches DoorBlockers / door sockets: slab half-width (blocker X size * 0.5), centers on X as placed in the dungeon scene.
const _DOOR_SLAB_HALF := 3.0
## Combat encounter trigger center sits this far past the door slab along the inward normal so the player is clearly inside before combat starts.
const _COMBAT_ENTRY_TRIGGER_INSET := 8.0
const _COMBAT_DOOR_X_W := 67.5
const _COMBAT_DOOR_X_E := 139.5
const _BOSS_DOOR_X_W := 184.5
## Only clamp bodies in the vertical doorway strip (opening is 12 units tall, ±6).
const _DOOR_CLAMP_Y_EXT := 7.02
const _PLAYER_CLAMP_R := 1.2676448
const _MOB_CLAMP_R := 1.15
const _REVIVE_TRIGGER_DISTANCE := _PLAYER_CLAMP_R * 2.0
const _TEAM_REVIVE_HEALTH := 50
## Do not pull actors far outside the door (other rooms).
const _W_EXT_X := 65.0
const _E_EXT_X := 143.0
const _BOSS_W_EXT_X := 182.0
const _BOSS_PORTAL_INSET := 1.5
const _ROOM_SIZE_SCALE := 1.5
const _BACK_HALF_MIN_RATIO := 0.22
const _ELEVATOR_PLAYER_SIZE_MULT := 4.0
const _ELEVATOR_VISUAL_CLEARANCE_Y := 0.12
const _DEBUG_ELEVATOR_YAW_OFFSET_DEG := 180.0
## Arrow towers are biased toward room center; keep planned spawns apart so two never share one spot.
const _TOWER_SPAWN_MIN_SEP := 4.5

@onready var _world_bounds: StaticBody2D = $GameWorld2D/WorldBounds
@onready var _rooms_root: Node2D = $GameWorld2D/Rooms
@onready var _piece_instances_root: Node2D = $GameWorld2D/PieceInstances
@onready var _encounter_modules_root: Node2D = $GameWorld2D/EncounterModules
@onready var _visual_world: Node3D = $VisualWorld3D
@onready var _room_visuals: Node3D = $VisualWorld3D/RoomVisuals
@onready var _wall_visuals: Node3D = $VisualWorld3D/WallVisuals
@onready var _door_visuals: Node3D = $VisualWorld3D/DoorVisuals
@onready var _camera_pivot: Marker3D = $VisualWorld3D/CameraPivot
@onready var _camera_3d: Camera3D = $VisualWorld3D/CameraPivot/Camera
@onready var _info_label: Label = $CanvasLayer/UI/InfoLabel
@onready var _minimap_panel: Control = $CanvasLayer/UI/MinimapPanel
@onready var _weapon_mode_label: Label = $CanvasLayer/UI/WeaponModeLabel
@onready var _boss_exit_portal: Area2D = $GameWorld2D/Triggers/BossExitPortal
@onready var _debug_spawn_exit_portal: Area2D = $GameWorld2D/Triggers/DebugSpawnExitPortal
@onready var _boss_portal_marker: MeshInstance3D = $VisualWorld3D/BossPortalMarker
@onready var _debug_spawn_portal_marker: MeshInstance3D = $VisualWorld3D/DebugSpawnPortalMarker

var _combat_started := false
var _combat_cleared := false
var _boss_started := false
var _boss_cleared := false
var _combat_door_visual_west: DungeonCellDoor3D
var _combat_door_visual_east: DungeonCellDoor3D
var _puzzle_door_visual: DungeonCellDoor3D
var _encounter_active: Dictionary = {}
var _encounter_completed: Dictionary = {}
var _encounter_mobs: Dictionary = {}
var _spawn_points_by_encounter: Dictionary = {}
var _spawn_volumes_by_encounter: Dictionary = {}
var _spawn_count_by_encounter: Dictionary = {}
var _planned_tower_positions_by_encounter: Dictionary = {}
var _entry_socket_by_encounter: Dictionary = {}
var _entry_socket_dir_by_encounter: Dictionary = {}
var _door_visual_by_socket_key: Dictionary = {}
## Neighboring rooms both emit the same boundary segment; keep one collider + one visual.
var _boundary_wall_keys: Dictionary = {}
## Merged mesh AABB in GLB root space (cached per path) for floor tile scaling.
var _floor_glb_aabb_by_path: Dictionary = {}
var _elevator_visual_aabb_cache := AABB()
var _has_elevator_visual_aabb_cache := false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _floor_index := 1
var _map_layout: Dictionary = {}
var _puzzle_solved := false
var _puzzle_gate_socket := Vector2.ZERO
var _combat_entry_dir := "west"
var _combat_exit_dir := "east"
var _combat_entry_socket := Vector2.ZERO
var _combat_exit_socket := Vector2.ZERO
var _combat_encounter_id: StringName = &""
var _boss_entry_dir := "west"
var _boss_entry_socket := Vector2.ZERO
var _puzzle_gate_dir := "east"
var _combat_door_x_w := _COMBAT_DOOR_X_W
var _combat_door_x_e := _COMBAT_DOOR_X_E
var _boss_door_x_w := _BOSS_DOOR_X_W
var _w_ext_x := _W_EXT_X
var _e_ext_x := _E_EXT_X
var _boss_w_ext_x := _BOSS_W_EXT_X
var _party_wipe_pending := false
var _prev_player_pos := Vector2.ZERO
var _prev_player_inside := true
var _prev_room_name := ""
var _floor_transition_pending := false
var _debug_portal_monitor_token := 0
var _last_assembly_errors: PackedStringArray = PackedStringArray()
var _room_queries: RoomQueryService
var _info_controller: InfoLabelController
var _camera_follow: CameraFollowController
var _door_lock_controller: DoorLockController
var _dungeon_world_environment: WorldEnvironment
var _dungeon_environment: Environment
var _backdrop_quad: MeshInstance3D
var _boss_exit_elevator_visual: Node3D
var _debug_spawn_exit_elevator_visual: Node3D
var _player: CharacterBody2D
var _players_by_peer: Dictionary = {}
var _peer_slots: Dictionary = {}
var _loadout_repository: Node
var _loadout_overlay: Control
var _network_session: Node
var _networked_run := false
var _bound_hit_player: CharacterBody2D
var _weapon_ui_bound_player: CharacterBody2D
var _has_generated_floor := false
var _enemy_nodes_by_network_id: Dictionary = {}
var _enemy_network_id_sequence := 0
var _coin_nodes_by_network_id: Dictionary = {}
var _coin_network_id_sequence := 0
var _coin_totals_by_peer: Dictionary = {}
var _shared_coin_total := 0
var _awaiting_layout_snapshot := false
## Accumulated LevelBackdropQuad position in Camera3D local XY (Z from BACKDROP_QUAD_DISTANCE).
var _backdrop_offset_cam := Vector3.ZERO
var _prev_backdrop_camera_ref := Vector3.ZERO
@export var show_combat_debug_overlay := true
@export var show_fps_counter := true
@export var combat_debug_update_interval := 0.25
@export var fps_counter_update_interval := 0.25
var _combat_debug_label: Label
var _combat_debug_last_text := ""
var _combat_debug_refresh_time_remaining := 0.0
var _fps_counter_label: Label
var _fps_counter_last_text := ""
var _fps_counter_refresh_time_remaining := 0.0

func _ready() -> void:
	_rng.randomize()
	_camera_pivot.rotation_degrees = Vector3(CAMERA_DIAG_PITCH_DEG, CAMERA_DIAG_YAW_DEG, 0.0)
	_network_session = get_node_or_null("/root/NetworkSession")
	_networked_run = _network_session != null and _network_session.has_method("has_active_peer") and bool(
		_network_session.call("has_active_peer")
	)
	if (
		_network_session != null
		and _network_session.has_signal("peer_slot_map_changed")
		and not _network_session.peer_slot_map_changed.is_connected(_on_network_slot_map_changed)
	):
		_network_session.peer_slot_map_changed.connect(_on_network_slot_map_changed)
	_ensure_loadout_repository()
	_initialize_player_roster()
	_ensure_coin_totals_for_roster()
	_refresh_local_coin_ui()
	_room_queries = RoomQueryService.new()
	_room_queries.rooms_root = _rooms_root
	add_child(_room_queries)
	_info_controller = InfoLabelController.new()
	_info_controller.info_label = _info_label
	_info_controller.player = _player
	_info_controller.room_queries = _room_queries
	add_child(_info_controller)
	_bind_minimap_runtime()
	_camera_follow = CameraFollowController.new()
	_camera_follow.camera_pivot = _camera_pivot
	_camera_follow.player = _player
	_camera_follow.lerp_speed = CAMERA_LERP_SPEED
	add_child(_camera_follow)
	_door_lock_controller = DoorLockController.new()
	_door_lock_controller.door_slab_half = _DOOR_SLAB_HALF
	_door_lock_controller.door_clamp_y_ext = _DOOR_CLAMP_Y_EXT
	_door_lock_controller.resolve_room_name_for_body = _door_resolve_room_name_for_body
	add_child(_door_lock_controller)
	_ensure_combat_debug_overlay()
	_ensure_fps_counter()
	_ensure_loadout_overlay()
	_regenerate_level(true)
	_bind_local_player_runtime_hooks()


func _multiplayer_api_safe() -> MultiplayerAPI:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_multiplayer()


func _local_peer_id() -> int:
	var mp := _multiplayer_api_safe()
	return mp.get_unique_id() if mp != null and mp.multiplayer_peer != null else 1


func _is_authoritative_world() -> bool:
	if not _networked_run:
		return true
	var mp := _multiplayer_api_safe()
	return mp != null and mp.multiplayer_peer != null and mp.is_server()


func _has_multiplayer_peer() -> bool:
	var mp := _multiplayer_api_safe()
	return mp != null and mp.multiplayer_peer != null


func _is_server_peer() -> bool:
	var mp := _multiplayer_api_safe()
	return mp != null and mp.multiplayer_peer != null and mp.is_server()


func _is_dedicated_server_session() -> bool:
	return (
		_network_session != null
		and _network_session.has_method("is_dedicated_server")
		and bool(_network_session.call("is_dedicated_server"))
	)


func _can_broadcast_world_replication() -> bool:
	if not _networked_run:
		return true
	if not _is_server_peer() or not _has_multiplayer_peer():
		return false
	if _network_session != null and _network_session.has_method("can_broadcast_world_replication"):
		return bool(_network_session.call("can_broadcast_world_replication"))
	return true


func _next_enemy_network_id() -> int:
	_enemy_network_id_sequence += 1
	return _enemy_network_id_sequence


func _enemy_scene_kind_from_scene(scene: PackedScene) -> int:
	if scene == ARROW_TOWER_SCENE:
		return ENEMY_SCENE_KIND_ARROW_TOWER
	return ENEMY_SCENE_KIND_DASHER


func _enemy_scene_kind_from_enemy_instance(enemy: EnemyBase) -> int:
	if enemy is ArrowTowerMob:
		return ENEMY_SCENE_KIND_ARROW_TOWER
	return ENEMY_SCENE_KIND_DASHER


func _enemy_scene_from_kind(kind: int) -> PackedScene:
	match kind:
		ENEMY_SCENE_KIND_ARROW_TOWER:
			return ARROW_TOWER_SCENE
		_:
			return DASHER_SCENE


func _register_encounter_enemy(encounter_id: StringName, enemy: EnemyBase) -> void:
	if enemy == null:
		return
	enemy.set_meta(&"encounter_id", encounter_id)
	if not _encounter_mobs.has(encounter_id):
		_encounter_mobs[encounter_id] = []
	var mobs: Array = _encounter_mobs[encounter_id] as Array
	mobs.append(enemy)
	_encounter_mobs[encounter_id] = mobs
	enemy.tree_exited.connect(
		func() -> void: _on_encounter_mob_removed(encounter_id, enemy),
		CONNECT_ONE_SHOT
	)
	if enemy.has_signal(&"coin_drop_requested") and not enemy.coin_drop_requested.is_connected(
		_on_enemy_coin_drop_requested
	):
		enemy.coin_drop_requested.connect(_on_enemy_coin_drop_requested)


func _register_enemy_network_id(enemy: EnemyBase, net_id: int) -> void:
	if enemy == null or net_id <= 0:
		return
	enemy.name = "Enemy_%s" % [net_id]
	enemy.set_meta(&"enemy_network_id", net_id)
	enemy.set_multiplayer_authority(1, true)
	_enemy_nodes_by_network_id[net_id] = enemy


func _next_coin_network_id() -> int:
	_coin_network_id_sequence += 1
	return _coin_network_id_sequence


func _normalize_coin_totals(raw_totals: Dictionary) -> Dictionary:
	var out := {}
	for key in raw_totals.keys():
		out[int(key)] = maxi(0, int(raw_totals[key]))
	return out


func _ensure_coin_totals_for_roster() -> void:
	var max_total := _shared_coin_total
	for value in _coin_totals_by_peer.values():
		max_total = maxi(max_total, int(value))
	_shared_coin_total = maxi(0, max_total)
	var peer_ids: Array[int] = _overlay_sorted_player_peer_ids()
	if peer_ids.is_empty():
		peer_ids.append(_local_peer_id())
	for peer_id in peer_ids:
		_coin_totals_by_peer[peer_id] = _shared_coin_total


func _refresh_local_coin_ui() -> void:
	var local_total := _shared_coin_total
	for n in get_tree().get_nodes_in_group(&"score_ui"):
		if n.has_method(&"set_score"):
			n.call(&"set_score", local_total)
		elif n.has_method(&"reset_score"):
			n.call(&"reset_score")
			if n.has_method(&"add_score") and local_total > 0:
				n.call(&"add_score", local_total)


func _broadcast_coin_totals_if_server() -> void:
	if not _networked_run or not _is_server_peer() or not _has_multiplayer_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_sync_coin_totals.rpc(_coin_totals_by_peer)


func _layout_snapshot_payload() -> Dictionary:
	return _map_layout.duplicate(true)


func _request_layout_snapshot_from_server() -> void:
	if not _networked_run or _is_authoritative_world() or not _has_multiplayer_peer():
		return
	if _awaiting_layout_snapshot:
		return
	_awaiting_layout_snapshot = true
	_rpc_request_layout_snapshot.rpc_id(1)


func _request_runtime_snapshot_from_server() -> void:
	if not _networked_run or _is_authoritative_world() or not _has_multiplayer_peer():
		return
	_rpc_request_runtime_snapshot.rpc_id(1)


func _broadcast_layout_snapshot_if_server() -> void:
	if not _networked_run or not _is_server_peer() or not _has_multiplayer_peer():
		return
	if _map_layout.is_empty():
		return
	_rpc_receive_layout_snapshot.rpc(_floor_index, _layout_snapshot_payload())


func _normalize_slot_map(slot_map: Dictionary) -> Dictionary:
	var out := {}
	for key in slot_map.keys():
		out[int(key)] = int(slot_map[key])
	return out


func _peer_ids_sorted_by_slot(slot_map: Dictionary) -> Array[int]:
	var keyed: Array[Dictionary] = []
	for peer_id in slot_map.keys():
		keyed.append({"peer_id": int(peer_id), "slot": int(slot_map[peer_id])})
	keyed.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var sa := int(a.get("slot", 0))
			var sb := int(b.get("slot", 0))
			if sa == sb:
				return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
			return sa < sb
	)
	var out: Array[int] = []
	for entry in keyed:
		out.append(int(entry.get("peer_id", 0)))
	return out


func _assign_player_authority(player: CharacterBody2D, peer_id: int) -> void:
	if player == null:
		return
	player.set_multiplayer_authority(peer_id, true)
	player.set_meta(&"peer_id", peer_id)
	if player.has_method("set_network_owner_peer_id"):
		player.call("set_network_owner_peer_id", peer_id)


func _ensure_player_node_for_peer(peer_id: int) -> CharacterBody2D:
	var existing: Variant = _players_by_peer.get(peer_id, null)
	if existing is CharacterBody2D and is_instance_valid(existing):
		var found := existing as CharacterBody2D
		_assign_player_authority(found, peer_id)
		return found
	var desired_name := "PlayerPeer_%s" % [peer_id]
	var conflicting := $GameWorld2D.get_node_or_null(NodePath(desired_name)) as CharacterBody2D
	if conflicting != null and conflicting != existing:
		$GameWorld2D.remove_child(conflicting)
		conflicting.queue_free()
	var spawned := PLAYER_SCENE.instantiate() as CharacterBody2D
	if spawned == null:
		return null
	spawned.name = desired_name
	$GameWorld2D.add_child(spawned)
	_assign_player_authority(spawned, peer_id)
	return spawned


func _initialize_player_roster() -> void:
	_players_by_peer.clear()
	_peer_slots.clear()
	var slot_map: Dictionary = {}
	if not _networked_run:
		slot_map[_local_peer_id()] = 0
	elif _network_session != null and _network_session.has_method("get_peer_slot_map"):
		slot_map = _network_session.call("get_peer_slot_map") as Dictionary
	_apply_player_roster_from_slot_map(slot_map)


func _apply_player_roster_from_slot_map(raw_slot_map: Dictionary) -> void:
	var slot_map: Dictionary = _normalize_slot_map(raw_slot_map)
	if slot_map.is_empty() and not _networked_run:
		slot_map[1] = 0
	_peer_slots = slot_map
	var ordered_peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	var seen: Dictionary = {}
	for peer_id in ordered_peer_ids:
		var p: CharacterBody2D = _ensure_player_node_for_peer(peer_id)
		if p == null:
			continue
		_players_by_peer[peer_id] = p
		_bind_player_loadout_runtime(p, peer_id)
		seen[peer_id] = true
	for key in _players_by_peer.keys():
		var peer_id := int(key)
		if seen.has(peer_id):
			continue
		var stale: Variant = _players_by_peer[peer_id]
		if stale is CharacterBody2D and is_instance_valid(stale):
			(stale as CharacterBody2D).queue_free()
		_players_by_peer.erase(peer_id)
	var local_peer := _local_peer_id()
	var resolved_local := _players_by_peer.get(local_peer, null) as CharacterBody2D
	if resolved_local == null:
		var is_headless_dedicated := (
			_networked_run and _is_server_peer() and _is_dedicated_server_session()
		)
		if not is_headless_dedicated:
			resolved_local = _ensure_player_node_for_peer(local_peer)
			if resolved_local != null:
				_players_by_peer[local_peer] = resolved_local
				_bind_player_loadout_runtime(resolved_local, local_peer)
	_player = resolved_local
	_ensure_coin_totals_for_roster()
	_refresh_local_coin_ui()
	_broadcast_coin_totals_if_server()
	_bind_local_player_runtime_hooks()
	_log_player_authority_roster("slot_map")
	if _has_generated_floor:
		var spawn_anchor: Vector2 = (
			_player.global_position if _player != null and is_instance_valid(_player) else Vector2.ZERO
		)
		_position_uninitialized_players(spawn_anchor)


func _on_network_slot_map_changed(slot_map: Dictionary) -> void:
	_apply_player_roster_from_slot_map(slot_map)


func _ensure_loadout_repository() -> void:
	if _loadout_repository != null and is_instance_valid(_loadout_repository):
		return
	_loadout_repository = LoadoutRepositoryScript.new()
	_loadout_repository.name = "LoadoutRepository"
	add_child(_loadout_repository)


func _ensure_loadout_overlay() -> void:
	var ui_root := get_node_or_null("CanvasLayer/UI") as Control
	if ui_root == null:
		return
	if _loadout_overlay != null and is_instance_valid(_loadout_overlay):
		return
	var existing := ui_root.get_node_or_null("LoadoutOverlay") as Control
	if existing != null:
		_loadout_overlay = existing
	else:
		var overlay := LOADOUT_OVERLAY_SCENE.instantiate() as Control
		if overlay == null:
			return
		overlay.name = "LoadoutOverlay"
		ui_root.add_child(overlay)
		_loadout_overlay = overlay
	if _loadout_overlay != null and _loadout_overlay.has_method(&"bind_player"):
		_loadout_overlay.call(&"bind_player", _player, Callable(self, "_room_type_at"))


func _loadout_owner_id_for_peer(peer_id: int) -> StringName:
	return StringName("peer_%s" % [maxi(1, peer_id)])


func _loadout_owner_id_for_player(player: CharacterBody2D) -> StringName:
	if player == null:
		return &""
	var peer_id := int(player.get_meta(&"peer_id", player.get_multiplayer_authority()))
	return _loadout_owner_id_for_peer(peer_id)


func _bind_player_loadout_runtime(player: CharacterBody2D, peer_id: int) -> void:
	if player == null:
		return
	var owner_id := _loadout_owner_id_for_peer(peer_id)
	if _is_authoritative_world() and _loadout_repository != null and _loadout_repository.has_method(&"ensure_owner_initialized"):
		_loadout_repository.call(&"ensure_owner_initialized", owner_id)
	if player.has_method(&"bind_loadout_runtime"):
		player.call(&"bind_loadout_runtime", self, Callable(self, "_room_type_at"), owner_id)
	if (
		_is_authoritative_world()
		and _loadout_repository != null
		and _loadout_repository.has_method(&"get_snapshot")
		and player.has_method(&"apply_authoritative_loadout_snapshot")
	):
		var snapshot_v: Variant = _loadout_repository.call(&"get_snapshot", owner_id)
		if snapshot_v is Dictionary:
			player.call(&"apply_authoritative_loadout_snapshot", snapshot_v as Dictionary)


func get_player_loadout_snapshot(player: CharacterBody2D) -> Dictionary:
	if player == null:
		return {}
	if _is_authoritative_world() and _loadout_repository != null and _loadout_repository.has_method(&"get_snapshot"):
		return _loadout_repository.call(&"get_snapshot", _loadout_owner_id_for_player(player)) as Dictionary
	if player.has_method(&"get_loadout_view_model"):
		var snapshot_v: Variant = player.call(&"get_loadout_view_model")
		if snapshot_v is Dictionary:
			return snapshot_v as Dictionary
	return {}


func handle_player_loadout_request(player: CharacterBody2D, action: StringName, value: StringName) -> Dictionary:
	if player == null or _loadout_repository == null:
		return {"ok": false, "message": "Loadout repository is unavailable.", "snapshot": {}}
	var owner_id := _loadout_owner_id_for_player(player)
	var context := {
		"safe_room_only": true,
		"is_safe_room": _room_type_at(player.global_position, 1.25) == "safe",
	}
	var result: Dictionary = {}
	match action:
		&"equip":
			result = _loadout_repository.call(&"request_equip", owner_id, value, context) as Dictionary
		&"unequip":
			result = _loadout_repository.call(&"request_unequip", owner_id, value, context) as Dictionary
		_:
			result = {"ok": false, "message": "Unsupported loadout action.", "snapshot": {}}
	if bool(result.get("ok", false)):
		var snapshot_v: Variant = result.get("snapshot", {})
		if snapshot_v is Dictionary:
			_apply_loadout_snapshot_to_player_and_replicate(player, snapshot_v as Dictionary)
	return result


func _apply_loadout_snapshot_to_player_and_replicate(player: CharacterBody2D, snapshot: Dictionary) -> void:
	if player == null or snapshot.is_empty():
		return
	if player.has_method(&"apply_authoritative_loadout_snapshot"):
		player.call(&"apply_authoritative_loadout_snapshot", snapshot)
	if _networked_run and _is_server_peer() and _has_multiplayer_peer() and _can_broadcast_world_replication():
		player.rpc(&"_rpc_receive_loadout_snapshot", snapshot)


func _bind_local_player_runtime_hooks() -> void:
	_bind_minimap_runtime()
	if _player == null:
		return
	if _bound_hit_player != null and _bound_hit_player.has_signal(&"hit") and _bound_hit_player.hit.is_connected(
		_on_player_hit
	):
		_bound_hit_player.hit.disconnect(_on_player_hit)
	_bound_hit_player = _player
	var local_player_authority := (
		not _has_multiplayer_peer() or _bound_hit_player.is_multiplayer_authority()
	)
	if (
		local_player_authority
		and _bound_hit_player.has_signal(&"hit")
		and not _bound_hit_player.hit.is_connected(_on_player_hit)
	):
		_bound_hit_player.hit.connect(_on_player_hit)
	_connect_player_weapon_ui()
	if _camera_follow != null:
		_camera_follow.player = _player
	if _info_controller != null:
		_info_controller.player = _player
	if _loadout_overlay != null and _loadout_overlay.has_method(&"bind_player"):
		_loadout_overlay.call(&"bind_player", _player, Callable(self, "_room_type_at"))
	_refresh_combat_debug_overlay(0.0, true)


func _bind_minimap_runtime() -> void:
	if _minimap_panel == null:
		return
	if _minimap_panel.has_method(&"bind_rooms_root"):
		_minimap_panel.call(&"bind_rooms_root", _rooms_root)
	if _minimap_panel.has_method(&"bind_player"):
		_minimap_panel.call(&"bind_player", _player)
	if _minimap_panel.has_method(&"refresh"):
		_minimap_panel.call(&"refresh")


func _connect_player_weapon_ui() -> void:
	if _player == null or _weapon_mode_label == null:
		return
	if (
		_weapon_ui_bound_player != null
		and _weapon_ui_bound_player.has_signal(&"weapon_mode_changed")
		and _weapon_ui_bound_player.weapon_mode_changed.is_connected(_on_player_weapon_mode_changed)
	):
		_weapon_ui_bound_player.weapon_mode_changed.disconnect(_on_player_weapon_mode_changed)
	_weapon_ui_bound_player = _player
	if _weapon_ui_bound_player.has_signal(&"weapon_mode_changed") and not _weapon_ui_bound_player.weapon_mode_changed.is_connected(
		_on_player_weapon_mode_changed
	):
		_weapon_ui_bound_player.weapon_mode_changed.connect(_on_player_weapon_mode_changed)
	if _player.has_method(&"get_weapon_mode_display"):
		var wname: Variant = _player.call(&"get_weapon_mode_display")
		_weapon_mode_label.text = "Weapon: %s" % String(wname)


func _on_player_weapon_mode_changed(display_name: String) -> void:
	if _weapon_mode_label != null:
		_weapon_mode_label.text = "Weapon: %s" % display_name


func _process(delta: float) -> void:
	if _camera_follow != null:
		_camera_follow.tick(delta)
	_refresh_info_label_with_room_type()
	_refresh_combat_debug_overlay(delta)
	_refresh_fps_counter(delta)
	if _is_authoritative_world():
		_process_authoritative_revive_and_wipe()
		_refresh_encounter_state()
		_try_schedule_floor_advance_if_all_players_on_elevator()
		_try_schedule_floor_advance_if_all_players_on_debug_elevator()
	_update_backdrop_parallax()
	_update_backdrop_quad_transform()


func _ensure_combat_debug_overlay() -> void:
	var ui_root := get_node_or_null("CanvasLayer/UI") as Control
	if ui_root == null:
		return
	var existing := ui_root.get_node_or_null("CombatDebugLabel") as Label
	if existing != null:
		_combat_debug_label = existing
	else:
		var lbl := Label.new()
		lbl.name = "CombatDebugLabel"
		lbl.layout_mode = 1
		lbl.offset_left = 10.0
		lbl.offset_top = 82.0
		lbl.offset_right = 860.0
		lbl.offset_bottom = 246.0
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = "CombatDebug: pending"
		ui_root.add_child(lbl)
		_combat_debug_label = lbl
	_combat_debug_label.offset_bottom = maxf(_combat_debug_label.offset_bottom, 246.0)
	_combat_debug_label.visible = show_combat_debug_overlay
	_refresh_combat_debug_overlay(0.0, true)


func _ensure_fps_counter() -> void:
	var ui_root := get_node_or_null("CanvasLayer/UI") as Control
	if ui_root == null:
		return
	var existing := ui_root.get_node_or_null("FpsCounterLabel") as Label
	if existing != null:
		_fps_counter_label = existing
	else:
		var lbl := Label.new()
		lbl.name = "FpsCounterLabel"
		lbl.layout_mode = 1
		lbl.anchors_preset = 1
		lbl.anchor_left = 1.0
		lbl.anchor_right = 1.0
		lbl.offset_left = -188.0
		lbl.offset_top = 244.0
		lbl.offset_right = -14.0
		lbl.offset_bottom = 270.0
		lbl.grow_horizontal = 0
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
		lbl.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.85))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.text = "FPS: --"
		ui_root.add_child(lbl)
		_fps_counter_label = lbl
	_fps_counter_label.visible = show_fps_counter
	_refresh_fps_counter(0.0)


func _refresh_fps_counter(delta: float) -> void:
	if _fps_counter_label == null:
		return
	_fps_counter_label.visible = show_fps_counter
	if not show_fps_counter:
		return
	_fps_counter_refresh_time_remaining = maxf(0.0, _fps_counter_refresh_time_remaining - delta)
	if _fps_counter_refresh_time_remaining > 0.0:
		return
	_fps_counter_refresh_time_remaining = maxf(0.05, fps_counter_update_interval)
	var fps := Engine.get_frames_per_second()
	var ms := 1000.0 / float(fps) if fps > 0 else 0.0
	var text := "FPS: %d  |  %.1f ms" % [fps, ms]
	if text == _fps_counter_last_text:
		return
	_fps_counter_last_text = text
	_fps_counter_label.text = text


func _set_combat_debug_overlay_text(text: String) -> void:
	if _combat_debug_label == null:
		return
	if _combat_debug_last_text == text:
		return
	_combat_debug_last_text = text
	_combat_debug_label.text = text


func _overlay_sorted_player_peer_ids() -> Array[int]:
	if not _peer_slots.is_empty():
		return _peer_ids_sorted_by_slot(_peer_slots)
	var peer_ids: Array[int] = []
	for key in _players_by_peer.keys():
		peer_ids.append(int(key))
	peer_ids.sort()
	return peer_ids


func _refresh_combat_debug_overlay(delta: float = 0.0, force: bool = false) -> void:
	if _combat_debug_label == null:
		return
	_combat_debug_label.visible = show_combat_debug_overlay
	if not show_combat_debug_overlay:
		_combat_debug_refresh_time_remaining = 0.0
		return
	_combat_debug_refresh_time_remaining = maxf(0.0, _combat_debug_refresh_time_remaining - delta)
	if not force and _combat_debug_refresh_time_remaining > 0.0:
		return
	_combat_debug_refresh_time_remaining = maxf(0.05, combat_debug_update_interval)
	var ordered_peer_ids: Array[int] = _overlay_sorted_player_peer_ids()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("CombatDebug players=%s" % [ordered_peer_ids.size()])
	if ordered_peer_ids.is_empty():
		lines.append("player roster empty")
	else:
		for idx in range(ordered_peer_ids.size()):
			var peer_id := ordered_peer_ids[idx]
			var player_label := "P%s" % [idx + 1]
			var player_v: Variant = _players_by_peer.get(peer_id, null)
			if player_v is not CharacterBody2D:
				lines.append("%s missing player node" % [player_label])
				continue
			var player_node: CharacterBody2D = player_v as CharacterBody2D
			if player_node == null or not is_instance_valid(player_node):
				lines.append("%s invalid player node" % [player_label])
				continue
			if not player_node.has_method(&"get_combat_debug_snapshot"):
				lines.append("%s debug snapshot missing" % [player_label])
				continue
			var snapshot_v: Variant = player_node.call(&"get_combat_debug_snapshot")
			if snapshot_v is not Dictionary:
				lines.append("%s debug snapshot invalid" % [player_label])
				continue
			var snapshot: Dictionary = snapshot_v as Dictionary
			var local_weapon := String(snapshot.get("weapon_mode", "?"))
			var weapon := String(snapshot.get("authoritative_weapon_mode", local_weapon))
			var local_melee_cd := float(snapshot.get("melee_cooldown", 0.0))
			var local_ranged_cd := float(snapshot.get("ranged_cooldown", 0.0))
			var local_bomb_cd := float(snapshot.get("bomb_cooldown", 0.0))
			var melee_cd := float(snapshot.get("authoritative_melee_cooldown", local_melee_cd))
			var ranged_cd := float(snapshot.get("authoritative_ranged_cooldown", local_ranged_cd))
			var bomb_cd := float(snapshot.get("authoritative_bomb_cooldown", local_bomb_cd))
			var local_stamina := float(snapshot.get("stamina", 0.0))
			var stamina := float(snapshot.get("authoritative_stamina", local_stamina))
			var local_guard_broken := bool(snapshot.get("stamina_broken", false))
			var guard_broken := bool(snapshot.get("authoritative_stamina_broken", local_guard_broken))
			var local_defending := bool(snapshot.get("is_defending", false))
			var defending := bool(snapshot.get("authoritative_is_defending", local_defending))
			var is_downed := bool(snapshot.get("is_downed", false))
			var row := "%s %s ST=%.1f guard=%s defend=%s down=%s CD[m/r/b]=%.2f/%.2f/%.2f" % [
				player_label,
				weapon,
				stamina,
				"broken" if guard_broken else "ready",
				defending,
				is_downed,
				melee_cd,
				ranged_cd,
				bomb_cd,
			]
			lines.append(row)
	_set_combat_debug_overlay_text("\n".join(lines))


func _physics_process(_delta: float) -> void:
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


func _regenerate_level(randomize_layout: bool) -> void:
	_has_generated_floor = false
	_floor_transition_pending = false
	_combat_started = false
	_combat_cleared = false
	_boss_started = false
	_boss_cleared = false
	_party_wipe_pending = false
	_puzzle_solved = false
	_puzzle_gate_socket = Vector2.ZERO
	_clear_floor_loot()
	for n in get_tree().get_nodes_in_group(&"mob"):
		if n is Node:
			(n as Node).queue_free()
	_enemy_nodes_by_network_id.clear()
	var assembled_ok := false
	if _networked_run and not _is_authoritative_world():
		if _map_layout.is_empty():
			_request_layout_snapshot_from_server()
			return
		_awaiting_layout_snapshot = false
		_destroy_dynamic_rooms()
		_spawn_rooms_from_layout(_map_layout)
		var links_client: Array = _map_layout.get("links", []) as Array
		_apply_adjacency_sockets(DungeonMapLayoutV1.adjacency_from_links(links_client))
		assembled_ok = _assemble_rooms_procedurally(_map_layout)
	else:
		_map_layout = {}
		var max_tries := 4 if randomize_layout else 1
		for _attempt in range(max_tries):
			var generated := DungeonMapLayoutV1.generate(_rng)
			if not bool(generated.get("ok", false)):
				continue
			var level_data := LevelDataV1.from_layout(
				generated,
				{
					"levelId": "floor_%s" % [_floor_index],
					"seed": int(_rng.seed),
					"difficulty": _floor_index,
					"theme": "procedural",
				}
			)
			var schema_check := LevelDataV1.validate(level_data)
			if not bool(schema_check.get("ok", false)):
				var schema_errors: Array = schema_check.get("errors", []) as Array
				var packed := PackedStringArray()
				for msg in schema_errors:
					packed.append(String(msg))
				_last_assembly_errors = packed
				continue
			_map_layout = generated
			_map_layout["level_data"] = level_data
			_destroy_dynamic_rooms()
			_spawn_rooms_from_layout(_map_layout)
			var links_server: Array = _map_layout.get("links", []) as Array
			_apply_adjacency_sockets(DungeonMapLayoutV1.adjacency_from_links(links_server))
			assembled_ok = _assemble_rooms_procedurally(_map_layout)
			if assembled_ok:
				break
	if not assembled_ok:
		push_warning(
			"Grid dungeon assembly failed (%s validation issues); skipping floor build." % [
				_last_assembly_errors.size()
			]
		)
		return
	_cache_runtime_door_positions()
	_position_runtime_markers()
	_build_world_bounds()
	_build_room_debug_visuals()
	_spawn_gameplay_objects()
	_spawn_encounter_modules()
	_spawn_entrance_exit_markers()
	_set_combat_doors_locked(false, false)
	_set_boss_entry_locked(false)
	_set_boss_exit_active(false)
	if _boss_portal_marker != null:
		_boss_portal_marker.visible = false
	_debug_spawn_exit_portal.monitoring = false
	_debug_spawn_exit_portal.monitorable = false
	if _debug_spawn_exit_elevator_visual != null and is_instance_valid(_debug_spawn_exit_elevator_visual):
		_debug_spawn_exit_elevator_visual.visible = false
	var entrance_spawn := _room_center_2d(_layout_room_name("start_room"))
	_position_players_at_spawn(entrance_spawn)
	_has_generated_floor = true
	_reset_backdrop_parallax_to_player()
	if _player != null and is_instance_valid(_player):
		_prev_player_pos = _player.global_position
		_prev_player_inside = _is_point_inside_any_room(_prev_player_pos, 1.25)
		_prev_room_name = _room_name_at(_prev_player_pos, 1.25)
	else:
		_prev_player_pos = Vector2.ZERO
		_prev_player_inside = true
		_prev_room_name = ""
	if OS.is_debug_build():
		# After teleport, CharacterBody2D syncs next physics tick; enabling monitoring earlier
		# still sees old overlap and fires body_entered once (double floor). Boss portal is fine
		# because the player is not on the debug portal when it enables.
		_debug_portal_monitor_token += 1
		var token := _debug_portal_monitor_token
		call_deferred("_enable_debug_spawn_portal_after_physics", token)
	else:
		if _debug_spawn_portal_marker != null:
			_debug_spawn_portal_marker.visible = false
		if _debug_spawn_exit_elevator_visual != null and is_instance_valid(_debug_spawn_exit_elevator_visual):
			_debug_spawn_exit_elevator_visual.visible = false
	if _is_authoritative_world():
		_ensure_layout_backdrop_path_server()
	_log_generation_debug(_map_layout)
	var room_count := (_map_layout.get("room_specs", []) as Array).size()
	_set_info_base_text(
		"Floor %s — linear spine (%s rooms). Puzzle button unlocks progression; treasure branch is optional." % [
			_floor_index,
			room_count,
		]
	)
	if _networked_run and not _is_authoritative_world():
		_request_runtime_snapshot_from_server()
	_apply_layout_backdrop_from_layout()
	_bind_minimap_runtime()
	if _is_authoritative_world():
		_broadcast_layout_snapshot_if_server()


func _position_players_at_spawn(entrance_spawn: Vector2) -> void:
	var peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	if peer_ids.is_empty():
		peer_ids.append(_local_peer_id())
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(4.0, 0.0),
		Vector2(-4.0, 0.0),
		Vector2(0.0, 4.0),
		Vector2(0.0, -4.0),
	]
	for i in range(peer_ids.size()):
		var peer_id := peer_ids[i]
		var node: Variant = _players_by_peer.get(peer_id, null)
		if node is not CharacterBody2D:
			continue
		var player := node as CharacterBody2D
		var offset: Vector2 = offsets[i] if i < offsets.size() else Vector2(float(i) * 2.0, 0.0)
		player.global_position = entrance_spawn + offset
		player.velocity = Vector2.ZERO
		player.set_meta(&"spawn_initialized", true)


func _position_uninitialized_players(anchor: Vector2) -> void:
	var peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	if peer_ids.is_empty():
		return
	var offsets: Array[Vector2] = [
		Vector2(4.0, 0.0),
		Vector2(-4.0, 0.0),
		Vector2(0.0, 4.0),
		Vector2(0.0, -4.0),
		Vector2(6.0, 3.0),
	]
	var offset_idx := 0
	for peer_id in peer_ids:
		var node: Variant = _players_by_peer.get(peer_id, null)
		if node is not CharacterBody2D:
			continue
		var player := node as CharacterBody2D
		if bool(player.get_meta(&"spawn_initialized", false)):
			continue
		var offset: Vector2 = (
			offsets[offset_idx] if offset_idx < offsets.size() else Vector2(float(offset_idx) * 2.0, 0.0)
		)
		player.global_position = anchor + offset
		player.velocity = Vector2.ZERO
		player.set_meta(&"spawn_initialized", true)
		offset_idx += 1


func _log_player_authority_roster(reason: String) -> void:
	if not OS.is_debug_build():
		return
	var local_peer := _local_peer_id()
	var has_peer := _has_multiplayer_peer()
	var peer_ids := _peer_ids_sorted_by_slot(_peer_slots)
	if peer_ids.is_empty():
		peer_ids.append(local_peer)
	var parts: Array[String] = []
	for peer_id in peer_ids:
		var node: Variant = _players_by_peer.get(peer_id, null)
		var node_name := "<missing>"
		var authority_peer := -1
		var is_local_authority := false
		if node is CharacterBody2D and is_instance_valid(node):
			var player := node as CharacterBody2D
			node_name = player.name
			authority_peer = player.get_multiplayer_authority()
			if has_peer:
				is_local_authority = player.is_multiplayer_authority()
			else:
				is_local_authority = authority_peer == local_peer
		var slot := int(_peer_slots.get(peer_id, -1))
		parts.append(
			"peer=%s slot=%s node=%s authority=%s local_auth=%s" % [
				peer_id,
				slot,
				node_name,
				authority_peer,
				is_local_authority,
			]
		)
	var summary := ""
	for i in range(parts.size()):
		if i > 0:
			summary += " | "
		summary += parts[i]
	print(
		"[M2][Roster][%s] local_peer=%s networked=%s players=%s :: %s" % [
			reason,
			local_peer,
			_networked_run,
			_players_by_peer.size(),
			summary,
		]
	)


func _enable_debug_spawn_portal_after_physics(token: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	if token != _debug_portal_monitor_token:
		return
	if not OS.is_debug_build() or not is_instance_valid(_debug_spawn_exit_portal):
		return
	_debug_spawn_exit_portal.monitoring = true
	_debug_spawn_exit_portal.monitorable = true
	if _debug_spawn_exit_elevator_visual != null and is_instance_valid(_debug_spawn_exit_elevator_visual):
		_debug_spawn_exit_elevator_visual.visible = true


func _ensure_dungeon_world_environment() -> void:
	if _dungeon_world_environment != null and is_instance_valid(_dungeon_world_environment):
		return
	_dungeon_environment = Environment.new()
	_dungeon_environment.background_mode = Environment.BG_COLOR
	_dungeon_environment.background_color = Color(0.035, 0.04, 0.055)
	# Single directional + dark BG leaves vertical wall normals starved (N·L ≈ 0); warm fill reads like bounce light.
	_dungeon_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_dungeon_environment.ambient_light_color = Color(0.62, 0.58, 0.52)
	_dungeon_environment.ambient_light_energy = 0.5
	_dungeon_world_environment = WorldEnvironment.new()
	_dungeon_world_environment.name = &"DungeonWorldEnvironment"
	_dungeon_world_environment.environment = _dungeon_environment
	_visual_world.add_child(_dungeon_world_environment)


func _ensure_boss_exit_elevator_visual() -> void:
	if _boss_exit_elevator_visual != null and is_instance_valid(_boss_exit_elevator_visual):
		return
	var visual := ELEVATOR_VISUAL_SCENE.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "BossExitElevatorVisual"
	visual.visible = false
	_visual_world.add_child(visual)
	_boss_exit_elevator_visual = visual
	_sync_boss_exit_elevator_visual_transform()


func _sync_boss_exit_elevator_visual_transform() -> void:
	if _boss_exit_elevator_visual == null or not is_instance_valid(_boss_exit_elevator_visual):
		return
	_set_elevator_visual_transform(
		_boss_exit_elevator_visual,
		_boss_exit_portal.position,
		_boss_entry_socket,
		0.0
	)


func _ensure_debug_spawn_exit_elevator_visual() -> void:
	if _debug_spawn_exit_elevator_visual != null and is_instance_valid(_debug_spawn_exit_elevator_visual):
		return
	var visual := ELEVATOR_VISUAL_SCENE.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "DebugSpawnExitElevatorVisual"
	visual.visible = false
	_visual_world.add_child(visual)
	_debug_spawn_exit_elevator_visual = visual
	_sync_debug_spawn_exit_elevator_visual_transform()


func _sync_debug_spawn_exit_elevator_visual_transform() -> void:
	if _debug_spawn_exit_elevator_visual == null or not is_instance_valid(_debug_spawn_exit_elevator_visual):
		return
	_set_elevator_visual_transform(
		_debug_spawn_exit_elevator_visual,
		_debug_spawn_exit_portal.position,
		_debug_spawn_exit_facing_target(),
		_DEBUG_ELEVATOR_YAW_OFFSET_DEG
	)


func _set_elevator_visual_transform(
	visual: Node3D, portal_position: Vector2, facing_target: Vector2, yaw_offset_deg: float = 0.0
) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var src := _get_elevator_visual_aabb()
	var player_diameter := maxf(0.01, _PLAYER_CLAMP_R * 2.0)
	var target_footprint := player_diameter * _ELEVATOR_PLAYER_SIZE_MULT
	var base_footprint := maxf(0.01, maxf(src.size.x, src.size.z))
	var uniform_scale := target_footprint / base_footprint
	visual.scale = Vector3.ONE * uniform_scale
	var visual_bottom_offset := src.position.y * uniform_scale
	var visual_y := FLOOR_SLAB_TOP_Y - visual_bottom_offset + _ELEVATOR_VISUAL_CLEARANCE_Y
	visual.position = Vector3(portal_position.x, visual_y, portal_position.y)
	var door_target := Vector3(
		facing_target.x,
		visual.position.y,
		facing_target.y
	)
	if door_target.distance_squared_to(visual.position) > 1e-8:
		visual.look_at(door_target, Vector3.UP)
		if absf(yaw_offset_deg) > 0.001:
			visual.rotate_y(deg_to_rad(yaw_offset_deg))


func _debug_spawn_exit_facing_target() -> Vector2:
	var forward := _critical_path_forward_dir_from_start()
	var start_room_name := _layout_room_name("start_room")
	var socket_target := _socket_world_position(start_room_name, forward)
	if socket_target.length_squared() > 0.0001:
		return socket_target
	return _debug_spawn_exit_portal.position + _direction_vector(forward) * 6.0


func _get_elevator_visual_aabb() -> AABB:
	if _has_elevator_visual_aabb_cache:
		return _elevator_visual_aabb_cache
	var inst := ELEVATOR_VISUAL_SCENE.instantiate() as Node3D
	var aabb := AABB()
	if inst != null:
		aabb = _merged_mesh_aabb_in_glb_root(inst)
		inst.free()
	if aabb.size.length_squared() < 1e-8:
		aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 1.0, 3.0))
	_elevator_visual_aabb_cache = aabb
	_has_elevator_visual_aabb_cache = true
	return aabb


func _ensure_backdrop_quad() -> void:
	if _backdrop_quad != null and is_instance_valid(_backdrop_quad):
		return
	if _camera_3d == null:
		return
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_backdrop_quad = MeshInstance3D.new()
	_backdrop_quad.name = &"LevelBackdropQuad"
	_backdrop_quad.mesh = qm
	_backdrop_quad.material_override = mat
	_backdrop_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop_quad.position = Vector3(0.0, 0.0, -BACKDROP_QUAD_DISTANCE)
	_camera_3d.add_child(_backdrop_quad)
	_reset_backdrop_parallax_reference()


func _reset_backdrop_parallax_reference() -> void:
	_backdrop_offset_cam = Vector3.ZERO
	if _camera_pivot != null:
		_prev_backdrop_camera_ref = _camera_pivot.global_position


func _reset_backdrop_parallax_to_player() -> void:
	_reset_backdrop_parallax_reference()


func _update_backdrop_parallax() -> void:
	if _camera_pivot == null or _camera_3d == null:
		return
	var ref := _camera_pivot.global_position
	if _backdrop_quad == null or not is_instance_valid(_backdrop_quad):
		_prev_backdrop_camera_ref = ref
		return
	var delta_w: Vector3 = ref - _prev_backdrop_camera_ref
	_prev_backdrop_camera_ref = ref
	if delta_w.length_squared() < 1e-16:
		return
	# Single motion frame: camera right + up only (no mixed world-axis fighting).
	var bx: Vector3 = _camera_3d.global_transform.basis.x
	var by: Vector3 = _camera_3d.global_transform.basis.y
	var along_right: float = delta_w.dot(bx)
	var along_up: float = delta_w.dot(by)
	# World-anchored feel: compensate opposite to camera travel at 2% so the layer stays almost static.
	var step := Vector3(-along_right, -along_up, 0.0) * BACKDROP_PARALLAX_CAMERA_FRACTION
	_backdrop_offset_cam += step
	if BACKDROP_PARALLAX_MAX_OFFSET > 0.0:
		var lim := BACKDROP_PARALLAX_MAX_OFFSET
		_backdrop_offset_cam.x = clampf(_backdrop_offset_cam.x, -lim, lim)
		_backdrop_offset_cam.y = clampf(_backdrop_offset_cam.y, -lim, lim)


func _update_backdrop_quad_transform() -> void:
	if _backdrop_quad == null or not is_instance_valid(_backdrop_quad) or _camera_3d == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 0.001)
	var h: float = _camera_3d.size * BACKDROP_QUAD_MARGIN
	var w: float = h * aspect
	_backdrop_quad.scale = Vector3(w, h, 1.0)
	_backdrop_quad.rotation = Vector3.ZERO
	_backdrop_quad.position = Vector3(
		_backdrop_offset_cam.x,
		_backdrop_offset_cam.y,
		-BACKDROP_QUAD_DISTANCE
	)


func _collect_backdrop_png_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(BACKDROP_IMAGE_DIR)
	if da == null:
		push_warning("Cannot open backdrop folder: %s" % BACKDROP_IMAGE_DIR)
		return out
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if not da.current_is_dir() and String(fn).get_extension().to_lower() == "png":
			out.append("%s/%s" % [BACKDROP_IMAGE_DIR, fn])
		fn = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _ensure_layout_backdrop_path_server() -> void:
	if not _is_authoritative_world():
		return
	if _map_layout.is_empty():
		return
	var existing := String(_map_layout.get(LAYOUT_KEY_BACKDROP_TEXTURE_PATH, "")).strip_edges()
	if not existing.is_empty():
		return
	var paths := _collect_backdrop_png_paths()
	if paths.is_empty():
		return
	_map_layout[LAYOUT_KEY_BACKDROP_TEXTURE_PATH] = paths[_rng.randi_range(0, paths.size() - 1)]


func _apply_layout_backdrop_from_layout() -> void:
	var tex_path := String(_map_layout.get(LAYOUT_KEY_BACKDROP_TEXTURE_PATH, "")).strip_edges()
	if tex_path.is_empty() and _is_authoritative_world():
		_ensure_layout_backdrop_path_server()
		tex_path = String(_map_layout.get(LAYOUT_KEY_BACKDROP_TEXTURE_PATH, "")).strip_edges()
	if tex_path.is_empty():
		push_warning("Layout missing backdrop texture path; skipping backdrop apply.")
		return
	_ensure_dungeon_world_environment()
	_ensure_backdrop_quad()
	var tex := load(tex_path)
	if tex is not Texture2D:
		push_warning("Backdrop is not a Texture2D: %s" % tex_path)
		return
	var mat := _backdrop_quad.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_texture = tex as Texture2D


func _log_generation_debug(layout: Dictionary) -> void:
	var debug := layout.get("stage_debug", {}) as Dictionary
	if debug.is_empty():
		return
	var graph := debug.get("graph", {}) as Dictionary
	var roles := debug.get("roles", {}) as Dictionary
	var spatial := debug.get("spatial", {}) as Dictionary
	print("Dungeon Pipeline Graph: %s" % [graph])
	print("Dungeon Pipeline Roles: %s" % [roles])
	print("Dungeon Pipeline Spatial: %s" % [spatial])


func _destroy_dynamic_rooms() -> void:
	var kids := _rooms_root.get_children()
	for c in kids:
		if c is Node:
			(c as Node).free()


func _spawn_rooms_from_layout(layout: Dictionary) -> void:
	var specs: Array = layout.get("room_specs", []) as Array
	for spec in specs:
		if spec is not Dictionary:
			continue
		var d: Dictionary = spec as Dictionary
		var room := ROOM_BASE_SCENE.instantiate() as RoomBase
		if room == null:
			continue
		var nm := String(d.get("name", "DM_Room"))
		room.name = nm
		room.room_id = nm
		var base_size := d.get("size", Vector2i(12, 12)) as Vector2i
		room.room_size_tiles = Vector2i(
			maxi(1, int(round(float(base_size.x) * _ROOM_SIZE_SCALE))),
			maxi(1, int(round(float(base_size.y) * _ROOM_SIZE_SCALE)))
		)
		room.tile_size = Vector2i(3, 3)
		var kind := String(d.get("kind", "start"))
		room.room_type = DungeonMapLayoutV1.kind_to_room_type(kind)
		room.room_tags = PackedStringArray([room.room_type])
		room.standard_room_sizes = PackedInt32Array([3, 5, 9, 12, 15, 18, 24])
		if kind == "exit":
			room.min_difficulty_tier = 4
			room.max_difficulty_tier = 8
		_rooms_root.add_child(room)


func _apply_adjacency_sockets(adj: Dictionary) -> void:
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var dirs: Dictionary = adj.get(String(r.name), {}) as Dictionary
		var half_w := r.room_size_tiles.x * r.tile_size.x * 0.5
		var half_h := r.room_size_tiles.y * r.tile_size.y * 0.5
		for socket in r.get_all_sockets():
			var w := int(dirs.get(socket.direction, 0))
			if w <= 0:
				socket.connector_type = &"inactive"
				continue
			socket.connector_type = &"standard"
			socket.width_tiles = w
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


func _collect_dropped_coins_under(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is DroppedCoin:
			out.append(c)
		else:
			_collect_dropped_coins_under(c, out)


func _clear_floor_loot() -> void:
	# Coins can live under PieceInstances (chests) or GameWorld2D root (mob death drops).
	_coin_nodes_by_network_id.clear()
	var gw := get_node_or_null("GameWorld2D") as Node
	if gw != null:
		var coins: Array = []
		_collect_dropped_coins_under(gw, coins)
		for n in coins:
			if n is Node and is_instance_valid(n):
				(n as Node).queue_free()
	# Safety net for any orphaned visual meshes from old floor coins.
	for n in _visual_world.find_children("DroppedCoinMesh", "MeshInstance3D", true, false):
		if n is Node:
			(n as Node).queue_free()


func _assemble_rooms_procedurally(layout: Dictionary) -> bool:
	var assembler: ProceduralAssemblyV1 = ProceduralAssemblyV1.new()
	var links: Array = layout.get("links", []) as Array
	var start_nm := StringName(String(layout.get("start_room", "")))
	if String(start_nm) == "":
		_last_assembly_errors = PackedStringArray(["Missing start_room in layout."])
		return false
	var result: Dictionary = assembler.assemble_from_socket_graph(_rooms_root, start_nm, links)
	_last_assembly_errors = PackedStringArray()
	if bool(result.get("ok", false)):
		var placed: int = int(result.get("placed_count", 0))
		var total: int = int(result.get("total_rooms", 0))
		print("Milestone 5: procedural assembly ready (%s/%s rooms connected)." % [placed, total])
		return true
	_last_assembly_errors = result.get("errors", PackedStringArray()) as PackedStringArray
	return false


func _room_by_name(room_name: StringName) -> RoomBase:
	return _room_queries.room_by_name(room_name) if _room_queries != null else null


func _layout_room_name(key: String, fallback: String = "") -> StringName:
	return StringName(String(_map_layout.get(key, fallback)))


func _tower_spawn_near_center(encounter_id: StringName, module_pos: Vector2) -> Vector2:
	if _map_layout.is_empty():
		return module_pos
	var id_text := String(encounter_id)
	var room_name := StringName()
	if id_text == "boss":
		room_name = _layout_room_name("exit_room")
	elif id_text.begins_with("arena_"):
		room_name = StringName(id_text.trim_prefix("arena_"))
	else:
		room_name = _layout_room_name("combat_room")
	var room := _room_by_name(room_name)
	if room == null:
		return module_pos
	return room.global_position.lerp(module_pos, 0.2)


func _encounter_room_for_tower_separation(encounter_id: StringName) -> RoomBase:
	var id_text := String(encounter_id)
	var room_name := StringName()
	if id_text == "boss":
		room_name = _layout_room_name("exit_room")
	elif id_text.begins_with("arena_"):
		room_name = StringName(id_text.trim_prefix("arena_"))
	else:
		room_name = _layout_room_name("combat_room")
	return _room_by_name(room_name)


func _clamp_pos_to_room(room: RoomBase, pos: Vector2) -> Vector2:
	if room == null:
		return pos
	var room_rect_local := room.get_room_rect_world()
	var room_rect := Rect2(room.global_position - room_rect_local.size * 0.5, room_rect_local.size)
	var inset := 0.9
	return Vector2(
		clampf(pos.x, room_rect.position.x + inset, room_rect.end.x - inset),
		clampf(pos.y, room_rect.position.y + inset, room_rect.end.y - inset)
	)


func _separate_tower_spawn(encounter_id: StringName, candidate: Vector2) -> Vector2:
	var room := _encounter_room_for_tower_separation(encounter_id)
	var min_sep_sq := _TOWER_SPAWN_MIN_SEP * _TOWER_SPAWN_MIN_SEP
	if not _planned_tower_positions_by_encounter.has(encounter_id):
		_planned_tower_positions_by_encounter[encounter_id] = []
	var planned: Array = _planned_tower_positions_by_encounter[encounter_id] as Array

	var pos := _clamp_pos_to_room(room, candidate)
	for _attempt in range(24):
		var ok := true
		for p in planned:
			if p is Vector2 and (p as Vector2).distance_squared_to(pos) < min_sep_sq:
				ok = false
				break
		if ok:
			return pos
		var tangent := Vector2(-(pos.y - room.global_position.y), pos.x - room.global_position.x)
		if tangent.length_squared() <= 0.0001:
			tangent = Vector2(1.0, 0.0)
		tangent = tangent.normalized()
		var step := _TOWER_SPAWN_MIN_SEP * (0.85 + 0.08 * float(_attempt))
		var side := 1.0 if (_attempt % 2) == 0 else -1.0
		pos = _clamp_pos_to_room(room, pos + tangent * step * side)
	return pos


func _register_planned_tower_spawn(encounter_id: StringName, world_pos: Vector2) -> void:
	if not _planned_tower_positions_by_encounter.has(encounter_id):
		_planned_tower_positions_by_encounter[encounter_id] = []
	var planned: Array = _planned_tower_positions_by_encounter[encounter_id] as Array
	planned.append(world_pos)
	_planned_tower_positions_by_encounter[encounter_id] = planned


func _room_half_extents(room: RoomBase) -> Vector2:
	return _room_queries.room_half_extents(room) if _room_queries != null else Vector2.ZERO


func _room_center_2d(room_name: StringName) -> Vector2:
	return _room_queries.room_center_2d(room_name) if _room_queries != null else Vector2.ZERO


func _socket_world_position(room_name: StringName, direction: String) -> Vector2:
	return _room_queries.socket_world_position(room_name, direction) if _room_queries != null else Vector2.ZERO


func _cache_runtime_door_positions() -> void:
	if _map_layout.is_empty():
		return
	var cr := _layout_room_name("combat_room")
	var er := _layout_room_name("exit_room")
	var pr := _layout_room_name("puzzle_room")
	_combat_entry_dir = String(_map_layout.get("combat_entry_dir", "west"))
	_combat_exit_dir = String(_map_layout.get("combat_exit_dir", "east"))
	_boss_entry_dir = String(_map_layout.get("boss_entry_dir", "west"))
	_puzzle_gate_dir = String(_map_layout.get("puzzle_gate_dir", "east"))
	_combat_entry_socket = _socket_world_position(cr, _combat_entry_dir)
	_combat_exit_socket = _socket_world_position(cr, _combat_exit_dir)
	_boss_entry_socket = _socket_world_position(er, _boss_entry_dir)
	_puzzle_gate_socket = _socket_world_position(pr, _puzzle_gate_dir)
	_combat_door_x_w = _combat_entry_socket.x
	_combat_door_x_e = _combat_exit_socket.x
	_boss_door_x_w = _boss_entry_socket.x
	_w_ext_x = _combat_door_x_w - 2.5
	_e_ext_x = _combat_door_x_e + 3.5
	_boss_w_ext_x = _boss_door_x_w - 2.5


func _position_runtime_markers() -> void:
	var exit_key := _layout_room_name("exit_room")
	var boss_room := _room_by_name(exit_key)
	if boss_room != null:
		var half := _room_half_extents(boss_room)
		var outward := _direction_vector(_opposite_direction(_boss_entry_dir))
		var inset_x := maxf(0.0, half.x - _BOSS_PORTAL_INSET)
		var inset_y := maxf(0.0, half.y - _BOSS_PORTAL_INSET)
		var offset := Vector2(outward.x * inset_x, outward.y * inset_y)
		_boss_exit_portal.position = boss_room.global_position + offset
		if _boss_portal_marker != null:
			_boss_portal_marker.visible = false
		_ensure_boss_exit_elevator_visual()
		if _boss_exit_elevator_visual != null and is_instance_valid(_boss_exit_elevator_visual):
			_sync_boss_exit_elevator_visual_transform()
			_boss_exit_elevator_visual.visible = false
	_position_debug_spawn_exit_portal()


func _grid_dir_from_delta(d: Vector2i) -> String:
	if d == Vector2i(1, 0):
		return "east"
	if d == Vector2i(-1, 0):
		return "west"
	if d == Vector2i(0, 1):
		return "south"
	if d == Vector2i(0, -1):
		return "north"
	return "east"


func _critical_path_forward_dir_from_start() -> String:
	var critical: Array = _map_layout.get("critical_path", []) as Array
	if critical.size() < 2:
		return "east"
	var start_id := String(critical[0])
	var next_id := String(critical[1])
	var start_grid := Vector2i.ZERO
	var next_grid := Vector2i.ZERO
	for spec in _map_layout.get("room_specs", []) as Array:
		if spec is not Dictionary:
			continue
		var d: Dictionary = spec as Dictionary
		var nm := String(d.get("name", ""))
		if nm == start_id:
			start_grid = d.get("grid", Vector2i.ZERO) as Vector2i
		elif nm == next_id:
			next_grid = d.get("grid", Vector2i.ZERO) as Vector2i
	return _grid_dir_from_delta(next_grid - start_grid)


func _position_debug_spawn_exit_portal() -> void:
	if not OS.is_debug_build():
		_debug_spawn_exit_portal.monitoring = false
		_debug_spawn_exit_portal.monitorable = false
		if _debug_spawn_portal_marker != null:
			_debug_spawn_portal_marker.visible = false
		if _debug_spawn_exit_elevator_visual != null and is_instance_valid(_debug_spawn_exit_elevator_visual):
			_debug_spawn_exit_elevator_visual.visible = false
		return
	var start_room := _room_by_name(_layout_room_name("start_room"))
	if start_room == null:
		return
	var forward := _critical_path_forward_dir_from_start()
	var back := _opposite_direction(forward)
	var half := _room_half_extents(start_room)
	var outward := _direction_vector(back)
	var inset_x := maxf(0.0, half.x - _BOSS_PORTAL_INSET)
	var inset_y := maxf(0.0, half.y - _BOSS_PORTAL_INSET)
	var off := Vector2(outward.x * inset_x, outward.y * inset_y)
	_debug_spawn_exit_portal.position = start_room.global_position + off
	if _debug_spawn_portal_marker != null:
		_debug_spawn_portal_marker.visible = false
	_ensure_debug_spawn_exit_elevator_visual()
	_sync_debug_spawn_exit_elevator_visual_transform()
	if _debug_spawn_exit_elevator_visual != null and is_instance_valid(_debug_spawn_exit_elevator_visual):
		_debug_spawn_exit_elevator_visual.visible = true


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


func _build_world_bounds() -> void:
	_boundary_wall_keys.clear()
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
	var k := _wall_boundary_key(position_2d, size_2d)
	if _boundary_wall_keys.has(k):
		return
	_boundary_wall_keys[k] = true
	_add_wall_piece(position_2d, size_2d)
	_add_wall_visual(position_2d, size_2d)


func _wall_boundary_key(position_2d: Vector2, size_2d: Vector2) -> String:
	var p := Vector2(snappedf(position_2d.x, 0.05), snappedf(position_2d.y, 0.05))
	var s := Vector2(snappedf(size_2d.x, 0.05), snappedf(size_2d.y, 0.05))
	return "%.2f,%.2f|%.2f,%.2f" % [p.x, p.y, s.x, s.y]


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


func _apply_disable_receive_shadows_on_mesh_instance(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for surf_idx in range(mesh.get_surface_count()):
		var src_mat: Material = mi.get_surface_override_material(surf_idx)
		if src_mat == null:
			src_mat = mesh.surface_get_material(surf_idx)
		if src_mat is BaseMaterial3D:
			var dup := (src_mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			dup.disable_receive_shadows = true
			mi.set_surface_override_material(surf_idx, dup)


func _disable_architecture_shadows(root: Node) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if root is MeshInstance3D:
		_apply_disable_receive_shadows_on_mesh_instance(root as MeshInstance3D)
	for c in root.get_children():
		if c is Node:
			_disable_architecture_shadows(c as Node)


func _add_wall_visual(position_2d: Vector2, size_2d: Vector2) -> void:
	var glb_scene := STONE_WALL_GLB
	var src := _get_floor_glb_tile_aabb(glb_scene)
	var tw := maxf(0.01, WALL_TEXTURE_TILE_WORLD)
	var wx := size_2d.x
	var wz := size_2d.y
	var wy := WALL_VISUAL_HEIGHT
	var tiles_x := maxi(1, ceili(wx / tw))
	var tiles_z := maxi(1, ceili(wz / tw))
	var tiles_y := maxi(1, ceili(wy / tw))
	var module_x := wx / float(tiles_x)
	var module_z := wz / float(tiles_z)
	var module_y := wy / float(tiles_y)
	var sx := module_x / maxf(0.01, src.size.x)
	var sy := module_y / maxf(0.01, src.size.y)
	var sz := module_z / maxf(0.01, src.size.z)
	var src_center := src.get_center()
	var base_x := position_2d.x - wx * 0.5 + module_x * 0.5
	var base_z := position_2d.y - wz * 0.5 + module_z * 0.5
	for ix in range(tiles_x):
		for iz in range(tiles_z):
			for iy in range(tiles_y):
				var tile := glb_scene.instantiate() as Node3D
				if tile == null:
					continue
				tile.scale = Vector3(sx, sy, sz)
				var px := base_x + float(ix) * module_x
				var pz := base_z + float(iz) * module_z
				var row_bottom := WALL_VISUAL_BASE_Y + float(iy) * module_y
				var py := row_bottom - src.position.y * sy
				tile.position = Vector3(px - src_center.x * sx, py, pz - src_center.z * sz)
				_disable_architecture_shadows(tile)
				_wall_visuals.add_child(tile)


func _build_room_debug_visuals() -> void:
	for child in _room_visuals.get_children():
		child.queue_free()
	for child in _door_visuals.get_children():
		child.queue_free()
	_door_visual_by_socket_key.clear()
	_puzzle_door_visual = null
	var door_specs_by_key: Dictionary = {}
	var combat_nm := _layout_room_name("combat_room")
	var puzzle_nm := _layout_room_name("puzzle_room")
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		var rect_local := r.get_room_rect_world()
		# Match _add_room_boundary: walls are centered on global_position with half-extents size*0.5.
		# Using rect_local.position + global would offset floors for odd tile counts (asymmetric tile rect).
		var half := rect_local.size * 0.5
		var rect := Rect2(r.global_position - half, rect_local.size)
		_add_room_floor_visual(rect, r.name + " (" + r.room_type.to_upper() + ")")
		for socket in r.get_all_sockets():
			if socket.connector_type == &"inactive":
				continue
			var world_pos := r.global_position + socket.position
			var dir_key := String(socket.direction)
			var combat_visuals := (
				r.name == combat_nm
				and (dir_key == _combat_entry_dir or dir_key == _combat_exit_dir)
			)
			var is_puzzle_gate := false
			if String(puzzle_nm) != "" and _puzzle_gate_socket.length_squared() > 0.0001:
				is_puzzle_gate = world_pos.distance_squared_to(_puzzle_gate_socket) < 0.49
			var dk := "%s:%s" % [int(roundf(world_pos.x * 100.0)), int(roundf(world_pos.y * 100.0))]
			if not door_specs_by_key.has(dk):
				door_specs_by_key[dk] = {
					"world_pos": world_pos,
					"wall_direction": dir_key,
					"use_combat_lock_visuals": combat_visuals,
					"is_puzzle_gate": is_puzzle_gate,
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
				if is_puzzle_gate:
					existing["is_puzzle_gate"] = true
				door_specs_by_key[dk] = existing

	for dk in door_specs_by_key.keys():
		var spec := door_specs_by_key[dk] as Dictionary
		var door_pos := spec["world_pos"] as Vector2
		_spawn_standard_door_piece(door_pos, int(spec.get("width_tiles", 1)))
		var is_pg := bool(spec.get("is_puzzle_gate", false))
		var use_cv := bool(spec.get("use_combat_lock_visuals", false)) or is_pg
		var door := _add_cell_door_3d(
			door_pos,
			String(spec.get("wall_direction", "west")),
			use_cv,
			is_pg
		)
		if is_pg:
			_puzzle_door_visual = door

	_assign_combat_door_visual_refs()


func _assign_combat_door_visual_refs() -> void:
	_combat_door_visual_west = null
	_combat_door_visual_east = null
	var cr := _room_by_name(_layout_room_name("combat_room"))
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


func _ground_glb_scene_for_dungeon_floor() -> PackedScene:
	var i := (_floor_index - 1) % 4
	match i:
		0:
			return GROUND_GLB_METAL
		1:
			return GROUND_GLB_GRASS
		2:
			return GROUND_GLB_DIRT
		_:
			return GROUND_GLB_STONE


func _get_floor_glb_tile_aabb(glb_scene: PackedScene) -> AABB:
	var path_key := glb_scene.resource_path
	if _floor_glb_aabb_by_path.has(path_key):
		return _floor_glb_aabb_by_path[path_key] as AABB
	var inst := glb_scene.instantiate() as Node3D
	var aabb := AABB()
	if inst != null:
		aabb = _merged_mesh_aabb_in_glb_root(inst)
		inst.free()
	if aabb.size.length_squared() < 1e-8:
		aabb = AABB(Vector3(-1.5, -0.05, -1.5), Vector3(3.0, 0.1, 3.0))
	_floor_glb_aabb_by_path[path_key] = aabb
	return aabb


func _merged_mesh_aabb_in_glb_root(root: Node3D) -> AABB:
	var merged := AABB()
	var any := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var root_to_mesh := _glb_transform_to_ancestor(mi, root)
		var aabb := _glb_transform_aabb(root_to_mesh, mi.mesh.get_aabb())
		if not any:
			merged = aabb
			any = true
		else:
			merged = merged.merge(aabb)
	return merged if any else AABB()


static func _glb_transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _glb_transform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
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


func _add_room_floor_visual(rect: Rect2, label_text: String) -> void:
	var glb_scene := _ground_glb_scene_for_dungeon_floor()
	var src := _get_floor_glb_tile_aabb(glb_scene)
	var tw := maxf(0.01, FLOOR_TEXTURE_TILE_WORLD)
	var tiles_x := maxi(1, ceili(rect.size.x / tw))
	var tiles_z := maxi(1, ceili(rect.size.y / tw))
	var module_x := rect.size.x / float(tiles_x)
	var module_z := rect.size.y / float(tiles_z)
	var sx := module_x / maxf(0.01, src.size.x)
	var sy := ROOM_HEIGHT / maxf(0.01, src.size.y)
	var sz := module_z / maxf(0.01, src.size.z)
	var src_center := src.get_center()
	var top_y := src.position.y + src.size.y
	var base_x := rect.position.x + module_x * 0.5
	var base_z := rect.position.y + module_z * 0.5
	for ix in range(tiles_x):
		for iz in range(tiles_z):
			var tile := glb_scene.instantiate() as Node3D
			if tile == null:
				continue
			tile.scale = Vector3(sx, sy, sz)
			var px := base_x + float(ix) * module_x
			var pz := base_z + float(iz) * module_z
			var py := FLOOR_SLAB_TOP_Y - top_y * sy
			tile.position = Vector3(px - src_center.x * sx, py, pz - src_center.z * sz)
			_disable_architecture_shadows(tile)
			_room_visuals.add_child(tile)

	var cx := rect.position.x + rect.size.x * 0.5
	var cz := rect.position.y + rect.size.y * 0.5
	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.BLACK
	label.position = Vector3(cx, FLOOR_SLAB_TOP_Y + 1.85, cz)
	label.scale = Vector3.ONE * LABEL_SCALE
	_room_visuals.add_child(label)


func _add_cell_door_3d(
	world_pos: Vector2,
	wall_direction: String,
	use_combat_lock_visuals: bool,
	start_visual_closed: bool = false
) -> DungeonCellDoor3D:
	var door := DUNGEON_CELL_DOOR_SCENE.instantiate() as DungeonCellDoor3D
	door.use_combat_lock_visuals = use_combat_lock_visuals
	door.start_visual_closed = start_visual_closed
	door.configure_for_socket(wall_direction)
	door.position = Vector3(world_pos.x, FLOOR_SLAB_TOP_Y, world_pos.y)
	_disable_architecture_shadows(door)
	_door_visuals.add_child(door)
	_door_visual_by_socket_key[_socket_pos_key(world_pos)] = door
	return door


func _apply_combat_doors_locked(locked: bool, animate: bool = true) -> void:
	# Entry door stays open; only combat exit door is gated by clear state.
	for asm in [_combat_door_visual_east]:
		if asm != null:
			asm.set_combat_locked(locked, animate)


func _set_combat_doors_locked(locked: bool, animate: bool = true) -> void:
	_apply_combat_doors_locked(locked, animate)
	if (
		_networked_run
		and _is_server_peer()
		and _has_multiplayer_peer()
		and _can_broadcast_world_replication()
	):
		_rpc_set_combat_doors_locked.rpc(locked, animate)


func _set_boss_entry_locked(_locked: bool) -> void:
	# Boss entry blocking uses _apply_hard_door_clamps while the boss encounter is active.
	pass


func _apply_hard_door_clamps() -> void:
	var mobs: Array[CharacterBody2D] = []
	for n in get_tree().get_nodes_in_group(&"mob"):
		if n is CharacterBody2D:
			mobs.append(n as CharacterBody2D)
	var players_to_clamp: Array[CharacterBody2D] = []
	for peer_id in _players_by_peer.keys():
		var node: Variant = _players_by_peer.get(peer_id, null)
		if node is CharacterBody2D and is_instance_valid(node):
			players_to_clamp.append(node as CharacterBody2D)
	if players_to_clamp.is_empty() and _player != null and is_instance_valid(_player):
		players_to_clamp.append(_player)
	if _door_lock_controller != null:
		for p in players_to_clamp:
			_door_lock_controller.apply_hard_door_clamps(
				p,
				_puzzle_solved,
				_puzzle_gate_socket,
				_puzzle_gate_dir,
				_encounter_active,
				_PLAYER_CLAMP_R,
				_MOB_CLAMP_R,
				mobs
			)


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


func _on_puzzle_floor_button_activated() -> void:
	if _networked_run and not _is_authoritative_world():
		return
	_set_puzzle_gate_solved(true, true, true)


func _apply_puzzle_gate_solved(solved: bool, animate: bool = true) -> void:
	_puzzle_solved = solved
	if _puzzle_door_visual != null and is_instance_valid(_puzzle_door_visual):
		_puzzle_door_visual.set_runtime_locked(not solved, animate)
	if solved:
		_set_info_base_text("Puzzle gate open.")


func _set_puzzle_gate_solved(solved: bool, animate: bool = true, replicate: bool = true) -> void:
	_apply_puzzle_gate_solved(solved, animate)
	if (
		replicate
		and _networked_run
		and _is_server_peer()
		and _has_multiplayer_peer()
		and _can_broadcast_world_replication()
	):
		_rpc_set_puzzle_gate_solved.rpc(solved, animate)


func _spawn_gameplay_objects() -> void:
	if _map_layout.is_empty():
		return
	var treasure_room := _layout_room_name("treasure_room")
	if String(treasure_room) != "":
		var treasure_center := _room_center_2d(treasure_room)
		var chest := TREASURE_CHEST_SCENE.instantiate() as TreasureChest2D
		if chest:
			chest.name = "TreasureChest"
			chest.coin_count = 10
			chest.mesh_ground_y = maxf(1.2, FLOOR_SLAB_TOP_Y + 1.7)
			chest.position = treasure_center
			if chest.has_signal(&"opened") and not chest.opened.is_connected(_on_treasure_chest_opened):
				chest.opened.connect(_on_treasure_chest_opened.bind(chest))
			if chest.has_signal(&"coin_spawn_requested") and not chest.coin_spawn_requested.is_connected(
				_on_treasure_chest_coin_spawn_requested
			):
				chest.coin_spawn_requested.connect(_on_treasure_chest_coin_spawn_requested)
			if _networked_run and not _is_authoritative_world() and chest.has_method(&"set_interaction_enabled"):
				chest.call(&"set_interaction_enabled", false)
			_piece_instances_root.add_child(chest)
	var combat_center := _room_center_2d(_layout_room_name("combat_room"))
	for off in _COMBAT_TRAP_OFFSETS:
		_spawn_trap_tile_at(combat_center + off)
	var trap_room := _layout_room_name("trap_room")
	if String(trap_room) != "":
		var trap_center := _room_center_2d(trap_room)
		for off in _TRAP_ROOM_OFFSETS:
			_spawn_trap_tile_at(trap_center + off)
	var puzzle_room := _layout_room_name("puzzle_room")
	if String(puzzle_room) != "":
		var puzzle_center := _room_center_2d(puzzle_room)
		var pbtn := PUZZLE_FLOOR_BUTTON_SCENE.instantiate() as PuzzleFloorButton2D
		if pbtn != null:
			pbtn.name = "PuzzleFloorButton"
			pbtn.position = puzzle_center
			pbtn.activated.connect(_on_puzzle_floor_button_activated)
			if _networked_run and not _is_authoritative_world() and pbtn.has_method(&"set_interaction_enabled"):
				pbtn.call(&"set_interaction_enabled", false)
			_piece_instances_root.add_child(pbtn)


func _on_treasure_chest_opened(chest: TreasureChest2D) -> void:
	if chest == null:
		return
	if not _networked_run or not _is_server_peer() or not _has_multiplayer_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_open_treasure_chest.rpc(chest.get_path())


func _on_treasure_chest_coin_spawn_requested(chest_center: Vector2, land_pos: Vector2) -> void:
	if not _is_authoritative_world():
		return
	_spawn_authoritative_coin(chest_center, land_pos, 1)


func _on_enemy_coin_drop_requested(spawn_position: Vector2, coin_value: int) -> void:
	if not _is_authoritative_world():
		return
	var landing_position := _random_enemy_coin_land_pos(spawn_position)
	_spawn_authoritative_coin(spawn_position, landing_position, maxi(1, coin_value))


func _random_enemy_coin_land_pos(spawn_position: Vector2) -> Vector2:
	var angle := randf() * TAU
	var distance := randf_range(1.4, 3.1)
	return spawn_position + Vector2.from_angle(angle) * distance


func _spawn_authoritative_coin(spawn_position: Vector2, landing_position: Vector2, coin_value: int) -> void:
	var coin_network_id := _next_coin_network_id()
	_spawn_coin_instance(coin_network_id, spawn_position, landing_position, coin_value, true)
	if _networked_run and _is_server_peer() and _has_multiplayer_peer() and _can_broadcast_world_replication():
		_rpc_spawn_coin.rpc(coin_network_id, spawn_position, landing_position, coin_value)


func _spawn_coin_instance(
	coin_network_id: int,
	spawn_position: Vector2,
	landing_position: Vector2,
	coin_value: int,
	authoritative_pickup: bool
) -> void:
	if coin_network_id <= 0:
		return
	var existing_v: Variant = _coin_nodes_by_network_id.get(coin_network_id, null)
	if existing_v is DroppedCoin and is_instance_valid(existing_v):
		return
	var coin := DROPPED_COIN_SCENE.instantiate() as DroppedCoin
	if coin == null:
		return
	coin.name = "Coin_%s" % [coin_network_id]
	coin.set_planar_arc_end(landing_position)
	$GameWorld2D.add_child(coin)
	coin.global_position = spawn_position
	coin.configure_network_coin(coin_network_id, coin_value, authoritative_pickup)
	_register_coin_instance(coin, coin_network_id)


func _register_coin_instance(coin: DroppedCoin, coin_network_id: int) -> void:
	if coin == null or coin_network_id <= 0:
		return
	_coin_nodes_by_network_id[coin_network_id] = coin
	if coin.has_signal(&"pickup_requested") and not coin.pickup_requested.is_connected(_on_coin_pickup_requested):
		coin.pickup_requested.connect(_on_coin_pickup_requested)
	coin.tree_exited.connect(_on_coin_tree_exited.bind(coin_network_id, coin), CONNECT_ONE_SHOT)


func _on_coin_tree_exited(coin_network_id: int, coin: DroppedCoin) -> void:
	var current_v: Variant = _coin_nodes_by_network_id.get(coin_network_id, null)
	if current_v == coin:
		_coin_nodes_by_network_id.erase(coin_network_id)


func _despawn_coin_local(coin_network_id: int) -> void:
	var coin_v: Variant = _coin_nodes_by_network_id.get(coin_network_id, null)
	if coin_v is DroppedCoin and is_instance_valid(coin_v):
		(coin_v as DroppedCoin).queue_free()
	_coin_nodes_by_network_id.erase(coin_network_id)


func _on_coin_pickup_requested(coin_network_id: int, picker_peer_id: int, coin_value: int) -> void:
	if not _is_authoritative_world():
		return
	var coin_v: Variant = _coin_nodes_by_network_id.get(coin_network_id, null)
	if coin_v == null or not is_instance_valid(coin_v):
		_coin_nodes_by_network_id.erase(coin_network_id)
		return
	var resolved_peer := picker_peer_id
	if resolved_peer <= 0:
		resolved_peer = _local_peer_id()
	if _networked_run and not _players_by_peer.has(resolved_peer):
		resolved_peer = 1
	_despawn_coin_local(coin_network_id)
	var next_total := _shared_coin_total + maxi(1, coin_value)
	_shared_coin_total = maxi(0, next_total)
	_ensure_coin_totals_for_roster()
	_refresh_local_coin_ui()
	if _networked_run and _is_server_peer() and _has_multiplayer_peer() and _can_broadcast_world_replication():
		_rpc_coin_collected.rpc(coin_network_id, resolved_peer, next_total)


func _spawn_trap_tile_at(world_pos: Vector2) -> void:
	var trap := TRAP_TILE_SCENE.instantiate() as TrapTile2D
	if trap == null:
		return
	trap.name = "TrapTile_%s_%s" % [int(world_pos.x), int(world_pos.y)]
	trap.mesh_ground_y = FLOOR_SLAB_TOP_Y + 0.22
	trap.position = world_pos
	if trap.has_method(&"set_authoritative_damage"):
		trap.call(&"set_authoritative_damage", _is_authoritative_world())
	_piece_instances_root.add_child(trap)


func _spawn_entrance_exit_markers() -> void:
	var entrance_pos := _room_center_2d(_layout_room_name("start_room"))
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
	_enemy_nodes_by_network_id.clear()
	if not _is_authoritative_world():
		_spawn_points_by_encounter.clear()
		_spawn_volumes_by_encounter.clear()
		_spawn_count_by_encounter.clear()
		_planned_tower_positions_by_encounter.clear()
		_entry_socket_by_encounter.clear()
		_entry_socket_dir_by_encounter.clear()
		if _door_lock_controller != null:
			_door_lock_controller.clear_encounter_locks()
		_encounter_active = {}
		_encounter_completed = {}
		_encounter_mobs = {}
		_combat_encounter_id = &""
		return
	_spawn_points_by_encounter.clear()
	_spawn_volumes_by_encounter.clear()
	_spawn_count_by_encounter.clear()
	_planned_tower_positions_by_encounter.clear()
	_entry_socket_by_encounter.clear()
	_entry_socket_dir_by_encounter.clear()
	if _door_lock_controller != null:
		_door_lock_controller.clear_encounter_locks()
	_encounter_active = {&"boss": false}
	_encounter_completed = {&"boss": false}
	_encounter_mobs = {&"boss": []}
	_combat_encounter_id = &""

	var combat_room_name := _layout_room_name("combat_room")
	var boss_room := _room_by_name(_layout_room_name("exit_room"))
	if boss_room == null:
		return
	var boss_center := boss_room.global_position
	_entry_socket_by_encounter[&"boss"] = _boss_entry_socket
	_entry_socket_dir_by_encounter[&"boss"] = _boss_entry_dir
	_cache_locked_sockets_for_encounter(boss_room, &"boss")
	_spawn_encounter_trigger(boss_center, &"boss", "BossEncounterTrigger")
	for room in _rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		if r.room_type != "arena":
			continue
		var encounter_id := StringName("arena_%s" % [String(r.name)])
		var trigger_name := "ArenaEncounterTrigger_%s" % [String(r.name)]
		_cache_entry_socket_for_encounter(r, encounter_id)
		_cache_locked_sockets_for_encounter(r, encounter_id)
		var trigger_pos := r.global_position
		var trigger_sz := Vector2.ZERO
		if r.name == combat_room_name and _combat_entry_socket.length_squared() > 0.01:
			# Fire once the player is well inside the arena (entry socket is excluded from pull-in clamps).
			var inward := (-_direction_vector(_combat_entry_dir)).normalized()
			trigger_pos = _combat_entry_socket + inward * (_DOOR_SLAB_HALF + _COMBAT_ENTRY_TRIGGER_INSET)
			match _combat_entry_dir:
				"west", "east":
					trigger_sz = Vector2(6.0, _DOOR_CLAMP_Y_EXT * 2.0 + 2.0)
				"north", "south":
					trigger_sz = Vector2(_DOOR_CLAMP_Y_EXT * 2.0 + 2.0, 6.0)
				_:
					trigger_sz = Vector2(6.0, 14.0)
		_spawn_encounter_trigger(trigger_pos, encounter_id, trigger_name, trigger_sz)
		_spawn_arena_modules_for_room(r, encounter_id)
		_spawn_count_by_encounter[encounter_id] = _rng.randi_range(2, 4)
		_encounter_active[encounter_id] = false
		_encounter_completed[encounter_id] = false
		_encounter_mobs[encounter_id] = []
		if r.name == combat_room_name:
			_combat_encounter_id = encounter_id

	var boss_half := _room_half_extents(boss_room)
	var bpx := maxf(5.0, boss_half.x - 12.0)
	var bpy := maxf(5.0, boss_half.y - 12.0)
	_spawn_enemy_spawn_point(boss_center + Vector2(-bpx, -bpy), &"boss")
	_spawn_enemy_spawn_point(boss_center + Vector2(bpx, bpy), &"boss")
	var boss_vol_size := Vector2(maxf(16.0, boss_half.x * 0.4), maxf(12.0, boss_half.y * 0.35))
	_spawn_enemy_spawn_volume(boss_center + Vector2(-bpx, bpy), boss_vol_size, &"boss")
	_prespawn_encounter_mobs()


func _cache_locked_sockets_for_encounter(room: RoomBase, encounter_id: StringName) -> void:
	if _door_lock_controller == null:
		return
	var ex_pos := _entry_socket_by_encounter.get(encounter_id, Vector2.ZERO) as Vector2
	var ex_dir := String(_entry_socket_dir_by_encounter.get(encounter_id, ""))
	_door_lock_controller.cache_room_locks(room, encounter_id, _door_visual_by_socket_key, ex_pos, ex_dir)


func _socket_pos_key(p: Vector2) -> String:
	var qx := int(roundf(p.x * 100.0))
	var qy := int(roundf(p.y * 100.0))
	return "%s:%s" % [qx, qy]


func _apply_encounter_door_visuals_locked(
	encounter_id: StringName, locked: bool, animate: bool = true
) -> void:
	if _door_lock_controller != null:
		_door_lock_controller.set_encounter_visuals_locked(encounter_id, locked, animate)


func _set_encounter_door_visuals_locked(encounter_id: StringName, locked: bool, animate: bool = true) -> void:
	_apply_encounter_door_visuals_locked(encounter_id, locked, animate)
	if (
		_networked_run
		and _is_server_peer()
		and _has_multiplayer_peer()
		and _can_broadcast_world_replication()
	):
		_rpc_set_encounter_door_visuals_locked.rpc(String(encounter_id), locked, animate)


func _spawn_encounter_trigger(
	position_2d: Vector2,
	encounter_id: StringName,
	node_name: String,
	trigger_size_override: Vector2 = Vector2.ZERO
) -> void:
	var trigger := ROOM_TRIGGER_SCENE.instantiate() as RoomEncounterTrigger2D
	if trigger == null:
		return
	trigger.name = node_name
	trigger.encounter_id = encounter_id
	trigger.position = position_2d
	if trigger_size_override.length_squared() > 0.001:
		trigger.trigger_size = trigger_size_override
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


func _spawn_arena_modules_for_room(room: RoomBase, encounter_id: StringName) -> void:
	var center := room.global_position
	var half := _room_half_extents(room)
	var margin := Vector2(minf(6.0, half.x * 0.35), minf(6.0, half.y * 0.35))
	var px := maxf(3.0, half.x - margin.x)
	var py := maxf(3.0, half.y - margin.y)
	for point_pos in [
		center + Vector2(-px, -py),
		center + Vector2(-px, py),
		center + Vector2(px, -py),
		center + Vector2(px, py),
	]:
		_spawn_enemy_spawn_point(point_pos, encounter_id)
	var vol_size := Vector2(maxf(12.0, half.x * 0.5), maxf(10.0, half.y * 0.4))
	_spawn_enemy_spawn_volume(center + Vector2(-px * 0.78, -py * 0.72), vol_size, encounter_id)
	_spawn_enemy_spawn_volume(center + Vector2(px * 0.78, py * 0.72), vol_size, encounter_id)


func _on_encounter_triggered(encounter_id: StringName) -> void:
	if not _is_authoritative_world():
		return
	if bool(_encounter_active.get(encounter_id, false)) or bool(_encounter_completed.get(encounter_id, false)):
		return
	match String(encounter_id):
		"boss":
			call_deferred("_start_boss_encounter")
		_:
			if String(encounter_id).begins_with("arena_"):
				call_deferred("_start_arena_encounter", encounter_id)


func _start_arena_encounter(encounter_id: StringName) -> void:
	_encounter_active[encounter_id] = true
	_set_encounter_door_visuals_locked(encounter_id, true, true)
	_set_encounter_mobs_aggro(encounter_id, true)
	var is_main_combat := encounter_id == _combat_encounter_id
	if is_main_combat:
		_combat_started = true
		_set_combat_doors_locked(true)
		_set_info_base_text("Combat started. Clear all enemies to unlock.")
	else:
		_set_info_base_text("Arena encounter started.")
	if (_encounter_mobs.get(encounter_id, []) as Array).is_empty():
		var count := int(_spawn_count_by_encounter.get(encounter_id, _rng.randi_range(2, 4)))
		_spawn_encounter_wave(encounter_id, clampi(count, 2, 4), 1.0 + float(_floor_index - 1) * 0.08)


func _start_boss_encounter() -> void:
	_boss_started = true
	_encounter_active[&"boss"] = true
	_set_encounter_door_visuals_locked(&"boss", true, true)
	_set_encounter_mobs_aggro(&"boss", true)
	_set_boss_entry_locked(true)
	_set_info_base_text("Boss encounter started. Defeat all enemies.")
	if (_encounter_mobs.get(&"boss", []) as Array).is_empty():
		var raw_count := 2 + int(floor(float(_floor_index - 1) / 2.0))
		var adjusted_count := maxi(1, int(ceili(float(raw_count) * 0.5)))
		_spawn_encounter_wave(
			&"boss",
			adjusted_count,
			1.25 + float(_floor_index - 1) * 0.05
		)


func _reference_player_position() -> Vector2:
	var ordered_peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	for peer_id in ordered_peer_ids:
		var node_v: Variant = _players_by_peer.get(peer_id, null)
		if node_v is CharacterBody2D and is_instance_valid(node_v):
			return (node_v as CharacterBody2D).global_position
	if _player != null and is_instance_valid(_player) and _player.is_in_group(&"player"):
		return _player.global_position
	var start_room := _layout_room_name("start_room")
	if String(start_room) != "":
		return _room_center_2d(start_room)
	return Vector2.ZERO


func _spawn_encounter_wave(encounter_id: StringName, total_count: int, speed_multiplier: float) -> void:
	if not _planned_tower_positions_by_encounter.has(encounter_id):
		_planned_tower_positions_by_encounter[encounter_id] = []
	var spawned := 0
	var points: Array = _spawn_points_by_encounter.get(encounter_id, []) as Array
	var volumes: Array = _spawn_volumes_by_encounter.get(encounter_id, []) as Array
	var player_pos := _reference_player_position()
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
			var pos := point.get_spawn_position()
			if scene_for_spawn == ARROW_TOWER_SCENE:
				pos = _tower_spawn_near_center(encounter_id, pos)
			pos = _bias_spawn_to_back_half(encounter_id, pos)
			if scene_for_spawn == ARROW_TOWER_SCENE:
				pos = _separate_tower_spawn(encounter_id, pos)
				_register_planned_tower_spawn(encounter_id, pos)
			_spawn_encounter_mob(
				encounter_id,
				pos,
				player_pos,
				speed_multiplier,
				scene_for_spawn,
				false
			)
			spawned += 1
	while spawned < total_count:
		if volumes.is_empty():
			break
		var volume_idx := randi() % volumes.size()
		var volume := volumes[volume_idx] as EnemySpawnVolume2D
		var scene_for_spawn := planned_scenes[spawned] if spawned < planned_scenes.size() else null
		var vpos := volume.sample_spawn_position()
		if scene_for_spawn == ARROW_TOWER_SCENE:
			vpos = _tower_spawn_near_center(encounter_id, vpos)
		vpos = _bias_spawn_to_back_half(encounter_id, vpos)
		if scene_for_spawn == ARROW_TOWER_SCENE:
			vpos = _separate_tower_spawn(encounter_id, vpos)
			_register_planned_tower_spawn(encounter_id, vpos)
		_spawn_encounter_mob(
			encounter_id,
			vpos,
			player_pos,
			speed_multiplier,
			scene_for_spawn,
			false
		)
		spawned += 1


func _spawn_encounter_mob(
	encounter_id: StringName,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	enemy_scene: PackedScene = null,
	start_aggro := false
) -> void:
	call_deferred(
		"_spawn_encounter_mob_deferred",
		encounter_id,
		spawn_position,
		target_position,
		speed_multiplier,
		enemy_scene,
		start_aggro
	)


func _spawn_encounter_mob_deferred(
	encounter_id: StringName,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	enemy_scene: PackedScene = null,
	start_aggro := false
) -> void:
	var resolved_encounter_id := _resolve_encounter_for_spawn(encounter_id, spawn_position)
	var scene_to_spawn := enemy_scene if enemy_scene != null else _pick_enemy_scene(encounter_id)
	var scene_kind := _enemy_scene_kind_from_scene(scene_to_spawn)
	var net_id := _next_enemy_network_id()
	var enemy := scene_to_spawn.instantiate() as EnemyBase
	if enemy == null:
		return
	enemy.apply_speed_multiplier(speed_multiplier)
	enemy.configure_spawn(spawn_position, target_position)
	_register_enemy_network_id(enemy, net_id)
	$GameWorld2D.add_child(enemy)
	var encounter_is_active := bool(_encounter_active.get(resolved_encounter_id, false))
	var final_aggro := start_aggro or encounter_is_active
	enemy.set_aggro_enabled(final_aggro)
	_register_encounter_enemy(resolved_encounter_id, enemy)
	if _is_server_peer() and _can_broadcast_world_replication():
		_rpc_spawn_enemy.rpc(
			net_id,
			String(resolved_encounter_id),
			scene_kind,
			spawn_position,
			target_position,
			speed_multiplier,
			final_aggro
		)


func _set_encounter_mobs_aggro(encounter_id: StringName, enabled: bool) -> void:
	var mobs: Array = _encounter_mobs.get(encounter_id, []) as Array
	for mob in mobs:
		if mob is EnemyBase and is_instance_valid(mob):
			(mob as EnemyBase).set_aggro_enabled(enabled)
	if _is_server_peer() and _can_broadcast_world_replication():
		_rpc_set_encounter_aggro.rpc(String(encounter_id), enabled)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_enemy(
	net_id: int,
	encounter_id_text: String,
	scene_kind: int,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	aggro_enabled: bool
) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var existing_v: Variant = _enemy_nodes_by_network_id.get(net_id, null)
	if existing_v is EnemyBase and is_instance_valid(existing_v):
		(existing_v as EnemyBase).set_aggro_enabled(aggro_enabled)
		return
	var scene_to_spawn := _enemy_scene_from_kind(scene_kind)
	if scene_to_spawn == null:
		return
	var enemy := scene_to_spawn.instantiate() as EnemyBase
	if enemy == null:
		return
	var encounter_id := StringName(encounter_id_text)
	enemy.apply_speed_multiplier(speed_multiplier)
	enemy.configure_spawn(spawn_position, target_position)
	_register_enemy_network_id(enemy, net_id)
	$GameWorld2D.add_child(enemy)
	enemy.set_aggro_enabled(aggro_enabled)
	_register_encounter_enemy(encounter_id, enemy)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_despawn_enemy(net_id: int) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var enemy_v: Variant = _enemy_nodes_by_network_id.get(net_id, null)
	if enemy_v is EnemyBase and is_instance_valid(enemy_v):
		(enemy_v as EnemyBase).queue_free()
	_enemy_nodes_by_network_id.erase(net_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_encounter_aggro(encounter_id_text: String, enabled: bool) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var encounter_id := StringName(encounter_id_text)
	var mobs: Array = _encounter_mobs.get(encounter_id, []) as Array
	for mob in mobs:
		if mob is EnemyBase and is_instance_valid(mob):
			(mob as EnemyBase).set_aggro_enabled(enabled)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_encounter_door_visuals_locked(
	encounter_id_text: String, locked: bool, animate: bool
) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_encounter_door_visuals_locked(StringName(encounter_id_text), locked, animate)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_combat_doors_locked(locked: bool, animate: bool) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_combat_doors_locked(locked, animate)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_boss_exit_active(active: bool) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_set_boss_exit_active(active, false)


@rpc("authority", "call_remote", "reliable")
func _rpc_set_puzzle_gate_solved(solved: bool, animate: bool) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_puzzle_gate_solved(solved, animate)


func _send_runtime_snapshot_to_peer(peer_id: int) -> void:
	if peer_id <= 0 or not _is_server_peer() or not _has_multiplayer_peer():
		return
	var enemy_ids: Array = _enemy_nodes_by_network_id.keys()
	enemy_ids.sort()
	for key in enemy_ids:
		var net_id := int(key)
		var enemy_v: Variant = _enemy_nodes_by_network_id.get(net_id, null)
		if enemy_v is not EnemyBase or not is_instance_valid(enemy_v):
			continue
		var enemy := enemy_v as EnemyBase
		var encounter_id := StringName(enemy.get_meta(&"encounter_id", &""))
		var scene_kind := _enemy_scene_kind_from_enemy_instance(enemy)
		var aggro_enabled := bool(_encounter_active.get(encounter_id, false))
		_rpc_spawn_enemy.rpc_id(
			peer_id,
			net_id,
			String(encounter_id),
			scene_kind,
			enemy.global_position,
			enemy.global_position,
			1.0,
			aggro_enabled
		)
	_rpc_set_puzzle_gate_solved.rpc_id(peer_id, _puzzle_solved, false)
	_ensure_coin_totals_for_roster()
	_rpc_sync_coin_totals.rpc_id(peer_id, _coin_totals_by_peer)
	for player_peer_id in _players_by_peer.keys():
		var player_v: Variant = _players_by_peer.get(player_peer_id, null)
		if player_v is not CharacterBody2D or not is_instance_valid(player_v):
			continue
		var player := player_v as CharacterBody2D
		if player == null or not player.has_method(&"get_loadout_view_model"):
			continue
		var snapshot := get_player_loadout_snapshot(player)
		if snapshot.is_empty():
			continue
		player.rpc_id(peer_id, &"_rpc_receive_loadout_snapshot", snapshot)
	_rpc_runtime_snapshot_complete.rpc_id(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_layout_snapshot() -> void:
	if not _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null:
		return
	var requester_peer := mp.get_remote_sender_id()
	if requester_peer <= 0:
		return
	if _map_layout.is_empty():
		return
	_rpc_receive_layout_snapshot.rpc_id(requester_peer, _floor_index, _layout_snapshot_payload())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_runtime_snapshot() -> void:
	if not _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null:
		return
	var requester_peer := mp.get_remote_sender_id()
	if requester_peer <= 0:
		return
	_send_runtime_snapshot_to_peer(requester_peer)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_runtime_snapshot_complete() -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if _network_session != null and _network_session.has_method("mark_runtime_scene_ready_local"):
		_network_session.call("mark_runtime_scene_ready_local")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_layout_snapshot(floor_index_value: int, layout_snapshot: Dictionary) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if layout_snapshot.is_empty():
		return
	_floor_index = maxi(1, floor_index_value)
	_map_layout = layout_snapshot.duplicate(true)
	_awaiting_layout_snapshot = false
	_regenerate_level(false)
	_request_runtime_snapshot_from_server()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_open_treasure_chest(chest_path: NodePath) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var chest := get_node_or_null(chest_path) as TreasureChest2D
	if chest == null:
		return
	if chest.has_method(&"open_visual_only"):
		chest.call(&"open_visual_only")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_coin(
	coin_network_id: int, spawn_position: Vector2, landing_position: Vector2, coin_value: int
) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_spawn_coin_instance(coin_network_id, spawn_position, landing_position, coin_value, false)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_coin_collected(coin_network_id: int, picker_peer_id: int, picker_new_total: int) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_despawn_coin_local(coin_network_id)
	_shared_coin_total = maxi(0, picker_new_total)
	_ensure_coin_totals_for_roster()
	_refresh_local_coin_ui()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_coin_totals(raw_totals: Dictionary) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_coin_totals_by_peer = _normalize_coin_totals(raw_totals)
	var synced_total := 0
	for value in _coin_totals_by_peer.values():
		synced_total = maxi(synced_total, int(value))
	_shared_coin_total = synced_total
	_ensure_coin_totals_for_roster()
	_refresh_local_coin_ui()


func _prespawn_encounter_mobs() -> void:
	for encounter_key in _spawn_count_by_encounter.keys():
		var encounter_id := encounter_key as StringName
		var count := clampi(int(_spawn_count_by_encounter.get(encounter_id, 0)), 0, 4)
		if count > 0:
			_spawn_encounter_wave(encounter_id, count, 1.0 + float(_floor_index - 1) * 0.08)
	var raw_count := 2 + int(floor(float(_floor_index - 1) / 2.0))
	var adjusted_count := maxi(1, int(ceili(float(raw_count) * 0.5)))
	_spawn_encounter_wave(&"boss", adjusted_count, 1.25 + float(_floor_index - 1) * 0.05)


func _cache_entry_socket_for_encounter(room: RoomBase, encounter_id: StringName) -> void:
	if room == null:
		return
	var start_center := _room_center_2d(_layout_room_name("start_room"))
	var best_socket := room.global_position
	var best_dist := 1.0e12
	var best_dir := ""
	for socket in room.get_all_sockets():
		if socket.connector_type == &"inactive":
			continue
		var world_pos := room.global_position + socket.position
		var d := world_pos.distance_squared_to(start_center)
		if d < best_dist:
			best_dist = d
			best_socket = world_pos
			best_dir = String(socket.direction)
	_entry_socket_by_encounter[encounter_id] = best_socket
	_entry_socket_dir_by_encounter[encounter_id] = best_dir


func _bias_spawn_to_back_half(encounter_id: StringName, candidate_pos: Vector2) -> Vector2:
	var room_name := StringName()
	var id_text := String(encounter_id)
	if id_text == "boss":
		room_name = _layout_room_name("exit_room")
	elif id_text.begins_with("arena_"):
		room_name = StringName(id_text.trim_prefix("arena_"))
	else:
		return candidate_pos
	var room := _room_by_name(room_name)
	if room == null:
		return candidate_pos
	var entry_socket := _entry_socket_by_encounter.get(encounter_id, room.global_position) as Vector2
	var to_entry := entry_socket - room.global_position
	if to_entry.length_squared() <= 0.0001:
		return candidate_pos
	var back_dir := -to_entry.normalized()
	var half := _room_half_extents(room)
	var back_limit := maxf(2.5, maxf(half.x, half.y) * _BACK_HALF_MIN_RATIO)
	var rel := candidate_pos - room.global_position
	var dot_back := rel.dot(back_dir)
	if dot_back >= back_limit:
		return candidate_pos
	var adjusted := candidate_pos + back_dir * (back_limit - dot_back)
	# Keep spawn inside the owning room even after back-half bias.
	var room_rect_local := room.get_room_rect_world()
	var room_rect := Rect2(room.global_position - room_rect_local.size * 0.5, room_rect_local.size)
	adjusted.x = clampf(adjusted.x, room_rect.position.x + 0.9, room_rect.end.x - 0.9)
	adjusted.y = clampf(adjusted.y, room_rect.position.y + 0.9, room_rect.end.y - 0.9)
	return adjusted


func _resolve_encounter_for_spawn(requested_encounter_id: StringName, spawn_pos: Vector2) -> StringName:
	if String(requested_encounter_id) == "boss":
		return requested_encounter_id
	var room_name := _room_name_at(spawn_pos, 1.25)
	if room_name.is_empty():
		return requested_encounter_id
	var resolved := StringName("arena_%s" % [room_name])
	if _encounter_active.has(resolved) and _encounter_completed.has(resolved):
		return resolved
	return requested_encounter_id


func _pick_enemy_scene(encounter_id: StringName) -> PackedScene:
	# Arena encounters mix towers; boss keeps lower tower frequency.
	var tower_weight := 0.35 if String(encounter_id) != "boss" else 0.25
	return ARROW_TOWER_SCENE if randf() < tower_weight else DASHER_SCENE


func _on_encounter_mob_removed(encounter_id: StringName, mob: EnemyBase) -> void:
	if not _encounter_mobs.has(encounter_id):
		pass
	else:
		var mobs: Array = _encounter_mobs[encounter_id] as Array
		mobs.erase(mob)
		_encounter_mobs[encounter_id] = mobs
	var net_id := -1
	if mob != null and mob.has_meta(&"enemy_network_id"):
		net_id = int(mob.get_meta(&"enemy_network_id", -1))
	if net_id > 0:
		_enemy_nodes_by_network_id.erase(net_id)
		if _is_server_peer() and _can_broadcast_world_replication():
			_rpc_despawn_enemy.rpc(net_id)


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
		"boss":
			_boss_cleared = true
			_set_encounter_door_visuals_locked(encounter_id, false, true)
			_set_boss_entry_locked(false)
			_set_boss_exit_active(true)
			_set_info_base_text("Boss defeated. Elevator is active. All players must board.")
		_:
			if String(encounter_id).begins_with("arena_"):
				_set_encounter_door_visuals_locked(encounter_id, false, true)
				if encounter_id == _combat_encounter_id:
					_combat_cleared = true
					_set_combat_doors_locked(false)
					_set_info_base_text("Combat room cleared. Doors unlocked.")
				else:
					_set_info_base_text("Arena room cleared.")


func _set_boss_exit_active(active: bool, replicate: bool = true) -> void:
	if _boss_exit_portal != null and is_instance_valid(_boss_exit_portal):
		_boss_exit_portal.monitoring = active
		_boss_exit_portal.monitorable = active
	if _boss_portal_marker != null:
		_boss_portal_marker.visible = false
	if _boss_exit_elevator_visual != null and is_instance_valid(_boss_exit_elevator_visual):
		_boss_exit_elevator_visual.visible = active
	if (
		replicate
		and _networked_run
		and _is_server_peer()
		and _has_multiplayer_peer()
		and _can_broadcast_world_replication()
	):
		_rpc_set_boss_exit_active.rpc(active)


func _required_floor_transition_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	if peer_ids.is_empty():
		peer_ids.append(_local_peer_id())
	return peer_ids


func _count_players_on_exit_elevator(required_peer_ids: Array[int]) -> int:
	if _boss_exit_portal == null:
		return 0
	var overlaps: Array = _boss_exit_portal.get_overlapping_bodies()
	var on_count := 0
	for peer_id in required_peer_ids:
		var node_v: Variant = _players_by_peer.get(peer_id, null)
		if node_v is not CharacterBody2D:
			continue
		var player := node_v as CharacterBody2D
		if player == null or not is_instance_valid(player):
			continue
		if overlaps.has(player):
			on_count += 1
	return on_count


func _try_schedule_floor_advance_if_all_players_on_elevator() -> void:
	if not _is_authoritative_world():
		return
	if not _boss_cleared or _floor_transition_pending:
		return
	if _boss_exit_portal == null or not _boss_exit_portal.monitoring:
		return
	var required_peer_ids: Array[int] = _required_floor_transition_peer_ids()
	if required_peer_ids.is_empty():
		return
	var on_count := _count_players_on_exit_elevator(required_peer_ids)
	if on_count < required_peer_ids.size():
		_set_info_base_text(
			"Boss defeated. Elevator boarding: %s/%s players." % [on_count, required_peer_ids.size()]
		)
		return
	_schedule_floor_advance_after_portal()


func _count_players_on_debug_exit_elevator(required_peer_ids: Array[int]) -> int:
	if _debug_spawn_exit_portal == null:
		return 0
	var overlaps: Array = _debug_spawn_exit_portal.get_overlapping_bodies()
	var on_count := 0
	for peer_id in required_peer_ids:
		var node_v: Variant = _players_by_peer.get(peer_id, null)
		if node_v is not CharacterBody2D:
			continue
		var player := node_v as CharacterBody2D
		if player == null or not is_instance_valid(player):
			continue
		if overlaps.has(player):
			on_count += 1
	return on_count


func _try_schedule_floor_advance_if_all_players_on_debug_elevator() -> void:
	if not _is_authoritative_world():
		return
	if _floor_transition_pending:
		return
	if not OS.is_debug_build():
		return
	if _debug_spawn_exit_portal == null or not _debug_spawn_exit_portal.monitoring:
		return
	var required_peer_ids: Array[int] = _required_floor_transition_peer_ids()
	if required_peer_ids.is_empty():
		return
	var on_count := _count_players_on_debug_exit_elevator(required_peer_ids)
	if on_count < required_peer_ids.size():
		_set_info_base_text(
			"Debug elevator boarding: %s/%s players." % [on_count, required_peer_ids.size()]
		)
		return
	_schedule_floor_advance_after_portal()


func _on_boss_exit_portal_body_entered(body: Node2D) -> void:
	if not _is_authoritative_world():
		return
	if not _boss_cleared or not _is_player_body(body):
		return
	_try_schedule_floor_advance_if_all_players_on_elevator()


func _on_debug_spawn_exit_portal_body_entered(body: Node2D) -> void:
	if not _is_authoritative_world():
		return
	if not OS.is_debug_build() or not _is_player_body(body):
		return
	_try_schedule_floor_advance_if_all_players_on_debug_elevator()


func _on_leave_run_pressed() -> void:
	var session := get_node_or_null("/root/NetworkSession")
	if session == null or not session.has_method("request_leave_run_from_local_peer"):
		return
	session.call("request_leave_run_from_local_peer")


func _schedule_floor_advance_after_portal() -> void:
	if _floor_transition_pending:
		return
	_floor_transition_pending = true
	_set_boss_exit_active(false)
	_debug_spawn_exit_portal.set_deferred("monitoring", false)
	_debug_spawn_exit_portal.set_deferred("monitorable", false)
	if _debug_spawn_exit_elevator_visual != null and is_instance_valid(_debug_spawn_exit_elevator_visual):
		_debug_spawn_exit_elevator_visual.visible = false
	call_deferred("_deferred_advance_floor_after_portal")


func _deferred_advance_floor_after_portal() -> void:
	if not _floor_transition_pending:
		return
	_floor_transition_pending = false
	for peer_id in _players_by_peer.keys():
		var node: Variant = _players_by_peer[peer_id]
		if node is CharacterBody2D and is_instance_valid(node):
			var player := node as CharacterBody2D
			if player.has_method(&"revive_to_full"):
				player.call(&"revive_to_full")
			elif player.has_method(&"heal_to_full"):
				player.call(&"heal_to_full")
	_floor_index += 1
	_regenerate_level(true)


func _on_player_hit() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var downed := false
	if _player.has_method(&"is_downed"):
		downed = bool(_player.call(&"is_downed"))
	if downed:
		_set_info_base_text("You are downed. A teammate can revive you by stepping on you.")


func _authoritative_roster_players() -> Array[CharacterBody2D]:
	var roster: Array[CharacterBody2D] = []
	for peer_id in _players_by_peer.keys():
		var node_v: Variant = _players_by_peer.get(peer_id, null)
		if node_v is CharacterBody2D and is_instance_valid(node_v):
			roster.append(node_v as CharacterBody2D)
	if roster.is_empty() and _player != null and is_instance_valid(_player):
		roster.append(_player)
	return roster


func _player_is_downed(player: CharacterBody2D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method(&"is_downed"):
		return bool(player.call(&"is_downed"))
	return false


func _try_revive_downed_players(roster: Array[CharacterBody2D]) -> bool:
	var revived_any := false
	var downed_players: Array[CharacterBody2D] = []
	var active_players: Array[CharacterBody2D] = []
	for player in roster:
		if _player_is_downed(player):
			downed_players.append(player)
		else:
			active_players.append(player)
	if downed_players.is_empty() or active_players.is_empty():
		return false
	for downed_player in downed_players:
		var revived := false
		for active_player in active_players:
			if active_player == downed_player:
				continue
			var dist := active_player.global_position.distance_to(downed_player.global_position)
			if dist > _REVIVE_TRIGGER_DISTANCE:
				continue
			if downed_player.has_method(&"revive"):
				downed_player.call(&"revive", _TEAM_REVIVE_HEALTH)
				revived_any = true
				revived = true
				break
		if revived:
			continue
	return revived_any


func _all_roster_players_downed(roster: Array[CharacterBody2D]) -> bool:
	if roster.is_empty():
		return false
	for player in roster:
		if not _player_is_downed(player):
			return false
	return true


func _process_authoritative_revive_and_wipe() -> void:
	if _party_wipe_pending:
		return
	var roster: Array[CharacterBody2D] = _authoritative_roster_players()
	if roster.is_empty():
		return
	var revived_any := _try_revive_downed_players(roster)
	if revived_any:
		_set_info_base_text("Teammate revived.")
		roster = _authoritative_roster_players()
	if _all_roster_players_downed(roster):
		_trigger_party_wipe_return_to_lobby()


func _trigger_party_wipe_return_to_lobby() -> void:
	if _party_wipe_pending:
		return
	_party_wipe_pending = true
	_set_info_base_text("All players are downed. Returning to lobby...")
	call_deferred("_deferred_return_party_to_lobby")


func _deferred_return_party_to_lobby() -> void:
	if not _party_wipe_pending:
		return
	_party_wipe_pending = false
	var session := get_node_or_null("/root/NetworkSession")
	if session == null:
		get_tree().change_scene_to_file("res://scenes/ui/lobby_menu.tscn")
		return
	if (
		session.has_method("has_active_peer")
		and bool(session.call("has_active_peer"))
		and _is_authoritative_world()
		and session.has_method("return_to_lobby")
	):
		session.call("return_to_lobby")
		return
	if session.has_method("disconnect_from_session"):
		session.call("disconnect_from_session")


func _reset_score_ui() -> void:
	_coin_totals_by_peer.clear()
	_shared_coin_total = 0
	_ensure_coin_totals_for_roster()
	_refresh_local_coin_ui()
	_broadcast_coin_totals_if_server()


func _is_point_inside_any_room(world_pos: Vector2, margin: float = 0.0) -> bool:
	return _room_queries.is_point_inside_any_room(world_pos, margin) if _room_queries != null else false


func _room_name_at(world_pos: Vector2, margin: float = 0.0) -> String:
	return _room_queries.room_name_at(world_pos, margin) if _room_queries != null else ""


func _door_resolve_room_name_for_body(body: CharacterBody2D) -> String:
	if body == null:
		return ""
	return _room_name_at(body.global_position, 1.25)


func _is_player_body(body: Node2D) -> bool:
	return body != null and body is CharacterBody2D and body.is_in_group(&"player")


func _room_type_at(world_pos: Vector2, margin: float = 0.0) -> String:
	return _room_queries.room_type_at(world_pos, margin) if _room_queries != null else ""


func _set_info_base_text(text: String) -> void:
	if _info_controller != null:
		_info_controller.set_base_text(text)


func _refresh_info_label_with_room_type() -> void:
	if _info_controller != null:
		_info_controller.refresh()
