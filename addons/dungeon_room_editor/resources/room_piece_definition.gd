@tool
extends Resource
class_name RoomPieceDefinition

@export var piece_id: StringName = &""
@export var display_name := ""
@export var category: StringName = &""
@export var preview_scene: PackedScene
@export var runtime_scene: PackedScene
@export var mapping_kind: StringName = &"visual_only"
@export var footprint := Vector2i.ONE
@export var supports_rotation := true
@export var allow_cell_overlap := false
@export var placement_layer: StringName = &""
@export var blocks_movement := false
@export var blocks_projectiles := false
@export var default_tags: PackedStringArray = []
@export var zone_type := ""
@export var zone_role: StringName = &"default"
@export var connector_type: StringName = &"standard"


func is_door_socket() -> bool:
	return mapping_kind == &"door_socket"


func is_zone_marker() -> bool:
	return mapping_kind == &"zone_marker"


func default_placement_layer() -> StringName:
	if placement_layer != &"":
		return placement_layer
	return &"ground" if category == &"floor" else &"overlay"
