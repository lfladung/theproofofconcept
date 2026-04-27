extends Node

## Dungeon floor orchestration: generation, encounters, multiplayer, doors, camera glue.
## Per-frame presentation/debug: `dungeon_orchestrator.gd`.

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
const LAYOUT_KEY_PHASE := "layout_phase"
const LAYOUT_PHASE_FLOOR := "floor"
const LAYOUT_PHASE_MINI_HUB := "mini_hub"
const DOOR_STANDARD_SCENE := preload("res://dungeon/modules/connectivity/door_standard_2d.tscn")
const ENTRANCE_MARKER_SCENE := preload("res://dungeon/modules/connectivity/entrance_marker_2d.tscn")
const EXIT_MARKER_SCENE := preload("res://dungeon/modules/connectivity/exit_marker_2d.tscn")
const FLOW_DASHER_SCENE := preload("res://scenes/entities/flow_dasher.tscn")
const FLOWFORM_SCENE := preload("res://scenes/entities/flowform.tscn")
const SCRAMBLER_SCENE := preload("res://scenes/entities/scrambler.tscn")
const STUMBLER_SCENE := preload("res://scenes/entities/stumbler.tscn")
const SHIELDWALL_SCENE := preload("res://scenes/entities/shieldwall.tscn")
const WARDEN_SCENE := preload("res://scenes/entities/warden.tscn")
const SPLITTER_SCENE := preload("res://scenes/entities/splitter.tscn")
const ECHOFORM_SCENE := preload("res://scenes/entities/echoform.tscn")
const TRIAD_SCENE := preload("res://scenes/entities/triad.tscn")
const ECHO_SPLINTER_SCENE := preload("res://scenes/entities/echo_splinter.tscn")
const ECHO_UNIT_SCENE := preload("res://scenes/entities/echo_unit.tscn")
const BINDER_SCENE := preload("res://scenes/entities/binder.tscn")
const LURKER_SCENE := preload("res://scenes/entities/lurker.tscn")
const LEECHER_SCENE := preload("res://scenes/entities/leecher.tscn")
const SKEWER_SCENE := preload("res://scenes/entities/skewer.tscn")
const GLAIVER_SCENE := preload("res://scenes/entities/glaiver.tscn")
const RAZORFORM_SCENE := preload("res://scenes/entities/razorform.tscn")
const SPLITTER_MOB_SCRIPT := preload("res://scripts/entities/splitter_mob.gd")
const ECHOFORM_MOB_SCRIPT := preload("res://scripts/entities/echoform_mob.gd")
const TRIAD_MOB_SCRIPT := preload("res://scripts/entities/triad_mob.gd")
const ECHO_SPLINTER_MOB_SCRIPT := preload("res://scripts/entities/echo_splinter_mob.gd")
const ECHO_UNIT_MOB_SCRIPT := preload("res://scripts/entities/echo_unit_mob.gd")
const BINDER_MOB_SCRIPT := preload("res://scripts/entities/binder_mob.gd")
const LURKER_MOB_SCRIPT := preload("res://scripts/entities/lurker_mob.gd")
const LEECHER_MOB_SCRIPT := preload("res://scripts/entities/leecher_mob.gd")
const SKEWER_MOB_SCRIPT := preload("res://scripts/entities/skewer_mob.gd")
const GLAIVER_MOB_SCRIPT := preload("res://scripts/entities/glaiver_mob.gd")
const RAZORFORM_MOB_SCRIPT := preload("res://scripts/entities/razorform_mob.gd")
const SPAWN_POINT_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_point_2d.tscn")
const SPAWN_VOLUME_SCENE := preload("res://dungeon/modules/encounter/enemy_spawn_volume_2d.tscn")
const ROOM_TRIGGER_SCENE := preload("res://dungeon/modules/encounter/room_encounter_trigger_2d.tscn")
const TREASURE_CHEST_SCENE := preload("res://dungeon/modules/gameplay/treasure_chest_2d.tscn")
const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")
const PUZZLE_FLOOR_BUTTON_SCENE := preload("res://dungeon/modules/gameplay/puzzle_floor_button_2d.tscn")
const ROOM_BASE_SCENE := preload("res://dungeon/rooms/base/room_base.tscn")
const TRAP_TILE_SCENE := preload("res://dungeon/modules/gameplay/trap_tile_2d.tscn")
const INFUSION_PILLAR_SCENE := preload("res://dungeon/modules/gameplay/infusion_pillar_2d.tscn")
const INFUSION_EDGE_PILLAR_VISUAL_SCENE := preload(
	"res://dungeon/modules/gameplay/infusion_edge_pillar_visual.tscn"
)
const InfusionConstantsBossPool = preload("res://scripts/infusion/infusion_constants.gd")
## Boss-room pillar rolls: full pillar set (matches `InfusionConstants.PILLAR_ORDER`).
const _BOSS_RANDOM_INFUSION_IDS: Array[StringName] = InfusionConstantsBossPool.PILLAR_ORDER
const DUNGEON_CELL_DOOR_SCENE := preload("res://dungeon/visuals/dungeon_cell_door_3d.tscn")
const RoomEditorSceneSyncScript = preload("res://addons/dungeon_room_editor/core/scene_sync.gd")
const RoomPreviewBuilderScript = preload("res://addons/dungeon_room_editor/preview/preview_builder.gd")
const ROOM_PIECE_CATALOG = preload("res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres")
const AuthoredRoomCatalogScript = preload("res://dungeon/game/floor_generation/authored_room_catalog.gd")
const AuthoredFloorGeneratorScript = preload("res://dungeon/game/floor_generation/authored_floor_generator.gd")
const EncounterSpawnControllerScript = preload("res://dungeon/game/components/encounter_spawn_controller.gd")
const ConnectionRoomGateControllerScript = preload("res://dungeon/game/components/connection_room_gate_controller.gd")
const EnemySpawnByEnemyId = preload("res://dungeon/game/enemy_spawn_by_id.gd")
const EncounterRunManagerScript = preload("res://dungeon/game/encounters/encounter_run_manager.gd")
const Layer1EncounterRegistry = preload("res://dungeon/game/encounters/layer_1_encounter_registry.gd")
const Layer2EncounterRegistry = preload("res://dungeon/game/encounters/layer_2_encounter_registry.gd")
const Layer3EncounterRegistry = preload("res://dungeon/game/encounters/layer_3_encounter_registry.gd")
const PLAYER_SCENE := preload("res://scenes/entities/player.tscn")
const LOADOUT_OVERLAY_SCENE := preload("res://scenes/ui/loadout/loadout_overlay.tscn")
const INFUSION_GUIDE_OVERLAY_SCENE := preload("res://scenes/ui/infusion_guide_overlay.tscn")
const ESCAPE_MENU_SCENE := preload("res://scenes/ui/escape_menu.tscn")
const LoadoutRepositoryScript = preload("res://scripts/loadout/loadout_repository.gd")
const _MetaProgressionConstantsRef = preload("res://scripts/meta_progression/meta_progression_constants.gd")
const _LoadoutConstantsRef = preload("res://scripts/loadout/loadout_constants.gd")
const _TemperingManagerScript = preload("res://scripts/meta_progression/tempering_manager.gd")
const ELEVATOR_VISUAL_SCENE := preload("res://art/props/interactables/elevator_texture.glb")
const ENEMY_SCENE_KIND_DASHER := 1
const ENEMY_SCENE_KIND_ARROW_TOWER := 2
const ENEMY_SCENE_KIND_SKEWER := 3
const ENEMY_SCENE_KIND_GLAIVER := 4
const ENEMY_SCENE_KIND_RAZORFORM := 5
const ENEMY_SCENE_KIND_SCRAMBLER := 6
const ENEMY_SCENE_KIND_FLOW_DASHER := 7
const ENEMY_SCENE_KIND_FLOWFORM := 8
const ENEMY_SCENE_KIND_STUMBLER := 9
const ENEMY_SCENE_KIND_SHIELDWALL := 10
const ENEMY_SCENE_KIND_WARDEN := 11
const ENEMY_SCENE_KIND_SPLITTER := 12
const ENEMY_SCENE_KIND_ECHOFORM := 13
const ENEMY_SCENE_KIND_TRIAD := 14
const ENEMY_SCENE_KIND_LURKER := 15
const ENEMY_SCENE_KIND_LEECHER := 16
const ENEMY_SCENE_KIND_BINDER := 17
const ENEMY_SCENE_KIND_FIZZLER := 18
const ENEMY_SCENE_KIND_BURSTER := 19
const ENEMY_SCENE_KIND_DETONATOR := 20
const ENEMY_SCENE_KIND_ECHO_SPLINTER := 21
const ENEMY_SCENE_KIND_ECHO_UNIT := 22
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
const _MINI_HUB_EXIT_ELEVATOR_INSET := 7.5
const _ROOM_SIZE_SCALE := 1.5
const _BACK_HALF_MIN_RATIO := 0.22
const _AUTHORED_VISUAL_STREAM_MARGIN := 18.0
const _AUTHORED_VISUAL_STREAM_UNLOAD_MARGIN := 36.0
const _AUTHORED_VISUAL_STREAM_BUCKET_SIZE := 96.0
const _AUTHORED_VISUAL_MAX_BUILDS_PER_TICK := 2
const _ENEMY_PREWARM_POSITION := Vector2(1000000.0, 1000000.0)
const _ELEVATOR_PLAYER_SIZE_MULT := 4.0
const _ELEVATOR_VISUAL_CLEARANCE_Y := 0.12
const _DEBUG_ELEVATOR_YAW_OFFSET_DEG := 180.0
const _SPEED_SCALE_PER_FLOOR := 0.08
## Arena enemy speed caps around floor 9 (1.0 + 8 * 0.08 = 1.64).
const _SPEED_SCALE_MAX_ARENA := 1.65
## Boss enemy speed cap is slightly lower — boss kits are tuned for deliberate pace.
const _SPEED_SCALE_MAX_BOSS := 1.55
## Arrow towers are biased toward room center; keep planned spawns apart so two never share one spot.
const _TOWER_SPAWN_MIN_SEP := 4.5
const _MULTIPLAYER_DEBUG_LOGGING := false

func _floor_ground_theme_data() -> Dictionary:
	var i := (_floor_index - 1) % 4
	match i:
		0:
			return {
				"glb_scene": GROUND_GLB_METAL,
				"room_theme": &"tile",
			}
		1:
			return {
				"glb_scene": GROUND_GLB_GRASS,
				"room_theme": &"dirt",
			}
		2:
			return {
				"glb_scene": GROUND_GLB_DIRT,
				"room_theme": &"dirt",
			}
		_:
			return {
				"glb_scene": GROUND_GLB_STONE,
				"room_theme": &"tile",
			}


func _loading_overlay_call(method_name: StringName) -> void:
	var n := get_node_or_null("/root/LoadingOverlay")
	if n != null and n.has_method(method_name):
		n.call(method_name)

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
var _encounter_template_by_encounter: Dictionary = {}
var _encounter_spawn_plan_by_encounter: Dictionary = {}
var _planned_tower_positions_by_encounter: Dictionary = {}
var _entry_socket_by_encounter: Dictionary = {}
var _entry_socket_dir_by_encounter: Dictionary = {}
var _door_visual_by_socket_key: Dictionary = {}
## Neighboring rooms both emit the same boundary segment; keep one collider + one visual.
var _boundary_wall_keys: Dictionary = {}
## Merged mesh AABB in GLB root space (cached per path) for floor tile scaling.
var _floor_glb_aabb_by_path: Dictionary = {}
## First usable floor material extracted from the source GLB, cached per path for top-only runtime tiles.
var _runtime_floor_material_by_path: Dictionary = {}
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
var _encounter_spawn_controller
var _connection_room_gate_controller
var _dungeon_world_environment: WorldEnvironment
var _dungeon_environment: Environment
var _backdrop_quad: MeshInstance3D
var _boss_exit_elevator_visual: Node3D
var _debug_spawn_exit_elevator_visual: Node3D
var _player: CharacterBody2D
var _players_by_peer: Dictionary = {}
var _peer_slots: Dictionary = {}
var _loadout_repository: Node
var _tempering_manager: RefCounted  # TemperingManager, run-scoped
var _loadout_overlay: Control
var _infusion_guide_overlay: Control
var _escape_menu: Control
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
var _mini_hub_active := false
var _mini_hub_interactions_active := false
var _mini_hub_arrival_retry_count := 0
var _pending_enemy_spawn_requests: Array[Dictionary] = []
var _authored_room_catalog
var _authored_floor_generator
var _room_editor_scene_sync
var _room_preview_builder
var _authored_room_visual_nodes: Dictionary = {}
var _authored_room_stream_buckets: Dictionary = {}
var _authored_room_stream_rooms_by_name: Dictionary = {}
var _encounter_run_manager: RefCounted
var _enemy_assets_prewarmed := false
## Cached score-UI node refs — populated once in _ready, avoids per-call get_nodes_in_group.
var _score_ui_nodes: Array[Node] = []
## Accumulates per-enemy transform updates in a physics tick; flushed as one RPC.
var _pending_transform_updates: Array = []
## True when coin totals changed since the last authoritative-maintenance flush.
var _coin_totals_dirty := false
## Accumulated LevelBackdropQuad position in Camera3D local XY (Z from BACKDROP_QUAD_DISTANCE).
var _backdrop_offset_cam := Vector3.ZERO
var _prev_backdrop_camera_ref := Vector3.ZERO
@export_enum("legacy_grid", "authored_rooms") var floor_generation_mode := "authored_rooms"
## When true, each floor uses exactly 3 rooms (authored generator + legacy layout). Default false keeps 7–9 / 8–10.
@export var floor_generation_compact_three_rooms := false
@export var show_combat_debug_overlay := false
@export var show_fps_counter := true
@export var combat_debug_update_interval := 0.25
@export var fps_counter_update_interval := 0.25
@export var authored_room_visual_streaming_enabled := true
@export var authored_room_visual_stream_update_interval := 0.2
@export var authoritative_maintenance_update_interval := 0.1
@export var info_label_update_interval := 0.12
@export var prespawn_encounter_mobs := false
@export var encounter_spawn_queue_interval := 0.05
@export var prewarm_enemy_assets := true
var _combat_debug_label: Label
var _combat_debug_last_text := ""
var _combat_debug_refresh_time_remaining := 0.0
var _fps_counter_label: Label
var _fps_counter_last_text := ""
var _fps_counter_refresh_time_remaining := 0.0
var _authored_room_visual_stream_time_remaining := 0.0
var _authored_room_visual_build_queue: Array[RoomBase] = []
var _authoritative_maintenance_time_remaining := 0.0
var _info_label_refresh_time_remaining := 0.0
var _info_label_last_room_name := ""
var _encounter_spawn_queue_time_remaining := 0.0

func _ready() -> void:
	_rng.randomize()
	_camera_pivot.rotation_degrees = Vector3(CAMERA_DIAG_PITCH_DEG, CAMERA_DIAG_YAW_DEG, 0.0)
	_score_ui_nodes = get_tree().get_nodes_in_group(&"score_ui")
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
	_connection_room_gate_controller = ConnectionRoomGateControllerScript.new()
	_connection_room_gate_controller.name = &"ConnectionRoomGateController"
	_connection_room_gate_controller.room_queries = _room_queries
	_connection_room_gate_controller.door_lock_controller = _door_lock_controller
	_connection_room_gate_controller.required_peer_ids_fn = Callable(self, "_required_floor_transition_peer_ids")
	_connection_room_gate_controller.player_for_peer_id_fn = Callable(self, "_player_for_peer_id")
	_connection_room_gate_controller.encounter_cleared_fn = Callable(self, "_encounter_is_cleared")
	_connection_room_gate_controller.gate_status_changed.connect(_on_connection_room_gate_status_changed)
	add_child(_connection_room_gate_controller)
	_encounter_spawn_controller = EncounterSpawnControllerScript.new()
	_encounter_spawn_controller.name = &"EncounterSpawnController"
	_encounter_spawn_controller.room_queries = _room_queries
	_encounter_spawn_controller.door_lock_controller = _door_lock_controller
	_encounter_spawn_controller.encounter_modules_root = _encounter_modules_root
	_encounter_spawn_controller.world_2d = $GameWorld2D
	_encounter_spawn_controller.rng = _rng
	_encounter_spawn_controller.is_authoritative_fn = Callable(self, "_is_authoritative_world")
	_encounter_spawn_controller.is_server_peer_fn = Callable(self, "_is_server_peer")
	_encounter_spawn_controller.can_broadcast_replication_fn = Callable(self, "_can_broadcast_world_replication")
	_encounter_spawn_controller.get_player_position_fn = Callable(self, "_reference_player_position")
	_encounter_spawn_controller.prespawn_mobs = prespawn_encounter_mobs
	_encounter_spawn_controller.spawn_queue_interval = encounter_spawn_queue_interval
	_encounter_spawn_controller.encounter_started.connect(_on_controller_encounter_started)
	_encounter_spawn_controller.encounter_cleared.connect(_on_controller_encounter_cleared)
	_encounter_spawn_controller.enemy_coin_drop_requested.connect(_on_enemy_coin_drop_requested)
	_encounter_spawn_controller.boss_setup_requested.connect(_setup_boss_infusion_pillars)
	add_child(_encounter_spawn_controller)
	_ensure_combat_debug_overlay()
	_ensure_fps_counter()
	_ensure_loadout_overlay()
	_ensure_infusion_guide_overlay()
	_ensure_escape_menu()
	_regenerate_level(true)
	_bind_local_player_runtime_hooks()
	if _is_authoritative_world():
		await get_tree().process_frame
		await get_tree().process_frame
		_loading_overlay_call(&"hide_loading")


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


func _on_controller_encounter_started(encounter_id: StringName, is_main_combat: bool) -> void:
	if String(encounter_id) == "boss":
		_boss_started = true
		_set_boss_entry_locked(true)
		_set_info_base_text("Boss encounter started. Defeat all enemies.")
		return
	if is_main_combat:
		_combat_started = true
		_set_combat_doors_locked(true)
		_set_info_base_text("Combat started. Clear all enemies to unlock.")
	else:
		_set_info_base_text("Arena encounter started.")


func _on_controller_encounter_cleared(
	encounter_id: StringName, is_boss: bool, is_main_combat: bool
) -> void:
	if is_boss:
		_boss_cleared = true
		_set_boss_entry_locked(false)
		_set_boss_exit_active(true)
		_set_info_base_text("Boss defeated. Elevator is active. All players must board.")
		_grant_tempering_xp_to_all_players(_MetaProgressionConstantsRef.TEMPERING_XP_PER_BOSS_KILL)
	elif is_main_combat:
		_combat_cleared = true
		_set_combat_doors_locked(false)
		_set_info_base_text("Combat room cleared. Doors unlocked.")
	else:
		_set_info_base_text("Arena room cleared.")
	_magnet_dropped_coins_for_encounter_room(encounter_id)
	if _connection_room_gate_controller != null:
		_connection_room_gate_controller.refresh()


func _on_connection_room_gate_status_changed(text: String) -> void:
	if text.is_empty():
		return
	_set_info_base_text(text)


func _next_coin_network_id() -> int:
	_coin_network_id_sequence += 1
	return _coin_network_id_sequence


func _normalize_coin_totals(raw_totals: Dictionary) -> Dictionary:
	var out := {}
	for key in raw_totals.keys():
		out[int(key)] = maxi(0, int(raw_totals[key]))
	return out


func _overlay_sorted_player_peer_ids() -> Array[int]:
	if not _peer_slots.is_empty():
		return _peer_ids_sorted_by_slot(_peer_slots)
	var peer_ids: Array[int] = []
	for key in _players_by_peer.keys():
		peer_ids.append(int(key))
	peer_ids.sort()
	return peer_ids


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
	for n in _score_ui_nodes:
		if not is_instance_valid(n):
			continue
		if n.has_method(&"set_score"):
			n.call(&"set_score", local_total)
		elif n.has_method(&"reset_score"):
			n.call(&"reset_score")
			if n.has_method(&"add_score") and local_total > 0:
				n.call(&"add_score", local_total)


## Marks coin totals as dirty; the actual RPC is batched through _tick_authoritative_maintenance
## so rapid consecutive pickups collapse into one network packet.
func _broadcast_coin_totals_if_server() -> void:
	if not _networked_run or not _is_server_peer() or not _has_multiplayer_peer():
		return
	_coin_totals_dirty = true


func _flush_coin_totals_if_dirty() -> void:
	if not _coin_totals_dirty:
		return
	_coin_totals_dirty = false
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
	if (
		_network_session != null
		and _network_session.has_method("mark_runtime_scene_ready_local")
		and not _is_authoritative_world()
	):
		_network_session.call("mark_runtime_scene_ready_local")


func _ensure_meta_progression_loaded(owner_id: StringName) -> void:
	var meta_store := get_node_or_null("/root/MetaProgressionStore")
	if meta_store == null:
		return
	if not bool(meta_store.call(&"is_initialized", owner_id)):
		meta_store.call(&"load_local", owner_id)


## Seeds the TemperingManager with the equipped gear instance IDs for this player.
func _register_equipped_gear_for_tempering(owner_id: StringName) -> void:
	if _tempering_manager == null:
		return
	var meta_store := get_node_or_null("/root/MetaProgressionStore")
	if meta_store == null:
		return
	for slot_id in _LoadoutConstantsRef.SLOT_ORDER:
		var gear_v: Variant = meta_store.call(&"get_equipped_gear", owner_id, slot_id)
		if gear_v == null:
			continue
		var iid_v: Variant = (gear_v as Object).get(&"instance_id") if gear_v is Object else null
		if iid_v == null:
			continue
		var iid := StringName(String(iid_v))
		if iid != &"":
			_tempering_manager.call(&"add_xp", iid, 0.0)


## Grants tempering XP to all tracked gear across all players.
func _grant_tempering_xp_to_all_players(amount: float) -> void:
	if _tempering_manager == null:
		return
	_tempering_manager.call(&"add_xp_to_all", amount)
	# Re-apply loadout stats so tempering bonuses take effect immediately.
	_reapply_loadout_snapshots_to_all_players()


## Re-pushes the loadout snapshot (with updated tempering) to all connected players.
func _reapply_loadout_snapshots_to_all_players() -> void:
	if _loadout_repository == null:
		return
	for peer_id in _players_by_peer.keys():
		var node: Variant = _players_by_peer[peer_id]
		if node is CharacterBody2D and is_instance_valid(node):
			var player := node as CharacterBody2D
			var owner_id := _loadout_owner_id_for_peer(int(peer_id))
			var snapshot_v: Variant = _loadout_repository.call(&"get_snapshot", owner_id)
			if snapshot_v is Dictionary:
				_apply_loadout_snapshot_to_player_and_replicate(player, snapshot_v as Dictionary)


## Called at run end. Grants promotion progress + familiarity XP, resets tempering, saves.
func _finalize_run_meta_progression() -> void:
	if not _is_authoritative_world():
		return
	var meta_store := get_node_or_null("/root/MetaProgressionStore")
	if meta_store == null:
		return
	var reached_tempered_ii := _tempering_manager != null and bool(_tempering_manager.call(&"any_reached_tempered_ii"))
	for peer_id in _players_by_peer.keys():
		var owner_id := _loadout_owner_id_for_peer(int(peer_id))
		if not bool(meta_store.call(&"is_initialized", owner_id)):
			continue
		# Familiarity XP: scales with floors cleared.
		var fam_xp := float(_floor_index) * 15.0
		meta_store.call(&"add_familiarity_xp_to_equipped", owner_id, fam_xp)
		# Promotion progress: based on run achievements.
		var promo := 0.0
		if reached_tempered_ii:
			promo += _MetaProgressionConstantsRef.PROMOTION_PROGRESS_TEMPERED_II
		if _boss_cleared:
			promo += _MetaProgressionConstantsRef.PROMOTION_PROGRESS_BOSS_CLEAR
		if _floor_index >= 3:
			promo += _MetaProgressionConstantsRef.PROMOTION_PROGRESS_DEEP_FLOOR
		if promo > 0.0:
			meta_store.call(&"grant_promotion_progress_to_equipped", owner_id, promo)
		# Save.
		meta_store.call(&"save_local", owner_id)
	# Reset tempering (run-scoped).
	if _tempering_manager != null:
		_tempering_manager.call(&"reset")


func _ensure_loadout_repository() -> void:
	if _loadout_repository != null and is_instance_valid(_loadout_repository):
		return
	_loadout_repository = LoadoutRepositoryScript.new()
	_loadout_repository.name = "LoadoutRepository"
	add_child(_loadout_repository)
	_ensure_tempering_manager()


func _ensure_tempering_manager() -> void:
	if _tempering_manager != null:
		return
	_tempering_manager = _TemperingManagerScript.new()
	if _loadout_repository != null and _loadout_repository.has_method(&"set_tempering_manager"):
		_loadout_repository.call(&"set_tempering_manager", _tempering_manager)


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
		_loadout_overlay.call(&"bind_player", _player, Callable(self, "_loadout_room_type_at"))


func _ensure_infusion_guide_overlay() -> void:
	var ui_root := get_node_or_null("CanvasLayer/UI") as Control
	if ui_root == null:
		return
	if _infusion_guide_overlay != null and is_instance_valid(_infusion_guide_overlay):
		return
	var existing := ui_root.get_node_or_null("InfusionGuideOverlay") as Control
	if existing != null:
		_infusion_guide_overlay = existing
	else:
		var overlay := INFUSION_GUIDE_OVERLAY_SCENE.instantiate() as Control
		if overlay == null:
			return
		overlay.name = "InfusionGuideOverlay"
		ui_root.add_child(overlay)
		_infusion_guide_overlay = overlay
	if _infusion_guide_overlay != null and _infusion_guide_overlay.has_method(&"bind_player"):
		_infusion_guide_overlay.call(&"bind_player", _player)


func _ensure_escape_menu() -> void:
	var ui_root := get_node_or_null("CanvasLayer/UI") as Control
	if ui_root == null:
		return
	if _escape_menu != null and is_instance_valid(_escape_menu):
		_refresh_escape_menu_return_to_hub_availability()
		return
	var existing := ui_root.get_node_or_null("EscapeMenu") as Control
	if existing != null:
		_escape_menu = existing
	else:
		var overlay := ESCAPE_MENU_SCENE.instantiate() as Control
		if overlay == null:
			return
		overlay.name = "EscapeMenu"
		ui_root.add_child(overlay)
		_escape_menu = overlay
	if (
		_escape_menu.has_signal(&"visibility_changed_for_input_block")
		and not _escape_menu.is_connected(&"visibility_changed_for_input_block", _on_escape_menu_visibility_changed)
	):
		_escape_menu.connect(&"visibility_changed_for_input_block", _on_escape_menu_visibility_changed)
	if (
		_escape_menu.has_signal(&"back_to_main_screen_requested")
		and not _escape_menu.is_connected(&"back_to_main_screen_requested", _on_escape_menu_back_to_main_requested)
	):
		_escape_menu.connect(&"back_to_main_screen_requested", _on_escape_menu_back_to_main_requested)
	if (
		_escape_menu.has_signal(&"return_to_hub_requested")
		and not _escape_menu.is_connected(&"return_to_hub_requested", _on_escape_menu_return_to_hub_requested)
	):
		_escape_menu.connect(&"return_to_hub_requested", _on_escape_menu_return_to_hub_requested)
	_refresh_escape_menu_return_to_hub_availability()
	_sync_escape_menu_input_block()


func _sync_escape_menu_input_block() -> void:
	if _escape_menu == null or not is_instance_valid(_escape_menu):
		return
	if _escape_menu.has_method(&"is_menu_open"):
		_on_escape_menu_visibility_changed(bool(_escape_menu.call(&"is_menu_open")))


func _refresh_escape_menu_return_to_hub_availability() -> void:
	if _escape_menu != null and is_instance_valid(_escape_menu) and _escape_menu.has_method(&"set_return_to_hub_available"):
		_escape_menu.call(&"set_return_to_hub_available", _is_multiplayer_run_return_to_hub_available())


func _on_escape_menu_visibility_changed(open: bool) -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method(&"set_menu_input_blocked"):
		_player.call(&"set_menu_input_blocked", open or _should_defer_escape_menu_to_existing_overlay())


func _on_escape_menu_back_to_main_requested() -> void:
	var session := get_node_or_null("/root/NetworkSession")
	if session != null and session.has_method("has_active_peer") and bool(session.call("has_active_peer")):
		if session.has_method("disconnect_from_session"):
			session.call("disconnect_from_session", true)
		return
	if session != null and session.has_method("disconnect_from_session"):
		session.call("disconnect_from_session", false)
	var err := get_tree().change_scene_to_file("res://scenes/ui/lobby_menu.tscn")
	if err != OK:
		push_warning("Failed to return to main screen (error %s)." % [err])


func _on_escape_menu_return_to_hub_requested() -> void:
	var session := get_node_or_null("/root/NetworkSession")
	if session == null or not session.has_method("request_leave_run_from_local_peer"):
		return
	session.call("request_leave_run_from_local_peer")


func _is_multiplayer_run_return_to_hub_available() -> bool:
	var session := get_node_or_null("/root/NetworkSession")
	return (
		session != null
		and session.has_method("has_active_peer")
		and bool(session.call("has_active_peer"))
	)


func _should_defer_escape_menu_to_existing_overlay() -> bool:
	if (
		_loadout_overlay != null
		and is_instance_valid(_loadout_overlay)
		and _loadout_overlay.has_method(&"is_loadout_panel_open")
		and bool(_loadout_overlay.call(&"is_loadout_panel_open"))
	):
		return true
	if (
		_infusion_guide_overlay != null
		and is_instance_valid(_infusion_guide_overlay)
		and _infusion_guide_overlay.has_method(&"is_infusion_guide_open")
		and bool(_infusion_guide_overlay.call(&"is_infusion_guide_open"))
	):
		return true
	return false


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
	if _is_authoritative_world():
		_ensure_meta_progression_loaded(owner_id)
	if _is_authoritative_world() and _loadout_repository != null:
		if _loadout_repository.has_method(&"ensure_owner_initialized"):
			_loadout_repository.call(&"ensure_owner_initialized", owner_id)
		# Re-sync from MetaProgressionStore in case it loaded after the first init.
		if _loadout_repository.has_method(&"refresh_owner_from_meta_store"):
			_loadout_repository.call(&"refresh_owner_from_meta_store", owner_id)
	if player.has_method(&"bind_loadout_runtime"):
		player.call(&"bind_loadout_runtime", self, Callable(self, "_loadout_room_type_at"), owner_id)
	if (
		_is_authoritative_world()
		and _loadout_repository != null
		and _loadout_repository.has_method(&"get_snapshot")
		and player.has_method(&"apply_authoritative_loadout_snapshot")
	):
		var snapshot_v: Variant = _loadout_repository.call(&"get_snapshot", owner_id)
		if snapshot_v is Dictionary:
			player.call(&"apply_authoritative_loadout_snapshot", snapshot_v as Dictionary)
	_register_equipped_gear_for_tempering(owner_id)


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
		"is_safe_room": _loadout_room_type_at(player.global_position, 1.25) == "safe",
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


# Stubs: real implementations on dungeon_orchestrator.gd (per-frame / debug UI).
func _ensure_combat_debug_overlay() -> void:
	pass


func _ensure_fps_counter() -> void:
	pass


func _refresh_combat_debug_overlay(_delta: float = 0.0, _force: bool = false) -> void:
	pass


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
		_loadout_overlay.call(&"bind_player", _player, Callable(self, "_loadout_room_type_at"))
	if _infusion_guide_overlay != null and _infusion_guide_overlay.has_method(&"bind_player"):
		_infusion_guide_overlay.call(&"bind_player", _player)
	_sync_escape_menu_input_block()
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


func _regenerate_level(randomize_layout: bool) -> void:
	_has_generated_floor = false
	_floor_transition_pending = false
	_mini_hub_interactions_active = false
	_combat_started = false
	_combat_cleared = false
	_boss_started = false
	_boss_cleared = false
	_party_wipe_pending = false
	_puzzle_solved = false
	_puzzle_gate_socket = Vector2.ZERO
	_info_label_refresh_time_remaining = 0.0
	_authoritative_maintenance_time_remaining = 0.0
	_info_label_last_room_name = ""
	if _encounter_spawn_controller != null:
		_encounter_spawn_controller.clear_runtime_state()
	if _connection_room_gate_controller != null:
		_connection_room_gate_controller.clear_runtime_state()
	_clear_floor_loot()
	for n in get_tree().get_nodes_in_group(&"mob"):
		if n is Node:
			(n as Node).queue_free()
	var assembled_ok := false
	if _mini_hub_active:
		if _networked_run and not _is_authoritative_world():
			if _map_layout.is_empty():
				_request_layout_snapshot_from_server()
				return
			_awaiting_layout_snapshot = false
		else:
			_map_layout = _generate_mini_hub_layout()
		_mini_hub_active = String(_map_layout.get(LAYOUT_KEY_PHASE, "")) == LAYOUT_PHASE_MINI_HUB
		_destroy_dynamic_rooms()
		_spawn_rooms_from_layout(_map_layout)
		assembled_ok = true
	elif _is_authored_floor_mode():
		if _networked_run and not _is_authoritative_world():
			if _map_layout.is_empty():
				_request_layout_snapshot_from_server()
				return
			_awaiting_layout_snapshot = false
			_destroy_dynamic_rooms()
			assembled_ok = _spawn_authored_rooms_from_layout(_map_layout)
		else:
			_map_layout = {}
			var max_tries := 4 if randomize_layout else 1
			for _attempt in range(max_tries):
				var generated := _generate_authored_floor_layout()
				if not bool(generated.get("ok", false)):
					var failures := generated.get("failure_buckets", {}) as Dictionary
					_last_assembly_errors = PackedStringArray([JSON.stringify(failures)])
					continue
				_map_layout = generated
				_destroy_dynamic_rooms()
				assembled_ok = _spawn_authored_rooms_from_layout(_map_layout)
				if assembled_ok:
					break
	else:
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
				var generated_legacy := DungeonMapLayoutV1.generate(_rng, _floor_generation_legacy_layout_config())
				if not bool(generated_legacy.get("ok", false)):
					continue
				var level_data := LevelDataV1.from_layout(
					generated_legacy,
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
				_map_layout = generated_legacy
				_map_layout["level_data"] = level_data
				_destroy_dynamic_rooms()
				_spawn_rooms_from_layout(_map_layout)
				var links_server: Array = _map_layout.get("links", []) as Array
				_apply_adjacency_sockets(DungeonMapLayoutV1.adjacency_from_links(links_server))
				assembled_ok = _assemble_rooms_procedurally(_map_layout)
				if assembled_ok:
					break
	if not assembled_ok:
		var label := "Authored room floor build" if _is_authored_floor_mode() else "Grid dungeon assembly"
		var details := ""
		if not _last_assembly_errors.is_empty():
			details = " Details: %s" % _last_assembly_errors[0]
		push_warning(
			"%s failed (%s validation issues); skipping floor build.%s" % [
				label,
				_last_assembly_errors.size(),
				details,
			]
		)
		return
	_cache_runtime_door_positions()
	_position_runtime_markers()
	_build_world_bounds()
	_build_room_debug_visuals()
	_spawn_gameplay_objects()
	_setup_encounter_spawn_controller_for_floor()
	_encounter_spawn_controller.setup_encounters()
	if _connection_room_gate_controller != null:
		if _is_authoritative_world():
			_connection_room_gate_controller.setup_gates(_map_layout)
		else:
			_connection_room_gate_controller.clear_runtime_state()
	_prewarm_enemy_assets_once()
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
	_position_players_at_floor_start()
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
		if not _mini_hub_active and not _map_layout.is_empty():
			_map_layout[LAYOUT_KEY_PHASE] = LAYOUT_PHASE_FLOOR
		_ensure_layout_backdrop_path_server()
	_log_generation_debug(_map_layout)
	var room_count := (_map_layout.get("room_specs", []) as Array).size()
	if _mini_hub_active:
		_set_info_base_text("Intermission after floor %s. Adjust loadout, then board the elevator together." % [_floor_index])
	elif _is_authored_floor_mode():
		_set_info_base_text("Floor %s — authored critical path (%s rooms)." % [_floor_index, room_count])
	else:
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
		if _mini_hub_active:
			call_deferred("_enable_mini_hub_elevator_after_arrival_sync")


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
		_place_player_at_spawn(player, entrance_spawn + offset)


func _position_players_at_floor_start() -> void:
	if _mini_hub_active:
		_position_players_at_mini_hub_start()
		return
	if not _is_authored_floor_mode():
		var entrance_spawn := _room_center_2d(_layout_room_name("start_room"))
		_position_players_at_spawn(entrance_spawn)
		return
	var start_room_name := _layout_room_name("start_room")
	var spawn_positions := _authored_spawn_positions(start_room_name)
	if spawn_positions.is_empty():
		spawn_positions.append(_room_center_2d(start_room_name))
	var peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	if peer_ids.is_empty():
		peer_ids.append(_local_peer_id())
	var fallback_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(4.0, 0.0),
		Vector2(-4.0, 0.0),
		Vector2(0.0, 4.0),
		Vector2(0.0, -4.0),
		Vector2(6.0, 3.0),
		Vector2(-6.0, 3.0),
	]
	var anchor := spawn_positions[0]
	for i in range(peer_ids.size()):
		var peer_id := peer_ids[i]
		var node: Variant = _players_by_peer.get(peer_id, null)
		if node is not CharacterBody2D:
			continue
		var player := node as CharacterBody2D
		var target := spawn_positions[i] if i < spawn_positions.size() else (
			anchor + (
				fallback_offsets[i]
				if i < fallback_offsets.size()
				else Vector2(float(i) * 2.0, 0.0)
			)
		)
		_place_player_at_spawn(player, target)


func _position_players_at_mini_hub_start() -> void:
	var hub_center := _room_center_2d(_layout_room_name("start_room"))
	var offsets: Array[Vector2] = [
		Vector2(-6.0, -4.0),
		Vector2(6.0, -4.0),
		Vector2(-6.0, 4.0),
		Vector2(6.0, 4.0),
		Vector2(0.0, -8.0),
	]
	var peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	if peer_ids.is_empty():
		peer_ids.append(_local_peer_id())
	for i in range(peer_ids.size()):
		var peer_id := peer_ids[i]
		var node: Variant = _players_by_peer.get(peer_id, null)
		if node is not CharacterBody2D:
			continue
		var player := node as CharacterBody2D
		var offset: Vector2 = offsets[i] if i < offsets.size() else Vector2(float(i) * 2.0, 0.0)
		_place_player_at_spawn(player, hub_center + offset)


func _authored_spawn_positions(start_room_name: StringName) -> Array[Vector2]:
	if _room_queries == null:
		return []
	return _room_queries.zone_marker_world_positions(start_room_name, "spawn_player", &"floor_start")


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
		_place_player_at_spawn(player, anchor + offset)
		offset_idx += 1


func _place_player_at_spawn(player: CharacterBody2D, spawn_position: Vector2) -> void:
	if player == null:
		return
	if player.has_method(&"set_spawn_position_immediate"):
		player.call(&"set_spawn_position_immediate", spawn_position, true)
		return
	player.global_position = spawn_position
	player.velocity = Vector2.ZERO
	player.set_meta(&"spawn_initialized", true)


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
	if OS.is_debug_build() and _MULTIPLAYER_DEBUG_LOGGING:
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
	_authored_room_stream_buckets.clear()
	_authored_room_stream_rooms_by_name.clear()
	if _room_queries != null:
		_room_queries.invalidate_cache()


func _spawn_rooms_from_layout(layout: Dictionary) -> void:
	if String(layout.get("generator_mode", "")) == "authored_rooms":
		_spawn_authored_rooms_from_layout(layout)
		return
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
		room.room_type = String(d.get("room_type", DungeonMapLayoutV1.kind_to_room_type(kind)))
		room.room_tags = _runtime_room_tags(room, d)
		room.safe_room = room.room_type == "safe"
		room.standard_room_sizes = PackedInt32Array([3, 5, 9, 12, 15, 18, 24])
		if kind == "mini_hub":
			_prepare_mini_hub_room(room)
		if kind == "exit":
			room.min_difficulty_tier = 4
			room.max_difficulty_tier = 8
		_rooms_root.add_child(room)
	if _room_queries != null:
		_room_queries.invalidate_cache()


func _prepare_mini_hub_room(room: RoomBase) -> void:
	if room == null:
		return
	room.room_id = "mini_hub"
	room.safe_room = true
	room.room_tags = PackedStringArray(["safe", "mini_hub"])
	room.allowed_connection_types = PackedStringArray([])
	var zones := room.get_node_or_null("Zones")
	if zones != null:
		_free_children_immediate(zones)
	var sockets := room.get_node_or_null("Sockets")
	if sockets != null:
		_free_children_immediate(sockets)


func _spawn_authored_rooms_from_layout(layout: Dictionary) -> bool:
	_ensure_authored_floor_generator()
	var specs: Array = layout.get("room_specs", []) as Array
	var floor_theme_data: Dictionary = _floor_ground_theme_data()
	var floor_room_theme: StringName = floor_theme_data.get("room_theme", &"dirt") as StringName
	var spawned_count := 0
	for spec_value in specs:
		if spec_value is not Dictionary:
			continue
		var spec := spec_value as Dictionary
		var scene_path := String(spec.get("scene_path", "")).strip_edges()
		if scene_path.is_empty():
			push_warning("Authored room spec missing scene_path.")
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("Could not load authored room scene: %s" % scene_path)
			continue
		var room := packed.instantiate() as RoomBase
		if room == null:
			push_warning("Authored room scene is not a RoomBase: %s" % scene_path)
			continue
		var room_name := String(spec.get("name", _scene_base_name(scene_path)))
		room.name = room_name
		room.room_id = String(spec.get("room_id", room.room_id))
		room.room_type = String(spec.get("room_type", room.room_type))
		room.room_tags = _runtime_room_tags(room, spec)
		room.position = spec.get("world_position", Vector2.ZERO) as Vector2
		room.rotation_degrees = float(int(spec.get("rotation_deg", 0)))
		room.set_meta(&"runtime_floor_theme", floor_room_theme)
		room.set_meta(&"runtime_floor_seed", _rng.randi())
		_rooms_root.add_child(room)
		if room.authored_layout != null and _room_editor_scene_sync != null:
			_room_editor_scene_sync.sync_room(room, room.authored_layout, ROOM_PIECE_CATALOG)
			var visual_proxy := room.get_node_or_null(^"Visual3DProxy") as Node3D
			if visual_proxy != null:
				visual_proxy.visible = false
		room.set_meta(&"authored_room_role", String(spec.get("role", "")))
		room.set_meta(&"authored_room_scene_path", scene_path)
		room.set_meta(&"authored_room_rotation_deg", int(spec.get("rotation_deg", 0)))
		room.set_meta(&"authored_room_center_cell", spec.get("grid", Vector2i.ZERO))
		room.set_meta(&"authored_room_tile_size", spec.get("tile_size", room.tile_size))
		room.set_meta(&"authored_room_occupied_cells_world", spec.get("occupied_cells", []))
		room.set_meta(&"authored_room_blocked_cells_world", spec.get("blocked_cells", []))
		room.set_meta(&"authored_room_walkable_cells_world", spec.get("walkable_cells", []))
		room.set_meta(&"authored_connection_markers_world", spec.get("connection_markers", []))
		room.set_meta(&"authored_zone_markers_world", spec.get("zone_markers", []))
		spawned_count += 1
	if _room_queries != null:
		_room_queries.invalidate_cache()
	_rebuild_authored_room_stream_buckets()
	return spawned_count == specs.size() and spawned_count > 0


func _runtime_room_tags(room: RoomBase, spec: Dictionary) -> PackedStringArray:
	var tags := PackedStringArray()
	_append_unique_tag(tags, String(room.room_type))
	_append_unique_tag(tags, String(spec.get("role", "")))
	var spec_tags_v: Variant = spec.get("room_tags", PackedStringArray())
	var role := String(spec.get("role", ""))
	if spec_tags_v is PackedStringArray:
		var packed_tags := spec_tags_v as PackedStringArray
		for tag in packed_tags:
			_append_unique_tag(tags, tag)
	elif spec_tags_v is Array:
		var array_tags := spec_tags_v as Array
		for tag_value in array_tags:
			var tag_text := String(tag_value)
			_append_unique_tag(tags, tag_text)
	_append_unique_tag(tags, String(room.size_class))
	_append_unique_tag(tags, _room_size_tag(room))
	if room.room_type == "corridor" or String(spec.get("role", "")) == "chokepoint":
		_append_unique_tag(tags, "corridor")
	if room.room_type == "arena":
		_append_unique_tag(tags, "open")
	return tags


func _room_size_tag(room: RoomBase) -> String:
	if room == null:
		return "medium"
	var tile_count := room.room_size_tiles.x * room.room_size_tiles.y
	if tile_count <= 16 * 16:
		return "small"
	if tile_count >= 30 * 30:
		return "large"
	return "medium"


func _append_unique_tag(tags: PackedStringArray, tag: String) -> void:
	var cleaned := tag.strip_edges().to_lower()
	if cleaned.is_empty():
		return
	if not tags.has(cleaned):
		tags.append(cleaned)


func _packed_tags_text(tags: PackedStringArray) -> String:
	var parts: Array[String] = []
	for tag in tags:
		parts.append(tag)
	return ",".join(parts)


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


func _clear_floor_loot() -> void:
	# Coins can live under PieceInstances (chests) or GameWorld2D root (mob death drops).
	_coin_nodes_by_network_id.clear()
	var gw := get_node_or_null("GameWorld2D") as Node
	if gw != null:
		for n in gw.find_children("*", "DroppedCoin", true, false):
			if is_instance_valid(n):
				(n as Node).queue_free()
	# Safety net for any orphaned visual meshes from old floor coins.
	for n in _visual_world.find_children("DroppedCoinMesh", "MeshInstance3D", true, false):
		if is_instance_valid(n):
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


func _scene_base_name(scene_path: String) -> String:
	return scene_path.get_file().get_basename()


func _is_authored_floor_mode() -> bool:
	return floor_generation_mode == "authored_rooms" and not _mini_hub_active


func _ensure_authored_floor_generator() -> void:
	if _authored_room_catalog == null:
		_authored_room_catalog = AuthoredRoomCatalogScript.new()
	if _authored_floor_generator == null:
		_authored_floor_generator = AuthoredFloorGeneratorScript.new()
	if _room_editor_scene_sync == null:
		_room_editor_scene_sync = RoomEditorSceneSyncScript.new()
	if _room_preview_builder == null:
		_room_preview_builder = RoomPreviewBuilderScript.new()


func _floor_generation_legacy_layout_config() -> Dictionary:
	if floor_generation_compact_three_rooms:
		return {
			"total_rooms_min": 5,
			"total_rooms_max": 5,
			"critical_path_min": 5,
			"critical_path_max": 5,
			"linear_spine_only": true,
		}
	return {}


func _authored_floor_room_count_bounds() -> Dictionary:
	if floor_generation_compact_three_rooms:
		return {"min_rooms": 5, "max_rooms": 5}
	return {"min_rooms": 7, "max_rooms": 9}


func _generate_authored_floor_layout() -> Dictionary:
	_ensure_authored_floor_generator()
	_authored_room_catalog.build()
	var room_bounds := _authored_floor_room_count_bounds()
	return _authored_floor_generator.generate_floor(
		_authored_room_catalog,
		_rng,
		{
			"min_rooms": room_bounds["min_rooms"],
			"max_rooms": room_bounds["max_rooms"],
			"max_floor_attempts": 20,
		}
	)


func _generate_mini_hub_layout() -> Dictionary:
	var room_name := "mini_hub_%02d" % [_floor_index]
	var room_spec := {
		"name": room_name,
		"room_instance_id": room_name,
		"kind": "mini_hub",
		"role": "mini_hub",
		"room_type": "safe",
		"size": Vector2i(16, 16),
		"grid": Vector2i.ZERO,
		"world_position": Vector2.ZERO,
	}
	var layout := {
		"ok": true,
		"generator_mode": LAYOUT_PHASE_MINI_HUB,
		"room_specs": [room_spec],
		"links": [],
		"start_room": room_name,
		"exit_room": room_name,
		"critical_path": [room_name],
		"combat_room": "",
		"combat_entry_dir": "west",
		"combat_exit_dir": "east",
		"boss_entry_dir": "south",
		"puzzle_room": "",
		"treasure_room": "",
		"trap_room": "",
		"stage_debug": {
			"graph": {"rooms": 1, "links": 0},
			"roles": {"sequence": ["mini_hub"]},
			"spatial": {"start_room": room_name},
		},
	}
	layout[LAYOUT_KEY_PHASE] = LAYOUT_PHASE_MINI_HUB
	return layout


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
	var room_rect := (
		_room_queries.room_bounds_rect(room)
		if _room_queries != null
		else Rect2(room.global_position - room.get_room_rect_world().size * 0.5, room.get_room_rect_world().size)
	)
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


func _connection_marker_world_position(
	room_name: StringName, direction: String, marker_kind: String = ""
) -> Vector2:
	return (
		_room_queries.connection_marker_world_position(room_name, direction, marker_kind)
		if _room_queries != null
		else Vector2.ZERO
	)


func _zone_marker_world_position(room_name: StringName, zone_type: String, zone_role: StringName = &"") -> Vector2:
	return (
		_room_queries.zone_marker_world_position(room_name, zone_type, zone_role)
		if _room_queries != null
		else Vector2.ZERO
	)


func _find_zone_marker_world_position(
	room_name: StringName,
	zone_type: String,
	zone_role: StringName = &""
) -> Dictionary:
	return (
		_room_queries.find_zone_marker_world_position(room_name, zone_type, zone_role)
		if _room_queries != null
		else {"found": false, "position": Vector2.ZERO}
	)


func _zone_markers(
	room_name: StringName,
	zone_type: String,
	zone_role: StringName = &""
) -> Array[Dictionary]:
	return (
		_room_queries.zone_markers(room_name, zone_type, zone_role)
		if _room_queries != null
		else []
	)


func _socket_world_position(room_name: StringName, direction: String) -> Vector2:
	return _connection_marker_world_position(room_name, direction)


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
	_combat_entry_socket = _connection_marker_world_position(cr, _combat_entry_dir, "entrance")
	_combat_exit_socket = _connection_marker_world_position(cr, _combat_exit_dir, "exit")
	_boss_entry_socket = _connection_marker_world_position(er, _boss_entry_dir, "entrance")
	_puzzle_gate_socket = _connection_marker_world_position(pr, _puzzle_gate_dir, "exit")
	_combat_door_x_w = _combat_entry_socket.x
	_combat_door_x_e = _combat_exit_socket.x
	_boss_door_x_w = _boss_entry_socket.x
	_w_ext_x = _combat_door_x_w - 2.5
	_e_ext_x = _combat_door_x_e + 3.5
	_boss_w_ext_x = _boss_door_x_w - 2.5


func _setup_encounter_spawn_controller_for_floor() -> void:
	if _encounter_spawn_controller == null:
		return
	_encounter_spawn_controller.floor_index = _floor_index
	_encounter_spawn_controller.map_layout = _map_layout
	_encounter_spawn_controller.mini_hub_active = _mini_hub_active
	_encounter_spawn_controller.combat_entry_dir = _combat_entry_dir
	_encounter_spawn_controller.combat_exit_dir = _combat_exit_dir
	_encounter_spawn_controller.combat_entry_socket = _combat_entry_socket
	_encounter_spawn_controller.boss_entry_dir = _boss_entry_dir
	_encounter_spawn_controller.boss_entry_socket = _boss_entry_socket
	_encounter_spawn_controller.prespawn_mobs = prespawn_encounter_mobs
	_encounter_spawn_controller.spawn_queue_interval = encounter_spawn_queue_interval


func _position_runtime_markers() -> void:
	if _mini_hub_active:
		var hub_exit_pos := _mini_hub_exit_elevator_world_position()
		_boss_exit_portal.position = hub_exit_pos
		if _boss_portal_marker != null:
			_boss_portal_marker.visible = false
		_ensure_boss_exit_elevator_visual()
		if _boss_exit_elevator_visual != null and is_instance_valid(_boss_exit_elevator_visual):
			_set_elevator_visual_transform(_boss_exit_elevator_visual, hub_exit_pos, hub_exit_pos + Vector2(0.0, -6.0))
			_boss_exit_elevator_visual.visible = false
		_position_debug_spawn_exit_portal()
		return
	var exit_key := _layout_room_name("exit_room")
	var boss_room := _room_by_name(exit_key)
	if boss_room != null:
		_boss_exit_portal.position = _boss_floor_exit_world_position(exit_key, boss_room)
		if _boss_portal_marker != null:
			_boss_portal_marker.visible = false
		_ensure_boss_exit_elevator_visual()
		if _boss_exit_elevator_visual != null and is_instance_valid(_boss_exit_elevator_visual):
			_sync_boss_exit_elevator_visual_transform()
			_boss_exit_elevator_visual.visible = false
	_position_debug_spawn_exit_portal()


func _boss_floor_exit_world_position(exit_key: StringName, boss_room: RoomBase) -> Vector2:
	var authored_floor_exit := _find_zone_marker_world_position(exit_key, "floor_exit")
	if bool(authored_floor_exit.get("found", false)):
		return authored_floor_exit.get("position", Vector2.ZERO)
	if boss_room == null:
		return Vector2.ZERO
	var half := _room_half_extents(boss_room)
	var outward := _direction_vector(_opposite_direction(_boss_entry_dir))
	var inset_x := maxf(0.0, half.x - _BOSS_PORTAL_INSET)
	var inset_y := maxf(0.0, half.y - _BOSS_PORTAL_INSET)
	var offset := Vector2(outward.x * inset_x, outward.y * inset_y)
	return boss_room.global_position + offset


func _mini_hub_exit_elevator_world_position() -> Vector2:
	var room_name := _layout_room_name("exit_room")
	var room := _room_by_name(room_name)
	if room == null:
		return _room_center_2d(room_name)
	var half := _room_half_extents(room)
	var north_offset := maxf(0.0, half.y - _MINI_HUB_EXIT_ELEVATOR_INSET)
	return room.global_position + Vector2(0.0, -north_offset)


func _spawn_exit_world_position(start_room_name: StringName, start_room: RoomBase) -> Vector2:
	var authored_spawn_exit := _find_zone_marker_world_position(start_room_name, "spawn_exit")
	if bool(authored_spawn_exit.get("found", false)):
		return authored_spawn_exit.get("position", Vector2.ZERO)
	if start_room == null:
		return Vector2.ZERO
	var forward := _critical_path_forward_dir_from_start()
	var back := _opposite_direction(forward)
	var half := _room_half_extents(start_room)
	var outward := _direction_vector(back)
	var inset_x := maxf(0.0, half.x - _BOSS_PORTAL_INSET)
	var inset_y := maxf(0.0, half.y - _BOSS_PORTAL_INSET)
	var offset := Vector2(outward.x * inset_x, outward.y * inset_y)
	return start_room.global_position + offset


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
	var start_exit_dir := _start_room_exit_direction()
	if not start_exit_dir.is_empty():
		return start_exit_dir
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


func _start_room_exit_direction() -> String:
	var start_room := _room_by_name(_layout_room_name("start_room"))
	if start_room == null:
		return ""
	var exit_markers := start_room.get_connection_markers_by_kind("exit")
	if exit_markers.size() == 1:
		var exit_marker := exit_markers[0] as ConnectorMarker2D
		if exit_marker != null:
			return String(exit_marker.direction)
	var best_dir := ""
	var best_distance_sq := INF
	for candidate in exit_markers:
		if candidate is not ConnectorMarker2D:
			continue
		var marker := candidate as ConnectorMarker2D
		if marker == null:
			continue
		var distance_sq := marker.global_position.distance_squared_to(start_room.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_dir = String(marker.direction)
	if not best_dir.is_empty():
		return best_dir
	for direction in ["north", "south", "east", "west"]:
		var marker_world := _connection_marker_world_position(
			_layout_room_name("start_room"),
			direction,
			"exit"
		)
		if marker_world.distance_squared_to(start_room.global_position) > 0.0001:
			return direction
	return ""


func _position_debug_spawn_exit_portal() -> void:
	if _mini_hub_active or not OS.is_debug_build():
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
	var start_room_name := _layout_room_name("start_room")
	_debug_spawn_exit_portal.position = _spawn_exit_world_position(start_room_name, start_room)
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
	if _is_authored_floor_mode():
		return
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
		var trimmed := _trim_wall_segment_at_room_corners(seg.x, seg.y, -half_width, half_width)
		var seg_start: float = trimmed.x
		var seg_end: float = trimmed.y
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
		var trimmed := _trim_wall_segment_at_room_corners(seg.x, seg.y, -half_height, half_height)
		var seg_start: float = trimmed.x
		var seg_end: float = trimmed.y
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


func _trim_wall_segment_at_room_corners(
	seg_start: float,
	seg_end: float,
	min_value: float,
	max_value: float
) -> Vector2:
	var trim_amount := WALL_THICKNESS * 0.5
	var trimmed_start := seg_start
	var trimmed_end := seg_end
	if is_equal_approx(seg_start, min_value):
		trimmed_start += trim_amount
	if is_equal_approx(seg_end, max_value):
		trimmed_end -= trim_amount
	if trimmed_end < trimmed_start:
		var midpoint := (trimmed_start + trimmed_end) * 0.5
		trimmed_start = midpoint
		trimmed_end = midpoint
	return Vector2(trimmed_start, trimmed_end)


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
	_clear_authored_room_visuals()
	for child in _door_visuals.get_children():
		child.queue_free()
	_door_visual_by_socket_key.clear()
	_puzzle_door_visual = null
	if _is_authored_floor_mode():
		_rebuild_authored_room_visuals()
		return
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


func _rebuild_authored_room_visuals() -> void:
	_authored_room_visual_stream_time_remaining = 0.0
	_authored_room_visual_build_queue.clear()
	if authored_room_visual_streaming_enabled:
		_refresh_authored_room_visual_streaming(false)
		return
	for room_node in _rooms_root.get_children():
		if room_node is not RoomBase:
			continue
		var room := room_node as RoomBase
		_ensure_authored_room_visual_loaded(room)


func _tick_authored_room_visual_streaming(delta: float) -> void:
	if not _is_authored_floor_mode() or not authored_room_visual_streaming_enabled:
		return
	if not _has_generated_floor:
		return
	_authored_room_visual_stream_time_remaining -= delta
	if _authored_room_visual_stream_time_remaining > 0.0:
		# Drain build queue between full streaming ticks so rooms load incrementally.
		if not _authored_room_visual_build_queue.is_empty():
			var room := _authored_room_visual_build_queue.pop_front() as RoomBase
			if room != null and is_instance_valid(room):
				_ensure_authored_room_visual_loaded(room)
		return
	_authored_room_visual_stream_time_remaining = maxf(authored_room_visual_stream_update_interval, 0.05)
	_refresh_authored_room_visual_streaming(false)
	var built := 0
	while not _authored_room_visual_build_queue.is_empty() and built < _AUTHORED_VISUAL_MAX_BUILDS_PER_TICK:
		var room := _authored_room_visual_build_queue.pop_front() as RoomBase
		if room != null and is_instance_valid(room):
			_ensure_authored_room_visual_loaded(room)
		built += 1


func _refresh_authored_room_visual_streaming(force: bool) -> void:
	if _room_queries == null:
		return
	var focus := _authored_visual_focus_position()
	var load_rect := _authored_visual_stream_rect(focus, _AUTHORED_VISUAL_STREAM_MARGIN)
	var unload_rect := _authored_visual_stream_rect(focus, _AUTHORED_VISUAL_STREAM_UNLOAD_MARGIN)
	for room in _authored_rooms_intersecting_rect(load_rect):
		var room_key := String(room.name)
		var room_bounds := _room_queries.room_bounds_rect(room)
		var should_load := force or load_rect.intersects(room_bounds)
		if should_load:
			_queue_authored_room_visual_load(room)
	for room_key in _authored_room_visual_nodes.keys():
		var room := _authored_room_stream_rooms_by_name.get(room_key, null) as RoomBase
		if room == null or not is_instance_valid(room):
			_unload_authored_room_visual(String(room_key))
			continue
		var room_bounds := _room_queries.room_bounds_rect(room)
		if not unload_rect.intersects(room_bounds):
			_unload_authored_room_visual(String(room_key))


func _queue_authored_room_visual_load(room: RoomBase) -> void:
	if room == null:
		return
	var room_key := String(room.name)
	var existing = _authored_room_visual_nodes.get(room_key, null)
	if existing is Node3D and is_instance_valid(existing):
		return
	if _authored_room_visual_build_queue.has(room):
		return
	_authored_room_visual_build_queue.append(room)


func _ensure_authored_room_visual_loaded(room: RoomBase) -> void:
	if room == null:
		return
	var room_key := String(room.name)
	var existing = _authored_room_visual_nodes.get(room_key, null)
	if existing is Node3D and is_instance_valid(existing):
		return
	var container := _build_authored_room_visual_container(room)
	if container == null:
		return
	_room_visuals.add_child(container)
	_authored_room_visual_nodes[room_key] = container


func _build_authored_room_visual_container(room: RoomBase) -> Node3D:
	if room == null or room.authored_layout == null or _room_preview_builder == null:
		return null
	var container := Node3D.new()
	container.name = "%s_VisualRoot" % String(room.name)
	container.position = Vector3(room.global_position.x, 0.0, room.global_position.y)
	container.rotation = Vector3(0.0, -deg_to_rad(room.rotation_degrees), 0.0)
	_room_preview_builder.rebuild_preview(
		container,
		room,
		room.authored_layout,
		ROOM_PIECE_CATALOG,
		&"all",
		false,
		true
	)
	if container.get_child_count() == 0:
		container.queue_free()
		return null
	return container


func _unload_authored_room_visual(room_key: String) -> void:
	var existing = _authored_room_visual_nodes.get(room_key, null)
	if existing is Node3D and is_instance_valid(existing):
		(existing as Node3D).queue_free()
	_authored_room_visual_nodes.erase(room_key)


func _clear_authored_room_visuals() -> void:
	for child in _room_visuals.get_children():
		child.queue_free()
	_authored_room_visual_nodes.clear()
	_authored_room_visual_build_queue.clear()


func _authored_visual_focus_position() -> Vector2:
	# Per-peer camera follows the local roster player; streaming must use that
	# position, not _reference_player_position() (lowest slot / often the host).
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return _reference_player_position()


func _authored_visual_stream_rect(focus: Vector2, extra_margin: float) -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 0.001)
	var half_height := (_camera_3d.size * 0.5) + extra_margin
	var half_width := (_camera_3d.size * aspect * 0.5) + extra_margin
	return Rect2(
		Vector2(focus.x - half_width, focus.y - half_height),
		Vector2(half_width * 2.0, half_height * 2.0)
	)


func _rebuild_authored_room_stream_buckets() -> void:
	_authored_room_stream_buckets.clear()
	_authored_room_stream_rooms_by_name.clear()
	if _rooms_root == null or _room_queries == null:
		return
	for room_node in _rooms_root.get_children():
		if room_node is not RoomBase:
			continue
		var room := room_node as RoomBase
		var room_key := String(room.name)
		_authored_room_stream_rooms_by_name[room_key] = room
		var bounds := _room_queries.room_bounds_rect(room)
		if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
			continue
		var min_x := int(floor(bounds.position.x / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
		var min_y := int(floor(bounds.position.y / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
		var max_x := int(floor((bounds.end.x - 0.001) / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
		var max_y := int(floor((bounds.end.y - 0.001) / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
		for by in range(min_y, max_y + 1):
			for bx in range(min_x, max_x + 1):
				var bucket := Vector2i(bx, by)
				var existing = _authored_room_stream_buckets.get(bucket)
				if existing is Array:
					(existing as Array).append(room)
				else:
					_authored_room_stream_buckets[bucket] = [room]


func _authored_rooms_intersecting_rect(world_rect: Rect2) -> Array[RoomBase]:
	var rooms: Array[RoomBase] = []
	if _authored_room_stream_buckets.is_empty():
		_rebuild_authored_room_stream_buckets()
	if _authored_room_stream_buckets.is_empty():
		return rooms
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return rooms
	var seen: Dictionary = {}
	var min_x := int(floor(world_rect.position.x / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
	var min_y := int(floor(world_rect.position.y / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
	var max_x := int(floor((world_rect.end.x - 0.001) / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
	var max_y := int(floor((world_rect.end.y - 0.001) / _AUTHORED_VISUAL_STREAM_BUCKET_SIZE))
	for by in range(min_y, max_y + 1):
		for bx in range(min_x, max_x + 1):
			var bucket_rooms = _authored_room_stream_buckets.get(Vector2i(bx, by))
			if bucket_rooms == null:
				continue
			for room_value in (bucket_rooms as Array):
				if room_value is not RoomBase:
					continue
				var room := room_value as RoomBase
				if not is_instance_valid(room):
					continue
				var room_key := String(room.name)
				if seen.has(room_key):
					continue
				seen[room_key] = true
				rooms.append(room)
	return rooms


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
		var sp := s.global_position
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
	return _floor_ground_theme_data().get("glb_scene", GROUND_GLB_DIRT) as PackedScene


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


func _runtime_floor_material(glb_scene: PackedScene) -> Material:
	if glb_scene == null:
		return null
	var path_key := glb_scene.resource_path
	if _runtime_floor_material_by_path.has(path_key):
		return _runtime_floor_material_by_path[path_key] as Material
	var root := glb_scene.instantiate() as Node3D
	if root == null:
		return null
	var material: Material = null
	for mesh_instance in _mesh_instances_in_root(root):
		if mesh_instance.material_override != null:
			material = mesh_instance.material_override
			break
		if mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			material = mesh_instance.mesh.surface_get_material(surface_index)
			if material != null:
				break
		if material != null:
			break
	root.free()
	if material != null:
		_runtime_floor_material_by_path[path_key] = material
	return material


func _mesh_instances_in_root(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance != null:
			out.append(mesh_instance)
	return out


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
	var tw := maxf(0.01, FLOOR_TEXTURE_TILE_WORLD)
	var tiles_x := maxi(1, ceili(rect.size.x / tw))
	var tiles_z := maxi(1, ceili(rect.size.y / tw))
	var module_x := rect.size.x / float(tiles_x)
	var module_z := rect.size.y / float(tiles_z)
	var base_x := rect.position.x + module_x * 0.5
	var base_z := rect.position.y + module_z * 0.5
	var runtime_floor_material := _runtime_floor_material(glb_scene)
	if runtime_floor_material != null:
		for ix in range(tiles_x):
			for iz in range(tiles_z):
				var tile := MeshInstance3D.new()
				var plane := PlaneMesh.new()
				plane.size = Vector2(module_x, module_z)
				tile.name = "RoomFloorTop_%s_%s" % [ix, iz]
				tile.mesh = plane
				tile.material_override = runtime_floor_material
				var px := base_x + float(ix) * module_x
				var pz := base_z + float(iz) * module_z
				tile.position = Vector3(px, FLOOR_SLAB_TOP_Y, pz)
				_disable_architecture_shadows(tile)
				_room_visuals.add_child(tile)
	else:
		var src := _get_floor_glb_tile_aabb(glb_scene)
		var sx := module_x / maxf(0.01, src.size.x)
		var sy := ROOM_HEIGHT / maxf(0.01, src.size.y)
		var sz := module_z / maxf(0.01, src.size.z)
		var src_center := src.get_center()
		var top_y := src.position.y + src.size.y
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
	return null


func _apply_combat_doors_locked(locked: bool, animate: bool = true) -> void:
	if _combat_door_visual_west != null and is_instance_valid(_combat_door_visual_west):
		_combat_door_visual_west.set_runtime_locked(locked, animate)
	if _combat_door_visual_east != null and is_instance_valid(_combat_door_visual_east):
		_combat_door_visual_east.set_runtime_locked(locked, animate)


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
	if _door_lock_controller == null:
		return
	var roster: Array[CharacterBody2D] = []
	if _is_authoritative_world():
		roster = _authoritative_roster_players()
	elif _player != null and is_instance_valid(_player):
		roster.append(_player)
	for player in roster:
		_door_lock_controller.apply_hard_door_clamps(
			player,
			_puzzle_solved,
			_puzzle_gate_socket,
			_puzzle_gate_dir,
			_encounter_spawn_controller.active_encounter_state() if _encounter_spawn_controller != null else {},
			_PLAYER_CLAMP_R,
			_MOB_CLAMP_R,
			[]
		)
	if not _is_authoritative_world():
		return
	var mob_bodies: Array[CharacterBody2D] = []
	if _encounter_spawn_controller != null:
		mob_bodies = _encounter_spawn_controller.get_all_active_mob_bodies()
	_door_lock_controller.apply_hard_door_clamps(
		null,
		_puzzle_solved,
		_puzzle_gate_socket,
		_puzzle_gate_dir,
		_encounter_spawn_controller.active_encounter_state() if _encounter_spawn_controller != null else {},
		_PLAYER_CLAMP_R,
		_MOB_CLAMP_R,
		mob_bodies
	)


func _spawn_standard_door_piece(world_pos: Vector2, width_tiles: int) -> void:
	return


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
	if _is_authored_floor_mode():
		return
	if _mini_hub_active:
		return
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


func _nearest_peer_id_to_world_pos(world_pos: Vector2) -> int:
	var best_peer := 0
	var best_d := INF
	for peer_id in _peer_ids_sorted_by_slot(_peer_slots):
		var node_v: Variant = _players_by_peer.get(peer_id, null)
		if node_v is not CharacterBody2D:
			continue
		var p := node_v as CharacterBody2D
		if not is_instance_valid(p):
			continue
		var d := world_pos.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best_peer = peer_id
	if best_peer > 0:
		return best_peer
	return maxi(0, _local_peer_id())


func _magnet_dropped_coins_for_encounter_room(encounter_id: StringName) -> void:
	if not _is_authoritative_world():
		return
	var room_name := _room_name_for_encounter(encounter_id)
	if room_name == &"" or _room_queries == null:
		return
	var room := _room_by_name(room_name)
	if room == null:
		return
	var bounds := _room_queries.room_bounds_rect(room)
	if not bounds.has_area():
		return
	bounds = bounds.grow(12.0)
	var should_rpc := (
		_networked_run
		and _is_server_peer()
		and _has_multiplayer_peer()
		and _can_broadcast_world_replication()
	)
	for net_id_key in _coin_nodes_by_network_id.keys():
		var coin_v: Variant = _coin_nodes_by_network_id.get(net_id_key, null)
		if coin_v is not DroppedCoin:
			continue
		var coin := coin_v as DroppedCoin
		if not is_instance_valid(coin):
			continue
		if not bounds.has_point(coin.global_position):
			continue
		var peer_pick := _nearest_peer_id_to_world_pos(coin.global_position)
		coin.begin_room_clear_magnet(peer_pick)
		if should_rpc:
			_rpc_coin_begin_room_clear_magnet.rpc(int(net_id_key), peer_pick)


func _room_name_for_encounter(encounter_id: StringName) -> StringName:
	var id_text := String(encounter_id)
	if id_text == "boss":
		return _layout_room_name("exit_room")
	if id_text.begins_with("arena_"):
		return StringName(id_text.trim_prefix("arena_"))
	return &""


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


func _collect_infusion_pillars_under(node: Node, out: Array[InfusionPillar2D]) -> void:
	if node == null:
		return
	for ch in node.get_children():
		_collect_infusion_pillars_under(ch, out)
		if ch is InfusionPillar2D:
			out.append(ch as InfusionPillar2D)


func _roster_any_player_under_infusion_cap(pillar_id: StringName) -> bool:
	if _players_by_peer.is_empty():
		return true
	for peer_key in _players_by_peer.keys():
		var p: Variant = _players_by_peer[peer_key]
		if p is not CharacterBody2D or not is_instance_valid(p):
			continue
		var im := p.get_node_or_null(^"InfusionManager") as InfusionManager
		if im != null and not im.is_at_pickup_cap_for_pillar(pillar_id):
			return true
	return false


func _eligible_boss_infusion_pillar_ids_for_roster() -> Array[StringName]:
	var elig: Array[StringName] = []
	for pid in _BOSS_RANDOM_INFUSION_IDS:
		if _roster_any_player_under_infusion_cap(pid):
			elig.append(pid)
	if elig.is_empty():
		return _BOSS_RANDOM_INFUSION_IDS.duplicate()
	return elig


func _pick_random_boss_infusion_pillar_id() -> StringName:
	var elig := _eligible_boss_infusion_pillar_ids_for_roster()
	var idx := _rng.randi_range(0, elig.size() - 1)
	return elig[idx]


## Authored `infusion_pillar_marker` → `InfusionPillar2D` under the boss room keep their layout positions.
## Locked until `_set_boss_exit_active(true)`. Procedural floors with no markers get one pillar at `boss_center`.
func _setup_boss_infusion_pillars(boss_room: RoomBase, boss_center: Vector2) -> void:
	if not _is_authoritative_world():
		return
	var in_room: Array[InfusionPillar2D] = []
	if boss_room != null:
		_collect_infusion_pillars_under(boss_room, in_room)
	var i := 0
	for pillar in in_room:
		if not is_instance_valid(pillar):
			continue
		if pillar.pillar_visual_scene == null:
			pillar.pillar_visual_scene = INFUSION_EDGE_PILLAR_VISUAL_SCENE
		pillar.infusion_pillar_id = _pick_random_boss_infusion_pillar_id()
		pillar.add_to_group(&"boss_floor_infusion_pillar")
		pillar.set_pickup_locked(true)
		i += 1
	if i > 0:
		return
	var pillar_v := INFUSION_PILLAR_SCENE.instantiate()
	if pillar_v is not InfusionPillar2D:
		return
	var fallback := pillar_v as InfusionPillar2D
	fallback.name = "BossInfusionPillar"
	fallback.position = boss_center
	fallback.infusion_pillar_id = _pick_random_boss_infusion_pillar_id()
	fallback.add_to_group(&"boss_floor_infusion_pillar")
	_piece_instances_root.add_child(fallback)
	fallback.set_pickup_locked(true)


func _unlock_boss_infusion_pillar_pickup() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(&"boss_floor_infusion_pillar"):
		if n is InfusionPillar2D and is_instance_valid(n):
			(n as InfusionPillar2D).set_pickup_locked(false)


func _spawn_entrance_exit_markers() -> void:
	var entrance_pos := _room_center_2d(_layout_room_name("start_room"))
	if _is_authored_floor_mode():
		var spawn_positions := _authored_spawn_positions(_layout_room_name("start_room"))
		if not spawn_positions.is_empty():
			entrance_pos = spawn_positions[0]
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
	if _encounter_spawn_controller == null:
		return
	_setup_encounter_spawn_controller_for_floor()
	_encounter_spawn_controller.setup_encounters()


## Server-only: queue a specific enemy scene with full replication (death splits, scripted adds).
func server_enqueue_enemy_spawn(
	encounter_id: StringName,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	enemy_scene: PackedScene,
	start_aggro: bool = true,
	spawn_config: Dictionary = {}
) -> void:
	if _encounter_spawn_controller == null:
		return
	_encounter_spawn_controller.server_enqueue_enemy_spawn(
		encounter_id,
		spawn_position,
		target_position,
		speed_multiplier,
		enemy_scene,
		start_aggro,
		spawn_config
	)


func spawn_runtime_enemy_by_kind(
	encounter_id: StringName,
	scene_kind: int,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float = 1.0,
	start_aggro: bool = true,
	spawn_config: Dictionary = {}
) -> EnemyBase:
	if _encounter_spawn_controller == null:
		return null
	return _encounter_spawn_controller.spawn_runtime_enemy_by_kind(
		encounter_id,
		scene_kind,
		spawn_position,
		target_position,
		speed_multiplier,
		start_aggro,
		spawn_config
	)

func _prewarm_enemy_assets_once() -> void:
	if _enemy_assets_prewarmed or not prewarm_enemy_assets or _is_dedicated_server_session():
		return
	# All 22 enemy scene types — first instantiation pays the shader/mesh compile cost;
	# doing it here during level load prevents mid-combat frame spikes.
	var scenes: Array[PackedScene] = [
		FLOW_DASHER_SCENE, FLOWFORM_SCENE, SCRAMBLER_SCENE, STUMBLER_SCENE,
		SHIELDWALL_SCENE, WARDEN_SCENE, SPLITTER_SCENE, ECHOFORM_SCENE,
		TRIAD_SCENE, ECHO_SPLINTER_SCENE, ECHO_UNIT_SCENE, BINDER_SCENE,
		LURKER_SCENE, LEECHER_SCENE, SKEWER_SCENE, GLAIVER_SCENE,
		RAZORFORM_SCENE,
		EnemySpawnByEnemyId.DASHER_SCENE, EnemySpawnByEnemyId.ARROW_TOWER_SCENE,
		EnemySpawnByEnemyId.FIZZLER_SCENE, EnemySpawnByEnemyId.BURSTER_SCENE,
		EnemySpawnByEnemyId.DETONATOR_SCENE,
	]
	for scene in scenes:
		if scene == null:
			continue
		var enemy: Node = scene.instantiate()
		if enemy == null:
			continue
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		if enemy is EnemyBase:
			var enemy_base := enemy as EnemyBase
			enemy_base.configure_spawn(_ENEMY_PREWARM_POSITION, _ENEMY_PREWARM_POSITION)
			enemy_base.set_aggro_enabled(false)
		if enemy is Node2D:
			(enemy as Node2D).global_position = _ENEMY_PREWARM_POSITION
		$GameWorld2D.add_child(enemy)
		$GameWorld2D.remove_child(enemy)
		enemy.queue_free()
	_enemy_assets_prewarmed = true


func broadcast_enemy_transform_state(
	net_id: int, world_pos: Vector2, planar_velocity: Vector2, compact_state: Dictionary
) -> void:
	if _encounter_spawn_controller == null:
		return
	_encounter_spawn_controller.broadcast_enemy_transform_state(
		net_id,
		world_pos,
		planar_velocity,
		compact_state
	)


## Sends all accumulated transform updates as one unreliable RPC, then clears the queue.
## Called at the end of each physics tick from dungeon_orchestrator.gd.
func _flush_enemy_transform_batch() -> void:
	if _encounter_spawn_controller == null:
		return
	_encounter_spawn_controller.flush_enemy_transform_batch()

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
	if _encounter_spawn_controller != null:
		_encounter_spawn_controller.send_runtime_snapshot_to_peer(peer_id)
	_rpc_set_puzzle_gate_solved.rpc_id(peer_id, _puzzle_solved, false)
	_rpc_set_boss_exit_active.rpc_id(peer_id, _boss_exit_portal != null and _boss_exit_portal.monitoring)
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
	await get_tree().process_frame
	await get_tree().process_frame
	_loading_overlay_call(&"hide_loading")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_layout_snapshot(floor_index_value: int, layout_snapshot: Dictionary) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if layout_snapshot.is_empty():
		return
	if _has_generated_floor:
		_loading_overlay_call(&"show_loading")
		await get_tree().process_frame
	_floor_index = maxi(1, floor_index_value)
	_map_layout = layout_snapshot.duplicate(true)
	_mini_hub_active = String(_map_layout.get(LAYOUT_KEY_PHASE, LAYOUT_PHASE_FLOOR)) == LAYOUT_PHASE_MINI_HUB
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
func _rpc_coin_begin_room_clear_magnet(coin_network_id: int, preferred_peer_id: int) -> void:
	if _is_authoritative_world():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var coin_v: Variant = _coin_nodes_by_network_id.get(coin_network_id, null)
	if coin_v is DroppedCoin and is_instance_valid(coin_v):
		(coin_v as DroppedCoin).begin_room_clear_magnet(preferred_peer_id)


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


func _set_boss_exit_active(active: bool, replicate: bool = true) -> void:
	if _mini_hub_active:
		_mini_hub_interactions_active = active
	if _boss_exit_portal != null and is_instance_valid(_boss_exit_portal):
		_boss_exit_portal.set_deferred("monitoring", active)
		_boss_exit_portal.set_deferred("monitorable", active)
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
	if active:
		_unlock_boss_infusion_pillar_pickup()


func _required_floor_transition_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = _peer_ids_sorted_by_slot(_peer_slots)
	if peer_ids.is_empty():
		peer_ids.append(_local_peer_id())
	return peer_ids


func _player_for_peer_id(peer_id: int) -> CharacterBody2D:
	var node_v: Variant = _players_by_peer.get(peer_id, null)
	if node_v is CharacterBody2D and is_instance_valid(node_v):
		return node_v as CharacterBody2D
	if peer_id == _local_peer_id() and _player != null and is_instance_valid(_player):
		return _player
	return null


func _encounter_is_cleared(encounter_id: StringName) -> bool:
	if _encounter_spawn_controller == null:
		return false
	if _encounter_spawn_controller.has_method("is_encounter_cleared"):
		return bool(_encounter_spawn_controller.call("is_encounter_cleared", encounter_id))
	return false


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
	if _floor_transition_pending:
		return
	if not _mini_hub_active and not _boss_cleared:
		return
	if _boss_exit_portal == null or not _boss_exit_portal.monitoring:
		return
	var required_peer_ids: Array[int] = _required_floor_transition_peer_ids()
	if required_peer_ids.is_empty():
		return
	var on_count := _count_players_on_exit_elevator(required_peer_ids)
	if on_count < required_peer_ids.size():
		if _mini_hub_active:
			_set_info_base_text(
				"Mini-hub elevator boarding: %s/%s players." % [on_count, required_peer_ids.size()]
			)
		else:
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
	if not (_boss_cleared or _mini_hub_active) or not _is_player_body(body):
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
	_loading_overlay_call(&"show_loading")
	await get_tree().process_frame
	for peer_id in _players_by_peer.keys():
		var node: Variant = _players_by_peer[peer_id]
		if node is CharacterBody2D and is_instance_valid(node):
			var player := node as CharacterBody2D
			if player.has_method(&"revive_to_full"):
				player.call(&"revive_to_full")
			elif player.has_method(&"heal_to_full"):
				player.call(&"heal_to_full")
	if _mini_hub_active:
		_mini_hub_active = false
		_floor_index += 1
		_sync_run_state_floor_index()
		_sync_run_state_phase(&"floor")
	else:
		_grant_tempering_xp_to_all_players(_MetaProgressionConstantsRef.TEMPERING_XP_PER_FLOOR)
		_mini_hub_active = true
		_mini_hub_arrival_retry_count = 0
		_map_layout = {}
		_sync_run_state_phase(&"mini_hub")
	_regenerate_level(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_loading_overlay_call(&"hide_loading")


func _sync_run_state_floor_index() -> void:
	var run_state := get_node_or_null("/root/RunState")
	if run_state != null and run_state.has_method(&"set_floor"):
		run_state.call(&"set_floor", _floor_index)


func _sync_run_state_phase(phase: StringName) -> void:
	var run_state := get_node_or_null("/root/RunState")
	if run_state != null and run_state.has_method(&"set_extra_value"):
		run_state.call(&"set_extra_value", &"phase", String(phase))


func _mini_hub_required_players_arrived(required_peer_ids: Array[int]) -> bool:
	if required_peer_ids.is_empty():
		return false
	var hub_room := _layout_room_name("start_room")
	for peer_id in required_peer_ids:
		var node_v: Variant = _players_by_peer.get(peer_id, null)
		if node_v is not CharacterBody2D:
			return false
		var player := node_v as CharacterBody2D
		if player == null or not is_instance_valid(player):
			return false
		if StringName(_room_name_at(player.global_position, 1.25)) != hub_room:
			return false
	return true


func _enable_mini_hub_elevator_after_arrival_sync() -> void:
	if not _is_authoritative_world() or not _mini_hub_active:
		return
	await get_tree().physics_frame
	if not _is_authoritative_world() or not _mini_hub_active:
		return
	var required_peer_ids := _required_floor_transition_peer_ids()
	if not _mini_hub_required_players_arrived(required_peer_ids):
		_mini_hub_arrival_retry_count += 1
		if _mini_hub_arrival_retry_count <= 10:
			call_deferred("_enable_mini_hub_elevator_after_arrival_sync")
		else:
			_set_info_base_text("Mini-hub waiting for all players to arrive.")
		return
	_mini_hub_arrival_retry_count = 0
	_set_boss_exit_active(true)
	_set_info_base_text("Mini-hub ready. Adjust loadout, then board the elevator together.")


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
	_finalize_run_meta_progression()
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


func _loadout_room_type_at(world_pos: Vector2, margin: float = 0.0) -> String:
	var room_type := _room_type_at(world_pos, margin)
	if room_type != "safe":
		return room_type
	if _mini_hub_active and _mini_hub_interactions_active:
		return room_type
	return "connector"


func _set_info_base_text(text: String) -> void:
	if _info_controller != null:
		_info_controller.set_base_text(text)


func _refresh_info_label_with_room_type() -> void:
	if _info_controller != null:
		_info_controller.refresh()


func _tick_info_label_refresh(delta: float) -> void:
	if _info_controller == null:
		return
	_info_label_refresh_time_remaining = maxf(0.0, _info_label_refresh_time_remaining - delta)
	var room_changed := _prev_room_name != _info_label_last_room_name
	if _info_label_refresh_time_remaining > 0.0 and not room_changed:
		return
	_refresh_info_label_with_room_type()
	_info_label_last_room_name = _prev_room_name
	_info_label_refresh_time_remaining = maxf(0.01, info_label_update_interval)


func _tick_authoritative_maintenance(delta: float) -> void:
	_authoritative_maintenance_time_remaining = maxf(
		0.0,
		_authoritative_maintenance_time_remaining - delta
	)
	if _authoritative_maintenance_time_remaining > 0.0:
		return
	_process_authoritative_revive_and_wipe()
	if _encounter_spawn_controller != null:
		_encounter_spawn_controller.refresh_encounter_state()
	if _connection_room_gate_controller != null:
		_connection_room_gate_controller.refresh()
	_try_schedule_floor_advance_if_all_players_on_elevator()
	_try_schedule_floor_advance_if_all_players_on_debug_elevator()
	_flush_coin_totals_if_dirty()
	_authoritative_maintenance_time_remaining = maxf(0.01, authoritative_maintenance_update_interval)
