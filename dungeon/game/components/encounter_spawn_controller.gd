extends Node
class_name EncounterSpawnController

signal encounter_started(encounter_id: StringName, is_main_combat: bool)
signal encounter_cleared(encounter_id: StringName, is_boss: bool, is_main_combat: bool)
signal enemy_coin_drop_requested(enemy: EnemyBase, drop_config: Dictionary)
signal boss_setup_requested(boss_room: RoomBase, boss_center: Vector2)

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
const EnemySpawnByEnemyId = preload("res://dungeon/game/enemy_spawn_by_id.gd")
const EncounterRunManagerScript = preload("res://dungeon/game/encounters/encounter_run_manager.gd")
const Layer1EncounterRegistry = preload("res://dungeon/game/encounters/layer_1_encounter_registry.gd")
const Layer2EncounterRegistry = preload("res://dungeon/game/encounters/layer_2_encounter_registry.gd")
const Layer3EncounterRegistry = preload("res://dungeon/game/encounters/layer_3_encounter_registry.gd")

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
const _COMBAT_ENTRY_TRIGGER_INSET := 8.0
const _DOOR_SLAB_HALF := 3.0
const _DOOR_CLAMP_Y_EXT := 7.02
const _BACK_HALF_MIN_RATIO := 0.22
const _SPEED_SCALE_PER_FLOOR := 0.08
const _SPEED_SCALE_MAX_ARENA := 1.65
const _SPEED_SCALE_MAX_BOSS := 1.55
const _TOWER_SPAWN_MIN_SEP := 4.5
const _ENEMY_PREWARM_POSITION := Vector2(1000000.0, 1000000.0)

var room_queries: RoomQueryService
var door_lock_controller: DoorLockController
var encounter_modules_root: Node2D
var world_2d: Node2D
var rng: RandomNumberGenerator
var floor_index: int = 1
var map_layout: Dictionary = {}
var mini_hub_active := false
var combat_entry_dir := "west"
var combat_exit_dir := "east"
var combat_entry_socket := Vector2.ZERO
var boss_entry_dir := "west"
var boss_entry_socket := Vector2.ZERO
var is_authoritative_fn: Callable
var is_server_peer_fn: Callable
var can_broadcast_replication_fn: Callable
var get_player_position_fn: Callable
var prespawn_mobs := false
var spawn_queue_interval := 0.05

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
var _enemy_nodes_by_network_id: Dictionary = {}
var _enemy_network_id_sequence := 0
var _pending_enemy_spawn_requests: Array[Dictionary] = []
var _encounter_spawn_queue_time_remaining := 0.0
var _encounter_run_manager: RefCounted
var _combat_encounter_id: StringName = &""
var _pending_transform_updates: Array = []

func clear_runtime_state() -> void:
	_pending_enemy_spawn_requests.clear()
	_encounter_spawn_queue_time_remaining = 0.0
	_enemy_nodes_by_network_id.clear()

func register_door_visual(socket_pos_key: String, door_visual: DungeonCellDoor3D) -> void:
	if socket_pos_key.is_empty() or door_visual == null:
		return
	_door_visual_by_socket_key[socket_pos_key] = door_visual

func get_all_active_mob_bodies() -> Array[CharacterBody2D]:
	var mob_bodies: Array[CharacterBody2D] = []
	for encounter_key in _encounter_mobs.keys():
		var encounter_id := encounter_key as StringName
		if not bool(_encounter_active.get(encounter_id, false)):
			continue
		var mobs: Array = _encounter_mobs.get(encounter_id, []) as Array
		for mob_value in mobs:
			if mob_value is CharacterBody2D and is_instance_valid(mob_value):
				mob_bodies.append(mob_value as CharacterBody2D)
	return mob_bodies

func get_combat_encounter_id() -> StringName:
	return _combat_encounter_id

func is_encounter_active(encounter_id: StringName) -> bool:
	return bool(_encounter_active.get(encounter_id, false))

func is_encounter_cleared(encounter_id: StringName) -> bool:
	return bool(_encounter_completed.get(encounter_id, false))

func active_encounter_state() -> Dictionary:
	return _encounter_active

func broadcast_enemy_transform_state(net_id: int, world_pos: Vector2, planar_velocity: Vector2, compact_state: Dictionary) -> void:
	if net_id <= 0 or not _is_server() or not _can_broadcast_replication():
		return
	_pending_transform_updates.append([net_id, world_pos, planar_velocity, compact_state])

func flush_enemy_transform_batch() -> void:
	if _pending_transform_updates.is_empty():
		return
	if not _is_server() or not _can_broadcast_replication():
		_pending_transform_updates.clear()
		return
	_rpc_receive_enemy_transform_batch.rpc(_pending_transform_updates)
	_pending_transform_updates.clear()

func send_runtime_snapshot_to_peer(peer_id: int) -> void:
	if peer_id <= 0 or not _is_server():
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
		var spawn_config := _enemy_spawn_config_from_instance(enemy)
		_rpc_spawn_enemy.rpc_id(peer_id, net_id, String(encounter_id), scene_kind, enemy.global_position, enemy.global_position, 1.0, aggro_enabled, spawn_config)

func enemy_prewarm_scenes() -> Array[PackedScene]:
	return [
		FLOW_DASHER_SCENE, FLOWFORM_SCENE, SCRAMBLER_SCENE, STUMBLER_SCENE,
		SHIELDWALL_SCENE, WARDEN_SCENE, SPLITTER_SCENE, ECHOFORM_SCENE,
		TRIAD_SCENE, ECHO_SPLINTER_SCENE, ECHO_UNIT_SCENE, BINDER_SCENE,
		LURKER_SCENE, LEECHER_SCENE, SKEWER_SCENE, GLAIVER_SCENE,
		RAZORFORM_SCENE, EnemySpawnByEnemyId.DASHER_SCENE, EnemySpawnByEnemyId.ARROW_TOWER_SCENE,
		EnemySpawnByEnemyId.FIZZLER_SCENE, EnemySpawnByEnemyId.BURSTER_SCENE,
		EnemySpawnByEnemyId.DETONATOR_SCENE,
	]

func enemy_prewarm_position() -> Vector2:
	return _ENEMY_PREWARM_POSITION

func _is_authoritative() -> bool:
	return bool(is_authoritative_fn.call()) if is_authoritative_fn.is_valid() else true

func _is_server() -> bool:
	return bool(is_server_peer_fn.call()) if is_server_peer_fn.is_valid() else false

func _can_broadcast_replication() -> bool:
	return bool(can_broadcast_replication_fn.call()) if can_broadcast_replication_fn.is_valid() else false

func _reference_player_position() -> Vector2:
	if not get_player_position_fn.is_valid():
		return Vector2.ZERO
	var value: Variant = get_player_position_fn.call()
	return value as Vector2 if value is Vector2 else Vector2.ZERO

func _room_by_name(room_name: StringName) -> RoomBase:
	return room_queries.room_by_name(room_name) if room_queries != null else null

func _layout_room_name(key: String, fallback: String = "") -> StringName:
	return StringName(String(map_layout.get(key, fallback)))

func _room_half_extents(room: RoomBase) -> Vector2:
	return room_queries.room_half_extents(room) if room_queries != null else Vector2.ZERO

func _room_center_2d(room_name: StringName) -> Vector2:
	return room_queries.room_center_2d(room_name) if room_queries != null else Vector2.ZERO

func _zone_markers(room_name: StringName, zone_type: String, zone_role: StringName = &"") -> Array[Dictionary]:
	return room_queries.zone_markers(room_name, zone_type, zone_role) if room_queries != null else []

func _room_name_at(world_pos: Vector2, margin: float = 0.0) -> String:
	return room_queries.room_name_at(world_pos, margin) if room_queries != null else ""

func _clamp_pos_to_room(room: RoomBase, pos: Vector2) -> Vector2:
	return room_queries.clamp_pos_to_room(room, pos) if room_queries != null else pos

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

func _on_enemy_coin_drop_requested(enemy: EnemyBase, drop_config: Dictionary) -> void:
	enemy_coin_drop_requested.emit(enemy, drop_config)


func _next_enemy_network_id() -> int:
	_enemy_network_id_sequence += 1
	return _enemy_network_id_sequence


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


func _packed_tags_text(tags: PackedStringArray) -> String:
	var parts: Array[String] = []
	for tag in tags:
		parts.append(tag)
	return ",".join(parts)


func _pick_scene_from_pool(pool: Array[PackedScene]) -> PackedScene:
	if pool.is_empty():
		return FLOW_DASHER_SCENE
	return pool[rng.randi_range(0, pool.size() - 1)]


func _pick_random_primary_family_scene() -> PackedScene:
	return _pick_scene_from_pool(EnemySpawnByEnemyId.primary_family_scenes())


func _ensure_encounter_run_manager() -> void:
	if _encounter_run_manager != null and _encounter_run_manager.is_configured():
		return
	_encounter_run_manager = EncounterRunManagerScript.new()
	var seed := _encounter_run_seed()
	var templates: Array = []
	templates.append_array(Layer1EncounterRegistry.templates())
	templates.append_array(Layer2EncounterRegistry.templates())
	templates.append_array(Layer3EncounterRegistry.templates())
	_encounter_run_manager.configure(seed, templates)
	if OS.is_debug_build():
		print("EncounterTemplate run_seed=%s templates=%s" % [seed, templates.size()])


func _current_layer() -> int:
	var run_state := get_node_or_null("/root/RunState")
	if run_state != null:
		var v: Variant = run_state.get(&"layer_index")
		if v is int and int(v) >= 1:
			return int(v)
	## Fallback: assume up to 5 floors per layer, clamped to the 3-layer structure.
	return clampi(ceili(float(floor_index) / 5.0), 1, 3)


func _encounter_run_seed() -> int:
	var run_state := get_node_or_null("/root/RunState")
	if run_state != null:
		var seed_v: Variant = run_state.get("run_seed")
		if seed_v is int and int(seed_v) != 0:
			return int(seed_v)
		if seed_v is float and int(seed_v) != 0:
			return int(seed_v)
	var fallback := int(rng.randi())
	return fallback if fallback != 0 else int(Time.get_unix_time_from_system())


func _enemy_scene_kind_from_scene(scene: PackedScene) -> int:
	if scene == SPLITTER_SCENE:
		return ENEMY_SCENE_KIND_SPLITTER
	if scene == ECHOFORM_SCENE:
		return ENEMY_SCENE_KIND_ECHOFORM
	if scene == TRIAD_SCENE:
		return ENEMY_SCENE_KIND_TRIAD
	if scene == ECHO_SPLINTER_SCENE:
		return ENEMY_SCENE_KIND_ECHO_SPLINTER
	if scene == ECHO_UNIT_SCENE:
		return ENEMY_SCENE_KIND_ECHO_UNIT
	if scene == BINDER_SCENE:
		return ENEMY_SCENE_KIND_BINDER
	if scene == LURKER_SCENE:
		return ENEMY_SCENE_KIND_LURKER
	if scene == LEECHER_SCENE:
		return ENEMY_SCENE_KIND_LEECHER
	if scene == SKEWER_SCENE:
		return ENEMY_SCENE_KIND_SKEWER
	if scene == GLAIVER_SCENE:
		return ENEMY_SCENE_KIND_GLAIVER
	if scene == RAZORFORM_SCENE:
		return ENEMY_SCENE_KIND_RAZORFORM
	if scene == STUMBLER_SCENE:
		return ENEMY_SCENE_KIND_STUMBLER
	if scene == SHIELDWALL_SCENE:
		return ENEMY_SCENE_KIND_SHIELDWALL
	if scene == WARDEN_SCENE:
		return ENEMY_SCENE_KIND_WARDEN
	if scene == FLOWFORM_SCENE:
		return ENEMY_SCENE_KIND_FLOWFORM
	if scene == SCRAMBLER_SCENE:
		return ENEMY_SCENE_KIND_SCRAMBLER
	if scene == FLOW_DASHER_SCENE:
		return ENEMY_SCENE_KIND_FLOW_DASHER
	if scene == EnemySpawnByEnemyId.DASHER_SCENE:
		return ENEMY_SCENE_KIND_DASHER
	if scene == EnemySpawnByEnemyId.ARROW_TOWER_SCENE:
		return ENEMY_SCENE_KIND_ARROW_TOWER
	if scene == EnemySpawnByEnemyId.FIZZLER_SCENE:
		return ENEMY_SCENE_KIND_FIZZLER
	if scene == EnemySpawnByEnemyId.BURSTER_SCENE:
		return ENEMY_SCENE_KIND_BURSTER
	if scene == EnemySpawnByEnemyId.DETONATOR_SCENE:
		return ENEMY_SCENE_KIND_DETONATOR
	return ENEMY_SCENE_KIND_FLOW_DASHER


func _enemy_scene_kind_from_enemy_instance(enemy: EnemyBase) -> int:
	var script_v: Variant = enemy.get_script() if enemy != null else null
	if script_v == SPLITTER_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_SPLITTER
	if script_v == ECHOFORM_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_ECHOFORM
	if script_v == TRIAD_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_TRIAD
	if script_v == ECHO_SPLINTER_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_ECHO_SPLINTER
	if script_v == ECHO_UNIT_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_ECHO_UNIT
	if script_v == BINDER_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_BINDER
	if script_v == LURKER_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_LURKER
	if script_v == LEECHER_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_LEECHER
	if script_v == SKEWER_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_SKEWER
	if script_v == GLAIVER_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_GLAIVER
	if script_v == RAZORFORM_MOB_SCRIPT:
		return ENEMY_SCENE_KIND_RAZORFORM
	if enemy is StumblerMob:
		return ENEMY_SCENE_KIND_STUMBLER
	if enemy is ShieldwallMob:
		return ENEMY_SCENE_KIND_SHIELDWALL
	if enemy is WardenMob:
		return ENEMY_SCENE_KIND_WARDEN
	if enemy is FlowformMob:
		return ENEMY_SCENE_KIND_FLOWFORM
	if enemy is ScramblerMob:
		return ENEMY_SCENE_KIND_SCRAMBLER
	if enemy is FizzlerMob:
		return ENEMY_SCENE_KIND_FIZZLER
	if enemy is BursterMob:
		return ENEMY_SCENE_KIND_BURSTER
	if enemy is DetonatorMob:
		return ENEMY_SCENE_KIND_DETONATOR
	if enemy is ArrowTowerMob:
		return ENEMY_SCENE_KIND_ARROW_TOWER
	return ENEMY_SCENE_KIND_FLOW_DASHER


func _enemy_scene_from_kind(kind: int) -> PackedScene:
	match kind:
		ENEMY_SCENE_KIND_DASHER:
			return EnemySpawnByEnemyId.DASHER_SCENE
		ENEMY_SCENE_KIND_ARROW_TOWER:
			return EnemySpawnByEnemyId.ARROW_TOWER_SCENE
		ENEMY_SCENE_KIND_SPLITTER:
			return SPLITTER_SCENE
		ENEMY_SCENE_KIND_ECHOFORM:
			return ECHOFORM_SCENE
		ENEMY_SCENE_KIND_TRIAD:
			return TRIAD_SCENE
		ENEMY_SCENE_KIND_ECHO_SPLINTER:
			return ECHO_SPLINTER_SCENE
		ENEMY_SCENE_KIND_ECHO_UNIT:
			return ECHO_UNIT_SCENE
		ENEMY_SCENE_KIND_BINDER:
			return BINDER_SCENE
		ENEMY_SCENE_KIND_LURKER:
			return LURKER_SCENE
		ENEMY_SCENE_KIND_LEECHER:
			return LEECHER_SCENE
		ENEMY_SCENE_KIND_SKEWER:
			return SKEWER_SCENE
		ENEMY_SCENE_KIND_GLAIVER:
			return GLAIVER_SCENE
		ENEMY_SCENE_KIND_RAZORFORM:
			return RAZORFORM_SCENE
		ENEMY_SCENE_KIND_STUMBLER:
			return STUMBLER_SCENE
		ENEMY_SCENE_KIND_SHIELDWALL:
			return SHIELDWALL_SCENE
		ENEMY_SCENE_KIND_WARDEN:
			return WARDEN_SCENE
		ENEMY_SCENE_KIND_FLOWFORM:
			return FLOWFORM_SCENE
		ENEMY_SCENE_KIND_SCRAMBLER:
			return SCRAMBLER_SCENE
		ENEMY_SCENE_KIND_FLOW_DASHER:
			return FLOW_DASHER_SCENE
		ENEMY_SCENE_KIND_FIZZLER:
			return EnemySpawnByEnemyId.FIZZLER_SCENE
		ENEMY_SCENE_KIND_BURSTER:
			return EnemySpawnByEnemyId.BURSTER_SCENE
		ENEMY_SCENE_KIND_DETONATOR:
			return EnemySpawnByEnemyId.DETONATOR_SCENE
		_:
			return FLOW_DASHER_SCENE

func _tower_spawn_near_center(encounter_id: StringName, module_pos: Vector2) -> Vector2:
	if map_layout.is_empty():
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

func setup_encounters() -> void:
	_enemy_nodes_by_network_id.clear()
	if mini_hub_active:
		_spawn_points_by_encounter.clear()
		_spawn_volumes_by_encounter.clear()
		_spawn_count_by_encounter.clear()
		_encounter_template_by_encounter.clear()
		_encounter_spawn_plan_by_encounter.clear()
		_planned_tower_positions_by_encounter.clear()
		_entry_socket_by_encounter.clear()
		_entry_socket_dir_by_encounter.clear()
		if door_lock_controller != null:
			door_lock_controller.clear_encounter_locks()
		_encounter_active = {}
		_encounter_completed = {}
		_encounter_mobs = {}
		_combat_encounter_id = &""
		return
	if not _is_authoritative():
		_spawn_points_by_encounter.clear()
		_spawn_volumes_by_encounter.clear()
		_spawn_count_by_encounter.clear()
		_encounter_template_by_encounter.clear()
		_encounter_spawn_plan_by_encounter.clear()
		_planned_tower_positions_by_encounter.clear()
		_entry_socket_by_encounter.clear()
		_entry_socket_dir_by_encounter.clear()
		if door_lock_controller != null:
			door_lock_controller.clear_encounter_locks()
		_encounter_active = {}
		_encounter_completed = {}
		_encounter_mobs = {}
		_combat_encounter_id = &""
		return
	_spawn_points_by_encounter.clear()
	_spawn_volumes_by_encounter.clear()
	_spawn_count_by_encounter.clear()
	_encounter_template_by_encounter.clear()
	_encounter_spawn_plan_by_encounter.clear()
	_planned_tower_positions_by_encounter.clear()
	_entry_socket_by_encounter.clear()
	_entry_socket_dir_by_encounter.clear()
	if door_lock_controller != null:
		door_lock_controller.clear_encounter_locks()
	_encounter_active = {&"boss": false}
	_encounter_completed = {&"boss": false}
	_encounter_mobs = {&"boss": []}
	_combat_encounter_id = &""
	_ensure_encounter_run_manager()

	var combat_room_name := _layout_room_name("combat_room")
	var boss_room := _room_by_name(_layout_room_name("exit_room"))
	if boss_room == null:
		return
	var boss_center := boss_room.global_position
	_entry_socket_by_encounter[&"boss"] = boss_entry_socket
	_entry_socket_dir_by_encounter[&"boss"] = boss_entry_dir
	_cache_locked_sockets_for_encounter(boss_room, &"boss")
	var boss_trigger := _encounter_trigger_config_for_room(boss_room, &"boss", boss_center)
	_spawn_encounter_trigger(
		boss_trigger.get("position", boss_center) as Vector2,
		&"boss",
		"BossEncounterTrigger",
		boss_trigger.get("size", Vector2.ZERO) as Vector2
	)
	var boss_template_count := _assign_encounter_template(boss_room, &"boss", _current_layer())
	if boss_template_count > 0:
		_spawn_count_by_encounter[&"boss"] = boss_template_count
	for room in room_queries.rooms_root.get_children():
		if room is not RoomBase:
			continue
		var r := room as RoomBase
		if not _room_should_register_encounter(r):
			continue
		var encounter_id := StringName("arena_%s" % [String(r.name)])
		var trigger_name := "ArenaEncounterTrigger_%s" % [String(r.name)]
		_cache_entry_socket_for_encounter(r, encounter_id)
		_cache_locked_sockets_for_encounter(r, encounter_id)
		var trigger_pos := r.global_position
		var trigger_sz := Vector2.ZERO
		if r.name == combat_room_name and combat_entry_socket.length_squared() > 0.01:
			# Fire once the player is well inside the arena (entry socket is excluded from pull-in clamps).
			var inward := (-_direction_vector(combat_entry_dir)).normalized()
			trigger_pos = combat_entry_socket + inward * (_DOOR_SLAB_HALF + _COMBAT_ENTRY_TRIGGER_INSET)
			trigger_sz = _encounter_entry_trigger_size(combat_entry_dir)
		var trigger_config := _encounter_trigger_config_for_room(
			r,
			encounter_id,
			trigger_pos,
			trigger_sz
		)
		_spawn_encounter_trigger(
			trigger_config.get("position", trigger_pos) as Vector2,
			encounter_id,
			trigger_name,
			trigger_config.get("size", trigger_sz) as Vector2
		)
		var authored_spawn_count := _spawn_authored_enemy_points_for_room(r, encounter_id)
		if authored_spawn_count <= 0:
			_spawn_arena_modules_for_room(r, encounter_id)
		var template_spawn_count := _assign_encounter_template(r, encounter_id, _current_layer())
		if template_spawn_count > 0:
			_spawn_count_by_encounter[encounter_id] = template_spawn_count
		elif authored_spawn_count > 0:
			_spawn_count_by_encounter[encounter_id] = authored_spawn_count
		else:
			_spawn_count_by_encounter[encounter_id] = rng.randi_range(2, 4)
		_encounter_active[encounter_id] = false
		_encounter_completed[encounter_id] = false
		_encounter_mobs[encounter_id] = []
		if r.name == combat_room_name:
			_combat_encounter_id = encounter_id

	var boss_spawn_count := _spawn_authored_enemy_points_for_room(boss_room, &"boss")
	if boss_spawn_count > 0:
		_spawn_count_by_encounter[&"boss"] = boss_spawn_count
	else:
		var boss_half := _room_half_extents(boss_room)
		var bpx := maxf(5.0, boss_half.x - 12.0)
		var bpy := maxf(5.0, boss_half.y - 12.0)
		_spawn_enemy_spawn_point(boss_center + Vector2(-bpx, -bpy), &"boss")
		_spawn_enemy_spawn_point(boss_center + Vector2(bpx, bpy), &"boss")
		var boss_vol_size := Vector2(maxf(16.0, boss_half.x * 0.4), maxf(12.0, boss_half.y * 0.35))
		_spawn_enemy_spawn_volume(boss_center + Vector2(-bpx, bpy), boss_vol_size, &"boss")
	boss_setup_requested.emit(boss_room, boss_center)
	if prespawn_mobs:
		_prespawn_encounter_mobs()


func _cache_locked_sockets_for_encounter(room: RoomBase, encounter_id: StringName) -> void:
	if room == null or door_lock_controller == null:
		return
	var exclude_socket := _entry_socket_by_encounter.get(encounter_id, Vector2.ZERO) as Vector2
	var exclude_dir := String(_entry_socket_dir_by_encounter.get(encounter_id, ""))
	door_lock_controller.cache_room_locks(
		room,
		encounter_id,
		_door_visual_by_socket_key,
		exclude_socket,
		exclude_dir
	)


func _socket_pos_key(p: Vector2) -> String:
	var qx := int(roundf(p.x * 100.0))
	var qy := int(roundf(p.y * 100.0))
	return "%s:%s" % [qx, qy]


func _apply_encounter_door_visuals_locked(
	encounter_id: StringName, locked: bool, animate: bool = true
) -> void:
	if door_lock_controller == null:
		return
	door_lock_controller.set_encounter_visuals_locked(encounter_id, locked, animate)


func _set_encounter_door_visuals_locked(encounter_id: StringName, locked: bool, animate: bool = true) -> void:
	_apply_encounter_door_visuals_locked(encounter_id, locked, animate)
	if (
		_is_server()
		and _can_broadcast_replication()
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
	encounter_modules_root.add_child(trigger)


func _spawn_enemy_spawn_point(
	position_2d: Vector2,
	encounter_id: StringName,
	enemy_id: StringName = &"",
	authored_marker := false
) -> void:
	var point := SPAWN_POINT_SCENE.instantiate() as EnemySpawnPoint2D
	if point == null:
		return
	point.encounter_id = encounter_id
	point.enemy_id = enemy_id
	point.position = position_2d
	if authored_marker:
		point.set_meta(&"authored_marker", true)
	encounter_modules_root.add_child(point)
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
	encounter_modules_root.add_child(volume)
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


func _spawn_authored_enemy_points_for_room(room: RoomBase, encounter_id: StringName) -> int:
	if room == null:
		return 0
	var room_name := StringName(room.name)
	var spawn_markers := _zone_markers(room_name, "enemy_spawn")
	var spawned_count := 0
	for marker in spawn_markers:
		var position := marker.get("world_position", Vector2.ZERO) as Vector2
		_spawn_enemy_spawn_point(
			position,
			encounter_id,
			marker.get("enemy_id", &"") as StringName,
			true
		)
		spawned_count += 1
	return spawned_count


func _room_should_register_encounter(room: RoomBase) -> bool:
	if room == null:
		return false
	if room.room_type == "arena":
		return true
	return not _zone_markers(StringName(room.name), "enemy_spawn").is_empty()


func _assign_encounter_template(room: RoomBase, encounter_id: StringName, layer: int) -> int:
	if room == null:
		return 0
	_ensure_encounter_run_manager()
	if _encounter_run_manager == null:
		return 0
	var selection: Dictionary = _encounter_run_manager.choose_template(layer, room.room_tags)
	var template = selection.get("template", null)
	if template == null:
		return 0
	var spawn_plan: Array = _encounter_run_manager.resolve_template_spawns(template)
	if spawn_plan.is_empty():
		return 0
	_encounter_template_by_encounter[encounter_id] = template
	_encounter_spawn_plan_by_encounter[encounter_id] = spawn_plan
	print(
		"EncounterTemplate selected room=%s encounter=%s template=%s display=%s repeated=%s stage=%s tags=%s" % [
			String(room.name),
			String(encounter_id),
			String(template.id),
			template.display_name,
			bool(selection.get("repeated", false)),
			String(selection.get("stage", "")),
			_packed_tags_text(room.room_tags),
		]
	)
	return spawn_plan.size()


func _encounter_trigger_config_for_room(
	room: RoomBase,
	encounter_id: StringName,
	fallback_position: Vector2,
	fallback_size: Vector2 = Vector2.ZERO
) -> Dictionary:
	if room == null:
		return {"position": fallback_position, "size": fallback_size}
	var markers := _zone_markers(StringName(room.name), "encounter_trigger", &"entry")
	if markers.is_empty():
		return {"position": fallback_position, "size": fallback_size}
	var direction := String(_entry_socket_dir_by_encounter.get(encounter_id, ""))
	return {
		"position": markers[0].get("world_position", fallback_position) as Vector2,
		"size": _encounter_entry_trigger_size(direction),
	}


func _encounter_entry_trigger_size(direction: String) -> Vector2:
	match direction:
		"west", "east":
			return Vector2(6.0, _DOOR_CLAMP_Y_EXT * 2.0 + 2.0)
		"north", "south":
			return Vector2(_DOOR_CLAMP_Y_EXT * 2.0 + 2.0, 6.0)
		_:
			return Vector2(6.0, 14.0)


func _on_encounter_triggered(encounter_id: StringName) -> void:
	if not _is_authoritative():
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
		# Orchestrator handles combat-start side effects.
		encounter_started.emit(encounter_id, true)
		pass
	else:
		encounter_started.emit(encounter_id, false)
	if (_encounter_mobs.get(encounter_id, []) as Array).is_empty():
		var count := int(_spawn_count_by_encounter.get(encounter_id, rng.randi_range(2, 4)))
		_spawn_encounter_wave(encounter_id, clampi(count, 2, 4), _encounter_speed_multiplier(false))


func _start_boss_encounter() -> void:
	encounter_started.emit(&"boss", false)
	_encounter_active[&"boss"] = true
	_set_encounter_door_visuals_locked(&"boss", true, true)
	_set_encounter_mobs_aggro(&"boss", true)
	pass
	pass
	if (_encounter_mobs.get(&"boss", []) as Array).is_empty():
		var raw_count := 2 + int(floor(float(floor_index - 1) / 2.0))
		var adjusted_count := maxi(1, int(ceili(float(raw_count) * 0.5)))
		_spawn_encounter_wave(
			&"boss",
			int(_spawn_count_by_encounter.get(&"boss", adjusted_count)),
			_encounter_speed_multiplier(true)
		)


func _encounter_speed_multiplier(is_boss: bool) -> float:
	var base := 1.25 if is_boss else 1.0
	var per_floor := 0.05 if is_boss else _SPEED_SCALE_PER_FLOOR
	var cap := _SPEED_SCALE_MAX_BOSS if is_boss else _SPEED_SCALE_MAX_ARENA
	return minf(base + float(floor_index - 1) * per_floor, cap)


func _spawn_encounter_wave(encounter_id: StringName, total_count: int, speed_multiplier: float) -> void:
	if not _planned_tower_positions_by_encounter.has(encounter_id):
		_planned_tower_positions_by_encounter[encounter_id] = []
	var spawned := 0
	var points: Array = _spawn_points_by_encounter.get(encounter_id, []) as Array
	var volumes: Array = _spawn_volumes_by_encounter.get(encounter_id, []) as Array
	var player_pos := _reference_player_position()
	var spawn_plan: Array = _encounter_spawn_plan_by_encounter.get(encounter_id, []) as Array
	var use_spawn_plan := not spawn_plan.is_empty()
	var planned_scenes: Array[PackedScene] = []
	if not use_spawn_plan:
		if total_count >= 1:
			planned_scenes.append(_pick_melee_enemy_scene(encounter_id))
		if total_count >= 2:
			planned_scenes.append(_pick_ranged_enemy_scene(encounter_id))
		if total_count >= 3:
			planned_scenes.append(_pick_random_primary_family_scene())
		for i in range(planned_scenes.size(), total_count):
			planned_scenes.append(_pick_enemy_scene(encounter_id))
		planned_scenes.shuffle()
	for point_node in points:
		if spawned >= total_count:
			break
		if point_node is EnemySpawnPoint2D:
			var point := point_node as EnemySpawnPoint2D
			var spawn_config: Dictionary = {}
			var scene_for_spawn: PackedScene = null
			if use_spawn_plan:
				var planned_spawn := _enemy_spawn_spec_from_plan_entry(spawn_plan[spawned % spawn_plan.size()] as Dictionary)
				scene_for_spawn = planned_spawn.get("scene", null) as PackedScene
				spawn_config = (planned_spawn.get("config", {}) as Dictionary).duplicate(true)
			else:
				scene_for_spawn = (
					_enemy_scene_from_id(point.enemy_id)
					if point.enemy_id != &""
					else planned_scenes[spawned] if spawned < planned_scenes.size() else null
				)
			if not use_spawn_plan and point.enemy_id != &"":
				var spec := _enemy_spawn_spec_from_id(point.enemy_id)
				if not spec.is_empty():
					scene_for_spawn = spec.get("scene", scene_for_spawn) as PackedScene
					spawn_config = (spec.get("config", {}) as Dictionary).duplicate(true)
			var pos := point.get_spawn_position()
			pos = _prepare_encounter_spawn_position(encounter_id, pos, scene_for_spawn)
			_spawn_encounter_mob(
				encounter_id,
				pos,
				player_pos,
				speed_multiplier,
				scene_for_spawn,
				false,
				spawn_config
			)
			spawned += 1
	while spawned < total_count:
		var spawn_config: Dictionary = {}
		var scene_for_spawn: PackedScene = null
		if use_spawn_plan:
			var planned_spawn := _enemy_spawn_spec_from_plan_entry(spawn_plan[spawned % spawn_plan.size()] as Dictionary)
			scene_for_spawn = planned_spawn.get("scene", null) as PackedScene
			spawn_config = (planned_spawn.get("config", {}) as Dictionary).duplicate(true)
		else:
			scene_for_spawn = planned_scenes[spawned] if spawned < planned_scenes.size() else null
		var vpos := _fallback_spawn_position_for_encounter(encounter_id)
		if not volumes.is_empty():
			var volume_idx := rng.randi_range(0, volumes.size() - 1)
			var volume := volumes[volume_idx] as EnemySpawnVolume2D
			if volume != null:
				vpos = volume.sample_spawn_position()
		vpos = _prepare_encounter_spawn_position(encounter_id, vpos, scene_for_spawn)
		_spawn_encounter_mob(
			encounter_id,
			vpos,
			player_pos,
			speed_multiplier,
			scene_for_spawn,
			false,
			spawn_config
		)
		spawned += 1


func _spawn_encounter_mob(
	encounter_id: StringName,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	enemy_scene: PackedScene = null,
	start_aggro := false,
	spawn_config: Dictionary = {}
) -> void:
	_pending_enemy_spawn_requests.append(
		{
			"encounter_id": encounter_id,
			"spawn_position": spawn_position,
			"target_position": target_position,
			"speed_multiplier": speed_multiplier,
			"enemy_scene": enemy_scene,
			"start_aggro": start_aggro,
			"spawn_config": spawn_config.duplicate(true),
		}
	)
	if _pending_enemy_spawn_requests.size() == 1:
		_encounter_spawn_queue_time_remaining = 0.0


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
	if not is_inside_tree() or not _is_server() or enemy_scene == null:
		return
	_spawn_encounter_mob(
		encounter_id,
		spawn_position,
		target_position,
		speed_multiplier,
		enemy_scene,
		start_aggro,
		spawn_config
	)


func _spawn_encounter_mob_deferred(
	encounter_id: StringName,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	enemy_scene: PackedScene = null,
	start_aggro := false,
	spawn_config: Dictionary = {}
) -> void:
	var resolved_encounter_id := _resolve_encounter_for_spawn(encounter_id, spawn_position)
	var scene_to_spawn := enemy_scene if enemy_scene != null else _pick_enemy_scene(encounter_id)
	var scene_kind := _enemy_scene_kind_from_scene(scene_to_spawn)
	var net_id := _next_enemy_network_id()
	var enemy := scene_to_spawn.instantiate() as EnemyBase
	if enemy == null:
		return
	_apply_enemy_spawn_config(enemy, spawn_config)
	enemy.apply_speed_multiplier(speed_multiplier)
	enemy.configure_spawn(spawn_position, target_position)
	_register_enemy_network_id(enemy, net_id)
	world_2d.add_child(enemy)
	var encounter_is_active := bool(_encounter_active.get(resolved_encounter_id, false))
	var final_aggro := start_aggro or encounter_is_active
	enemy.set_aggro_enabled(final_aggro)
	_register_encounter_enemy(resolved_encounter_id, enemy)
	if _is_server() and _can_broadcast_replication():
		_rpc_spawn_enemy.rpc(
			net_id,
			String(resolved_encounter_id),
			scene_kind,
			spawn_position,
			target_position,
			speed_multiplier,
			final_aggro,
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
	if not _is_authoritative():
		return null
	var scene_to_spawn := _enemy_scene_from_kind(scene_kind)
	if scene_to_spawn == null:
		return null
	var resolved_encounter_id := _resolve_encounter_for_spawn(encounter_id, spawn_position)
	var net_id := _next_enemy_network_id()
	var enemy := scene_to_spawn.instantiate() as EnemyBase
	if enemy == null:
		return null
	_apply_enemy_spawn_config(enemy, spawn_config)
	enemy.apply_speed_multiplier(speed_multiplier)
	enemy.configure_spawn(spawn_position, target_position)
	_register_enemy_network_id(enemy, net_id)
	world_2d.add_child(enemy)
	var encounter_is_active := bool(_encounter_active.get(resolved_encounter_id, false))
	var final_aggro := start_aggro or encounter_is_active
	enemy.set_aggro_enabled(final_aggro)
	_register_encounter_enemy(resolved_encounter_id, enemy)
	if _is_server() and _can_broadcast_replication():
		_rpc_spawn_enemy.rpc(
			net_id,
			String(resolved_encounter_id),
			scene_kind,
			spawn_position,
			target_position,
			speed_multiplier,
			final_aggro,
			spawn_config
		)
	return enemy


func flush_spawn_queue(delta: float) -> void:
	if _pending_enemy_spawn_requests.is_empty():
		return
	_encounter_spawn_queue_time_remaining -= delta
	if _encounter_spawn_queue_time_remaining > 0.0:
		return
	var request := _pending_enemy_spawn_requests.pop_front() as Dictionary
	_spawn_encounter_mob_deferred(
		request.get("encounter_id", &"") as StringName,
		request.get("spawn_position", Vector2.ZERO) as Vector2,
		request.get("target_position", Vector2.ZERO) as Vector2,
		float(request.get("speed_multiplier", 1.0)),
		request.get("enemy_scene", null) as PackedScene,
		bool(request.get("start_aggro", false)),
		(request.get("spawn_config", {}) as Dictionary).duplicate(true)
	)
	_encounter_spawn_queue_time_remaining = maxf(0.01, spawn_queue_interval)


func refresh_encounter_state() -> void:
	_refresh_encounter_state()


func _set_encounter_mobs_aggro(encounter_id: StringName, enabled: bool) -> void:
	var mobs: Array = _encounter_mobs.get(encounter_id, []) as Array
	for mob in mobs:
		if mob is EnemyBase and is_instance_valid(mob):
			(mob as EnemyBase).set_aggro_enabled(enabled)
	if _is_server() and _can_broadcast_replication():
		_rpc_set_encounter_aggro.rpc(String(encounter_id), enabled)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_enemy(
	net_id: int,
	encounter_id_text: String,
	scene_kind: int,
	spawn_position: Vector2,
	target_position: Vector2,
	speed_multiplier: float,
	aggro_enabled: bool,
	spawn_config: Dictionary = {}
) -> void:
	if _is_authoritative():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var existing_v: Variant = _enemy_nodes_by_network_id.get(net_id, null)
	if existing_v is EnemyBase and is_instance_valid(existing_v):
		var existing_enemy := existing_v as EnemyBase
		_apply_enemy_spawn_config(existing_enemy, spawn_config)
		existing_enemy.set_aggro_enabled(aggro_enabled)
		return
	var scene_to_spawn := _enemy_scene_from_kind(scene_kind)
	if scene_to_spawn == null:
		return
	var enemy := scene_to_spawn.instantiate() as EnemyBase
	if enemy == null:
		return
	var encounter_id := StringName(encounter_id_text)
	_apply_enemy_spawn_config(enemy, spawn_config)
	enemy.apply_speed_multiplier(speed_multiplier)
	enemy.configure_spawn(spawn_position, target_position)
	_register_enemy_network_id(enemy, net_id)
	world_2d.add_child(enemy)
	enemy.set_aggro_enabled(aggro_enabled)
	_register_encounter_enemy(encounter_id, enemy)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_despawn_enemy(net_id: int) -> void:
	if _is_authoritative():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var enemy_v: Variant = _enemy_nodes_by_network_id.get(net_id, null)
	if enemy_v is EnemyBase and is_instance_valid(enemy_v):
		(enemy_v as EnemyBase).queue_free()
	_enemy_nodes_by_network_id.erase(net_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_enemy_transform_batch(updates: Array) -> void:
	if _is_authoritative():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	for entry in updates:
		if entry is not Array or (entry as Array).size() < 4:
			continue
		var row := entry as Array
		var net_id := int(row[0])
		var enemy_v: Variant = _enemy_nodes_by_network_id.get(net_id, null)
		if enemy_v is not EnemyBase or not is_instance_valid(enemy_v):
			continue
		var enemy := enemy_v as EnemyBase
		if enemy.has_method(&"apply_remote_enemy_transform_state"):
			enemy.call(&"apply_remote_enemy_transform_state", row[1], row[2], row[3])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_encounter_aggro(encounter_id_text: String, enabled: bool) -> void:
	if _is_authoritative():
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
	if _is_authoritative():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_encounter_door_visuals_locked(StringName(encounter_id_text), locked, animate)

func _prespawn_encounter_mobs() -> void:
	for encounter_key in _spawn_count_by_encounter.keys():
		var encounter_id := encounter_key as StringName
		var count := clampi(int(_spawn_count_by_encounter.get(encounter_id, 0)), 0, 4)
		if count > 0:
			var speed_multiplier := _encounter_speed_multiplier(encounter_id == &"boss")
			_spawn_encounter_wave(encounter_id, count, speed_multiplier)
	if not _spawn_count_by_encounter.has(&"boss"):
		var raw_count := 2 + int(floor(float(floor_index - 1) / 2.0))
		var adjusted_count := maxi(1, int(ceili(float(raw_count) * 0.5)))
		_spawn_encounter_wave(&"boss", adjusted_count, _encounter_speed_multiplier(true))


func _cache_entry_socket_for_encounter(room: RoomBase, encounter_id: StringName) -> void:
	if room == null:
		return
	var room_rot := int(round(room.rotation_degrees))
	# Prefer the explicit entrance marker. Proximity to start_room can pick the wrong socket when
	# rooms are placed at non-zero rotation (e.g. 180° swaps entrance and exit positions in world space).
	for socket in room.get_all_sockets():
		if socket.connector_type == &"inactive":
			continue
		if socket.marker_kind == "entrance":
			_entry_socket_by_encounter[encounter_id] = socket.global_position
			_entry_socket_dir_by_encounter[encounter_id] = RoomTransformUtils.rotate_direction(
				String(socket.direction), room_rot
			)
			return
	# Fallback: room has no entrance marker — use closest socket to start room.
	var start_center := _room_center_2d(_layout_room_name("start_room"))
	var best_socket := room.global_position
	var best_dist := 1.0e12
	var best_dir := ""
	for socket in room.get_all_sockets():
		if socket.connector_type == &"inactive":
			continue
		var world_pos := socket.global_position
		var d := world_pos.distance_squared_to(start_center)
		if d < best_dist:
			best_dist = d
			best_socket = world_pos
			best_dir = RoomTransformUtils.rotate_direction(String(socket.direction), room_rot)
	_entry_socket_by_encounter[encounter_id] = best_socket
	_entry_socket_dir_by_encounter[encounter_id] = best_dir


func _bias_spawn_to_back_half(encounter_id: StringName, candidate_pos: Vector2) -> Vector2:
	var room_name := _room_name_for_encounter(encounter_id)
	if room_name == &"":
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
	return _clamp_pos_to_room(room, adjusted)


func _prepare_encounter_spawn_position(
	encounter_id: StringName, candidate_pos: Vector2, scene_for_spawn: PackedScene
) -> Vector2:
	var room_name := _room_name_for_encounter(encounter_id)
	var room := _room_by_name(room_name)
	var pos := _bias_spawn_to_exit_side(encounter_id, candidate_pos)
	if scene_for_spawn == EnemySpawnByEnemyId.ARROW_TOWER_SCENE:
		pos = _tower_spawn_near_center(encounter_id, pos)
		pos = _separate_tower_spawn(encounter_id, pos)
		_register_planned_tower_spawn(encounter_id, pos)
	if room != null:
		pos = _clamp_pos_to_room(room, pos)
	return pos


func _fallback_spawn_position_for_encounter(encounter_id: StringName) -> Vector2:
	var room_name := _room_name_for_encounter(encounter_id)
	var room := _room_by_name(room_name)
	if room == null:
		return _reference_player_position()
	var half := _room_half_extents(room)
	var usable_half := Vector2(maxf(1.0, half.x * 0.55), maxf(1.0, half.y * 0.55))
	var candidate := room.global_position + Vector2(
		rng.randf_range(-usable_half.x, usable_half.x),
		rng.randf_range(-usable_half.y, usable_half.y)
	)
	return _clamp_pos_to_room(room, candidate)


func _bias_spawn_to_exit_side(encounter_id: StringName, candidate_pos: Vector2) -> Vector2:
	var room_name := _room_name_for_encounter(encounter_id)
	if room_name == &"":
		return candidate_pos
	var room := _room_by_name(room_name)
	if room == null:
		return candidate_pos
	var exit_dir := _encounter_exit_direction(encounter_id)
	if exit_dir.is_empty():
		return _bias_spawn_to_back_half(encounter_id, candidate_pos)
	var exit_dir_vec := _direction_vector(exit_dir).normalized()
	if exit_dir_vec.length_squared() <= 0.0001:
		return _bias_spawn_to_back_half(encounter_id, candidate_pos)
	var half := _room_half_extents(room)
	var exit_limit := maxf(2.5, maxf(half.x, half.y) * _BACK_HALF_MIN_RATIO)
	var rel := candidate_pos - room.global_position
	var dot_exit := rel.dot(exit_dir_vec)
	if dot_exit >= exit_limit:
		return _clamp_pos_to_room(room, candidate_pos)
	var adjusted := candidate_pos + exit_dir_vec * (exit_limit - dot_exit)
	return _clamp_pos_to_room(room, adjusted)


func _encounter_exit_direction(encounter_id: StringName) -> String:
	var id_text := String(encounter_id)
	if id_text == "boss":
		return ""
	var room_name := _room_name_for_encounter(encounter_id)
	if room_name == &"":
		return ""
	var room := _room_by_name(room_name)
	if room == null:
		return ""
	var room_rot := int(round(room.rotation_degrees))
	for socket in room.get_all_sockets():
		if socket.connector_type == &"inactive":
			continue
		if socket.marker_kind == "exit":
			return RoomTransformUtils.rotate_direction(String(socket.direction), room_rot)
	if room_name == _layout_room_name("combat_room"):
		return combat_exit_dir
	return ""


func _enemy_spawn_spec_from_plan_entry(entry: Dictionary) -> Dictionary:
	var enemy_id := entry.get("enemy_id", &"") as StringName
	var spec := _enemy_spawn_spec_from_id(enemy_id)
	var scene := spec.get("scene", null) as PackedScene
	var config := (spec.get("config", {}) as Dictionary).duplicate(true)
	if scene == null:
		scene = _enemy_scene_from_id(enemy_id)
	return {
		"scene": scene,
		"config": config,
	}


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


func _pick_enemy_scene(_encounter_id: StringName) -> PackedScene:
	return _pick_random_primary_family_scene()


func _pick_melee_enemy_scene(_encounter_id: StringName) -> PackedScene:
	return _pick_scene_from_pool(EnemySpawnByEnemyId.melee_family_scenes())


func _pick_ranged_enemy_scene(_encounter_id: StringName) -> PackedScene:
	return _pick_scene_from_pool(EnemySpawnByEnemyId.ranged_family_scenes())


func _enemy_scene_from_id(enemy_id: StringName) -> PackedScene:
	var resolved := EnemySpawnByEnemyId.scene_for_enemy_id(enemy_id)
	if resolved != null:
		return resolved
	return _pick_random_primary_family_scene()


func _enemy_spawn_spec_from_id(enemy_id: StringName) -> Dictionary:
	var spec := EnemySpawnByEnemyId.spawn_spec_for_enemy_id(enemy_id)
	if spec is Dictionary:
		return (spec as Dictionary).duplicate(true)
	return {}


func _apply_enemy_spawn_config(enemy: EnemyBase, spawn_config: Dictionary) -> void:
	if enemy == null or spawn_config.is_empty():
		return
	if enemy.has_method(&"configure_ranged_family"):
		enemy.call(&"configure_ranged_family", spawn_config)


func _enemy_spawn_config_from_instance(enemy: EnemyBase) -> Dictionary:
	if enemy != null and enemy.has_method(&"get_enemy_spawn_config"):
		var config_v: Variant = enemy.call(&"get_enemy_spawn_config")
		if config_v is Dictionary:
			return (config_v as Dictionary).duplicate(true)
	return {}


func _room_name_for_encounter(encounter_id: StringName) -> StringName:
	var id_text := String(encounter_id)
	if id_text == "boss":
		return _layout_room_name("exit_room")
	if id_text.begins_with("arena_"):
		return StringName(id_text.trim_prefix("arena_"))
	return &""


func _on_encounter_mob_removed(encounter_id: StringName, mob: EnemyBase) -> void:
	var mobs = _encounter_mobs.get(encounter_id)
	if mobs is Array:
		(mobs as Array).erase(mob)
	var net_id := -1
	if mob != null and mob.has_meta(&"enemy_network_id"):
		net_id = int(mob.get_meta(&"enemy_network_id", -1))
	if net_id > 0:
		_enemy_nodes_by_network_id.erase(net_id)
		if _is_server() and _can_broadcast_replication():
			_rpc_despawn_enemy.rpc(net_id)


func _refresh_encounter_state() -> void:
	for encounter_key in _encounter_active.keys():
		var encounter_id := encounter_key as StringName
		if not bool(_encounter_active[encounter_id]):
			continue
		var mobs: Array = _encounter_mobs.get(encounter_id, []) as Array
		# Remove stale refs in-place — no Array allocation.
		var i := mobs.size() - 1
		while i >= 0:
			if not is_instance_valid(mobs[i]):
				mobs.remove_at(i)
			i -= 1
		if mobs.is_empty():
			_complete_encounter(encounter_id)


func _complete_encounter(encounter_id: StringName) -> void:
	_encounter_active[encounter_id] = false
	_encounter_completed[encounter_id] = true
	match String(encounter_id):
		"boss":
			# Orchestrator handles boss-clear side effects.
			_set_encounter_door_visuals_locked(encounter_id, false, true)
			pass
			encounter_cleared.emit(encounter_id, true, false)
			pass
		_:
			if String(encounter_id).begins_with("arena_"):
				_set_encounter_door_visuals_locked(encounter_id, false, true)
				if encounter_id == _combat_encounter_id:
					# Orchestrator handles combat-clear side effects.
					encounter_cleared.emit(encounter_id, false, true)
					pass
				else:
					encounter_cleared.emit(encounter_id, false, false)

