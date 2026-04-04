extends Node
class_name InfusionManager

const IC := preload("res://scripts/infusion/infusion_constants.gd")
const InstScr := preload("res://scripts/infusion/infusion_instance.gd")
const RulesScr := preload("res://scripts/infusion/infusion_threshold_rules.gd")

## Max `add_infusion` instances per `pillar_id` per run (HUD dot count cap).
const MAX_PICKUPS_PER_PILLAR_ID := 3

## Infusion progression — not StatPillar2D / menu `pillar_root.gd`.
##
## Multiplayer: server applies pickups; owning client mirrors via `skip_authority_gate` (see `Player.receive_infusion_pickup`).
signal infusion_added(instance_id: int, pillar_id: StringName, stack_contribution: float, source_kind: int)
signal infusion_removed(instance_id: int, pillar_id: StringName, stack_contribution: float)
## Emitted only when this pillar's resolved threshold int actually changes (not on stack-only changes).
signal pillar_state_changed(pillar_id: StringName, old_threshold: int, new_threshold: int)

@export var threshold_rules: Resource
@export var auto_bind_run_state: bool = true
@export var require_server_for_mutations: bool = true
@export var warn_unknown_pillars: bool = true

var _instances: Dictionary = {} # int -> InfusionInstance
var _next_instance_id: int = 1
var _pillar_stacks: Dictionary = {} # StringName -> float
var _pillar_thresholds: Dictionary = {} # StringName -> int
var _default_rules: Resource
var _run_state: Node


func _ready() -> void:
	_bootstrap_threshold_cache()
	if auto_bind_run_state:
		_run_state = get_node_or_null("/root/RunState") as Node
		if _run_state != null:
			_run_state.run_started.connect(_on_run_boundary)
			_run_state.run_ended.connect(_on_run_boundary)


func _rules():
	if threshold_rules != null:
		return threshold_rules
	if _default_rules == null:
		_default_rules = RulesScr.new()
	return _default_rules


func _bootstrap_threshold_cache() -> void:
	for p in IC.PILLAR_ORDER:
		_pillar_stacks[p] = 0.0
		_pillar_thresholds[p] = int(IC.InfusionThreshold.INACTIVE)


func _on_run_boundary(_snap := {}) -> void:
	clear_run_infusions()


func _allow_mutations() -> bool:
	if not require_server_for_mutations:
		return true
	var mp := multiplayer
	if mp == null or mp.multiplayer_peer == null:
		return true
	return mp.is_server()


## `source_kind`: `InfusionConstants.SourceKind` (int). `skip_authority_gate`: only for validated owner RPC mirror.
func add_infusion(
	pillar_id: StringName,
	stack_contribution: float = IC.STACK_NORMAL,
	source_kind: int = IC.SourceKind.NORMAL,
	skip_authority_gate: bool = false
) -> int:
	if not skip_authority_gate and not _allow_mutations():
		return -1
	pillar_id = IC.coerce_pillar_id(pillar_id)
	if count_pickups_for_pillar(pillar_id) >= MAX_PICKUPS_PER_PILLAR_ID:
		return -1
	if warn_unknown_pillars and not IC.is_known_pillar(pillar_id):
		push_warning("InfusionManager: unknown pillar_id '%s' (still accepted)." % pillar_id)
	var id := _next_instance_id
	_next_instance_id += 1
	var inst = InstScr.new(pillar_id, stack_contribution, source_kind)
	inst.instance_id = id
	_instances[id] = inst
	infusion_added.emit(id, pillar_id, stack_contribution, source_kind)
	_emit_pillar_threshold_change_if_any(pillar_id)
	return id


func remove_infusion_by_id(instance_id: int) -> bool:
	if not _allow_mutations():
		return false
	var inst = _instances.get(instance_id)
	if inst == null:
		return false
	var pillar_id: StringName = inst.pillar_id
	var contrib: float = inst.stack_contribution
	_instances.erase(instance_id)
	infusion_removed.emit(instance_id, pillar_id, contrib)
	_emit_pillar_threshold_change_if_any(pillar_id)
	return true


func clear_run_infusions() -> void:
	if _instances.is_empty():
		return
	var ids: Array = _instances.keys()
	for id in ids:
		var inst = _instances[id]
		_instances.erase(id)
		infusion_removed.emit(int(id), inst.pillar_id, inst.stack_contribution)
	for p in IC.PILLAR_ORDER:
		_emit_pillar_threshold_change_if_any(p)


func get_pillar_stack(pillar_id: StringName) -> float:
	return float(_pillar_stacks.get(pillar_id, 0.0))


func get_pillar_threshold(pillar_id: StringName) -> int:
	return int(_pillar_thresholds.get(pillar_id, int(IC.InfusionThreshold.INACTIVE)))


func get_all_pillar_thresholds() -> Dictionary:
	return _pillar_thresholds.duplicate(true)


func count_pickups_for_pillar(pillar_id: StringName) -> int:
	var n := 0
	for id in _instances:
		var inst: InfusionInstance = _instances[id]
		if inst.pillar_id == pillar_id:
			n += 1
	return n


func is_at_pickup_cap_for_pillar(pillar_id: StringName) -> bool:
	return count_pickups_for_pillar(pillar_id) >= MAX_PICKUPS_PER_PILLAR_ID


## Stable order by `instance_id` for HUD (one dot per pickup).
func list_infusions_for_ui() -> Array[Dictionary]:
	var keys: Array = _instances.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for k in keys:
		var inst: InfusionInstance = _instances[k]
		out.append({"id": int(k), "pillar_id": inst.pillar_id})
	return out


func has_reached_threshold(pillar_id: StringName, minimum_threshold: int) -> bool:
	return get_pillar_threshold(pillar_id) >= minimum_threshold


func _emit_pillar_threshold_change_if_any(pillar_id: StringName) -> void:
	var delta := _recompute_pillar(pillar_id)
	if delta.is_empty():
		return
	pillar_state_changed.emit(pillar_id, int(delta[0]), int(delta[1]))


func _effective_stack(pillar_id: StringName) -> float:
	var sum := 0.0
	for id in _instances:
		var inst = _instances[id]
		if inst.pillar_id == pillar_id:
			sum += inst.stack_contribution
	return sum


## Returns [old_thr, new_thr] if threshold changed; updates stack/threshold caches always.
func _recompute_pillar(pillar_id: StringName) -> Array:
	var old_stack := float(_pillar_stacks.get(pillar_id, 0.0))
	var old_thr := int(_pillar_thresholds.get(pillar_id, int(IC.InfusionThreshold.INACTIVE)))
	var new_stack := _effective_stack(pillar_id)
	var rules = _rules()
	var new_thr: int = rules.resolve_threshold(new_stack)
	_pillar_stacks[pillar_id] = new_stack
	_pillar_thresholds[pillar_id] = new_thr
	if old_thr == new_thr:
		return []
	return [old_thr, new_thr]
