extends RefCounted
class_name LoadoutItemDefinition

const LoadoutVisualDefinition = preload("res://scripts/loadout/loadout_visual_definition.gd")

var item_id: StringName = &""
var display_name := ""
var slot_id: StringName = &""
var description := ""
var stat_modifiers: Dictionary = {}
var visual_definition: LoadoutVisualDefinition


func _init(
	next_item_id: StringName = &"",
	next_display_name: String = "",
	next_slot_id: StringName = &"",
	next_description: String = "",
	next_stat_modifiers: Dictionary = {},
	next_visual_definition: LoadoutVisualDefinition = null
) -> void:
	item_id = next_item_id
	display_name = next_display_name
	slot_id = next_slot_id
	description = next_description
	stat_modifiers = next_stat_modifiers.duplicate(true)
	visual_definition = next_visual_definition if next_visual_definition != null else LoadoutVisualDefinition.new()


func to_dictionary() -> Dictionary:
	return {
		"item_id": String(item_id),
		"display_name": display_name,
		"slot_id": String(slot_id),
		"description": description,
		"stat_modifiers": stat_modifiers.duplicate(true),
		"visual": visual_definition.to_dictionary(),
	}
