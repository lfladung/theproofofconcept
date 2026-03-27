extends RefCounted
class_name LoadoutVisualDefinition

var equipment_scene_path: String
var projectile_style_id: StringName = &""


func _init(scene_path: String = "", projectile_style: StringName = &"") -> void:
	equipment_scene_path = scene_path
	projectile_style_id = projectile_style


func to_dictionary() -> Dictionary:
	return {
		"equipment_scene_path": equipment_scene_path,
		"projectile_style_id": String(projectile_style_id),
	}
