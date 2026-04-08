@tool
extends Resource
class_name RoomPieceDefinition

@export var piece_id: StringName = &""
@export var display_name := ""
@export var category: StringName = &""
## Under **Spawn** category only: groups pieces in the palette tree (e.g. `edge`, `echo`). Empty = General.
@export var palette_subfolder: StringName = &""
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
@export var enemy_id: StringName = &""
@export var connector_type: StringName = &"standard"
@export_enum("entrance", "exit") var marker_kind := "entrance"
@export_range(1, 8, 1) var marker_width_tiles := 3


func is_door_socket() -> bool:
	return mapping_kind == &"door_socket"


func is_connection_marker() -> bool:
	return mapping_kind == &"connection_marker"


func is_entrance_marker() -> bool:
	return is_connection_marker() and marker_kind == "entrance"


func is_exit_marker() -> bool:
	return is_connection_marker() and marker_kind == "exit"


func is_zone_marker() -> bool:
	return mapping_kind == &"zone_marker"


func is_enemy_spawn_marker() -> bool:
	return is_zone_marker() and zone_type == "enemy_spawn"


func default_placement_layer() -> StringName:
	if placement_layer != &"":
		return placement_layer
	return &"ground" if category == &"floor" else &"overlay"
