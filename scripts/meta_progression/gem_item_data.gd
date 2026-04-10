extends Resource
class_name GemItemData

## A single gem instance with pillar affinity, behavior effect, and durability.
## Gems weaken with use (fatigue model) and eventually break. (META_PROGRESSION.md §7)

## Unique instance identifier, e.g. "edge_bleed_1234567".
var instance_id: StringName = &""

## Gem archetype, e.g. &"edge_bleed", &"flow_chain_dodge", &"surge_slow_on_charge".
var gem_type_id: StringName = &""

## Pillar this gem belongs to. Must be an InfusionConstants.PILLAR_* value.
var pillar_id: StringName = &""

## Identifies the behavior this gem enables (checked at runtime to apply effects).
## e.g. &"crits_apply_bleed", &"chaining_extends_dodge", &"charged_attacks_slow"
var effect_key: StringName = &""

## Current durability in range [0.0, 1.0]. Depletes with use; at 0 the gem is broken.
var durability: float = 1.0

## Set to true once durability reaches 0. Broken gems provide no effect.
var is_broken: bool = false


## Reduces durability by [amount]. Clamps to 0 and marks broken if depleted.
func deplete(amount: float) -> void:
	if is_broken:
		return
	durability = maxf(0.0, durability - absf(amount))
	if is_zero_approx(durability):
		is_broken = true


## Serializes to a plain Dictionary (JSON-safe).
func to_dictionary() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"gem_type_id": String(gem_type_id),
		"pillar_id": String(pillar_id),
		"effect_key": String(effect_key),
		"durability": durability,
		"is_broken": is_broken,
	}


## Deserializes from a Dictionary. Returns a new GemItemData.
static func from_dictionary(d: Dictionary) -> GemItemData:
	var gem := GemItemData.new()
	gem.instance_id = StringName(String(d.get("instance_id", "")))
	gem.gem_type_id = StringName(String(d.get("gem_type_id", "")))
	gem.pillar_id = StringName(String(d.get("pillar_id", "")))
	gem.effect_key = StringName(String(d.get("effect_key", "")))
	gem.durability = clampf(float(d.get("durability", 1.0)), 0.0, 1.0)
	gem.is_broken = bool(d.get("is_broken", false))
	return gem


## Creates a fresh gem instance from a type id, pillar, and effect key.
static func create_new(
	p_gem_type_id: StringName,
	p_pillar_id: StringName,
	p_effect_key: StringName
) -> GemItemData:
	var gem := GemItemData.new()
	gem.gem_type_id = p_gem_type_id
	gem.pillar_id = p_pillar_id
	gem.effect_key = p_effect_key
	gem.durability = 1.0
	gem.is_broken = false
	gem.instance_id = StringName("%s_%d" % [String(p_gem_type_id), randi()])
	return gem
