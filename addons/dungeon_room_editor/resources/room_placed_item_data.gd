@tool
extends Resource
class_name RoomPlacedItemData

@export var item_id := ""
@export var piece_id: StringName = &""
@export var category: StringName = &""
@export var grid_position := Vector2i.ZERO
@export_range(0, 3, 1) var rotation_steps := 0
@export var tags: PackedStringArray = []
@export var encounter_group_id: StringName = &""
@export var placement_layer: StringName = &""
@export var blocks_movement := false
@export var blocks_projectiles := false


func normalized_rotation_steps() -> int:
	return posmod(rotation_steps, 4)


func duplicate_item():
	var duplicate = get_script().new()
	duplicate.item_id = item_id
	duplicate.piece_id = piece_id
	duplicate.category = category
	duplicate.grid_position = grid_position
	duplicate.rotation_steps = normalized_rotation_steps()
	duplicate.tags = tags.duplicate()
	duplicate.encounter_group_id = encounter_group_id
	duplicate.placement_layer = placement_layer
	duplicate.blocks_movement = blocks_movement
	duplicate.blocks_projectiles = blocks_projectiles
	return duplicate


func resolved_placement_layer(piece = null) -> StringName:
	if placement_layer != &"":
		return placement_layer
	if piece != null and piece.has_method(&"default_placement_layer"):
		return piece.default_placement_layer()
	return &"ground" if category == &"floor" else &"overlay"
