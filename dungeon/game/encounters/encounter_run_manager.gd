extends RefCounted
class_name EncounterRunManager

const ROOM_MATCH_TAGS := ["open", "corridor", "small", "medium", "large"]

## Maps room tags to the template tags that are compatible with them.
## A template earns +1.0 score for each of its tags that appears in the
## compat list for a given room tag. Broad templates (no size/layout tags)
## receive a 0.1 baseline so they still surface as fallbacks.
## Keys and values use StringName so _score_template_for_room needs no String() casts.
const _ROOM_TAG_COMPAT: Dictionary = {
	&"corridor":   [&"corridor", &"small", &"low_intensity"],
	&"connector":  [&"corridor", &"small", &"low_intensity"],
	&"chokepoint": [&"corridor", &"small", &"medium", &"low_intensity"],
	&"small":      [&"small", &"low_intensity"],
	&"medium":     [&"medium", &"open"],
	&"large":      [&"large", &"medium", &"open"],
	&"arena":      [&"open", &"medium", &"large"],
	&"boss":       [&"boss"],
}
## Shared empty array returned by _ROOM_TAG_COMPAT.get() on a miss — avoids per-call allocation.
static var _EMPTY_COMPAT: Array = []

var _rng := RandomNumberGenerator.new()
var _templates_by_layer: Dictionary = {}
var _bags_by_layer: Dictionary = {}
var _used_by_layer: Dictionary = {}
var _ever_used_by_layer: Dictionary = {}
var _configured := false


func configure(run_seed: int, templates: Array) -> void:
	_rng.seed = run_seed
	_templates_by_layer.clear()
	_bags_by_layer.clear()
	_used_by_layer.clear()
	_ever_used_by_layer.clear()
	for template in templates:
		if template == null:
			continue
		if not _templates_by_layer.has(template.layer):
			_templates_by_layer[template.layer] = []
		var layer_templates: Array = _templates_by_layer[template.layer] as Array
		layer_templates.append(template)
		_templates_by_layer[template.layer] = layer_templates
	for layer_key in _templates_by_layer.keys():
		_rebuild_bag(int(layer_key))
		_used_by_layer[int(layer_key)] = {}
		_ever_used_by_layer[int(layer_key)] = {}
	_configured = true


func is_configured() -> bool:
	return _configured


func choose_template(layer: int, room_tags: PackedStringArray) -> Dictionary:
	if not _configured:
		return {}
	if not _templates_by_layer.has(layer):
		return {}
	var template = _choose_from_stage(layer, room_tags, true, true)
	var stage := "unused_compatible"
	if template == null:
		template = _choose_from_stage(layer, room_tags, true, false)
		stage = "unused_broad"
	if template == null:
		template = _choose_any_unused(layer)
		stage = "unused_any"
	if template == null:
		_rebuild_bag(layer)
		_used_by_layer[layer] = {}
		template = _choose_from_stage(layer, room_tags, false, true)
		stage = "repeat_compatible"
	if template == null:
		template = _choose_from_stage(layer, room_tags, false, false)
		stage = "repeat_broad"
	if template == null:
		template = _choose_any(layer)
		stage = "repeat_any"
	if template == null:
		return {}
	var repeated := _was_ever_used(layer, template.id)
	_mark_used(layer, template.id)
	return {
		"template": template,
		"repeated": repeated,
		"stage": stage,
	}


func resolve_template_spawns(template) -> Array[Dictionary]:
	if template == null:
		return []
	return template.resolve_spawn_entries(_rng)


func _choose_from_stage(
	layer: int,
	room_tags: PackedStringArray,
	unused_only: bool,
	require_positive_score: bool
) -> Variant:
	var bag := _bags_by_layer.get(layer, []) as Array
	var best = null
	var best_score := -1.0
	for value in bag:
		var template = value
		if template == null:
			continue
		if unused_only and _is_used(layer, template.id):
			continue
		var score := _score_template_for_room(template, room_tags)
		if require_positive_score and score <= 0.0:
			continue
		if score > best_score:
			best_score = score
			best = template
	return best


func _score_template_for_room(template, room_tags: PackedStringArray) -> float:
	if template == null:
		return -1.0
	var score := 0.0
	for room_tag: String in room_tags:
		var compat: Array = _ROOM_TAG_COMPAT.get(StringName(room_tag), _EMPTY_COMPAT)
		if compat.is_empty():
			continue
		for t_tag: String in template.tags:
			if compat.has(StringName(t_tag)):
				score += 1.0
	if _is_broad_template(template):
		score = maxf(score, 0.1)
	return score


func _choose_any_unused(layer: int) -> Variant:
	var bag := _bags_by_layer.get(layer, []) as Array
	for value in bag:
		var template = value
		if template != null and not _is_used(layer, template.id):
			return template
	return null


func _choose_any(layer: int) -> Variant:
	var bag := _bags_by_layer.get(layer, []) as Array
	for value in bag:
		if value != null:
			return value
	return null


func _is_broad_template(template) -> bool:
	if template == null:
		return false
	for tag in ROOM_MATCH_TAGS:
		if template.tags.has(tag):
			return false
	return true


func _is_used(layer: int, template_id: StringName) -> bool:
	var used = _used_by_layer.get(layer)
	if used == null:
		return false
	return bool((used as Dictionary).get(template_id, false))


func _mark_used(layer: int, template_id: StringName) -> void:
	# _configure() pre-initialises both dicts for every layer so .get() returns the live ref.
	var used = _used_by_layer.get(layer)
	if used is Dictionary:
		(used as Dictionary)[template_id] = true
	var ever_used = _ever_used_by_layer.get(layer)
	if ever_used is Dictionary:
		(ever_used as Dictionary)[template_id] = true


func _was_ever_used(layer: int, template_id: StringName) -> bool:
	var ever_used = _ever_used_by_layer.get(layer)
	if ever_used == null:
		return false
	return bool((ever_used as Dictionary).get(template_id, false))


func _rebuild_bag(layer: int) -> void:
	var source := _templates_by_layer.get(layer, []) as Array
	var bag := source.duplicate()
	for i in range(bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	_bags_by_layer[layer] = bag
