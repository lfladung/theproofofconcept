extends RefCounted
class_name InfusionEdge

## Edge pillar identity: precision, overkill chains, execution thresholds (Sharpen → Sever → Execution).
const IC := preload("res://scripts/infusion/infusion_constants.gd")

# --- Tier 1 — Sharpen ---
## Extra flat melee damage (legacy pacing hook).
static func melee_damage_bonus(threshold: int) -> int:
	var b := int(IC.InfusionThreshold.BASELINE)
	var e := int(IC.InfusionThreshold.ESCALATED)
	if threshold >= e:
		return 20
	if threshold >= b:
		return 10
	return 0


## Multiplier applied on top of the player’s melee crit multiplier when the hit is a crit (Sharpen).
static func sharpen_crit_damage_multiplier(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 1.45
	if threshold >= int(IC.InfusionThreshold.BASELINE):
		return 1.28
	return 1.0


## Kill splash: fraction of killing hit damage dealt as AoE (Sharpen, server).
static func sharpen_kill_splash_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 0.38
	return 0.28


static func sharpen_kill_splash_radius(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 8.4
	return 6.4


# --- Tier 2 — Sever ---
## Overkill damage spilled as a cone hit (ratio of overkill amount).
static func sever_overkill_spill_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 0.72
	return 0.55


static func sever_overkill_cone_degrees(threshold: int) -> float:
	return 68.0 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 52.0


static func sever_overkill_range(threshold: int) -> float:
	return 11.5 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 9.0


## Extra damage multiplier while Edge-marked (from crits); only vs Edge-attuned attackers.
static func sever_mark_damage_multiplier(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 1.0
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 1.22
	return 1.14


static func sever_mark_duration_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 4.5 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 3.2


## Bleed DPS ticks: total damage ≈ dps * duration (applied on melee crit).
static func sever_bleed_dps(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0
	return 4 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 3


static func sever_bleed_duration_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 2.8 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 2.0


## Temporary crit chance bonus after a kill (flat, added before clamp).
static func sever_kill_window_crit_bonus(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.22 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.14


static func sever_kill_window_duration_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 2.4 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 1.6


# --- Tier 3 — Execution (rework) ---
## Instant execute when HP% at or below this (no stacking).
static func execution_base_hp_fraction(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 0.20


## Crits apply “primed” for this long (Expression); larger glow + bonus Edge damage + death burst.
static func execution_prime_duration_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 5.0


## Multiplier on incoming Edge damage while primed (after Sever mark, if any).
static func execution_prime_edge_damage_multiplier(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 1.0
	return 1.16


## Extra targets after the first spill hop (primed death burst + normal expression chains).
static func execution_overkill_max_extra_hops(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0
	return 2


# --- Expression geometry (existing hook) ---
static func expression_geometry_mult(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 1.5
	return 1.0


static func is_edge_attuned(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)
