extends DungeonPiece2D
class_name ArenaBoundaryPiece2D

@export var active := false
@export var active_color := Color(0.77, 0.21, 0.21, 1.0)
@export var inactive_color := Color(0.62, 0.26, 0.86, 0.35)


func _ready() -> void:
	super._ready()
	set_active(active)


func set_active(value: bool) -> void:
	active = value
	set_blocks_movement(active)
	walkable = not active
	display_color = active_color if active else inactive_color
	_rebuild_piece_geometry()
