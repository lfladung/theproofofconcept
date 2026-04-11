extends RefCounted
class_name MissionLaunchResolver

const DEFAULT_RUN_SCENE_PATH := "res://dungeon/game/dungeon_orchestrator.tscn"
const MissionRegistryRef = preload("res://scripts/missions/mission_registry.gd")


static func resolve_scene_path(mission_id: StringName) -> String:
	var definition = MissionRegistryRef.get_mission(mission_id)
	if definition == null:
		return ""
	if definition.mission_target.strip_edges().is_empty():
		return DEFAULT_RUN_SCENE_PATH
	return definition.mission_target
