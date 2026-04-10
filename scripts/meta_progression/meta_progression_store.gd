extends Node

## Authoritative store for all persistent meta-progression state.
##
## This is the single mutation gateway for gear instances, gems, and materials.
## All reads and writes go through this node — nothing mutates state directly.
##
## Persistence design:
##   Now:    Local JSON per player at user://meta_progression_{player_id}.json
##   Later:  swap save_local/load_local for server RPC calls.
##           apply_server_state() is the future server-authority entry point;
##           it uses the same deserialization path as the local file loader.

const _MetaConstants = preload("res://scripts/meta_progression/meta_progression_constants.gd")
const _GearItemData = preload("res://scripts/meta_progression/gear_item_data.gd")
const _GemItemData = preload("res://scripts/meta_progression/gem_item_data.gd")
const _LoadoutConstants = preload("res://scripts/loadout/loadout_constants.gd")
const _InfusionConstants = preload("res://scripts/infusion/infusion_constants.gd")

## Emitted whenever any player's state changes (gear equip, materials, gems, etc.).
signal store_changed(player_id: StringName)

## Internal state: Dictionary[String → _PlayerState dict]
## _PlayerState shape documented at bottom of this file.
var _player_states: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if RunState != null:
		RunState.run_ended.connect(_on_run_ended)


func _on_run_ended(_snapshot: Dictionary) -> void:
	# Auto-save all initialized players after every run.
	for player_id_str in _player_states.keys():
		save_local(StringName(player_id_str))


# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------

## Ensures a player has an initialized state (with starter gear).
## Safe to call multiple times — no-ops if already initialized.
func ensure_player_initialized(player_id: StringName) -> void:
	var key := _key(player_id)
	if _player_states.has(key):
		return
	_player_states[key] = _build_starter_state()


## Returns true if player state is loaded/initialized.
func is_initialized(player_id: StringName) -> bool:
	return _player_states.has(_key(player_id))


# ---------------------------------------------------------------------------
# Query — Gear
# ---------------------------------------------------------------------------

## Returns the GearItemData equipped in [slot_id] for [player_id], or null.
func get_equipped_gear(player_id: StringName, slot_id: StringName) -> _GearItemData:
	var state := _get_state(player_id)
	var equipped: Dictionary = state.get("equipped_instance_ids", {})
	var instance_id := StringName(String(equipped.get(String(slot_id), "")))
	if instance_id == &"":
		return null
	return _get_gear_instance(state, instance_id)


## Returns the stash gear items for [slot_id] (up to MAX_STASH_PER_SLOT).
func get_stash_gear(player_id: StringName, slot_id: StringName) -> Array[_GearItemData]:
	var state := _get_state(player_id)
	var stash_map: Dictionary = state.get("stash_instance_ids", {})
	var stash_ids: Array = stash_map.get(String(slot_id), [])
	var result: Array[_GearItemData] = []
	for iid in stash_ids:
		var item := _get_gear_instance(state, StringName(String(iid)))
		if item != null:
			result.append(item)
	return result


## Returns all owned gear instances for this player (equipped + stash).
func get_all_gear_instances(player_id: StringName) -> Array[_GearItemData]:
	var state := _get_state(player_id)
	var gear_map: Dictionary = state.get("gear_instances", {})
	var result: Array[_GearItemData] = []
	for item_v in gear_map.values():
		if item_v is _GearItemData:
			result.append(item_v as _GearItemData)
	return result


# ---------------------------------------------------------------------------
# Query — Gems
# ---------------------------------------------------------------------------

## Returns the GearItemData for a specific instance_id, or null.
func get_gear_instance(player_id: StringName, instance_id: StringName) -> _GearItemData:
	var state := _get_state(player_id)
	return _get_gear_instance(state, instance_id)


## Returns the GemItemData for a specific instance_id, or null.
func get_gem_instance(player_id: StringName, instance_id: StringName) -> _GemItemData:
	var state := _get_state(player_id)
	return _get_gem_instance(state, instance_id)


## Returns gems currently socketed in the active gem bar (in slot order).
## Entries may be null for empty slots.
func get_socketed_gems(player_id: StringName) -> Array[_GemItemData]:
	var state := _get_state(player_id)
	var slots: Array = state.get("socketed_gem_slots", [])
	var count: int = int(state.get("gem_slot_count", _MetaConstants.MAX_GEM_SLOTS_BASE))
	var result: Array[_GemItemData] = []
	for i in range(count):
		if i < slots.size():
			var iid := StringName(String(slots[i]))
			result.append(_get_gem_instance(state, iid) if iid != &"" else null)
		else:
			result.append(null)
	return result


## Returns all gem instances in this player's inventory (including socketed).
func get_all_gem_instances(player_id: StringName) -> Array[_GemItemData]:
	var state := _get_state(player_id)
	var gem_map: Dictionary = state.get("gem_instances", {})
	var result: Array[_GemItemData] = []
	for gem_v in gem_map.values():
		if gem_v is _GemItemData:
			result.append(gem_v as _GemItemData)
	return result


## Returns the current gem slot count for this player.
func get_gem_slot_count(player_id: StringName) -> int:
	var state := _get_state(player_id)
	return int(state.get("gem_slot_count", _MetaConstants.MAX_GEM_SLOTS_BASE))


# ---------------------------------------------------------------------------
# Query — Materials
# ---------------------------------------------------------------------------

## Returns a copy of the materials dict { pillar_id (String) → float }.
func get_materials(player_id: StringName) -> Dictionary:
	var state := _get_state(player_id)
	return (state.get("materials", {}) as Dictionary).duplicate()


## Returns the amount of a specific pillar material.
func get_material_amount(player_id: StringName, pillar_id: StringName) -> float:
	var state := _get_state(player_id)
	var materials: Dictionary = state.get("materials", {})
	return float(materials.get(String(pillar_id), 0.0))


## Returns the current resonant dust amount.
func get_resonant_dust(player_id: StringName) -> float:
	var state := _get_state(player_id)
	return float(state.get("resonant_dust", 0.0))


# ---------------------------------------------------------------------------
# Mutations — Materials
# ---------------------------------------------------------------------------

## Adds [amount] of pillar material to this player's ledger.
func add_materials(player_id: StringName, pillar_id: StringName, amount: float) -> void:
	var state := _get_state(player_id)
	var materials: Dictionary = state.get("materials", {})
	var key := String(pillar_id)
	materials[key] = float(materials.get(key, 0.0)) + maxf(0.0, amount)
	state["materials"] = materials
	_set_state(player_id, state)


## Spends [amount] of pillar material. Returns true on success, false if insufficient.
func spend_materials(player_id: StringName, pillar_id: StringName, amount: float) -> bool:
	var state := _get_state(player_id)
	var materials: Dictionary = state.get("materials", {})
	var key := String(pillar_id)
	var current := float(materials.get(key, 0.0))
	if current < amount:
		return false
	materials[key] = current - amount
	state["materials"] = materials
	_set_state(player_id, state)
	return true


## Adds resonant dust.
func add_resonant_dust(player_id: StringName, amount: float) -> void:
	var state := _get_state(player_id)
	state["resonant_dust"] = float(state.get("resonant_dust", 0.0)) + maxf(0.0, amount)
	_set_state(player_id, state)


# ---------------------------------------------------------------------------
# Mutations — Gear
# ---------------------------------------------------------------------------

## Equips [instance_id] into its slot. Moves the previous equipped item to stash if possible.
## Returns true on success.
func equip_gear(player_id: StringName, instance_id: StringName) -> bool:
	var state := _get_state(player_id)
	var item := _get_gear_instance(state, instance_id)
	if item == null:
		return false
	var slot_key := String(item.slot_id)
	var equipped: Dictionary = state.get("equipped_instance_ids", {})
	var prev_equipped_id := StringName(String(equipped.get(slot_key, "")))
	# Remove the incoming item from stash first — this frees a slot so the previously
	# equipped item can always swap in, even when the stash was full.
	_remove_from_stash(state, item.slot_id, instance_id)
	# Move the previously equipped item to stash.
	if prev_equipped_id != &"" and prev_equipped_id != instance_id:
		var stash_map: Dictionary = state.get("stash_instance_ids", {})
		var stash_ids: Array = stash_map.get(slot_key, []).duplicate()
		if stash_ids.size() < _MetaConstants.MAX_STASH_PER_SLOT:
			stash_ids.append(String(prev_equipped_id))
			stash_map[slot_key] = stash_ids
			state["stash_instance_ids"] = stash_map
	equipped[slot_key] = String(instance_id)
	state["equipped_instance_ids"] = equipped
	_set_state(player_id, state)
	return true


## Moves [instance_id] to the stash for its slot (unequips it if equipped).
## Returns true on success, false if stash is full or item not found.
func stash_gear(player_id: StringName, instance_id: StringName) -> bool:
	var state := _get_state(player_id)
	var item := _get_gear_instance(state, instance_id)
	if item == null:
		return false
	var slot_key := String(item.slot_id)
	var stash_map: Dictionary = state.get("stash_instance_ids", {})
	var stash_ids: Array = stash_map.get(slot_key, []).duplicate()
	# Already in stash.
	for iid in stash_ids:
		if StringName(String(iid)) == instance_id:
			return true
	if stash_ids.size() >= _MetaConstants.MAX_STASH_PER_SLOT:
		return false
	# If this was equipped, clear the slot.
	var equipped: Dictionary = state.get("equipped_instance_ids", {})
	if StringName(String(equipped.get(slot_key, ""))) == instance_id:
		equipped[slot_key] = ""
		state["equipped_instance_ids"] = equipped
	stash_ids.append(String(instance_id))
	stash_map[slot_key] = stash_ids
	state["stash_instance_ids"] = stash_map
	_set_state(player_id, state)
	return true


## Adds a new gear instance to this player's collection (not equipped; goes to stash or equipped if slot is empty).
func add_gear_instance(player_id: StringName, item: _GearItemData) -> void:
	var state := _get_state(player_id)
	var gear_map: Dictionary = state.get("gear_instances", {})
	gear_map[String(item.instance_id)] = item
	state["gear_instances"] = gear_map
	# Auto-equip if the slot is empty.
	var equipped: Dictionary = state.get("equipped_instance_ids", {})
	var slot_key := String(item.slot_id)
	if String(equipped.get(slot_key, "")) == "":
		equipped[slot_key] = String(item.instance_id)
		state["equipped_instance_ids"] = equipped
	_set_state(player_id, state)


# ---------------------------------------------------------------------------
# Mutations — Gear Evolution & Promotion
# ---------------------------------------------------------------------------

## Evolves a gear piece to the next tier. (META_PROGRESSION.md §1)
## For tier 1→2, [target_pillar] chooses the pillar alignment (required).
## For tier 2→3, [target_pillar] is ignored (keeps existing alignment).
## Returns { "ok": bool, "message": String }.
func evolve_gear(player_id: StringName, instance_id: StringName, target_pillar: StringName = &"") -> Dictionary:
	var state := _get_state(player_id)
	var item := _get_gear_instance(state, instance_id)
	if item == null:
		return {"ok": false, "message": "Gear not found."}
	if item.tier >= _MetaConstants.TIER_SPECIALIZED:
		return {"ok": false, "message": "Already at max tier."}
	if item.promotion_progress < 1.0:
		return {"ok": false, "message": "Promotion not complete."}
	# Determine pillar for this evolution.
	var pillar := target_pillar
	if item.tier == _MetaConstants.TIER_BASE:
		if pillar == &"":
			return {"ok": false, "message": "Choose a pillar alignment."}
	else:
		pillar = item.pillar_alignment
	# Check material costs.
	var mat_cost := _MetaConstants.evolution_material_cost(item.tier)
	var dust_cost := _MetaConstants.evolution_dust_cost(item.tier)
	var materials: Dictionary = state.get("materials", {})
	var current_mats := float(materials.get(String(pillar), 0.0))
	if current_mats < mat_cost:
		return {"ok": false, "message": "Not enough %s materials (%d/%d)." % [String(pillar), int(current_mats), int(mat_cost)]}
	var current_dust := float(state.get("resonant_dust", 0.0))
	if current_dust < dust_cost:
		return {"ok": false, "message": "Not enough resonant dust (%d/%d)." % [int(current_dust), int(dust_cost)]}
	# Apply evolution (irreversible).
	materials[String(pillar)] = current_mats - mat_cost
	state["materials"] = materials
	state["resonant_dust"] = current_dust - dust_cost
	item.tier += 1
	item.pillar_alignment = pillar
	item.promotion_progress = 0.0
	_set_state(player_id, state)
	return {"ok": true, "message": ""}


## Grants promotion progress to a specific gear instance. Clamps to [0, 1].
func grant_promotion_progress(player_id: StringName, instance_id: StringName, amount: float) -> void:
	var state := _get_state(player_id)
	var item := _get_gear_instance(state, instance_id)
	if item == null or item.tier >= _MetaConstants.TIER_SPECIALIZED:
		return
	item.promotion_progress = clampf(item.promotion_progress + amount, 0.0, 1.0)
	_set_state(player_id, state)


## Grants promotion progress to ALL equipped gear for a player.
func grant_promotion_progress_to_equipped(player_id: StringName, amount: float) -> void:
	var state := _get_state(player_id)
	var equipped: Dictionary = state.get("equipped_instance_ids", {})
	var changed := false
	for slot_key in equipped.keys():
		var iid := StringName(String(equipped.get(slot_key, "")))
		var item := _get_gear_instance(state, iid)
		if item == null or item.tier >= _MetaConstants.TIER_SPECIALIZED:
			continue
		item.promotion_progress = clampf(item.promotion_progress + amount, 0.0, 1.0)
		changed = true
	if changed:
		_set_state(player_id, state)


## Adds familiarity XP to a specific gear instance.
func add_familiarity_xp(player_id: StringName, instance_id: StringName, amount: float) -> void:
	var state := _get_state(player_id)
	var item := _get_gear_instance(state, instance_id)
	if item == null:
		return
	item.familiarity_xp += maxf(0.0, amount)
	_set_state(player_id, state)


## Adds familiarity XP to ALL equipped gear for a player (e.g. after a run).
func add_familiarity_xp_to_equipped(player_id: StringName, amount: float) -> void:
	var state := _get_state(player_id)
	var equipped: Dictionary = state.get("equipped_instance_ids", {})
	var changed := false
	for slot_key in equipped.keys():
		var iid := StringName(String(equipped.get(slot_key, "")))
		var item := _get_gear_instance(state, iid)
		if item == null:
			continue
		item.familiarity_xp += maxf(0.0, amount)
		changed = true
	if changed:
		_set_state(player_id, state)


# ---------------------------------------------------------------------------
# Mutations — Gems
# ---------------------------------------------------------------------------

## Adds a gem instance to this player's gem inventory.
func add_gem(player_id: StringName, gem: _GemItemData) -> void:
	var state := _get_state(player_id)
	var gem_map: Dictionary = state.get("gem_instances", {})
	gem_map[String(gem.instance_id)] = gem
	state["gem_instances"] = gem_map
	_set_state(player_id, state)


## Sockets gem [gem_instance_id] into active gem bar slot [slot_index].
## Returns true on success. Replaces whatever was in that slot (unsockets it, keeps in inventory).
func socket_gem(player_id: StringName, gem_instance_id: StringName, slot_index: int) -> bool:
	var state := _get_state(player_id)
	var count := int(state.get("gem_slot_count", _MetaConstants.MAX_GEM_SLOTS_BASE))
	if slot_index < 0 or slot_index >= count:
		return false
	if _get_gem_instance(state, gem_instance_id) == null:
		return false
	var slots: Array = (state.get("socketed_gem_slots", []) as Array).duplicate()
	while slots.size() <= slot_index:
		slots.append("")
	slots[slot_index] = String(gem_instance_id)
	state["socketed_gem_slots"] = slots
	_set_state(player_id, state)
	return true


## Clears the gem bar slot at [slot_index] (gem remains in inventory).
func unsocket_gem(player_id: StringName, slot_index: int) -> void:
	var state := _get_state(player_id)
	var slots: Array = (state.get("socketed_gem_slots", []) as Array).duplicate()
	if slot_index >= 0 and slot_index < slots.size():
		slots[slot_index] = ""
	state["socketed_gem_slots"] = slots
	_set_state(player_id, state)


## Expands gem slot count by 1, up to MAX_GEM_SLOTS_MAX.
func unlock_gem_slot(player_id: StringName) -> void:
	var state := _get_state(player_id)
	var current := int(state.get("gem_slot_count", _MetaConstants.MAX_GEM_SLOTS_BASE))
	state["gem_slot_count"] = mini(current + 1, _MetaConstants.MAX_GEM_SLOTS_MAX)
	_set_state(player_id, state)


# ---------------------------------------------------------------------------
# Persistence — Local
# ---------------------------------------------------------------------------

## Saves the player's full state to user://meta_progression_{player_id}.json.
func save_local(player_id: StringName) -> void:
	ensure_player_initialized(player_id)
	var path := _save_path(player_id)
	var data := serialize_player_state(player_id)
	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("MetaProgressionStore: failed to open %s for writing (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(json_string)
	file.close()


## Loads player state from user://meta_progression_{player_id}.json.
## Returns true on success. Initializes with starter state if file not found.
func load_local(player_id: StringName) -> bool:
	var path := _save_path(player_id)
	if not FileAccess.file_exists(path):
		ensure_player_initialized(player_id)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MetaProgressionStore: failed to open %s for reading (error %d)" % [path, FileAccess.get_open_error()])
		ensure_player_initialized(player_id)
		return false
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or parsed is not Dictionary:
		push_error("MetaProgressionStore: failed to parse %s" % path)
		ensure_player_initialized(player_id)
		return false
	apply_server_state(player_id, parsed as Dictionary)
	return true


# ---------------------------------------------------------------------------
# Persistence — Server sync (future authority entry point)
# ---------------------------------------------------------------------------

## Serializes the full player state to a plain Dictionary (JSON-safe).
## This is the canonical wire format for future server communication.
func serialize_player_state(player_id: StringName) -> Dictionary:
	ensure_player_initialized(player_id)
	var state := _get_state(player_id)
	# Serialize gear instances.
	var gear_serialized := {}
	var gear_map: Dictionary = state.get("gear_instances", {})
	for iid in gear_map.keys():
		var item: _GearItemData = gear_map[iid] as _GearItemData
		if item != null:
			gear_serialized[String(iid)] = item.to_dictionary()
	# Serialize equipped slots.
	var equipped_serialized := {}
	var equipped: Dictionary = state.get("equipped_instance_ids", {})
	for slot_key in equipped.keys():
		equipped_serialized[String(slot_key)] = String(equipped[slot_key])
	# Serialize stash.
	var stash_serialized := {}
	var stash_map: Dictionary = state.get("stash_instance_ids", {})
	for slot_key in stash_map.keys():
		var ids: Array = stash_map[slot_key]
		var ids_str: Array = []
		for iid in ids:
			ids_str.append(String(iid))
		stash_serialized[String(slot_key)] = ids_str
	# Serialize gem instances.
	var gem_serialized := {}
	var gem_map: Dictionary = state.get("gem_instances", {})
	for iid in gem_map.keys():
		var gem: _GemItemData = gem_map[iid] as _GemItemData
		if gem != null:
			gem_serialized[String(iid)] = gem.to_dictionary()
	# Serialize socketed gem slots (array of instance_id strings).
	var slots_raw: Array = state.get("socketed_gem_slots", [])
	var slots_str: Array = []
	for s in slots_raw:
		slots_str.append(String(s))
	# Serialize materials.
	var materials_serialized := {}
	var materials: Dictionary = state.get("materials", {})
	for k in materials.keys():
		materials_serialized[String(k)] = float(materials[k])
	return {
		"player_id": String(player_id),
		"gear_instances": gear_serialized,
		"equipped_instance_ids": equipped_serialized,
		"stash_instance_ids": stash_serialized,
		"gem_instances": gem_serialized,
		"socketed_gem_slots": slots_str,
		"gem_slot_count": int(state.get("gem_slot_count", _MetaConstants.MAX_GEM_SLOTS_BASE)),
		"materials": materials_serialized,
		"resonant_dust": float(state.get("resonant_dust", 0.0)),
	}


## Applies a serialized state dict (from server or local file) as the canonical state.
## Replaces any existing state for this player.
func apply_server_state(player_id: StringName, state_dict: Dictionary) -> void:
	var key := _key(player_id)
	var gear_map := {}
	var raw_gear: Dictionary = state_dict.get("gear_instances", {})
	for iid in raw_gear.keys():
		var item := _GearItemData.from_dictionary(raw_gear[iid] as Dictionary)
		gear_map[String(iid)] = item
	var equipped := {}
	var raw_equipped: Dictionary = state_dict.get("equipped_instance_ids", {})
	for slot_key in raw_equipped.keys():
		equipped[String(slot_key)] = String(raw_equipped[slot_key])
	var stash_map := {}
	var raw_stash: Dictionary = state_dict.get("stash_instance_ids", {})
	for slot_key in raw_stash.keys():
		var ids_v: Variant = raw_stash[slot_key]
		var ids: Array = ids_v as Array if ids_v is Array else []
		var ids_arr: Array = []
		for iid in ids:
			ids_arr.append(String(iid))
		stash_map[String(slot_key)] = ids_arr
	var gem_map := {}
	var raw_gems: Dictionary = state_dict.get("gem_instances", {})
	for iid in raw_gems.keys():
		var gem := _GemItemData.from_dictionary(raw_gems[iid] as Dictionary)
		gem_map[String(iid)] = gem
	var raw_slots: Array = state_dict.get("socketed_gem_slots", [])
	var slots_arr: Array = []
	for s in raw_slots:
		slots_arr.append(String(s))
	var materials := {}
	var raw_materials: Dictionary = state_dict.get("materials", {})
	for k in raw_materials.keys():
		materials[String(k)] = float(raw_materials[k])
	_player_states[key] = {
		"gear_instances": gear_map,
		"equipped_instance_ids": equipped,
		"stash_instance_ids": stash_map,
		"gem_instances": gem_map,
		"socketed_gem_slots": slots_arr,
		"gem_slot_count": int(state_dict.get("gem_slot_count", _MetaConstants.MAX_GEM_SLOTS_BASE)),
		"materials": materials,
		"resonant_dust": float(state_dict.get("resonant_dust", 0.0)),
	}
	store_changed.emit(player_id)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _key(player_id: StringName) -> String:
	return String(player_id).strip_edges()


func _get_state(player_id: StringName) -> Dictionary:
	ensure_player_initialized(player_id)
	return _player_states.get(_key(player_id), {}) as Dictionary


func _set_state(player_id: StringName, state: Dictionary) -> void:
	_player_states[_key(player_id)] = state
	store_changed.emit(player_id)


func _get_gear_instance(state: Dictionary, instance_id: StringName) -> _GearItemData:
	if instance_id == &"":
		return null
	var gear_map: Dictionary = state.get("gear_instances", {})
	var item_v: Variant = gear_map.get(String(instance_id), null)
	return item_v as _GearItemData if item_v is _GearItemData else null


func _get_gem_instance(state: Dictionary, instance_id: StringName) -> _GemItemData:
	if instance_id == &"":
		return null
	var gem_map: Dictionary = state.get("gem_instances", {})
	var gem_v: Variant = gem_map.get(String(instance_id), null)
	return gem_v as _GemItemData if gem_v is _GemItemData else null


func _remove_from_stash(state: Dictionary, slot_id: StringName, instance_id: StringName) -> void:
	var slot_key := String(slot_id)
	var stash_map: Dictionary = state.get("stash_instance_ids", {})
	var stash_ids: Array = stash_map.get(slot_key, []).duplicate()
	var target := String(instance_id)
	var new_stash: Array = []
	for iid in stash_ids:
		if String(iid) != target:
			new_stash.append(iid)
	stash_map[slot_key] = new_stash
	state["stash_instance_ids"] = stash_map


func _save_path(player_id: StringName) -> String:
	return "user://meta_progression_%s.json" % _key(player_id)


## Builds the starter state:
##   - T1 unaligned (equipped) + T2 Aligned + T3 Specialized (stash) per slot.
##   - Each slot uses a distinct pillar so the UI shows pillar color variety.
##   - Seed materials and resonant dust for immediate UI testing.
func _build_starter_state() -> Dictionary:
	var gear_map := {}
	var equipped := {}
	var stash_map := {}

	# slot → base_id + which pillar the T2/T3 variants align to.
	# Pillars spread across all 6 slots to exercise the full color palette.
	var starter_items: Array[Dictionary] = [
		{"slot": _LoadoutConstants.SLOT_HELMET,  "base_id": &"helmet_knight",            "pillar": _InfusionConstants.PILLAR_EDGE},
		{"slot": _LoadoutConstants.SLOT_ARMOR,   "base_id": &"armor_brigandine",          "pillar": _InfusionConstants.PILLAR_FLOW},
		{"slot": _LoadoutConstants.SLOT_SWORD,   "base_id": &"sword_kaykit_1handed",      "pillar": _InfusionConstants.PILLAR_MASS},
		{"slot": _LoadoutConstants.SLOT_HANDGUN, "base_id": &"handgun_red",               "pillar": _InfusionConstants.PILLAR_ECHO},
		{"slot": _LoadoutConstants.SLOT_BOMB,    "base_id": &"bomb_iron",                 "pillar": _InfusionConstants.PILLAR_SURGE},
		{"slot": _LoadoutConstants.SLOT_SHIELD,  "base_id": &"shield_kaykit_round_color", "pillar": _InfusionConstants.PILLAR_PHASE},
	]

	for entry in starter_items:
		var slot_id: StringName = entry["slot"]
		var base_id: StringName = entry["base_id"]
		var pillar: StringName  = entry["pillar"]

		# T1 — unaligned, equipped.
		var t1 := _GearItemData.create_new(base_id, slot_id)
		gear_map[String(t1.instance_id)] = t1
		equipped[String(slot_id)] = String(t1.instance_id)

		# T2 — Aligned, Familiar familiarity, 60% promotion toward T3.
		var t2 := _GearItemData.create_new(base_id, slot_id)
		t2.tier = _MetaConstants.TIER_ALIGNED
		t2.pillar_alignment = pillar
		t2.familiarity_xp = 110.0   # Familiar (+2%)
		t2.promotion_progress = 0.6
		gear_map[String(t2.instance_id)] = t2

		# T3 — Specialized, Masterwork familiarity, fully evolved.
		var t3 := _GearItemData.create_new(base_id, slot_id)
		t3.tier = _MetaConstants.TIER_SPECIALIZED
		t3.pillar_alignment = pillar
		t3.familiarity_xp = 320.0   # Masterwork (+6%)
		t3.promotion_progress = 0.0
		gear_map[String(t3.instance_id)] = t3

		stash_map[String(slot_id)] = [String(t2.instance_id), String(t3.instance_id)]

	# Seed materials — enough to show pillar colors and test evolution flow.
	var materials := {}
	for pillar_id in _InfusionConstants.PILLAR_ORDER:
		materials[String(pillar_id)] = 30.0

	return {
		"gear_instances": gear_map,
		"equipped_instance_ids": equipped,
		"stash_instance_ids": stash_map,
		"gem_instances": {},
		"socketed_gem_slots": [],
		"gem_slot_count": _MetaConstants.MAX_GEM_SLOTS_BASE,
		"materials": materials,
		"resonant_dust": 15.0,
	}


# ---------------------------------------------------------------------------
# _PlayerState shape (reference comment)
# ---------------------------------------------------------------------------
# {
#   "gear_instances":        { String(instance_id): GearItemData },
#   "equipped_instance_ids": { String(slot_id): String(instance_id) },
#   "stash_instance_ids":    { String(slot_id): Array[String(instance_id)] },
#   "gem_instances":         { String(instance_id): GemItemData },
#   "socketed_gem_slots":    Array[String(instance_id)],  # active gem bar
#   "gem_slot_count":        int,
#   "materials":             { String(pillar_id): float },
#   "resonant_dust":         float,
# }
