extends Resource
class_name GearItemData

## A single owned gear instance with full meta-progression state.
## This is a long-lived object — not disposable loot.
## Serializes to/from Dictionary for local save and future server sync.

const _MetaConstants = preload("res://scripts/meta_progression/meta_progression_constants.gd")

## Unique instance identifier, e.g. "sword_kaykit_1handed_2847361092".
## Generated once on creation; never changes.
var instance_id: StringName = &""

## Base item type — maps to a LoadoutItemDefinition key (e.g. &"sword_kaykit_1handed").
var base_item_id: StringName = &""

## Equipment slot — copied from the base definition for quick access.
var slot_id: StringName = &""

## Tier 1 = Base, 2 = Aligned, 3 = Specialized. (META_PROGRESSION.md §1)
var tier: int = _MetaConstants.TIER_BASE

## Which infusion pillar this item has evolved toward.
## Blank for tier 1 (unaligned). Must be an InfusionConstants.PILLAR_* value for tier 2+.
var pillar_alignment: StringName = &""

## Which pillar this item is attuned to. Independent of evolution path.
var attunement_pillar: StringName = &""

## 0 = none, 1 = Attuned I, 2 = Attuned II.
var attunement_level: int = 0

## Persistent synergy nodes bound to this item. (META_PROGRESSION.md §5)
## Each entry: { "pillar_id": StringName, "level": int }
## Max one entry per pillar_id; level range 1–MAX_INSCRIPTION_LEVEL.
var inscriptions: Array[Dictionary] = []

## Instance IDs of gems currently socketed in this item.
## Max slots = MetaProgressionConstants.gem_sockets_for_tier(tier).
var socketed_gem_instance_ids: Array[StringName] = []

## Accumulated XP from using this item in runs. Drives familiarity bonuses.
var familiarity_xp: float = 0.0


## Returns the current familiarity level based on accumulated XP.
func familiarity_level() -> _MetaConstants.FamiliarityLevel:
	return _MetaConstants.familiarity_level_for_xp(familiarity_xp)


## Returns the flat stat multiplier bonus from familiarity (0.0, 0.02, or 0.06).
func familiarity_stat_bonus() -> float:
	return _MetaConstants.familiarity_bonus_for_xp(familiarity_xp)


## Max gem sockets available on this item at its current tier.
func max_gem_sockets() -> int:
	return _MetaConstants.gem_sockets_for_tier(tier)


## Returns the inscription entry for a pillar, or null if none.
func inscription_for_pillar(pillar_id: StringName) -> Dictionary:
	for entry in inscriptions:
		if StringName(String(entry.get("pillar_id", ""))) == pillar_id:
			return entry
	return {}


## Serializes to a plain Dictionary (JSON-safe; all StringNames become Strings).
func to_dictionary() -> Dictionary:
	var inscriptions_serialized: Array = []
	for entry in inscriptions:
		inscriptions_serialized.append({
			"pillar_id": String(entry.get("pillar_id", "")),
			"level": int(entry.get("level", 1)),
		})
	var gems_serialized: Array = []
	for gem_id in socketed_gem_instance_ids:
		gems_serialized.append(String(gem_id))
	return {
		"instance_id": String(instance_id),
		"base_item_id": String(base_item_id),
		"slot_id": String(slot_id),
		"tier": tier,
		"pillar_alignment": String(pillar_alignment),
		"attunement_pillar": String(attunement_pillar),
		"attunement_level": attunement_level,
		"inscriptions": inscriptions_serialized,
		"socketed_gem_instance_ids": gems_serialized,
		"familiarity_xp": familiarity_xp,
	}


## Deserializes from a Dictionary. Returns a new GearItemData.
static func from_dictionary(d: Dictionary) -> GearItemData:
	var item := GearItemData.new()
	item.instance_id = StringName(String(d.get("instance_id", "")))
	item.base_item_id = StringName(String(d.get("base_item_id", "")))
	item.slot_id = StringName(String(d.get("slot_id", "")))
	item.tier = clampi(int(d.get("tier", 1)), 1, 3)
	item.pillar_alignment = StringName(String(d.get("pillar_alignment", "")))
	item.attunement_pillar = StringName(String(d.get("attunement_pillar", "")))
	item.attunement_level = clampi(int(d.get("attunement_level", 0)), 0, 2)
	item.familiarity_xp = maxf(0.0, float(d.get("familiarity_xp", 0.0)))
	var inscriptions_raw: Array = d.get("inscriptions", [])
	for entry in inscriptions_raw:
		if entry is Dictionary:
			item.inscriptions.append({
				"pillar_id": StringName(String((entry as Dictionary).get("pillar_id", ""))),
				"level": clampi(int((entry as Dictionary).get("level", 1)), 1, 3),
			})
	var gems_raw: Array = d.get("socketed_gem_instance_ids", [])
	for gem_id in gems_raw:
		item.socketed_gem_instance_ids.append(StringName(String(gem_id)))
	return item


## Creates a new tier-1 unaligned gear instance from a base item id and slot.
## Caller is responsible for providing a globally unique instance_id prefix.
static func create_new(p_base_item_id: StringName, p_slot_id: StringName) -> GearItemData:
	var item := GearItemData.new()
	item.base_item_id = p_base_item_id
	item.slot_id = p_slot_id
	item.tier = 1
	# Generate a unique instance_id from the base item id + a random integer.
	item.instance_id = StringName("%s_%d" % [String(p_base_item_id), randi()])
	return item
