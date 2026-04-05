extends RefCounted
class_name InfusionFlow

## Flow pillar: tempo stacks, conditional recovery, chain windows, earned Overdrive.
## Thresholds map Baseline → tier 1 (Accelerate), Escalated → tier 2 (Chain), Expression → tier 3 (Overdrive).
const IC := preload("res://scripts/infusion/infusion_constants.gd")

enum ActionKind { MELEE = 0, RANGED = 1, BOMB = 2 }

# --- Tier 1 — Accelerate (baseline tempo) ---
## Small always-on attack-speed floor so Flow is felt before stacks ramp.
const BASELINE_ATTACK_SPEED := 1.08
const ESCALATED_ATTACK_SPEED_FLOOR := 1.12
const EXPRESSION_ATTACK_SPEED_FLOOR := 1.12

## Tempo is a 0..1 pressure meter; actions add, time decays.
const TEMPO_DECAY_PER_SEC := 1.15
const TEMPO_ADD_PER_MELEE := 0.22
const TEMPO_ADD_PER_RANGED := 0.18
const TEMPO_ADD_PER_BOMB := 0.16
## Extra tempo when the Flow chain window is active (tier 2+).
const TEMPO_ADD_CHAIN_BONUS := 0.12
## While this timer > 0, ability cooldown *ticks* faster (not a passive shorter cap).
const AGGRESSION_WINDOW_SEC := 0.55
const AGGRESSION_COOLDOWN_TICK_BONUS := 0.22

# --- Tier 2 — Chain (action linking) ---
const CHAIN_WINDOW_BASELINE_SEC := 0.82
const CHAIN_WINDOW_EXPRESSION_SEC := 1.08
## Extends the window when alternating action families (melee / gun / bomb).
const CHAIN_ALTERNATE_EXTENSION_SEC := 0.35
const CHAIN_ATTACK_SPEED_BONUS := 1.12
## Melee hits shave extra time off gun/bomb cooldowns during the chain window (server tick hook).
const CHAIN_MELEE_ABILITY_CD_PULSE_SEC := 0.07

# --- Tier 3 — Overdrive (expression) ---
const OVERDRIVE_TEMPO_COST := 1.0
const OVERDRIVE_DURATION_SEC := 3.2
const OVERDRIVE_ATTACK_SPEED_MULT := 1.55
const OVERDRIVE_COOLDOWN_TICK_MULT := 2.15
const OVERDRIVE_MOVE_SPEED_MULT := 1.18
## Compress presentation lock time (not hitbox authority).
const OVERDRIVE_ANIM_TIME_MULT := 0.72
const OVERDRIVE_EXIT_TEMPO_MULT := 0.18
const OVERDRIVE_EXIT_CHAIN_CLEAR := true

# --- Echo-lite (flow-only, kept rare / conditional) ---
const OVERDRIVE_ECHO_MELEE_CHANCE := 0.08
const OVERDRIVE_ECHO_DAMAGE_MULT := 0.34


static func flow_threshold_active(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.BASELINE)


static func passive_attack_speed_floor(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return EXPRESSION_ATTACK_SPEED_FLOOR
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return ESCALATED_ATTACK_SPEED_FLOOR
	if threshold >= int(IC.InfusionThreshold.BASELINE):
		return BASELINE_ATTACK_SPEED
	return 1.0


## Legacy hook: prefer tempo + aggression; keep a tiny passive only at Escalated+ so Baseline has no boring global CDR.
static func cooldown_multiplier(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return 0.97
	return 1.0


static func tempo_attack_speed_multiplier(tempo: float, threshold: int) -> float:
	if not flow_threshold_active(threshold):
		return 1.0
	var w := clampf(tempo, 0.0, 1.0)
	var ramp := 1.0 + 0.28 * w
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		ramp += 0.06 * w
	return ramp


static func chain_attack_speed_multiplier(chain_remaining: float, threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.ESCALATED):
		return 1.0
	if chain_remaining <= 0.0:
		return 1.0
	return CHAIN_ATTACK_SPEED_BONUS


static func overdrive_attack_speed_multiplier(overdrive_remaining: float, threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION):
		return 1.0
	if overdrive_remaining <= 0.0:
		return 1.0
	return OVERDRIVE_ATTACK_SPEED_MULT


static func combined_attack_speed_multiplier(
	tempo: float, chain_remaining: float, overdrive_remaining: float, threshold: int
) -> float:
	var m := passive_attack_speed_floor(threshold)
	m *= tempo_attack_speed_multiplier(tempo, threshold)
	m *= chain_attack_speed_multiplier(chain_remaining, threshold)
	m *= overdrive_attack_speed_multiplier(overdrive_remaining, threshold)
	return maxf(1.0, m)


static func cooldown_tick_multiplier(
	aggression_remaining: float, overdrive_remaining: float, threshold: int
) -> float:
	if not flow_threshold_active(threshold):
		return 1.0
	var m := cooldown_multiplier(threshold)
	if aggression_remaining > 0.0:
		var u := clampf(aggression_remaining / maxf(1e-3, AGGRESSION_WINDOW_SEC), 0.0, 1.0)
		m *= 1.0 + AGGRESSION_COOLDOWN_TICK_BONUS * u
	if overdrive_remaining > 0.0 and threshold >= int(IC.InfusionThreshold.EXPRESSION):
		m *= OVERDRIVE_COOLDOWN_TICK_MULT
	return maxf(1.0, m)


static func overdrive_move_speed_multiplier(overdrive_remaining: float, threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION) or overdrive_remaining <= 0.0:
		return 1.0
	return OVERDRIVE_MOVE_SPEED_MULT


static func flow_animation_time_multiplier(overdrive_remaining: float, threshold: int) -> float:
	if threshold < int(IC.InfusionThreshold.EXPRESSION) or overdrive_remaining <= 0.0:
		return 1.0
	return OVERDRIVE_ANIM_TIME_MULT


static func should_extend_combo_window(threshold: int) -> bool:
	return threshold >= int(IC.InfusionThreshold.EXPRESSION)


static func _chain_window_duration(threshold: int) -> float:
	if threshold >= int(IC.InfusionThreshold.EXPRESSION):
		return CHAIN_WINDOW_EXPRESSION_SEC
	if threshold >= int(IC.InfusionThreshold.ESCALATED):
		return CHAIN_WINDOW_BASELINE_SEC
	return 0.0


static func state_decay(delta: float, threshold: int, state: Dictionary) -> Dictionary:
	var tempo := clampf(float(state.get("tempo", 0.0)), 0.0, 1.0)
	var chain_rem := maxf(0.0, float(state.get("chain_rem", 0.0)))
	var od_rem := maxf(0.0, float(state.get("od_rem", 0.0)))
	var agg_rem := maxf(0.0, float(state.get("agg_rem", 0.0)))
	var last_kind := int(state.get("last_kind", -1))
	if not flow_threshold_active(threshold):
		return {
			"tempo": 0.0,
			"chain_rem": 0.0,
			"od_rem": 0.0,
			"agg_rem": 0.0,
			"last_kind": -1,
		}
	var d := maxf(0.0, delta)
	var had_od := od_rem > 0.0
	od_rem = maxf(0.0, od_rem - d)
	chain_rem = maxf(0.0, chain_rem - d)
	agg_rem = maxf(0.0, agg_rem - d)
	tempo = maxf(0.0, tempo - TEMPO_DECAY_PER_SEC * d)
	if had_od and od_rem <= 0.0:
		tempo *= OVERDRIVE_EXIT_TEMPO_MULT
		if OVERDRIVE_EXIT_CHAIN_CLEAR:
			chain_rem = 0.0
	return {
		"tempo": tempo,
		"chain_rem": chain_rem,
		"od_rem": od_rem,
		"agg_rem": agg_rem,
		"last_kind": last_kind,
	}


static func _tempo_add_for_kind(kind: int) -> float:
	match kind:
		ActionKind.MELEE:
			return TEMPO_ADD_PER_MELEE
		ActionKind.RANGED:
			return TEMPO_ADD_PER_RANGED
		ActionKind.BOMB:
			return TEMPO_ADD_PER_BOMB
		_:
			return 0.15


static func weapon_action_advance(threshold: int, state: Dictionary, kind: int) -> Dictionary:
	var tempo := clampf(float(state.get("tempo", 0.0)), 0.0, 1.0)
	var chain_rem := maxf(0.0, float(state.get("chain_rem", 0.0)))
	var od_rem := maxf(0.0, float(state.get("od_rem", 0.0)))
	var agg_rem := maxf(0.0, float(state.get("agg_rem", 0.0)))
	var last_kind := int(state.get("last_kind", -1))
	if not flow_threshold_active(threshold):
		return {
			"tempo": tempo,
			"chain_rem": chain_rem,
			"od_rem": od_rem,
			"agg_rem": agg_rem,
			"last_kind": last_kind,
		}
	var in_chain := chain_rem > 0.0
	var add := _tempo_add_for_kind(kind)
	if in_chain:
		add += TEMPO_ADD_CHAIN_BONUS
	tempo = clampf(tempo + add, 0.0, 1.0)
	agg_rem = maxf(agg_rem, AGGRESSION_WINDOW_SEC)
	var nw := _chain_window_duration(threshold)
	if nw > 0.0:
		var extended := nw
		if last_kind >= 0 and last_kind != kind:
			extended += CHAIN_ALTERNATE_EXTENSION_SEC
		chain_rem = maxf(chain_rem, extended)
	if threshold >= int(IC.InfusionThreshold.EXPRESSION) and od_rem <= 0.0 and tempo >= OVERDRIVE_TEMPO_COST - 1e-4:
		od_rem = OVERDRIVE_DURATION_SEC
		tempo = maxf(0.0, tempo - OVERDRIVE_TEMPO_COST) * OVERDRIVE_EXIT_TEMPO_MULT
	last_kind = kind
	return {
		"tempo": tempo,
		"chain_rem": chain_rem,
		"od_rem": od_rem,
		"agg_rem": agg_rem,
		"last_kind": last_kind,
	}

## Echo-lite tuning (Flow-only follow-up strike) — not wired into hit pipeline yet; see `ideas/GAMEPLAY_IDEAS.md`.
