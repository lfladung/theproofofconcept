extends RefCounted
class_name InfusionSurge

## Surge pillar: Primed Charge → Overcharge → Overdrive (protection-oriented charge fantasy).
const IC := preload("res://scripts/infusion/infusion_constants.gd")


static func is_surge_attuned(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)


static func melee_flat_damage_bonus(threshold: int) -> int:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return 8
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 5
	if threshold >= int(IC.InfusionThreshold.BASELINE):
		return 3
	return 0


## Extra flat damage when releasing a full melee charge (primed), before overcharge scaling.
static func primed_full_charge_flat_bonus(threshold: int) -> int:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 12
	return 8


static func allows_melee_overcharge_hold(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.ESCALATED)


static func overcharge_max_hold_sec(threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	return 2.35 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 1.65


## Normalized overcharge 0..1 multiplies damage and secondary burst scaling.
static func overcharge_melee_damage_multiplier(threshold: int, over_norm: float) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 1.0
	var cap := 1.48 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 1.26
	return lerpf(1.0, cap, clampf(over_norm, 0.0, 1.0))


static func charge_field_radius(
	threshold: int, charge_ratio: float, overcharge_norm: float, in_overdrive: bool
) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	var base := 4.6
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		base = 8.2
	elif threshold >= int(IC.InfusionThreshold.ESCALATED):
		base = 6.4
	if in_overdrive:
		return base * 1.32
	var cr := lerpf(0.38, 1.0, clampf(charge_ratio, 0.0, 1.0))
	if overcharge_norm > 0.001:
		cr = lerpf(cr, 1.0, clampf(overcharge_norm, 0.0, 1.0) * 0.88)
	return base * cr


## Movement speed multiplier applied to enemies (lower = slower).
static func charge_field_enemy_speed_mult(
	threshold: int, charge_ratio: float, overcharge_norm: float, in_overdrive: bool
) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 1.0
	var floor_m := 0.74
	if in_overdrive:
		floor_m = 0.40
	elif threshold >= int(IC.InfusionThreshold.ESCALATED):
		floor_m = 0.52
	elif threshold >= int(IC.InfusionThreshold.BASELINE):
		floor_m = 0.66
	var t := lerpf(0.0, 1.0, clampf(charge_ratio, 0.0, 1.0))
	if overcharge_norm > 0.001:
		t = lerpf(t, 1.0, clampf(overcharge_norm, 0.0, 1.0))
	if in_overdrive:
		t = 1.0
	return lerpf(1.0, floor_m, t)


## Multiplies enemy attack cooldown tick (lower = attacks less often).
static func charge_field_enemy_cooldown_tick_mult(
	threshold: int, overcharge_norm: float, in_overdrive: bool
) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 1.0
	var floor_m := 0.58
	if in_overdrive:
		floor_m = 0.36
	var t := 0.0
	if in_overdrive:
		t = 1.0
	elif overcharge_norm > 0.04:
		t = clampf(overcharge_norm, 0.0, 1.0)
	else:
		t = 0.28
	return lerpf(1.0, floor_m, clampf(t, 0.0, 1.0))


static func field_refresh_ttl_msec() -> int:
	return 130


static func field_pulse_interval_sec(threshold: int, in_overdrive: bool) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 999.0
	if in_overdrive:
		return 0.42
	return 0.62 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.78


static func field_pulse_micro_interrupt_sec(threshold: int, in_overdrive: bool) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 0.0
	if in_overdrive:
		return 0.085
	return 0.055 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 0.038


static func secondary_burst_radius(threshold: int, overcharge_norm: float) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	var r := 2.2 if threshold >= int(IC.InfusionThreshold.ESCALATED) else 1.65
	r += clampf(overcharge_norm, 0.0, 1.0) * (
		3.4 if threshold >= int(IC.InfusionThreshold.EXPRESSION) else 2.2
	)
	return r


static func secondary_burst_damage_ratio(threshold: int, overcharge_norm: float) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	var b := 0.18 if threshold >= int(IC.InfusionThreshold.ESCALATED) else 0.13
	b += clampf(overcharge_norm, 0.0, 1.0) * 0.16
	return b


static func surge_energy_gain_from_melee(
	threshold: int, hit_count: int, charge_ratio: float, full_charge: bool, overcharge_norm: float
) -> float:
	if threshold < int(IC.InfusionThreshold.BASELINE):
		return 0.0
	var g := (7.0 if full_charge else 2.8 * clampf(charge_ratio, 0.0, 1.0))
	g += maxi(0, hit_count - 1) * (4.5 if full_charge else 2.0)
	if overcharge_norm > 0.08:
		g += 9.0 * clampf(overcharge_norm, 0.0, 1.0)
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		g *= 1.12
	return g


static func surge_energy_max() -> float:
	return 100.0


static func can_start_overdrive(threshold: int, overcharge_norm: float, energy: float) -> bool:
	return (
		threshold >= int(IC.InfusionThreshold.EXPRESSION)
		and overcharge_norm >= 0.76
		and energy >= overdrive_entry_energy_cost()
	)


static func overdrive_entry_energy_cost() -> float:
	return 16.0


static func overdrive_energy_drain_per_sec() -> float:
	return 15.0


static func overdrive_player_move_speed_mult() -> float:
	return 0.87


static func finale_damage_ratio_for_energy_used(energy_used: float) -> float:
	var e := clampf(energy_used, 0.0, 120.0)
	return 0.34 + e * 0.0065


static func finale_knockback() -> float:
	return 9.5


static func max_client_reported_overcharge_sec_fudge() -> float:
	return 2.8
