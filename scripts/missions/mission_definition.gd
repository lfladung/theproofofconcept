extends Resource
class_name MissionDefinition

@export var mission_id: StringName = &""
@export var display_name := ""
@export var difficulty := ""
@export var floor_count := 1
@export var enemy_theme := ""
@export var rewards: PackedStringArray = []
@export var mission_target := ""
@export var is_placeholder := true


func to_dictionary() -> Dictionary:
	return {
		"mission_id": String(mission_id),
		"display_name": display_name,
		"difficulty": difficulty,
		"floor_count": floor_count,
		"enemy_theme": enemy_theme,
		"rewards": Array(rewards),
		"mission_target": mission_target,
		"is_placeholder": is_placeholder,
	}


static func from_dictionary(data: Dictionary):
	var definition = load("res://scripts/missions/mission_definition.gd").new()
	definition.mission_id = StringName(String(data.get("mission_id", "")))
	definition.display_name = String(data.get("display_name", ""))
	definition.difficulty = String(data.get("difficulty", ""))
	definition.floor_count = maxi(1, int(data.get("floor_count", 1)))
	definition.enemy_theme = String(data.get("enemy_theme", ""))
	definition.rewards = PackedStringArray(data.get("rewards", []))
	definition.mission_target = String(data.get("mission_target", ""))
	definition.is_placeholder = bool(data.get("is_placeholder", true))
	return definition
