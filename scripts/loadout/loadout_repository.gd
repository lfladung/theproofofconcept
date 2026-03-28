extends Node
class_name LoadoutRepository

signal owner_snapshot_changed(owner_id: StringName, snapshot: Dictionary)

const LoadoutConstants = preload("res://scripts/loadout/loadout_constants.gd")
const LoadoutItemDefinition = preload("res://scripts/loadout/loadout_item_definition.gd")
const LoadoutVisualDefinition = preload("res://scripts/loadout/loadout_visual_definition.gd")

var _definitions_by_id: Dictionary = {}
var _owner_states: Dictionary = {}


func _ready() -> void:
	_definitions_by_id = _build_default_definitions()


func ensure_owner_initialized(owner_id: StringName) -> void:
	var normalized_owner_id := _normalize_owner_id(owner_id)
	if normalized_owner_id == &"":
		return
	if _owner_states.has(normalized_owner_id):
		return
	var starter_owned: Array[StringName] = []
	for item_id in _definitions_by_id.keys():
		starter_owned.append(StringName(String(item_id)))
	starter_owned = LoadoutConstants.sort_item_ids_by_slot_and_name(starter_owned, _serialized_definitions_by_id())
	var equipped_slots := LoadoutConstants.create_empty_equipped_slots()
	equipped_slots[LoadoutConstants.SLOT_ARMOR] = &"armor_brigandine"
	equipped_slots[LoadoutConstants.SLOT_HELMET] = &"helmet_knight"
	equipped_slots[LoadoutConstants.SLOT_SWORD] = &"sword_knight"
	equipped_slots[LoadoutConstants.SLOT_HANDGUN] = &"handgun_red"
	equipped_slots[LoadoutConstants.SLOT_BOMB] = &"bomb_iron"
	equipped_slots[LoadoutConstants.SLOT_SHIELD] = &"shield_warden"
	_owner_states[normalized_owner_id] = {
		"owned_items": starter_owned,
		"equipped_slots": equipped_slots,
		"revision": 1,
	}


func get_snapshot(owner_id: StringName) -> Dictionary:
	var normalized_owner_id := _normalize_owner_id(owner_id)
	ensure_owner_initialized(normalized_owner_id)
	var state_v: Variant = _owner_states.get(normalized_owner_id, null)
	if state_v is not Dictionary:
		return {}
	return _build_snapshot(normalized_owner_id, state_v as Dictionary)


func request_equip(owner_id: StringName, item_id: StringName, context: Dictionary) -> Dictionary:
	var normalized_owner_id := _normalize_owner_id(owner_id)
	ensure_owner_initialized(normalized_owner_id)
	var validation := validate_request(normalized_owner_id, &"equip", item_id, context)
	if not bool(validation.get("ok", false)):
		return validation
	var state := (_owner_states.get(normalized_owner_id, {}) as Dictionary).duplicate(true)
	var definition := _definition_for_item(item_id)
	state["equipped_slots"][definition.slot_id] = definition.item_id
	state["revision"] = int(state.get("revision", 0)) + 1
	_owner_states[normalized_owner_id] = state
	var snapshot := _build_snapshot(normalized_owner_id, state)
	owner_snapshot_changed.emit(normalized_owner_id, snapshot)
	return {
		"ok": true,
		"message": "",
		"snapshot": snapshot,
	}


func request_unequip(owner_id: StringName, slot_id: StringName, context: Dictionary) -> Dictionary:
	var normalized_owner_id := _normalize_owner_id(owner_id)
	ensure_owner_initialized(normalized_owner_id)
	var snapshot := get_snapshot(normalized_owner_id)
	return {
		"ok": false,
		"message": "Each loadout slot must always stay equipped. Choose another item to replace it.",
		"snapshot": snapshot,
	}


func validate_request(owner_id: StringName, action: StringName, value: StringName, context: Dictionary) -> Dictionary:
	var normalized_owner_id := _normalize_owner_id(owner_id)
	var safe_room_only := bool(context.get("safe_room_only", true))
	var is_safe_room := bool(context.get("is_safe_room", false))
	if safe_room_only and not is_safe_room:
		return {
			"ok": false,
			"message": "Loadout is only available in safe rooms.",
			"snapshot": get_snapshot(normalized_owner_id),
		}
	var state_v: Variant = _owner_states.get(normalized_owner_id, null)
	if state_v is not Dictionary:
		return {
			"ok": false,
			"message": "Missing loadout state.",
			"snapshot": {},
		}
	var state: Dictionary = state_v as Dictionary
	var owned_items: Array = state.get("owned_items", [])
	if action == &"equip":
		if not _definitions_by_id.has(value):
			return {
				"ok": false,
				"message": "Unknown item.",
				"snapshot": _build_snapshot(normalized_owner_id, state),
			}
		var item_owned := false
		for owned in owned_items:
			if StringName(String(owned)) == value:
				item_owned = true
				break
		if not item_owned:
			return {
				"ok": false,
				"message": "Item is not owned.",
				"snapshot": _build_snapshot(normalized_owner_id, state),
			}
		return {
			"ok": true,
			"message": "",
			"snapshot": _build_snapshot(normalized_owner_id, state),
		}
	if action == &"unequip":
		return {
			"ok": false,
			"message": "Each loadout slot must always stay equipped. Choose another item to replace it.",
			"snapshot": _build_snapshot(normalized_owner_id, state),
		}
	return {
		"ok": false,
		"message": "Unsupported request.",
		"snapshot": _build_snapshot(normalized_owner_id, state),
	}


func get_item_definition(item_id: StringName) -> Dictionary:
	var normalized_item_id := StringName(String(item_id))
	if not _definitions_by_id.has(normalized_item_id):
		return {}
	var definition: LoadoutItemDefinition = _definitions_by_id[normalized_item_id] as LoadoutItemDefinition
	return definition.to_dictionary() if definition != null else {}


func _normalize_owner_id(owner_id: StringName) -> StringName:
	return StringName(String(owner_id).strip_edges())


func _build_snapshot(owner_id: StringName, state: Dictionary) -> Dictionary:
	var owned_raw: Array = state.get("owned_items", [])
	var owned_items: Array[StringName] = []
	for item_id in owned_raw:
		owned_items.append(StringName(String(item_id)))
	var equipped_slots: Dictionary = LoadoutConstants.create_empty_equipped_slots()
	var stored_slots: Dictionary = state.get("equipped_slots", {})
	for slot_id in equipped_slots.keys():
		equipped_slots[slot_id] = StringName(String(stored_slots.get(slot_id, "")))
	var grouped_owned_items := {}
	for slot_id in LoadoutConstants.SLOT_ORDER:
		grouped_owned_items[String(slot_id)] = []
	for item_id in owned_items:
		var definition := get_item_definition(item_id)
		var slot_id := StringName(String(definition.get("slot_id", "")))
		var slot_key := String(slot_id)
		if not grouped_owned_items.has(slot_key):
			grouped_owned_items[slot_key] = []
		var slot_items: Array = grouped_owned_items.get(slot_key, [])
		slot_items.append(String(item_id))
		grouped_owned_items[slot_key] = slot_items
	var owned_item_strings: Array[String] = []
	for item_id in owned_items:
		owned_item_strings.append(String(item_id))
	return {
		"owner_id": String(owner_id),
		"revision": int(state.get("revision", 0)),
		"owned_items": owned_item_strings,
		"owned_items_by_slot": grouped_owned_items,
		"equipped_slots": _stringify_dictionary_keys_and_values(equipped_slots),
		"item_definitions": _serialized_definitions_by_id(),
		"aggregated_stats": _aggregate_stats_for_slots(equipped_slots),
	}


func _stringify_dictionary_keys_and_values(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source.keys():
		out[String(key)] = String(source[key])
	return out


func _serialized_definitions_by_id() -> Dictionary:
	var out := {}
	for item_id in _definitions_by_id.keys():
		var definition: LoadoutItemDefinition = _definitions_by_id[item_id] as LoadoutItemDefinition
		if definition == null:
			continue
		out[String(item_id)] = definition.to_dictionary()
	return out


func _aggregate_stats_for_slots(equipped_slots: Dictionary) -> Dictionary:
	var totals := {}
	for stat_key in LoadoutConstants.STAT_ORDER:
		totals[String(stat_key)] = 0.0
	for slot_id in equipped_slots.keys():
		var item_id := StringName(String(equipped_slots.get(slot_id, "")))
		if item_id == &"":
			continue
		var definition := _definition_for_item(item_id)
		if definition == null:
			continue
		for stat_key in definition.stat_modifiers.keys():
			var normalized_stat_key := LoadoutConstants.normalize_stat_key(stat_key)
			var key_string := String(normalized_stat_key)
			var current_value := float(totals.get(key_string, 0.0))
			totals[key_string] = current_value + float(definition.stat_modifiers.get(stat_key, 0.0))
	return totals


func _definition_for_item(item_id: StringName) -> LoadoutItemDefinition:
	var definition_v: Variant = _definitions_by_id.get(item_id, null)
	return definition_v as LoadoutItemDefinition if definition_v is LoadoutItemDefinition else null


func _build_default_definitions() -> Dictionary:
	var definitions := {}
	definitions[&"armor_brigandine"] = LoadoutItemDefinition.new(
		&"armor_brigandine",
		"Red Chestplate",
		LoadoutConstants.SLOT_ARMOR,
		"Red chestplate variant for the safe-room loadout test.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 15.0,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/armor/red_chestplate.tscn")
	)
	definitions[&"armor_scale"] = LoadoutItemDefinition.new(
		&"armor_scale",
		"Blue Chestplate",
		LoadoutConstants.SLOT_ARMOR,
		"Blue chestplate variant for swapping and stat checks.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 8.0,
			LoadoutConstants.STAT_SPEED: 1.25,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/armor/blue_chestplate.tscn")
	)
	definitions[&"helmet_knight"] = LoadoutItemDefinition.new(
		&"helmet_knight",
		"Knight Helmet",
		LoadoutConstants.SLOT_HELMET,
		"Base helmet using the standard knight texture.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 6.0,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/helmet/helmet_knight_base.tscn")
	)
	definitions[&"helmet_knight_orange"] = LoadoutItemDefinition.new(
		&"helmet_knight_orange",
		"Knight Helmet Orange",
		LoadoutConstants.SLOT_HELMET,
		"Variant helmet using the new orange texture pass.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 4.0,
			LoadoutConstants.STAT_SPEED: 0.5,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/helmet/helmet_knight_orange.tscn")
	)
	definitions[&"sword_knight"] = LoadoutItemDefinition.new(
		&"sword_knight",
		"Sword",
		LoadoutConstants.SLOT_SWORD,
		"Standard sword for melee combat.",
		{
			LoadoutConstants.STAT_MELEE_DAMAGE: 5.0,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/weapons/sword_texture.tscn")
	)
	definitions[&"sword_knight_v2"] = LoadoutItemDefinition.new(
		&"sword_knight_v2",
		"Sword V2",
		LoadoutConstants.SLOT_SWORD,
		"Variant sword using the second texture set.",
		{
			LoadoutConstants.STAT_MELEE_DAMAGE: 7.0,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/weapons/sword_v2_texture.tscn")
	)
	definitions[&"handgun_red"] = LoadoutItemDefinition.new(
		&"handgun_red",
		"Red Handgun",
		LoadoutConstants.SLOT_HANDGUN,
		"Fires red player projectiles while using the shared placeholder stowed mesh.",
		{
			LoadoutConstants.STAT_RANGED_DAMAGE: 4.0,
		},
		LoadoutVisualDefinition.new(
			"res://scenes/equipment/weapons/handgun_placeholder.tscn",
			LoadoutConstants.PROJECTILE_STYLE_RED
		)
	)
	definitions[&"handgun_blue"] = LoadoutItemDefinition.new(
		&"handgun_blue",
		"Blue Handgun",
		LoadoutConstants.SLOT_HANDGUN,
		"Fires blue player projectiles while using the shared placeholder stowed mesh.",
		{
			LoadoutConstants.STAT_RANGED_DAMAGE: 4.0,
		},
		LoadoutVisualDefinition.new(
			"res://scenes/equipment/weapons/handgun_placeholder.tscn",
			LoadoutConstants.PROJECTILE_STYLE_BLUE
		)
	)
	definitions[&"bomb_iron"] = LoadoutItemDefinition.new(
		&"bomb_iron",
		"Iron Bomb",
		LoadoutConstants.SLOT_BOMB,
		"Round bomb placeholder for dedicated throw input testing.",
		{
			LoadoutConstants.STAT_BOMB_DAMAGE: 6.0,
		},
		LoadoutVisualDefinition.new(
			"res://scenes/equipment/bombs/bomb_round_placeholder.tscn",
			LoadoutConstants.PROJECTILE_STYLE_RED
		)
	)
	definitions[&"bomb_satchel"] = LoadoutItemDefinition.new(
		&"bomb_satchel",
		"Satchel Bomb",
		LoadoutConstants.SLOT_BOMB,
		"Alternate bomb placeholder with slightly higher splash emphasis.",
		{
			LoadoutConstants.STAT_BOMB_DAMAGE: 4.0,
			LoadoutConstants.STAT_MAX_HEALTH: 2.0,
		},
		LoadoutVisualDefinition.new(
			"res://scenes/equipment/bombs/bomb_satchel_placeholder.tscn",
			LoadoutConstants.PROJECTILE_STYLE_BLUE
		)
	)
	definitions[&"shield_warden"] = LoadoutItemDefinition.new(
		&"shield_warden",
		"Shield",
		LoadoutConstants.SLOT_SHIELD,
		"Standard shield for guarding and defense.",
		{
			LoadoutConstants.STAT_DEFEND_DAMAGE_MULTIPLIER: -0.15,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/shields/base_model_v01_shield.tscn")
	)
	definitions[&"shield_warden_v2"] = LoadoutItemDefinition.new(
		&"shield_warden_v2",
		"Shield V2",
		LoadoutConstants.SLOT_SHIELD,
		"Variant shield using the new shield texture set.",
		{
			LoadoutConstants.STAT_DEFEND_DAMAGE_MULTIPLIER: -0.25,
			LoadoutConstants.STAT_SPEED: -0.4,
		},
		LoadoutVisualDefinition.new("res://scenes/equipment/shields/shield_v2_texture.tscn")
	)
	return definitions
