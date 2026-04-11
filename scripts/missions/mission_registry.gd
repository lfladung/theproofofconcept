extends RefCounted
class_name MissionRegistry

const MissionDefinitionScript = preload("res://scripts/missions/mission_definition.gd")
const DEFAULT_RUN_SCENE_PATH := "res://dungeon/game/dungeon_orchestrator.tscn"


static func all_missions() -> Array:
	return [
		_make_mission(
			&"mission_01",
			"Cavern Sweep",
			"Scout",
			1,
			"Flow stragglers and shielded Mass scouts",
			PackedStringArray(["Tempering XP", "Minor Resonance", "Common gear cache"])
		),
		_make_mission(
			&"mission_02",
			"Deep Relay",
			"Standard",
			1,
			"Edge raiders around unstable relay rooms",
			PackedStringArray(["Tempering XP", "Phase shards", "Weapon cache"])
		),
		_make_mission(
			&"mission_03",
			"Vault Descent",
			"Hard",
			1,
			"Echo and Anchor pressure near sealed vaults",
			PackedStringArray(["Tempering XP", "Vault materials", "Armor cache"])
		),
	]


static func get_mission(mission_id: StringName):
	for mission in all_missions():
		if mission != null and mission.mission_id == mission_id:
			return mission
	return null


static func has_mission(mission_id: StringName) -> bool:
	return get_mission(mission_id) != null


static func mission_payload(mission_id: StringName) -> Dictionary:
	var mission = get_mission(mission_id)
	return mission.to_dictionary() if mission != null else {}


static func default_mission_id() -> StringName:
	var missions = all_missions()
	return missions[0].mission_id if not missions.is_empty() else &""


static func _make_mission(
	mission_id: StringName,
	display_name: String,
	difficulty: String,
	floor_count: int,
	enemy_theme: String,
	rewards: PackedStringArray
):
	var definition = MissionDefinitionScript.new()
	definition.mission_id = mission_id
	definition.display_name = display_name
	definition.difficulty = difficulty
	definition.floor_count = floor_count
	definition.enemy_theme = enemy_theme
	definition.rewards = rewards
	definition.mission_target = DEFAULT_RUN_SCENE_PATH
	definition.is_placeholder = true
	return definition
