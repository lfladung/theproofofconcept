extends Node
class_name HubWorld

const PLAYER_SCENE := preload("res://scenes/entities/player.tscn")
const HUB_ROOM_SCENE := preload("res://dungeon/rooms/authored/hub_room.tscn")
const HUB_ROOM_LAYOUT_PATH := "res://dungeon/rooms/authored/layouts/hub_room.layout.tres"
const MISSION_INTERFACE_SCENE := preload("res://scenes/hub/mission_interface.tscn")
const UPGRADE_AREA_SCENE := preload("res://scenes/hub/upgrade_area.tscn")
const MISSION_SELECT_SCENE := preload("res://scenes/ui/mission_select_ui.tscn")
const ESCAPE_MENU_SCENE := preload("res://scenes/ui/escape_menu.tscn")
const MissionInterfaceScript = preload("res://scripts/hub/mission_interface.gd")
const UpgradeAreaScript = preload("res://scripts/hub/upgrade_area.gd")
const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const PreviewBuilderScript = preload("res://addons/dungeon_room_editor/preview/preview_builder.gd")
const RoomEditorSceneSyncScript = preload("res://addons/dungeon_room_editor/core/scene_sync.gd")
const ROOM_PIECE_CATALOG = preload("res://addons/dungeon_room_editor/resources/default_room_piece_catalog.tres")
const CAMERA_LERP_SPEED := 8.0
const CAMERA_DIAG_PITCH_DEG := -38.0
const CAMERA_DIAG_YAW_DEG := 180.0
const STALE_PLAYER_RPC_GRACE_SECONDS := 1.0

@onready var _game_world_2d: Node2D = $GameWorld2D
@onready var _rooms_root: Node2D = $GameWorld2D/Rooms
@onready var _interactables_root: Node2D = $GameWorld2D/Interactables
@onready var _room_visuals: Node3D = $VisualWorld3D/RoomVisuals
@onready var _camera_pivot: Marker3D = $VisualWorld3D/CameraPivot
@onready var _prompt_label: Label = $CanvasLayer/UI/PromptLabel
@onready var _overlay_root: Control = $CanvasLayer/UI/OverlayRoot

var _preview_builder = PreviewBuilderScript.new()
var _players_by_peer: Dictionary = {}
var _retired_players_by_peer: Dictionary = {}
var _local_player: CharacterBody2D
var _focused_interactable: Node
var _mission_select_ui: Control
var _escape_menu: Control
var _hub_room: RoomBase
var _runtime_scene_ready_sent := false


func _ready() -> void:
	_camera_pivot.rotation_degrees = Vector3(CAMERA_DIAG_PITCH_DEG, CAMERA_DIAG_YAW_DEG, 0.0)
	_spawn_hub_room()
	_spawn_interactables()
	_apply_player_roster_from_slot_map(_current_slot_map())
	var session := _session()
	if session != null and session.has_signal("peer_slot_map_changed"):
		session.peer_slot_map_changed.connect(_on_peer_slot_map_changed)
	_maybe_mark_runtime_scene_ready()
	_prompt_label.visible = false
	_ensure_escape_menu()


func _exit_tree() -> void:
	var session := _session()
	if session != null and session.has_signal("peer_slot_map_changed"):
		if session.peer_slot_map_changed.is_connected(_on_peer_slot_map_changed):
			session.peer_slot_map_changed.disconnect(_on_peer_slot_map_changed)


func _process(delta: float) -> void:
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			if _is_mission_select_open():
				return
			_ensure_escape_menu()
			if _escape_menu != null and _escape_menu.has_method(&"handle_escape") and bool(_escape_menu.call(&"handle_escape")):
				get_viewport().set_input_as_handled()


func _spawn_hub_room() -> void:
	var room := HUB_ROOM_SCENE.instantiate() as RoomBase
	if room == null:
		return
	room.name = "HubRoom"
	room.room_id = "hub_room"
	room.room_type = "safe"
	room.room_tags = PackedStringArray(["safe", "hub"])
	room.safe_room = true
	room.authored_layout = _load_hub_room_layout(room)
	room.set_meta(&"runtime_floor_theme", "tile")
	room.set_meta(&"runtime_floor_seed", 1)
	_rooms_root.add_child(room)
	if room.authored_layout != null:
		var sync = RoomEditorSceneSyncScript.new()
		sync.sync_room(room, room.authored_layout, ROOM_PIECE_CATALOG)
		var visual_proxy := room.get_node_or_null(^"Visual3DProxy") as Node3D
		if visual_proxy != null:
			visual_proxy.visible = false
		_rebuild_hub_room_visuals(room)
	_hub_room = room


func _load_hub_room_layout(room: RoomBase) -> Resource:
	if ResourceLoader.exists(HUB_ROOM_LAYOUT_PATH):
		var sidecar_layout := load(HUB_ROOM_LAYOUT_PATH) as Resource
		if sidecar_layout != null:
			return sidecar_layout
	return room.authored_layout if room != null else null


func _spawn_interactables() -> void:
	_spawn_interactable(
		MISSION_INTERFACE_SCENE,
		"MissionInterface",
		&"hub_mission_interface",
		"mission_interface",
		Vector2(-9.0, -18.0)
	)
	_spawn_interactable(
		UPGRADE_AREA_SCENE,
		"UpgradeArea",
		&"hub_upgrade_area",
		"upgrade_area",
		Vector2(12.0, -18.0)
	)


func _spawn_interactable(
	scene: PackedScene,
	node_name: String,
	piece_id: StringName,
	required_tag: String,
	fallback_position: Vector2
) -> void:
	var interactable := scene.instantiate() as HubInteractable
	if interactable == null:
		return
	var placement := _hub_authored_item_position(piece_id, required_tag)
	interactable.name = node_name
	interactable.position = placement.get("position", fallback_position) as Vector2
	if bool(placement.get("authored_visual", false)):
		interactable.visual_scene = null
	_bind_interactable(interactable)
	_interactables_root.add_child(interactable)


func _hub_authored_item_position(piece_id: StringName, required_tag: String) -> Dictionary:
	if _hub_room == null or _hub_room.authored_layout == null:
		return {}
	var items: Array = _hub_room.authored_layout.get("items")
	for item in items:
		if item == null:
			continue
		var item_piece_id := item.get("piece_id") as StringName
		var tags := item.get("tags") as PackedStringArray
		var grid_position := item.get("grid_position") as Vector2i
		if item_piece_id != piece_id and not tags.has(required_tag):
			continue
		var local_position := GridMath.grid_to_local(grid_position, _hub_room.authored_layout, _hub_room)
		return {
			"position": _hub_room.to_global(local_position),
			"authored_visual": true,
		}
	return {}


func _rebuild_hub_room_visuals(room: RoomBase) -> void:
	if room == null or room.authored_layout == null or _room_visuals == null:
		return
	for child in _room_visuals.get_children():
		child.queue_free()
	var container := Node3D.new()
	container.name = "%s_VisualRoot" % String(room.name)
	container.position = Vector3(room.global_position.x, 0.0, room.global_position.y)
	_room_visuals.add_child(container)
	_preview_builder.rebuild_preview(
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


func _bind_interactable(interactable: Node) -> void:
	interactable.local_focus_changed.connect(_on_interactable_focus_changed)
	interactable.local_interacted.connect(_on_interactable_used)


func _current_slot_map() -> Dictionary:
	var session := _session()
	if session != null and session.has_method("get_peer_slot_map"):
		return session.call("get_peer_slot_map") as Dictionary
	return {1: 0}


func _on_peer_slot_map_changed(slot_map: Dictionary) -> void:
	_runtime_scene_ready_sent = false
	_apply_player_roster_from_slot_map(slot_map)
	_maybe_mark_runtime_scene_ready()


func _apply_player_roster_from_slot_map(raw_slot_map: Dictionary) -> void:
	var slot_map := _normalize_slot_map(raw_slot_map)
	if slot_map.is_empty() and _should_use_offline_slot_fallback():
		slot_map[_local_peer_id()] = 0
	var seen: Dictionary = {}
	for peer_id in _peer_ids_sorted_by_slot(slot_map):
		var player_entry := _ensure_player_node_for_peer(peer_id)
		var player := player_entry.get("player", null) as CharacterBody2D
		if player == null:
			continue
		if bool(player_entry.get("created", false)):
			var slot := int(slot_map.get(peer_id, 0))
			_place_player_at_spawn(player, _spawn_position_for_slot(slot))
		_players_by_peer[peer_id] = player
		seen[peer_id] = true
	for key in _players_by_peer.keys():
		var peer_id := int(key)
		if seen.has(peer_id):
			continue
		var stale := _players_by_peer[peer_id] as Node
		if stale != null and is_instance_valid(stale):
			_retire_player_node_for_peer(peer_id, stale)
		_players_by_peer.erase(peer_id)
	_resolve_local_player()


func _ensure_player_node_for_peer(peer_id: int) -> Dictionary:
	var existing := _players_by_peer.get(peer_id, null) as CharacterBody2D
	if existing != null and is_instance_valid(existing):
		_assign_player_authority(existing, peer_id)
		return {"player": existing, "created": false}
	var desired_name := "PlayerPeer_%s" % [peer_id]
	var found := _game_world_2d.get_node_or_null(NodePath(desired_name)) as CharacterBody2D
	if found != null:
		_assign_player_authority(found, peer_id)
		return {"player": found, "created": false}
	var spawned := PLAYER_SCENE.instantiate() as CharacterBody2D
	if spawned == null:
		return {"player": null, "created": false}
	spawned.name = desired_name
	_game_world_2d.add_child(spawned)
	_assign_player_authority(spawned, peer_id)
	return {"player": spawned, "created": true}


func _assign_player_authority(player: CharacterBody2D, peer_id: int) -> void:
	player.set_multiplayer_authority(peer_id, true)
	player.set_meta(&"peer_id", peer_id)
	if player.has_method("set_network_owner_peer_id"):
		player.call("set_network_owner_peer_id", peer_id)


func _retire_player_node_for_peer(peer_id: int, player: Node) -> void:
	_retired_players_by_peer[peer_id] = player
	player.set_meta(&"retired_from_hub_roster", true)
	player.remove_from_group(&"player")
	player.set_process(false)
	player.set_physics_process(false)
	if player is CanvasItem:
		(player as CanvasItem).visible = false
	if player.has_method("set_menu_input_blocked"):
		player.call("set_menu_input_blocked", true)
	if player.has_method("suppress_placeholder_visual"):
		player.call("suppress_placeholder_visual")
	for child in player.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred(&"disabled", true)
		elif child is Area2D:
			(child as Area2D).monitoring = false
			(child as Area2D).monitorable = false
	var tree := get_tree()
	if tree == null:
		player.queue_free()
		return
	tree.create_timer(STALE_PLAYER_RPC_GRACE_SECONDS).timeout.connect(
		_free_retired_player.bind(peer_id, player)
	)


func _free_retired_player(peer_id: int, player: Node) -> void:
	if _retired_players_by_peer.get(peer_id, null) == player:
		_retired_players_by_peer.erase(peer_id)
	if player != null and is_instance_valid(player):
		player.queue_free()


func _resolve_local_player() -> void:
	_local_player = _players_by_peer.get(_local_peer_id(), null) as CharacterBody2D
	_sync_escape_menu_input_block()


func _local_peer_id() -> int:
	var session := _session()
	if session != null and session.has_method("get_local_peer_id"):
		return int(session.call("get_local_peer_id"))
	return 1


func _should_use_offline_slot_fallback() -> bool:
	var session := _session()
	if session == null:
		return true
	if not (session.has_method("has_active_peer") and bool(session.call("has_active_peer"))):
		return true
	return false


func _maybe_mark_runtime_scene_ready() -> void:
	if _runtime_scene_ready_sent:
		return
	var session := _session()
	if session == null or not session.has_method("mark_runtime_scene_ready_local"):
		return
	if session.has_method("has_active_peer") and not bool(session.call("has_active_peer")):
		return
	if _local_player == null or not is_instance_valid(_local_player):
		return
	var slot_map := _current_slot_map()
	if not slot_map.has(_local_peer_id()):
		return
	_runtime_scene_ready_sent = true
	session.call("mark_runtime_scene_ready_local")


func _should_assign_initial_spawn(peer_id: int) -> bool:
	var session := _session()
	if session == null or not (session.has_method("has_active_peer") and bool(session.call("has_active_peer"))):
		return true
	if multiplayer.is_server():
		return true
	return peer_id == _local_peer_id()


func _place_player_at_spawn(player: CharacterBody2D, spawn_position: Vector2) -> void:
	if player == null:
		return
	if player.has_method(&"set_spawn_position_immediate"):
		player.call(&"set_spawn_position_immediate", spawn_position, true)
		return
	player.global_position = spawn_position
	player.velocity = Vector2.ZERO
	player.set_meta(&"spawn_initialized", true)


func _spawn_position_for_slot(slot: int) -> Vector2:
	var positions := _hub_spawn_positions()
	return positions[clampi(slot, 0, positions.size() - 1)]


func _hub_spawn_positions() -> Array[Vector2]:
	var authored_positions := _hub_authored_positions(&"spawn_player_marker", "player")
	if authored_positions.is_empty():
		authored_positions.append(Vector2(0.0, -30.0))
	var base: Vector2 = authored_positions[0]
	var positions: Array[Vector2] = []
	for position in authored_positions:
		positions.append(position)
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(-4.0, 0.0),
		Vector2(4.0, 0.0),
		Vector2(0.0, 4.0),
		Vector2(-4.0, 4.0),
		Vector2(4.0, 4.0),
	]
	for offset in offsets:
		if positions.size() >= 6:
			break
		var candidate: Vector2 = base + offset
		if not positions.has(candidate):
			positions.append(candidate)
	return positions


func _hub_authored_positions(piece_id: StringName, required_tag: String) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if _hub_room == null or _hub_room.authored_layout == null:
		return positions
	var items: Array = _hub_room.authored_layout.get("items")
	for item in items:
		if item == null:
			continue
		var item_piece_id := item.get("piece_id") as StringName
		var tags := item.get("tags") as PackedStringArray
		if item_piece_id != piece_id and not tags.has(required_tag):
			continue
		var grid_position := item.get("grid_position") as Vector2i
		var local_position := GridMath.grid_to_local(grid_position, _hub_room.authored_layout, _hub_room)
		positions.append(_hub_room.to_global(local_position))
	return positions


func _normalize_slot_map(slot_map: Dictionary) -> Dictionary:
	var out := {}
	for key in slot_map.keys():
		out[int(key)] = int(slot_map[key])
	return out


func _peer_ids_sorted_by_slot(slot_map: Dictionary) -> Array[int]:
	var keyed: Array[Dictionary] = []
	for key in slot_map.keys():
		var peer_id := int(key)
		keyed.append({"peer_id": peer_id, "slot": int(slot_map[key])})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var slot_a := int(a.get("slot", 0))
		var slot_b := int(b.get("slot", 0))
		if slot_a == slot_b:
			return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
		return slot_a < slot_b
	)
	var out: Array[int] = []
	for entry in keyed:
		out.append(int(entry.get("peer_id", 0)))
	return out


func _on_interactable_focus_changed(interactable: Node, focused: bool) -> void:
	if focused:
		if _focused_interactable != null and _focused_interactable != interactable:
			if _focused_interactable.has_method("clear_local_focus"):
				_focused_interactable.call("clear_local_focus")
		_focused_interactable = interactable
		_prompt_label.text = String(interactable.get("prompt_text"))
		_prompt_label.visible = true
		return
	if _focused_interactable == interactable:
		_focused_interactable = null
		_prompt_label.visible = false


func _on_interactable_used(interactable: Node) -> void:
	if interactable.get_script() == MissionInterfaceScript:
		_open_mission_select()
	elif interactable.get_script() == UpgradeAreaScript:
		_prompt_label.text = "Upgrades coming soon"
		_prompt_label.visible = true


func _open_mission_select() -> void:
	if _mission_select_ui != null and is_instance_valid(_mission_select_ui):
		_mission_select_ui.visible = true
		_set_local_player_menu_blocked(true)
		return
	_mission_select_ui = MISSION_SELECT_SCENE.instantiate() as Control
	if _mission_select_ui == null:
		return
	_overlay_root.add_child(_mission_select_ui)
	if _mission_select_ui.has_signal("close_requested"):
		_mission_select_ui.close_requested.connect(_close_mission_select)
	_set_local_player_menu_blocked(true)


func _close_mission_select() -> void:
	if _mission_select_ui != null and is_instance_valid(_mission_select_ui):
		_mission_select_ui.queue_free()
	_mission_select_ui = null
	_set_local_player_menu_blocked(false)


func _set_local_player_menu_blocked(blocked: bool) -> void:
	if _local_player != null and is_instance_valid(_local_player) and _local_player.has_method("set_menu_input_blocked"):
		_local_player.call("set_menu_input_blocked", blocked)


func _ensure_escape_menu() -> void:
	if _escape_menu != null and is_instance_valid(_escape_menu):
		return
	var existing := _overlay_root.get_node_or_null("EscapeMenu") as Control
	if existing != null:
		_escape_menu = existing
	else:
		var overlay := ESCAPE_MENU_SCENE.instantiate() as Control
		if overlay == null:
			return
		overlay.name = "EscapeMenu"
		_overlay_root.add_child(overlay)
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
	_sync_escape_menu_input_block()


func _sync_escape_menu_input_block() -> void:
	if _escape_menu == null or not is_instance_valid(_escape_menu):
		return
	if _escape_menu.has_method(&"is_menu_open"):
		_on_escape_menu_visibility_changed(bool(_escape_menu.call(&"is_menu_open")))


func _on_escape_menu_visibility_changed(open: bool) -> void:
	_set_local_player_menu_blocked(open or _is_mission_select_open())


func _on_escape_menu_back_to_main_requested() -> void:
	var session := _session()
	if session != null and session.has_method("has_active_peer") and bool(session.call("has_active_peer")):
		var role_name := String(session.call("get_role_name")) if session.has_method("get_role_name") else ""
		if role_name == "HOST" and session.has_method("close_lobby_from_host"):
			session.call("close_lobby_from_host")
		elif session.has_method("disconnect_from_session"):
			session.call("disconnect_from_session", true)
		return
	if session != null and session.has_method("disconnect_from_session"):
		session.call("disconnect_from_session", false)
	var err := get_tree().change_scene_to_file("res://scenes/ui/lobby_menu.tscn")
	if err != OK:
		push_warning("Failed to return to main screen (error %s)." % [err])


func _is_mission_select_open() -> bool:
	return _mission_select_ui != null and is_instance_valid(_mission_select_ui) and _mission_select_ui.visible


func _update_camera(delta: float) -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		return
	var target := Vector3(_local_player.global_position.x, 0.0, _local_player.global_position.y)
	_camera_pivot.position = _camera_pivot.position.lerp(target, clampf(delta * CAMERA_LERP_SPEED, 0.0, 1.0))


func _session() -> Node:
	return get_node_or_null("/root/NetworkSession")
