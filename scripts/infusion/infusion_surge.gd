extends RefCounted
class_name InfusionSurge

const IC := preload("res://scripts/infusion/infusion_constants.gd")


## Stub until Surge-specific mechanics exist: +10 melee damage per pickup of this pillar.
static func melee_bonus_from_manager(mgr: Node) -> int:
	if mgr == null or not mgr.has_method(&"count_pickups_for_pillar"):
		return 0
	var n := int(mgr.call(&"count_pickups_for_pillar", IC.PILLAR_SURGE))
	return 10 * maxi(0, n)
