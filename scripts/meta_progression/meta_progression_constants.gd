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
