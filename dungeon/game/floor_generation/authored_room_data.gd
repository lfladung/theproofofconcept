extends RefCounted
class_name AuthoredRoomData

var scene_path := ""
var room_id := ""
var role := ""
var room_type := ""
var room_tags: PackedStringArray = PackedStringArray()
var tile_size := Vector2i(3, 3)
var room_size_tiles := Vector2i.ONE
var allowed_rotations: PackedInt32Array = PackedInt32Array([0, 90, 180, 270])
var connection_markers: Array[Dictionary] = []
var spawn_markers: Array[Dictionary] = []
var floor_exit_marker: Dictionary = {}
var zone_markers: Array[Dictionary] = []
var occupied_cells: Array[Vector2i] = []
var walkable_cells: Array[Vector2i] = []


func entrance_markers() -> Array[Dictionary]:
	return _markers_by_kind("entrance")


func exit_markers() -> Array[Dictionary]:
	return _markers_by_kind("exit")


func supports_rotation(rotation_deg: int) -> bool:
	return allowed_rotations.has(rotation_deg)


func _markers_by_kind(marker_kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for marker in connection_markers:
		if String(marker.get("marker_kind", "")) == marker_kind:
			out.append(marker)
	return out
