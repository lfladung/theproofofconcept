extends RefCounted
class_name LoadoutConstants

const SLOT_ARMOR: StringName = &"armor"
const SLOT_HELMET: StringName = &"helmet"
const SLOT_SWORD: StringName = &"sword"
const SLOT_HANDGUN: StringName = &"handgun"
const SLOT_BOMB: StringName = &"bomb"
const SLOT_SHIELD: StringName = &"shield"

const SLOT_ORDER: Array[StringName] = [
	SLOT_HELMET,
	SLOT_ARMOR,
	SLOT_SWORD,
	SLOT_HANDGUN,
	SLOT_BOMB,
	SLOT_SHIELD,
]

const SLOT_DISPLAY_NAMES := {
	SLOT_ARMOR: "Armor",
	SLOT_HELMET: "Helmet",
	SLOT_SWORD: "Sword",
	SLOT_HANDGUN: "Handgun",
	SLOT_BOMB: "Bomb",
	SLOT_SHIELD: "Shield",
}

const STAT_MAX_HEALTH: StringName = &"max_health"
const STAT_SPEED: StringName = &"speed"
const STAT_MELEE_DAMAGE: StringName = &"melee_attack_damage"
const STAT_RANGED_DAMAGE: StringName = &"ranged_damage"
const STAT_BOMB_DAMAGE: StringName = &"bomb_damage"
const STAT_DEFEND_DAMAGE_MULTIPLIER: StringName = &"defend_damage_multiplier"
# Edge affix
const STAT_CRIT_CHANCE_BONUS: StringName = &"crit_chance_bonus"
# Flow affix
const STAT_ATTACK_SPEED_MULTIPLIER: StringName = &"attack_speed_multiplier"
const STAT_COOLDOWN_REDUCTION: StringName = &"cooldown_reduction"
# Mass affix
const STAT_KNOCKBACK_MULTIPLIER: StringName = &"knockback_multiplier"
const STAT_AOE_RADIUS_BONUS: StringName = &"aoe_radius_bonus"
# Leech secondary
const STAT_LIFESTEAL_PERCENT: StringName = &"lifesteal_percent"
# Bind secondary
const STAT_ON_HIT_SLOW_CHANCE: StringName = &"on_hit_slow_chance"

# Stats that are displayed as percentages in the UI
const PERCENT_STATS: Array[StringName] = [
	STAT_CRIT_CHANCE_BONUS,
	STAT_COOLDOWN_REDUCTION,
	STAT_LIFESTEAL_PERCENT,
	STAT_ON_HIT_SLOW_CHANCE,
]

# Stats that are displayed as multipliers (e.g. x1.20) in the UI
const MULTIPLIER_STATS: Array[StringName] = [
	STAT_ATTACK_SPEED_MULTIPLIER,
	STAT_KNOCKBACK_MULTIPLIER,
]

const STAT_ORDER: Array[StringName] = [
	STAT_MAX_HEALTH,
	STAT_SPEED,
	STAT_MELEE_DAMAGE,
	STAT_RANGED_DAMAGE,
	STAT_BOMB_DAMAGE,
	STAT_DEFEND_DAMAGE_MULTIPLIER,
	STAT_CRIT_CHANCE_BONUS,
	STAT_ATTACK_SPEED_MULTIPLIER,
	STAT_COOLDOWN_REDUCTION,
	STAT_KNOCKBACK_MULTIPLIER,
	STAT_AOE_RADIUS_BONUS,
	STAT_LIFESTEAL_PERCENT,
	STAT_ON_HIT_SLOW_CHANCE,
]

const PROJECTILE_STYLE_RED: StringName = &"red"
const PROJECTILE_STYLE_BLUE: StringName = &"blue"


static func create_empty_equipped_slots() -> Dictionary:
	var slots := {}
	for slot_id in SLOT_ORDER:
		slots[slot_id] = &""
	return slots


static func slot_display_name(slot_id: StringName) -> String:
	return String(SLOT_DISPLAY_NAMES.get(slot_id, String(slot_id).capitalize()))


static func normalize_stat_key(stat_key: Variant) -> StringName:
	return StringName(String(stat_key))


static func sort_item_ids_by_slot_and_name(item_ids: Array, definitions_by_id: Dictionary) -> Array[StringName]:
	var normalized: Array[StringName] = []
	for item_id in item_ids:
		normalized.append(StringName(String(item_id)))
	normalized.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			var def_a: Dictionary = definitions_by_id.get(String(a), {})
			var def_b: Dictionary = definitions_by_id.get(String(b), {})
			var slot_a: StringName = StringName(String(def_a.get("slot_id", "")))
			var slot_b: StringName = StringName(String(def_b.get("slot_id", "")))
			var slot_idx_a := SLOT_ORDER.find(slot_a)
			var slot_idx_b := SLOT_ORDER.find(slot_b)
			if slot_idx_a != slot_idx_b:
				return slot_idx_a < slot_idx_b
			var name_a := String(def_a.get("display_name", String(a)))
			var name_b := String(def_b.get("display_name", String(b)))
			return name_a.naturalnocasecmp_to(name_b) < 0
	)
	return normalized


static func format_stat_modifier_lines(stat_modifiers: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for stat_key in STAT_ORDER:
		if not stat_modifiers.has(stat_key):
			continue
		var value: Variant = stat_modifiers.get(stat_key, 0)
		var amount := float(value)
		if is_zero_approx(amount):
			continue
		var sign_prefix := "+" if amount > 0.0 else ""
		var stat_label := String(stat_key).replace("_", " ").capitalize()
		if stat_key in PERCENT_STATS:
			lines.append("%s%d%% %s" % [sign_prefix, int(roundf(amount * 100.0)), stat_label])
		elif stat_key in MULTIPLIER_STATS:
			lines.append("%sx%.2f %s" % [sign_prefix, amount, stat_label])
		elif stat_key == STAT_DEFEND_DAMAGE_MULTIPLIER:
			lines.append("%s%.2f %s" % [sign_prefix, amount, stat_label])
		elif absf(amount - roundf(amount)) <= 0.001:
			lines.append("%s%d %s" % [sign_prefix, int(roundf(amount)), stat_label])
		else:
			lines.append("%s%.2f %s" % [sign_prefix, amount, stat_label])
	return lines
