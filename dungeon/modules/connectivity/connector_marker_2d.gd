@tool
extends Marker2D
class_name ConnectorMarker2D

@export_enum("entrance", "exit")
var marker_kind := "entrance"

@export_enum("north", "south", "east", "west", "up", "down")
var direction := "east"

@export var marker_color := Color(0.62, 0.26, 0.86, 1.0)
@export var connection_tag: StringName = &"standard"

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	if _visual:
		_visual.color = marker_color
	if Engine.is_editor_hint():
		set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _visual:
		_visual.color = marker_color
