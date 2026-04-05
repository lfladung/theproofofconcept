extends RefCounted
class_name InfusionMass

## Mass pillar: knockback weight, stagger / downed, impact pulse, wall & carrier payoffs, shockwave (Heft → Crush → Cataclysm).
const IC := preload("res://scripts/infusion/infusion_constants.gd")


static func is_mass_attuned(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)


## Flat melee damage by tier (replaces the old linear per-pickup stub).
static func melee_damage_bonus(threshold: int) -> int:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 15
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 10
	if threshold >= int(IC.InfusionThreshold.BASELINE):
		return 6
	return 0


static func melee_knockback_multiplier(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 1.34
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 1.18
	if threshold >= int(IC.InfusionThreshold.BASELINE):
		return 1.10
	return 1.0


static func hit_stun_duration_multiplier(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 1.32
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 1.18
	if threshold >= int(IC.InfusionThreshold.BASELINE):
		return 1.10
	return 1.0


static func stagger_build_per_melee_hit(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 32.0
	return 20.0


static func stagger_downed_threshold() -> float:
	return 100.0


static func impact_pulse_radius(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 5.6
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 4.5
	return 3.7


static func impact_pulse_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 0.30
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 0.24
	return 0.18


static func impact_pulse_knockback(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	return 6.2 if threshold >= int(IC.InfusionThreshold.ESCALATED) else 4.9


static func wall_slam_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.42 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.30


static func wall_slam_extra_stun_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.52 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.34


static func carrier_hit_damage(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0
	return 8 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 5


static func carrier_hit_knockback(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 5.2 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 3.8


static func downed_duration_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 1.05 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.78


static func downed_melee_damage_multiplier(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 1.0
	return 1.26 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 1.14


static func unstable_window_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.48


static func unstable_launch_knockback_threshold(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return INF
	return 11.5


static func unstable_burst_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.38


static func unstable_burst_radius(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 5.0 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 4.0


static func shockwave_buildup_hits(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 999999
	return 4


static func shockwave_radius(threshold: int) -> float:
	return 13.0


static func shockwave_damage_ratio(threshold: int) -> float:
	return 0.36


static func shockwave_knockback(threshold: int) -> float:
	return 15.0


static func shockwave_chain_radius_bonus_per_enemy(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 1.6


## Expression: slight inward bias on knockback direction (toward attacker) for vacuum-like weight.
static func expression_inward_knockback_blend(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 0.20
