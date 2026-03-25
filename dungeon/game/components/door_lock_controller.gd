extends Node
class_name DoorLockController

var door_slab_half := 3.0
var door_clamp_y_ext := 7.02
## Set from dungeon root: `Callable` taking CharacterBody2D, returning current room name String (or compatible).
var resolve_room_name_for_body: Callable = Callable()

var _locked_sockets_by_encounter: Dictionary = {}
var _locked_door_visuals_by_encounter: Dictionary = {}


func clear_encounter_locks() -> void:
	_locked_sockets_by_encounter.clear()
	_locked_door_visuals_by_encounter.clear()


func cache_room_locks(
	room: RoomBase,
	encounter_id: StringName,
	door_visual_by_socket_key: Dictionary,
	exclude_clamp_socket_world: Vector2 = Vector2.ZERO,
	exclude_clamp_dir: String = ""
) -> void:
	if room == null:
		return
	var sockets: Array[Dictionary] = []
	var visuals: Array[DungeonCellDoor3D] = []
	var exclude_clamp := exclude_clamp_socket_world.length_squared() > 0.0001 and exclude_clamp_dir != ""
	for socket in room.get_all_sockets():
		if socket.connector_type == &"inactive":
			continue
		var world_pos := room.global_position + socket.position
		var dir := String(socket.direction)
		if exclude_clamp:
			if dir == exclude_clamp_dir and world_pos.distance_squared_to(exclude_clamp_socket_world) < 0.49:
				# Entry socket is intentionally left open; only exit/other encounter doors lock.
				continue
		var entry := {"pos": world_pos, "dir": dir}
		sockets.append(entry)
		var dk := _socket_pos_key(world_pos)
		if door_visual_by_socket_key.has(dk):
			var vis := door_visual_by_socket_key[dk] as DungeonCellDoor3D
			if vis != null and not visuals.has(vis):
				visuals.append(vis)
	_locked_sockets_by_encounter[encounter_id] = sockets
	_locked_door_visuals_by_encounter[encounter_id] = visuals


func set_encounter_visuals_locked(encounter_id: StringName, locked: bool, animate: bool = true) -> void:
	var visuals: Array = _locked_door_visuals_by_encounter.get(encounter_id, []) as Array
	for v in visuals:
		if v is DungeonCellDoor3D:
			(v as DungeonCellDoor3D).set_runtime_locked(locked, animate)


func apply_hard_door_clamps(
	player: CharacterBody2D,
	puzzle_solved: bool,
	puzzle_gate_socket: Vector2,
	puzzle_gate_dir: String,
	encounter_active: Dictionary,
	player_radius: float,
	mob_radius: float,
	mob_bodies: Array[CharacterBody2D]
) -> void:
	if player == null:
		return
	if not puzzle_solved and puzzle_gate_socket != Vector2.ZERO:
		_clamp_to_locked_socket(player, player_radius, puzzle_gate_socket, puzzle_gate_dir)
	for encounter_key in encounter_active.keys():
		var encounter_id := encounter_key as StringName
		if not bool(encounter_active.get(encounter_id, false)):
			continue
		_clamp_encounter_doors(player, player_radius, encounter_id)
		for mob in mob_bodies:
			if not _mob_matches_encounter(mob, encounter_id):
				continue
			_clamp_encounter_doors(mob, mob_radius, encounter_id)


func _clamp_encounter_doors(body: CharacterBody2D, radius: float, encounter_id: StringName) -> void:
	if body == null:
		return
	var sockets: Array = _locked_sockets_by_encounter.get(encounter_id, []) as Array
	for s_variant in sockets:
		if s_variant is not Dictionary:
			continue
		var s := s_variant as Dictionary
		_clamp_to_locked_socket(
			body,
			radius,
			s.get("pos", Vector2.ZERO) as Vector2,
			String(s.get("dir", ""))
		)


func _clamp_to_locked_socket(
	body: CharacterBody2D,
	radius: float,
	socket_pos: Vector2,
	door_direction: String
) -> void:
	if body == null:
		return
	var p := body.global_position
	var v := body.velocity
	var changed := false
	match door_direction:
		"west":
			if absf(p.y - socket_pos.y) <= door_clamp_y_ext:
				var lim := socket_pos.x + door_slab_half + radius
				if p.x < lim:
					p.x = lim
					v.x = maxf(0.0, v.x)
					changed = true
		"east":
			if absf(p.y - socket_pos.y) <= door_clamp_y_ext:
				var lim := socket_pos.x - door_slab_half - radius
				if p.x > lim:
					p.x = lim
					v.x = minf(0.0, v.x)
					changed = true
		"north":
			if absf(p.x - socket_pos.x) <= door_clamp_y_ext:
				var lim := socket_pos.y + door_slab_half + radius
				if p.y < lim:
					p.y = lim
					v.y = maxf(0.0, v.y)
					changed = true
		"south":
			if absf(p.x - socket_pos.x) <= door_clamp_y_ext:
				var lim := socket_pos.y - door_slab_half - radius
				if p.y > lim:
					p.y = lim
					v.y = minf(0.0, v.y)
					changed = true
		_:
			pass
	if changed:
		body.global_position = p
		body.velocity = v


func _socket_pos_key(p: Vector2) -> String:
	var qx := int(roundf(p.x * 100.0))
	var qy := int(roundf(p.y * 100.0))
	return "%s:%s" % [qx, qy]


func _mob_matches_encounter(mob: CharacterBody2D, encounter_id: StringName) -> bool:
	if mob == null:
		return false
	var mob_encounter := StringName(String(mob.get_meta(&"encounter_id", &"")))
	return mob_encounter == encounter_id
