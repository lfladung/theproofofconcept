extends RefCounted
class_name MetaProgressionConstants

## Constants for the meta-progression system (gear tiers, gems, materials, familiarity).
## Pillar IDs reuse InfusionConstants.PILLAR_* — do not redeclare them here.

# --- Gear Tiers ---
const TIER_BASE: int = 1        # Neutral identity, minimal stats, limited interactions
const TIER_ALIGNED: int = 2     # Commits to a pillar, unlocks core behavior
const TIER_SPECIALIZED: int = 3 # Full expression, new mechanics, capped stats

# --- Inventory Limits ---
# Per-slot: 1 equipped + MAX_STASH_PER_SLOT stored (INVENTORY.md §2)
const MAX_STASH_PER_SLOT: int = 2

# Gem slots: starts at base, unlockable up to max (INVENTORY.md §4)
const MAX_GEM_SLOTS_BASE: int = 6
const MAX_GEM_SLOTS_MAX: int = 16

# Gem sockets per gear piece scales with tier (tier 1 = 1, tier 2 = 2, tier 3 = 3)
static func gem_sockets_for_tier(tier: int) -> int:
	return clampi(tier, TIER_BASE, TIER_SPECIALIZED)

# Stat multiplier per tier. Target: ~1.5x–2x total growth start→endgame (META_PROGRESSION.md §9).
# Tier 1 = 1.0x, Tier 2 = 1.25x, Tier 3 = 1.5x. Combined with masterwork familiarity (+6%) → max ~1.59x.
static func tier_stat_multiplier(tier: int) -> float:
	match tier:
		TIER_SPECIALIZED:
			return 1.5
		TIER_ALIGNED:
			return 1.25
	return 1.0

# --- Familiarity (Gear XP) ---
# META_PROGRESSION.md §9: small bounded stat growth from using gear
const FAMILIARITY_FAMILIAR_THRESHOLD: float = 100.0
const FAMILIARITY_MASTERWORK_THRESHOLD: float = 300.0
const FAMILIARITY_FAMILIAR_BONUS: float = 0.02   # +2% to all stats from this piece
const FAMILIARITY_MASTERWORK_BONUS: float = 0.06  # +6% to all stats from this piece

enum FamiliarityLevel {
	STANDARD = 0,   # 0–99 XP
	FAMILIAR = 1,   # 100–299 XP  (+2%)
	MASTERWORK = 2, # 300+ XP     (+6%)
}

static func familiarity_level_for_xp(xp: float) -> FamiliarityLevel:
	if xp >= FAMILIARITY_MASTERWORK_THRESHOLD:
		return FamiliarityLevel.MASTERWORK
	if xp >= FAMILIARITY_FAMILIAR_THRESHOLD:
		return FamiliarityLevel.FAMILIAR
	return FamiliarityLevel.STANDARD

static func familiarity_bonus_for_xp(xp: float) -> float:
	match familiarity_level_for_xp(xp):
		FamiliarityLevel.MASTERWORK:
			return FAMILIARITY_MASTERWORK_BONUS
		FamiliarityLevel.FAMILIAR:
			return FAMILIARITY_FAMILIAR_BONUS
	return 0.0

static func familiarity_display_name(level: FamiliarityLevel) -> String:
	match level:
		FamiliarityLevel.FAMILIAR:
			return "Familiar"
		FamiliarityLevel.MASTERWORK:
			return "Masterwork"
	return "Standard"

# --- Tempering (Run-Stepping System) ---
# META_PROGRESSION.md §2: temporary amplifications during a run.
enum TemperingState {
	NONE = 0,
	TEMPERED_I = 1,   # Early run: minor stat boost + behavior enhancement
	TEMPERED_II = 2,  # Late run: stronger boost + partial next-tier mechanics
}

# Tempering XP thresholds (accumulated per gear piece per run).
const TEMPERING_THRESHOLD_I: float = 30.0
const TEMPERING_THRESHOLD_II: float = 80.0

# Stat multiplier applied ON TOP of tier multiplier during a run.
static func tempering_stat_multiplier(state: TemperingState) -> float:
	match state:
		TemperingState.TEMPERED_II:
			return 1.15  # +15% (midpoint of 10–20% range)
		TemperingState.TEMPERED_I:
			return 1.075 # +7.5% (midpoint of 5–10% range)
	return 1.0

# Tempering XP sources (per event).
const TEMPERING_XP_PER_FLOOR: float = 10.0
const TEMPERING_XP_PER_INFUSION_PICKUP: float = 8.0
const TEMPERING_XP_PER_BOSS_KILL: float = 15.0

# --- Promotion ---
# META_PROGRESSION.md §3: high-performance runs → permanent tier unlock progress.
# Progress is granted at end of run based on tempering state and objectives.
const PROMOTION_PROGRESS_TEMPERED_II: float = 0.35   # Reached Tempered II this run
const PROMOTION_PROGRESS_BOSS_CLEAR: float = 0.25     # Cleared a boss
const PROMOTION_PROGRESS_DEEP_FLOOR: float = 0.15     # Reached a deep floor (floor >= 3)
const PROMOTION_PROGRESS_FULL_CLEAR: float = 0.25     # Cleared all rooms on a floor

# --- Gear Evolution ---
# META_PROGRESSION.md §1: irreversible tier upgrades, costs pillar materials.
# Tier 1→2 requires choosing a pillar. Tier 2→3 deepens the existing pillar.
const EVOLUTION_COST_TIER_2: float = 50.0   # pillar materials for tier 1→2
const EVOLUTION_COST_TIER_3: float = 120.0  # pillar materials for tier 2→3
const EVOLUTION_DUST_COST_TIER_2: float = 10.0  # resonant dust for tier 1→2
const EVOLUTION_DUST_COST_TIER_3: float = 25.0  # resonant dust for tier 2→3

static func evolution_material_cost(current_tier: int) -> float:
	if current_tier == TIER_BASE:
		return EVOLUTION_COST_TIER_2
	if current_tier == TIER_ALIGNED:
		return EVOLUTION_COST_TIER_3
	return 0.0

static func evolution_dust_cost(current_tier: int) -> float:
	if current_tier == TIER_BASE:
		return EVOLUTION_DUST_COST_TIER_2
	if current_tier == TIER_ALIGNED:
		return EVOLUTION_DUST_COST_TIER_3
	return 0.0

# --- Attunement ---
# 0 = none, 1 = Attuned I, 2 = Attuned II
const MAX_ATTUNEMENT_LEVEL: int = 2

# --- Inscriptions ---
# Persistent synergy nodes bound to gear; up to 3 tiers per node (META_PROGRESSION.md §5)
const MAX_INSCRIPTION_LEVEL: int = 3

# --- Materials ---
# Pillar materials are abstract counters (no inventory slots).
# Key = InfusionConstants.PILLAR_* StringName.
# Resonant dust is a small universal pacing resource.
const RESONANT_DUST_KEY: StringName = &"resonant_dust"
