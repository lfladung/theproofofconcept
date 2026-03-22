extends Area2D
class_name ZoneMarker2D

@export_enum(
	"enemy_spawn",
	"prop_placement",
	"patrol_hint",
	"encounter_trigger",
	"loot_marker",
	"nav_boundary"
)
var zone_type := "enemy_spawn"

@export var zone_role: StringName = &"default"
@export var zone_weight := 1.0
@export var tags: PackedStringArray = []


func get_zone_metadata() -> Dictionary:
	return {
		"zone_type": zone_type,
		"zone_role": zone_role,
		"zone_weight": zone_weight,
		"tags": tags,
		"position": global_position,
	}
