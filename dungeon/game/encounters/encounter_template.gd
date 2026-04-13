extends RefCounted
class_name EncounterTemplate

var id: StringName = &""
var display_name := ""
var layer := 1
var tags: PackedStringArray = PackedStringArray()
var entries: Array[Dictionary] = []


static func make(
	template_id: StringName,
	template_display_name: String,
	template_layer: int,
	template_tags: PackedStringArray,
	template_entries: Array[Dictionary]
) -> RefCounted:
	var template = (load("res://dungeon/game/encounters/encounter_template.gd") as GDScript).new()
	template.id = template_id
	template.display_name = template_display_name
	template.layer = template_layer
	template.tags = template_tags.duplicate()
	template.entries = template_entries.duplicate(true)
	return template


static func enemy(enemy_id: StringName, count_min: int, count_max: int = -1) -> Dictionary:
	if count_max < 0:
		count_max = count_min
	return {
		"enemy_id": enemy_id,
		"count_min": maxi(0, count_min),
		"count_max": maxi(0, count_max),
	}


static func choice(choices: Array[StringName], count_min: int = 1, count_max: int = -1) -> Dictionary:
	if count_max < 0:
		count_max = count_min
	return {
		"choices": choices.duplicate(),
		"count_min": maxi(0, count_min),
		"count_max": maxi(0, count_max),
	}


func resolve_spawn_entries(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	for entry in entries:
		var count_min := int(entry.get("count_min", 1))
		var count_max := int(entry.get("count_max", count_min))
		if count_max < count_min:
			count_max = count_min
		var count := count_min
		if count_max > count_min:
			count = rng.randi_range(count_min, count_max)
		for _i in range(count):
			var enemy_id := _resolve_entry_enemy_id(entry, rng)
			if enemy_id == &"":
				continue
			resolved.append({"enemy_id": enemy_id})
	return resolved


func all_possible_enemy_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in entries:
		var enemy_id := entry.get("enemy_id", &"") as StringName
		if enemy_id != &"" and not out.has(enemy_id):
			out.append(enemy_id)
		var choices := entry.get("choices", []) as Array
		for choice_value in choices:
			var choice_id := choice_value as StringName
			if choice_id != &"" and not out.has(choice_id):
				out.append(choice_id)
	return out


func has_any_tag(wanted_tags: PackedStringArray) -> bool:
	for tag in wanted_tags:
		if tags.has(tag):
			return true
	return false


func _resolve_entry_enemy_id(entry: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var enemy_id := entry.get("enemy_id", &"") as StringName
	if enemy_id != &"":
		return enemy_id
	var choices := entry.get("choices", []) as Array
	if choices.is_empty():
		return &""
	var idx := rng.randi_range(0, choices.size() - 1)
	return choices[idx] as StringName
