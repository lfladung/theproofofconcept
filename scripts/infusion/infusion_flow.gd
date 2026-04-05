extends RefCounted
class_name InfusionFlow

const IC := preload("res://scripts/infusion/infusion_constants.gd")


static func attack_speed_multiplier(threshold: int) -> float:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 1.2
	if threshold >= b:
		return 1.1
	return 1.0


static func cooldown_multiplier(threshold: int) -> float:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 0.85
	if threshold >= b:
		return 0.92
	return 1.0


static func should_extend_combo_window(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.EXPRESSION)
