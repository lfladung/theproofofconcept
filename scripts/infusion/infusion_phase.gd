extends RefCounted
class_name InfusionPhase

## Phase pillar: Slip → Skew → Fracture (spatial rule-breaking). See Phase infusion plan.
const IC := preload("res://scripts/infusion/infusion_constants.gd")

## Mob CharacterBody2D layer in this project (`collision_layer = 2` on enemies).
const MOB_BODY_PHYSICS_LAYER_BIT: int = 2

# --- Tier 1 — Slip (Baseline) ---
const BASELINE_MELEE_DEPTH_MULT := 1.04
## Total forward depth multiplier at Expression (replaces baseline-only boost).
const EXPRESSION_MELEE_DEPTH_MULT := 1.09

## Armor / mitigation bypass fraction carried on `DamagePacket.mitigation_ignore_ratio`.
static func armor_ignore_ratio(threshold: int) -> float:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 0.30
	if threshold >= b:
		return 0.15
	return 0.0


static func combined_melee_depth_multiplier(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 1.0
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return BASELINE_MELEE_DEPTH_MULT
	return EXPRESSION_MELEE_DEPTH_MULT


static func slip_collision_window_extra_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	return 0.04


# --- Tier 2 — Skew (Escalated) ---
static func ghost_strike_delay_min_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.11 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.13


static func ghost_strike_delay_max_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.19 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.21


static func ghost_strike_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.48 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.40


static func facing_warp_max_degrees(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 18.0 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 14.0


static func facing_warp_cone_degrees(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 72.0


static func dash_trail_radius(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 5.2 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 4.2


static func dash_trail_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.34 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.28


static func dash_trail_cooldown_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.55


static func contact_chip_damage(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0
	return 3 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 2


static func contact_chip_cooldown_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.65


# --- Tier 3 — Fracture (Expression) ---
static func multi_origin_flank_offset(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 2.35


static func multi_origin_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 0.38


static func ranged_wall_pierce_hits(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0
	return 2


static func is_phase_attuned(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)


static func is_skew_or_higher(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.ESCALATED)


static func is_fracture(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.EXPRESSION)
