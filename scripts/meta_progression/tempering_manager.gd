extends RefCounted
class_name TemperingManager

## Run-scoped manager for gear Tempering state. (META_PROGRESSION.md §2)
##
## Tempering is temporary — it resets when the run ends.
## During a run, gear accumulates tempering XP from floors cleared,
## infusion pickups, and boss kills. When thresholds are crossed,
## the gear enters Tempered I / Tempered II, granting stat bonuses.
##
## Usage:
##   var mgr = TemperingManager.new()
##   mgr.add_xp("sword_abc123", MetaProgressionConstants.TEMPERING_XP_PER_FLOOR)
##   var state = mgr.get_state("sword_abc123")  # → TEMPERED_I or TEMPERED_II
##   var mult = MetaProgressionConstants.tempering_stat_multiplier(state)

const _MetaConstants = preload("res://scripts/meta_progression/meta_progression_constants.gd")

## Emitted when any gear piece crosses a tempering threshold.
## new_state is a MetaProgressionConstants.TemperingState int value.
signal tempering_state_changed(instance_id: StringName, new_state: int)

## Accumulated XP per gear instance_id.
var _xp: Dictionary = {}  # { String(instance_id): float }


## Resets all tempering state (call at run start or run end).
func reset() -> void:
	_xp.clear()


## Adds tempering XP to a gear instance. Emits signal on threshold crossing.
func add_xp(instance_id: StringName, amount: float) -> void:
	var key := String(instance_id)
	var prev_state := _state_for_xp(float(_xp.get(key, 0.0)))
	_xp[key] = float(_xp.get(key, 0.0)) + maxf(0.0, amount)
	var new_state := _state_for_xp(float(_xp[key]))
	if new_state != prev_state:
		tempering_state_changed.emit(instance_id, new_state)


## Adds tempering XP to ALL tracked gear instances at once (e.g. on floor clear).
func add_xp_to_all(amount: float) -> void:
	for key in _xp.keys():
		add_xp(StringName(key), amount)


## Adds XP to all equipped gear for a player. Call with instance_ids from MetaProgressionStore.
func add_xp_to_equipped(equipped_instance_ids: Array[StringName], amount: float) -> void:
	for iid in equipped_instance_ids:
		# Ensure entry exists so add_xp_to_all includes it later.
		if not _xp.has(String(iid)):
			_xp[String(iid)] = 0.0
		add_xp(iid, amount)


## Returns the current tempering state for a gear instance.
func get_state(instance_id: StringName) -> int:
	return _state_for_xp(float(_xp.get(String(instance_id), 0.0)))


## Returns the stat multiplier for a gear instance's current tempering state.
func get_stat_multiplier(instance_id: StringName) -> float:
	return _MetaConstants.tempering_stat_multiplier(get_state(instance_id))


## Returns the current XP for a gear instance.
func get_xp(instance_id: StringName) -> float:
	return float(_xp.get(String(instance_id), 0.0))


## Returns true if ANY tracked gear reached Tempered II this run (used for promotion).
func any_reached_tempered_ii() -> bool:
	for key in _xp.keys():
		if _state_for_xp(float(_xp[key])) == _MetaConstants.TemperingState.TEMPERED_II:
			return true
	return false


## Returns all instance_ids that reached Tempered II.
func get_tempered_ii_instance_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _xp.keys():
		if _state_for_xp(float(_xp[key])) == _MetaConstants.TemperingState.TEMPERED_II:
			result.append(StringName(key))
	return result


func _state_for_xp(xp: float) -> int:
	if xp >= _MetaConstants.TEMPERING_THRESHOLD_II:
		return _MetaConstants.TemperingState.TEMPERED_II
	if xp >= _MetaConstants.TEMPERING_THRESHOLD_I:
		return _MetaConstants.TemperingState.TEMPERED_I
	return _MetaConstants.TemperingState.NONE
