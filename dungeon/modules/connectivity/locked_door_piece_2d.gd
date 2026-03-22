extends DungeonPiece2D
class_name LockedDoorPiece2D

@export var locked := true
@export var locked_color := Color(0.50, 0.16, 0.70, 1.0)
@export var unlocked_color := Color(0.62, 0.26, 0.86, 1.0)


func _ready() -> void:
	super._ready()
	_apply_lock_state()


func set_locked(value: bool) -> void:
	locked = value
	_apply_lock_state()


func lock() -> void:
	set_locked(true)


func unlock() -> void:
	set_locked(false)


func _apply_lock_state() -> void:
	set_blocks_movement(locked)
	display_color = locked_color if locked else unlocked_color
	_rebuild_piece_geometry()
