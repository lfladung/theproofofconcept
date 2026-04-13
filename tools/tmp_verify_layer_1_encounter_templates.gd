extends SceneTree

const Layer1EncounterRegistry = preload("res://dungeon/game/encounters/layer_1_encounter_registry.gd")
const EncounterRunManagerScript = preload("res://dungeon/game/encounters/encounter_run_manager.gd")
const EnemySpawnByEnemyId = preload("res://dungeon/game/enemy_spawn_by_id.gd")

var _failures: Array[String] = []


func _init() -> void:
	_verify_unique_template_ids()
	_verify_enemy_ids_resolve()
	_verify_no_repeats_before_exhaustion()
	_verify_seeded_resolution_is_deterministic()
	_verify_filter_fallbacks()
	if _failures.is_empty():
		print("Layer 1 encounter template verification passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_unique_template_ids() -> void:
	var seen := {}
	for template in Layer1EncounterRegistry.templates():
		if template == null:
			_failures.append("Registry contains a null template.")
			continue
		if template.id == &"":
			_failures.append("Registry contains a template with an empty id.")
		if seen.has(template.id):
			_failures.append("Duplicate template id: %s" % [String(template.id)])
		seen[template.id] = true


func _verify_enemy_ids_resolve() -> void:
	for template in Layer1EncounterRegistry.templates():
		if template == null:
			continue
		for enemy_id in template.all_possible_enemy_ids():
			if EnemySpawnByEnemyId.scene_for_enemy_id(enemy_id) == null:
				_failures.append(
					"Template %s references unresolved enemy id %s." % [
						String(template.id),
						String(enemy_id),
					]
				)


func _verify_no_repeats_before_exhaustion() -> void:
	var manager = EncounterRunManagerScript.new()
	var templates := Layer1EncounterRegistry.templates()
	manager.configure(12345, templates)
	var seen := {}
	var room_tags := PackedStringArray(["arena", "open", "large"])
	for _i in range(templates.size()):
		var selection := manager.choose_template(1, room_tags)
		var template = selection.get("template", null)
		if template == null:
			_failures.append("Manager returned null before Layer 1 pool exhaustion.")
			return
		if seen.has(template.id):
			_failures.append("Template repeated before pool exhaustion: %s" % [String(template.id)])
			return
		seen[template.id] = true
	var repeat_selection := manager.choose_template(1, room_tags)
	if repeat_selection.get("template", null) == null:
		_failures.append("Manager failed to return a template after pool exhaustion.")
	if not bool(repeat_selection.get("repeated", false)):
		_failures.append("Manager did not mark post-exhaustion selection as repeated.")


func _verify_seeded_resolution_is_deterministic() -> void:
	var manager_a = EncounterRunManagerScript.new()
	var manager_b = EncounterRunManagerScript.new()
	var templates := Layer1EncounterRegistry.templates()
	manager_a.configure(777, templates)
	manager_b.configure(777, templates)
	var room_tags := PackedStringArray(["arena", "open", "large"])
	for _i in range(8):
		var selection_a := manager_a.choose_template(1, room_tags)
		var selection_b := manager_b.choose_template(1, room_tags)
		var template_a = selection_a.get("template", null)
		var template_b = selection_b.get("template", null)
		if template_a == null or template_b == null:
			_failures.append("Seeded manager returned null during determinism check.")
			return
		if template_a.id != template_b.id:
			_failures.append("Seeded manager selected different template order.")
			return
		var spawns_a := manager_a.resolve_template_spawns(template_a)
		var spawns_b := manager_b.resolve_template_spawns(template_b)
		if JSON.stringify(spawns_a) != JSON.stringify(spawns_b):
			_failures.append("Seeded manager resolved different spawn composition.")
			return


func _verify_filter_fallbacks() -> void:
	var manager = EncounterRunManagerScript.new()
	manager.configure(999, Layer1EncounterRegistry.templates())
	var corridor_selection := manager.choose_template(1, PackedStringArray(["arena", "chokepoint", "corridor"]))
	if corridor_selection.get("template", null) == null:
		_failures.append("Corridor room tags did not resolve any Layer 1 template.")
	var odd_selection := manager.choose_template(1, PackedStringArray(["arena", "strange_test_tag"]))
	if odd_selection.get("template", null) == null:
		_failures.append("Unknown room tags did not fall back to a Layer 1 template.")
