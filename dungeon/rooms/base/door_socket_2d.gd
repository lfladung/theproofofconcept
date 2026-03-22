extends Marker2D
class_name DoorSocket2D

@export_enum("north", "south", "east", "west", "up", "down")
var direction := "north"

@export_range(1, 8, 1)
var width_tiles := 1

@export var elevation_level := 0
@export var connector_type: StringName = &"standard"
@export var allow_room_rotation := true


func socket_signature() -> Dictionary:
	return {
		"direction": direction,
		"width_tiles": width_tiles,
		"elevation_level": elevation_level,
		"connector_type": connector_type,
	}


func is_compatible_with(other: DoorSocket2D) -> bool:
	if other == null:
		return false
	var expected := _opposite_direction(direction)
	if expected != other.direction:
		return false
	if width_tiles != other.width_tiles:
		return false
	if elevation_level != other.elevation_level:
		return false
	return connector_type == other.connector_type


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
