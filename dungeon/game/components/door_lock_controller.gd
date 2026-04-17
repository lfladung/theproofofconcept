extends Node
class_name DoorLockController

var door_slab_half := 3.0
var door_clamp_y_ext := 7.02
## Set from dungeon root: `Callable` taking CharacterBody2D, returning current room name String (or compatible).
var resolve_room_name_for_body: Callable = Callable()

var _locked_sockets_by_encounter: Dictionary = {}
var _locked_door_visuals_by_encounter: Dictionary = {}
var _named_locked_sockets: Dictionary = {}


func clear_encounter_locks() -> void:
	_locked_sockets_by_encounter.clear()
	_locked_door_visuals_by_encounter.clear()


func clear_named_locks() -> void:
	_named_locked_sockets.clear()


func clear_named_locks_by_prefix(prefix: String) -> void:
	var keys_to_remove: Array[StringName] = []
	for key in _named_locked_sockets.keys():
		var lock_id := StringName(key)
		if String(lock_id).begins_with(prefix):
			keys_to_remove.append(lock_id)
	for lock_id in keys_to_remove:
		_named_locked_sockets.erase(lock_id)


func set_named_lock_sockets(lock_id: StringName, sockets: Array[Dictionary]) -> void:
	if String(lock_id).is_empty():
		return
	if sockets.is_empty():
		_named_locked_sockets.erase(lock_id)
		return
	_named_locked_sockets[lock_id] = sockets.duplicate(true)


func set_named_socket_lock(lock_id: StringName, socket_pos: Vector2, socket_dir: String, locked: bool) -> void:
	set_named_room_socket_lock(lock_id, &"", socket_pos, socket_dir, locked)


func set_named_room_socket_lock(
	lock_id: StringName,
	room_name: StringName,
	socket_pos: Vector2,
	socket_dir: String,
	locked: bool
) -> void:
	if not locked:
		set_named_lock_sockets(lock_id, [])
		return
	if socket_pos == Vector2.ZERO or socket_dir.is_empty():
		set_named_lock_sockets(lock_id, [])
		return
	set_named_lock_sockets(lock_id, [{"pos": socket_pos, "dir": socket_dir, "room_name": room_name}])


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
	var room_rot := int(round(room.rotation_degrees))
	for socket in room.get_all_sockets():
		if socket.connector_type == &"inactive":
			continue
		# Use socket.global_position so room rotation is accounted for.
		var world_pos := socket.global_position
		# Rotate local socket direction to world space.
		var dir := _rotate_direction(String(socket.direction), room_rot)
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
	if player != null and not puzzle_solved and puzzle_gate_socket != Vector2.ZERO:
		_clamp_to_locked_socket(player, player_radius, puzzle_gate_socket, puzzle_gate_dir)
	for encounter_key in encounter_active.keys():
		var encounter_id := encounter_key as StringName
		if not bool(encounter_active.get(encounter_id, false)):
			continue
		if player != null:
			_clamp_encounter_doors(player, player_radius, encounter_id)
		for mob in mob_bodies:
			if not _mob_matches_encounter(mob, encounter_id):
				continue
			_clamp_encounter_doors(mob, mob_radius, encounter_id)
	if player != null:
		_clamp_named_locks(player, player_radius)
	for mob in mob_bodies:
		_clamp_named_locks(mob, mob_radius)


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


func _clamp_named_locks(body: CharacterBody2D, radius: float) -> void:
	if body == null:
		return
	var body_room_name := _resolve_body_room_name(body)
	for lock_key in _named_locked_sockets.keys():
		var sockets: Array = _named_locked_sockets.get(lock_key, []) as Array
		for s_variant in sockets:
			if s_variant is not Dictionary:
				continue
			var s := s_variant as Dictionary
			var lock_room_name := StringName(String(s.get("room_name", "")))
			if lock_room_name != &"" and body_room_name != lock_room_name:
				continue
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


func _rotate_direction(direction: String, rotation_deg: int) -> String:
	var dirs := ["north", "east", "south", "west"]
	var idx := dirs.find(direction)
	if idx < 0:
		return direction
	var steps := posmod(posmod(rotation_deg, 360) / 90, 4)
	return dirs[(idx + steps) % 4]


func _resolve_body_room_name(body: CharacterBody2D) -> StringName:
	if body == null or not resolve_room_name_for_body.is_valid():
		return &""
	var value: Variant = resolve_room_name_for_body.call(body)
	return StringName(String(value))


func _mob_matches_encounter(mob: CharacterBody2D, encounter_id: StringName) -> bool:
	if mob == null:
		return false
	var mob_encounter := StringName(String(mob.get_meta(&"encounter_id", &"")))
	return mob_encounter == encounter_id
