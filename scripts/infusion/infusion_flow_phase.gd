extends RefCounted
class_name InfusionFlowPhase

const IC := preload("res://scripts/infusion/infusion_constants.gd")

## Forward melee depth multiplier at Phase expression (composed with Edge).
const PHASE_EXPRESSION_DEPTH_MULT := 1.09


static func flow_attack_speed_multiplier(threshold: int) -> float:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 1.2
	if threshold >= b:
		return 1.1
	return 1.0


static func flow_cooldown_multiplier(threshold: int) -> float:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 0.85
	if threshold >= b:
		return 0.92
	return 1.0


static func flow_should_extend_combo_window(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.EXPRESSION)


static func phase_armor_ignore_ratio(threshold: int) -> float:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 0.30
	if threshold >= b:
		return 0.15
	return 0.0


static func phase_should_use_hit_extension(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.EXPRESSION)


static func phase_expression_depth_multiplier(threshold: int) -> float:
	return PHASE_EXPRESSION_DEPTH_MULT if phase_should_use_hit_extension(threshold) else 1.0
