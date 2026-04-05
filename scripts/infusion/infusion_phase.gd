extends RefCounted
class_name InfusionPhase

const IC := preload("res://scripts/infusion/infusion_constants.gd")

## Forward melee depth multiplier at Phase expression (composed with Edge).
const EXPRESSION_DEPTH_MULT := 1.09


static func armor_ignore_ratio(threshold: int) -> float:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 0.30
	if threshold >= b:
		return 0.15
	return 0.0


static func should_use_hit_extension(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.EXPRESSION)


static func expression_depth_multiplier(threshold: int) -> float:
	return EXPRESSION_DEPTH_MULT if should_use_hit_extension(threshold) else 1.0
