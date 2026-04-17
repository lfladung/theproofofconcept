extends SceneTree

const AuthoredFloorGeneratorScript = preload("res://dungeon/game/floor_generation/authored_floor_generator.gd")
const AuthoredRoomCatalogScript = preload("res://dungeon/game/floor_generation/authored_room_catalog.gd")


func _init() -> void:
	var failures: Array[String] = []
	_verify_legacy_layouts(failures)
	_verify_authored_layouts(failures)
	if failures.is_empty():
		print("ConnectionRoomGateCheck: ok")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _verify_legacy_layouts(failures: Array[String]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10101
	var configs := [
		{},
		{
			"total_rooms_min": 5,
			"total_rooms_max": 5,
			"critical_path_min": 5,
			"critical_path_max": 5,
			"linear_spine_only": true,
		},
	]
	for config in configs:
		var layout := DungeonMapLayoutV1.generate(rng, config)
		if not bool(layout.get("ok", false)):
			failures.append("Legacy layout failed to generate: %s" % [layout])
			continue
		_validate_layout("legacy", layout, failures)
		var level_data := LevelDataV1.from_layout(layout)
		var schema_check := LevelDataV1.validate(level_data)
		if not bool(schema_check.get("ok", false)):
			failures.append("Legacy LevelDataV1 validation failed: %s" % [schema_check.get("errors", [])])


func _verify_authored_layouts(failures: Array[String]) -> void:
	var catalog = AuthoredRoomCatalogScript.new()
	catalog.build()
	var generator = AuthoredFloorGeneratorScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20202
	for config in [
		{"min_rooms": 5, "max_rooms": 5, "max_floor_attempts": 20},
		{"min_rooms": 7, "max_rooms": 9, "max_floor_attempts": 20},
	]:
		var layout: Dictionary = generator.generate_floor(catalog, rng, config)
		if not bool(layout.get("ok", false)):
			failures.append("Authored layout failed to generate: %s" % [layout.get("failure_buckets", {})])
			continue
		_validate_layout("authored", layout, failures)


func _validate_layout(label: String, layout: Dictionary, failures: Array[String]) -> void:
	var roles := _roles_by_room(layout)
	var critical := layout.get("critical_path", []) as Array
	var gates := layout.get("progression_gates", []) as Array
	var connection_rooms := layout.get("connection_rooms", []) as Array
	if gates.is_empty():
		failures.append("%s layout emitted no progression_gates." % label)
	if critical.size() >= 3:
		var first_role := String(roles.get(String(critical[1]), ""))
		var second_role := String(roles.get(String(critical[2]), ""))
		if first_role != "connection_room" or not _is_gated_encounter_role(second_role):
			failures.append(
				"%s layout must start with spawn -> connection_room -> encounter; got %s -> %s." % [
					label,
					first_role,
					second_role,
				]
			)
	for i in range(1, critical.size() - 1):
		var room := String(critical[i])
		var role := String(roles.get(room, ""))
		if role != "connection_room":
			continue
		var next_room := String(critical[i + 1])
		var next_role := String(roles.get(next_room, ""))
		if not _is_gated_encounter_role(next_role):
			continue
		if not connection_rooms.has(room):
			failures.append("%s connection_room %s missing from connection_rooms." % [label, room])
		if not _has_gate_for_connector(gates, room):
			failures.append("%s connection_room %s missing progression gate." % [label, room])
		var gate := _gate_for_connector(gates, room)
		var advance_rooms := gate.get("advance_room_names", []) as Array
		if not advance_rooms.has(room) or not advance_rooms.has(next_room):
			failures.append(
				"%s gate for %s must advance when players are in connector or beyond; got %s." % [
					label,
					room,
					advance_rooms,
				]
			)
	for i in range(1, critical.size() - 1):
		var role_at_i := String(roles.get(String(critical[i]), ""))
		var role_next := String(roles.get(String(critical[i + 1]), ""))
		if _is_gated_encounter_role(role_at_i) and _is_gated_encounter_role(role_next):
			failures.append("%s layout has adjacent gated rooms without connector at index %s." % [label, i])


func _roles_by_room(layout: Dictionary) -> Dictionary:
	var roles := {}
	for spec_value in layout.get("room_specs", []) as Array:
		if spec_value is not Dictionary:
			continue
		var spec := spec_value as Dictionary
		var name := String(spec.get("name", ""))
		var role := String(spec.get("role", spec.get("kind", "")))
		roles[name] = role
	return roles


func _has_gate_for_connector(gates: Array, connector_room: String) -> bool:
	return not _gate_for_connector(gates, connector_room).is_empty()


func _gate_for_connector(gates: Array, connector_room: String) -> Dictionary:
	for gate_value in gates:
		if gate_value is Dictionary and String((gate_value as Dictionary).get("connector_room", "")) == connector_room:
			return gate_value as Dictionary
	return {}


func _is_gated_encounter_role(role: String) -> bool:
	return role == "combat" or role == "chokepoint" or role == "boss" or role == "exit"
