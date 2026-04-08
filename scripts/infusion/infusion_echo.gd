extends RefCounted
class_name InfusionEcho

## Echo pillar identity: Reverberate → Chorus → Resonance Cascade.
## Tier 1 leans on a **single** proc chance band (not linear 20→40→60% scaling); tier 2 adds **imprint** state;
## tier 3 allows **controlled** recursive echoes with a hard generation cap.
const IC := preload("res://scripts/infusion/infusion_constants.gd")

# --- Tier 1 — Reverberate (Baseline+) ---
## One roll band for melee afterimage; Chorus imprint can guarantee a follow-up instead (tier 2).
static func reverberate_proc_chance(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	return 0.22


## Damage fraction for afterimage / micro-echo hits (primary hit already applied full damage).
static func afterimage_damage_ratio(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 0.52
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 0.48
	return 0.44


static func afterimage_delay_min_sec(threshold: int) -> float:
	return 0.10 if threshold >= int(IC.InfusionThreshold.ESCALATED) else 0.12


static func afterimage_delay_max_sec(threshold: int) -> float:
	return 0.20 if threshold >= int(IC.InfusionThreshold.ESCALATED) else 0.18


# --- Tier 2 — Chorus (Escalated+) ---
## Imprint left on enemies so **subsequent** hits are conditional, not more RNG.
static func imprint_duration_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 1.35 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 1.15


## When the victim already had an active imprint, convert one echo proc into this many rapid hits.
static func chorus_micro_hit_count(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 1
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 3
	return 2


## Soft chain: after a melee echo resolves on the primary target, spill to a nearby enemy.
static func linked_chain_radius(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 8.0 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 6.5


static func linked_chain_damage_ratio(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 0.36 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.32


static func chorus_micro_hit_spacing_sec(threshold: int) -> float:
	return 0.045 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.055


# --- Tier 3 — Resonance Cascade (Expression) ---
static func max_echo_generation(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0
	return 2


## Chance for an echo hit to schedule one child echo (same target), decayed again by `child_echo_damage_ratio`.
static func child_echo_proc_chance(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 0.0
	return 0.18


static func child_echo_damage_ratio(_threshold: int) -> float:
	return 0.38


# --- Handgun twin (non-melee; Baseline+) ---
static func projectile_twin_chance(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 0.20
	return 0.14


static func projectile_twin_damage_ratio(_threshold: int) -> float:
	return 0.52


## Twin bolt spawn is this many game units **behind** the primary along facing (trailing read).
static func projectile_twin_behind_distance(threshold: int) -> float:
	return 1.22 if threshold >= int(IC.InfusionThreshold.ESCALATED) else 1.02


# --- Queries ---
static func is_echo_attuned(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)
