@tool
extends Marker2D
class_name ConnectorMarker2D

@export_enum("entrance", "exit")
var marker_kind := "entrance"

@export_enum("north", "south", "east", "west", "up", "down")
var direction := "east"

@export var marker_color := Color(0.62, 0.26, 0.86, 1.0)
@export var show_marker_visual := false
@export var connection_tag: StringName = &"standard"
@export var connector_type: StringName = &"standard"
@export_range(1, 8, 1) var width_tiles := 3
@export var elevation_level := 0
@export var allow_room_rotation := true

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	if connector_type == &"standard" and connection_tag != &"standard":
		connector_type = connection_tag
	else:
		connection_tag = connector_type
	_sync_visual_state()
	if Engine.is_editor_hint():
		set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_visual_state()


func _sync_visual_state() -> void:
	if _visual == null:
		return
	_visual.color = marker_color
	_visual.visible = _show_marker_visual_value()


func _show_marker_visual_value() -> bool:
	if typeof(show_marker_visual) == TYPE_BOOL:
		return show_marker_visual
	show_marker_visual = false
	return false


func marker_signature() -> Dictionary:
	return {
		"marker_kind": marker_kind,
		"direction": direction,
		"width_tiles": width_tiles,
		"elevation_level": elevation_level,
		"connection_tag": connector_type,
	}


func is_compatible_with(other: ConnectorMarker2D) -> bool:
	if other == null:
		return false
	if _opposite_direction(direction) != other.direction:
		return false
	if marker_kind == other.marker_kind:
		return false
	if width_tiles != other.width_tiles:
		return false
	if elevation_level != other.elevation_level:
		return false
	return connector_type == other.connector_type


func socket_signature() -> Dictionary:
	return marker_signature()


func _opposite_direction(source_direction: String) -> String:
	match source_direction:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		"west":
			return "east"
		"up":
			return "down"
		"down":
			return "up"
		_:
			return ""
