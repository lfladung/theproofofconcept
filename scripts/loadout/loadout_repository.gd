extends Node
class_name LoadoutRepository

signal owner_snapshot_changed(owner_id: StringName, snapshot: Dictionary)

const LoadoutConstants = preload("res://scripts/loadout/loadout_constants.gd")
const LoadoutItemDefinition = preload("res://scripts/loadout/loadout_item_definition.gd")
const LoadoutVisualDefinition = preload("res://scripts/loadout/loadout_visual_definition.gd")
const _MetaConstants = preload("res://scripts/meta_progression/meta_progression_constants.gd")
const _GearItemData = preload("res://scripts/meta_progression/gear_item_data.gd")
const _TemperingManager = preload("res://scripts/meta_progression/tempering_manager.gd")

var _definitions_by_id: Dictionary = {}

## Optional reference to the run-scoped TemperingManager. Set by the orchestrator.
var _tempering_manager: _TemperingManager = null
var _owner_states: Dictionary = {}

## Tracks which instance_id keys were dynamically registered per owner so they can be
## cleaned up before a re-init (avoids stale definitions after a meta-store reload).
var _dynamic_instance_keys: Dictionary = {}  # String(owner_id) → Array[StringName]


func _ready() -> void:
	_definitions_by_id = _build_default_definitions()


## Set by the orchestrator at run start; cleared at run end.
func set_tempering_manager(mgr: RefCounted) -> void:
	_tempering_manager = mgr as _TemperingManager


func ensure_owner_initialized(owner_id: StringName) -> void:
	var normalized_owner_id := _normalize_owner_id(owner_id)
	if normalized_owner_id == &"" or _owner_states.has(normalized_owner_id):
		return
	var meta_store := _get_meta_store()
	if meta_store != null and bool(meta_store.call(&"is_initialized", normalized_owner_id)):
		_init_from_meta_store(normalized_owner_id, meta_store)
	else:
		_init_with_defaults(normalized_owner_id)


## Initializes owner state from MetaProgressionStore.
## Each gear instance gets its own item definition keyed by instance_id so that T1/T2/T3
## variants of the same base item all appear as separate rows in the loadout panel.
func _init_from_meta_store(owner_id: StringName, meta_store: Node) -> void:
	# Remove any stale dynamic definitions from a previous init for this owner.
	_cleanup_dynamic_definitions(owner_id)

	var all_gear_v: Variant = meta_store.call(&"get_all_gear_instances", owner_id)
	var all_gear: Array = all_gear_v as Array if all_gear_v is Array else []
	var owned_items: Array[StringName] = []
	var dynamic_keys: Array[StringName] = []
	var equipped_slots := LoadoutConstants.create_empty_equipped_slots()

	for gear_v in all_gear:
		if not (gear_v is Object):
			continue
		var gear := gear_v as Object
		var base_id    := StringName(String(gear.get(&"base_item_id")))
		var instance_id := StringName(String(gear.get(&"instance_id")))
		var slot_id    := StringName(String(gear.get(&"slot_id")))
		var tier       := int(gear.get(&"tier")) if gear.get(&"tier") != null else 1
		var pillar     := StringName(String(gear.get(&"pillar_alignment")))
		if base_id == &"" or instance_id == &"":
			continue

		# Build display name: "[T2 Edge] 1-Handed Sword"
		var tier_tag := "T%d" % tier
		if pillar != &"":
			tier_tag += " %s" % String(pillar).capitalize()
		var display_name := "[%s] %s" % [tier_tag, LoadoutConstants.item_display_name(base_id)]

		# Inherit stat_modifiers from the base definition (stats are scaled at aggregate time).
		var base_def := _definition_for_item(base_id)
		var stat_mods: Dictionary = base_def.stat_modifiers.duplicate() if base_def != null else {}

		# Inherit visual from base definition so the correct weapon mesh is used.
		var visual: LoadoutVisualDefinition = (
			base_def.visual_definition
			if base_def != null and base_def.visual_definition != null
			else LoadoutVisualDefinition.new("")
		)

		_definitions_by_id[instance_id] = LoadoutItemDefinition.new(
			instance_id, display_name, slot_id, "", stat_mods, visual
		)
		dynamic_keys.append(instance_id)
		owned_items.append(instance_id)

	_dynamic_instance_keys[String(owner_id)] = dynamic_keys
	owned_items = LoadoutConstants.sort_item_ids_by_slot_and_name(owned_items, _serialized_definitions_by_id())

	for slot_id in LoadoutConstants.SLOT_ORDER:
		var gear_v: Variant = meta_store.call(&"get_equipped_gear", owner_id, slot_id)
		if gear_v is Object and gear_v != null:
			var instance_id := StringName(String((gear_v as Object).get(&"instance_id")))
			if instance_id != &"" and _definitions_by_id.has(instance_id):
				equipped_slots[slot_id] = instance_id

	_owner_states[owner_id] = {
		"owned_items": owned_items,
		"equipped_slots": equipped_slots,
		"revision": 1,
	}


## Removes dynamic instance_id-keyed definitions registered for this owner.
func _cleanup_dynamic_definitions(owner_id: StringName) -> void:
	var key := String(owner_id)
	var keys: Array = _dynamic_instance_keys.get(key, [])
	for iid in keys:
		_definitions_by_id.erase(iid)
	_dynamic_instance_keys.erase(key)


## Fallback: initializes with hardcoded defaults (used when MetaProgressionStore has no data yet).
func _init_with_defaults(owner_id: StringName) -> void:
	var starter_owned: Array[StringName] = []
	for item_id in _definitions_by_id.keys():
		starter_owned.append(StringName(String(item_id)))
	starter_owned = LoadoutConstants.sort_item_ids_by_slot_and_name(starter_owned, _serialized_definitions_by_id())
	var equipped_slots := LoadoutConstants.create_empty_equipped_slots()
	equipped_slots[LoadoutConstants.SLOT_ARMOR] = &"armor_brigandine"
	equipped_slots[LoadoutConstants.SLOT_HELMET] = &"helmet_knight"
	equipped_slots[LoadoutConstants.SLOT_SWORD] = &"sword_kaykit_1handed"
	equipped_slots[LoadoutConstants.SLOT_HANDGUN] = &"handgun_red"
	equipped_slots[LoadoutConstants.SLOT_BOMB] = &"bomb_iron"
	equipped_slots[LoadoutConstants.SLOT_SHIELD] = &"shield_kaykit_round_color"
	_owner_states[owner_id] = {
		"owned_items": starter_owned,
		"equipped_slots": equipped_slots,
		"revision": 1,
	}


## Forces a re-sync of owned_items and equipped_slots from MetaProgressionStore.
## Call this after meta store data is loaded, before issuing a snapshot.
func refresh_owner_from_meta_store(owner_id: StringName) -> void:
	var normalized_owner_id := _normalize_owner_id(owner_id)
	if normalized_owner_id == &"":
		return
	var meta_store := _get_meta_store()
	if meta_store == null or not bool(meta_store.call(&"is_initialized", normalized_owner_id)):
		return
	_init_from_meta_store(normalized_owner_id, meta_store)


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
	# Sync equip change to MetaProgressionStore so it persists after the run.
	_sync_equip_to_meta_store(normalized_owner_id, item_id, definition.slot_id)
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
		"aggregated_stats": _aggregate_stats_for_slots(equipped_slots, owner_id),
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


func _aggregate_stats_for_slots(equipped_slots: Dictionary, owner_id: StringName = &"") -> Dictionary:
	var totals := {}
	for stat_key in LoadoutConstants.STAT_ORDER:
		totals[String(stat_key)] = 0.0
	var meta_store: Node = _get_meta_store()
	for slot_id in equipped_slots.keys():
		var item_id := StringName(String(equipped_slots.get(slot_id, "")))
		if item_id == &"":
			continue
		var definition := _definition_for_item(item_id)
		if definition == null:
			continue
		# Look up gear instance from MetaProgressionStore for tier/familiarity bonuses.
		var gear: _GearItemData = null
		if meta_store != null and owner_id != &"":
			var gear_v: Variant = meta_store.call(&"get_equipped_gear", owner_id, StringName(String(slot_id)))
			if gear_v is _GearItemData:
				gear = gear_v as _GearItemData
		var tier_mult := _MetaConstants.tier_stat_multiplier(gear.tier) if gear != null else 1.0
		var fam_bonus := gear.familiarity_stat_bonus() if gear != null else 0.0
		var temper_mult := 1.0
		if gear != null and _tempering_manager != null:
			temper_mult = _tempering_manager.get_stat_multiplier(gear.instance_id)
		var item_mult := tier_mult * (1.0 + fam_bonus) * temper_mult
		for stat_key in definition.stat_modifiers.keys():
			var normalized_stat_key := LoadoutConstants.normalize_stat_key(stat_key)
			var key_string := String(normalized_stat_key)
			var base_value := float(definition.stat_modifiers.get(stat_key, 0.0))
			var current_value := float(totals.get(key_string, 0.0))
			totals[key_string] = current_value + base_value * item_mult
	return totals


func _definition_for_item(item_id: StringName) -> LoadoutItemDefinition:
	var definition_v: Variant = _definitions_by_id.get(item_id, null)
	return definition_v as LoadoutItemDefinition if definition_v is LoadoutItemDefinition else null


func _build_default_definitions() -> Dictionary:
	var definitions := {}
	definitions[&"armor_brigandine"] = LoadoutItemDefinition.new(
		&"armor_brigandine",
		LoadoutConstants.item_display_name(&"armor_brigandine"),
		LoadoutConstants.SLOT_ARMOR,
		"Armor stats for the Knight body using the new green Knight texture.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 15.0,
		},
		LoadoutVisualDefinition.new("")
	)
	definitions[&"armor_scale"] = LoadoutItemDefinition.new(
		&"armor_scale",
		LoadoutConstants.item_display_name(&"armor_scale"),
		LoadoutConstants.SLOT_ARMOR,
		"Alternate armor stats for the Knight body using the original Knight texture.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 8.0,
			LoadoutConstants.STAT_SPEED: 1.25,
		},
		LoadoutVisualDefinition.new("")
	)
	definitions[&"helmet_knight"] = LoadoutItemDefinition.new(
		&"helmet_knight",
		LoadoutConstants.item_display_name(&"helmet_knight"),
		LoadoutConstants.SLOT_HELMET,
		"Base helmet using the standard knight texture.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 6.0,
		},
		LoadoutVisualDefinition.new("")
	)
	definitions[&"helmet_knight_orange"] = LoadoutItemDefinition.new(
		&"helmet_knight_orange",
		LoadoutConstants.item_display_name(&"helmet_knight_orange"),
		LoadoutConstants.SLOT_HELMET,
		"Variant helmet using the new orange texture pass.",
		{
			LoadoutConstants.STAT_MAX_HEALTH: 4.0,
			LoadoutConstants.STAT_SPEED: 0.5,
		},
		LoadoutVisualDefinition.new("")
	)
	var sword_items: Array[Dictionary] = [
		{
			"item_id": "sword_kaykit_1handed",
			"display_name": "1-Handed Sword",
			"description": "KayKit testing sword with the one-handed silhouette.",
			"scene_path": "res://scenes/equipment/weapons/kaykit_sword_1handed.tscn",
		},
		{
			"item_id": "sword_kaykit_a",
			"display_name": "Sword A",
			"description": "KayKit testing sword A.",
			"scene_path": "res://scenes/equipment/weapons/kaykit_sword_a.tscn",
		},
		{
			"item_id": "sword_kaykit_b",
			"display_name": "Sword B",
			"description": "KayKit testing sword B.",
			"scene_path": "res://scenes/equipment/weapons/kaykit_sword_b.tscn",
		},
		{
			"item_id": "sword_kaykit_c",
			"display_name": "Sword C",
			"description": "KayKit testing sword C.",
			"scene_path": "res://scenes/equipment/weapons/kaykit_sword_c.tscn",
		},
		{
			"item_id": "sword_kaykit_d",
			"display_name": "Sword D",
			"description": "KayKit testing sword D.",
			"scene_path": "res://scenes/equipment/weapons/kaykit_sword_d.tscn",
		},
		{
			"item_id": "sword_kaykit_e",
			"display_name": "Sword E",
			"description": "KayKit testing sword E.",
			"scene_path": "res://scenes/equipment/weapons/kaykit_sword_e.tscn",
		},
	]
	for sword_item in sword_items:
		var sword_item_id := StringName(String(sword_item.get("item_id", "")))
		definitions[sword_item_id] = LoadoutItemDefinition.new(
			sword_item_id,
			LoadoutConstants.item_display_name(sword_item_id),
			LoadoutConstants.SLOT_SWORD,
			String(sword_item.get("description", "")),
			{
				LoadoutConstants.STAT_MELEE_DAMAGE: 5.0,
			},
			LoadoutVisualDefinition.new(String(sword_item.get("scene_path", "")))
		)
	definitions[&"handgun_red"] = LoadoutItemDefinition.new(
		&"handgun_red",
		LoadoutConstants.item_display_name(&"handgun_red"),
		LoadoutConstants.SLOT_HANDGUN,
		"Fires red player projectiles while using the imported handgun mesh.",
		{
			LoadoutConstants.STAT_RANGED_DAMAGE: 4.0,
		},
		LoadoutVisualDefinition.new(
			"res://scenes/equipment/weapons/handgun_1.tscn",
			LoadoutConstants.PROJECTILE_STYLE_RED
		)
	)
	definitions[&"handgun_blue"] = LoadoutItemDefinition.new(
		&"handgun_blue",
		LoadoutConstants.item_display_name(&"handgun_blue"),
		LoadoutConstants.SLOT_HANDGUN,
		"Fires blue player projectiles while using the imported handgun mesh.",
		{
			LoadoutConstants.STAT_RANGED_DAMAGE: 4.0,
		},
		LoadoutVisualDefinition.new(
			"res://scenes/equipment/weapons/handgun_1.tscn",
			LoadoutConstants.PROJECTILE_STYLE_BLUE
		)
	)
	definitions[&"bomb_iron"] = LoadoutItemDefinition.new(
		&"bomb_iron",
		LoadoutConstants.item_display_name(&"bomb_iron"),
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
		LoadoutConstants.item_display_name(&"bomb_satchel"),
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
	var shield_items: Array[Dictionary] = [
		{
			"item_id": "shield_kaykit_badge_color",
			"display_name": "Shield Badge Color",
			"description": "KayKit testing shield with the preferred badge color variant.",
			"scene_path": "res://scenes/equipment/shields/kaykit_shield_badge_color.tscn",
		},
		{
			"item_id": "shield_kaykit_round_color",
			"display_name": "Shield Round Color",
			"description": "KayKit testing shield with the preferred round color variant.",
			"scene_path": "res://scenes/equipment/shields/kaykit_shield_round_color.tscn",
		},
		{
			"item_id": "shield_kaykit_spikes_color",
			"display_name": "Shield Spikes Color",
			"description": "KayKit testing shield with the preferred spiked color variant.",
			"scene_path": "res://scenes/equipment/shields/kaykit_shield_spikes_color.tscn",
		},
		{
			"item_id": "shield_kaykit_square_color",
			"display_name": "Shield Square Color",
			"description": "KayKit testing shield with the preferred square color variant.",
			"scene_path": "res://scenes/equipment/shields/kaykit_shield_square_color.tscn",
		},
	]
	for shield_item in shield_items:
		var shield_item_id := StringName(String(shield_item.get("item_id", "")))
		definitions[shield_item_id] = LoadoutItemDefinition.new(
			shield_item_id,
			LoadoutConstants.item_display_name(shield_item_id),
			LoadoutConstants.SLOT_SHIELD,
			String(shield_item.get("description", "")),
			{
				LoadoutConstants.STAT_DEFEND_DAMAGE_MULTIPLIER: -0.15,
			},
			LoadoutVisualDefinition.new(String(shield_item.get("scene_path", "")))
		)
	return definitions


## Syncs an equip change back to MetaProgressionStore so the choice persists after the run.
## [item_key] is an instance_id when the owner was initialized from the meta store,
## or a base_item_id for fallback/default owners.
func _sync_equip_to_meta_store(owner_id: StringName, item_key: StringName, slot_id: StringName) -> void:
	var meta_store := _get_meta_store()
	if meta_store == null:
		return
	# If item_key is a registered instance_id, use it directly.
	var dynamic_keys: Array = _dynamic_instance_keys.get(String(owner_id), [])
	if item_key in dynamic_keys:
		meta_store.call(&"equip_gear", owner_id, item_key)
		return
	# Fallback: treat item_key as base_item_id and find the first matching instance.
	var all_gear_v: Variant = meta_store.call(&"get_all_gear_instances", owner_id)
	if not (all_gear_v is Array):
		return
	for gear_v in (all_gear_v as Array):
		if not (gear_v is Object):
			continue
		var gear_base := StringName(String((gear_v as Object).get(&"base_item_id")))
		var gear_slot := StringName(String((gear_v as Object).get(&"slot_id")))
		if gear_base == item_key and gear_slot == slot_id:
			meta_store.call(&"equip_gear", owner_id, StringName(String((gear_v as Object).get(&"instance_id"))))
			return


func _get_meta_store() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/MetaProgressionStore")
