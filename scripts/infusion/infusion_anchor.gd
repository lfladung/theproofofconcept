extends RefCounted
class_name InfusionAnchor

## Anchor pillar: Fortify → Brace → Bastion (stability, delayed damage reserve, rooted eruption).
const IC := preload("res://scripts/infusion/infusion_constants.gd")


static func is_anchor_attuned(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)


# --- Tier 1 — Fortify ---
static func fortify_flat_damage_reduction(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 2
	return 1


static func fortify_micro_shield_gain_per_hit(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 4
	return 3


static func fortify_micro_shield_cap(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 22.0
	return 14.0


static func fortify_attack_commit_knockback_immunity(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)


# --- Tier 2 — Brace (delayed damage / reserve) ---
static func brace_reserve_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 0.50
	return 0.36


static func brace_pressure_decay_per_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 8.5 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 6.0


static func brace_hit_spill_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.40 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.30


static func brace_while_reserve_melee_bonus(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0
	return 5 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 3


static func brace_purge_fraction(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.36 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.26


static func brace_purge_shockwave_radius(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 6.0 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 4.6


static func brace_purge_shockwave_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.50 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.38


# --- Tier 3 — Bastion ---
static func bastion_charge_rate_per_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 0.78


static func bastion_charge_decay_per_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 1.05


static func bastion_incoming_to_reserve_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 0.72


static func bastion_extra_flat_reduction_while_rooted(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0
	return 3


static func bastion_release_radius(threshold: int) -> float:
	return 10.5 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 8.5


static func bastion_release_damage_ratio(threshold: int) -> float:
	return 0.58 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.44


static func bastion_critical_pressure_threshold(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 1e9
	return 40.0


static func bastion_critical_release_multiplier(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 1.0
	return 1.40


## Extra melee damage while reserve is up and while rooted / critical bastion.
static func outgoing_melee_bonus(
	threshold: int, pressure: float, rooted: bool, critical_bastion: bool
) -> int:
	var bonus := 0
	if threshold >= int(IC.InfusionThreshold.ESCALATED) and pressure > 0.25:
		var cap := 7.0 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 4.0
		bonus += int(floor(minf(pressure * 0.22, cap)))
		bonus += brace_while_reserve_melee_bonus(threshold)
	if rooted and threshold >= int(IC.InfusionThreshold.EXPRESSION):
		bonus += 6
	if critical_bastion and threshold >= int(IC.InfusionThreshold.EXPRESSION):
		bonus += 5
	return bonus
