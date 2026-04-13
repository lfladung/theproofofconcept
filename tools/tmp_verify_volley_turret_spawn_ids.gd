extends SceneTree

const EnemySpawnById = preload("res://dungeon/game/enemy_spawn_by_id.gd")


func _init() -> void:
	var ids: Array[StringName] = []
	for archetype in EnemySpawnById.RANGED_ARCHETYPES:
		for family in EnemySpawnById.RANGED_FAMILIES:
			ids.append(StringName("%s_%s" % [String(archetype), String(family)]))
	ids.append(&"arrow_tower")
	var failures: Array[String] = []
	for id in ids:
		var spec := EnemySpawnById.spawn_spec_for_enemy_id(id)
		var scene := EnemySpawnById.scene_for_enemy_id(id)
		if spec.is_empty() or scene == null:
			failures.append(String(id))
			continue
		var config := spec.get("config", {}) as Dictionary
		if config.is_empty() and id != &"arrow_tower":
			failures.append(String(id))
	if not failures.is_empty():
		push_error("Missing volley turret spawn specs: %s" % [", ".join(failures)])
		quit(1)
		return
	print("Verified %s volley turret spawn ids." % [ids.size()])
	quit(0)
