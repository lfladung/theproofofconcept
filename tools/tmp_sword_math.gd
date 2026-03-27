extends SceneTree
func _init() -> void:
	var rot_deg := Vector3(27.8, 63.0, -34.8)
	var offs := Vector3(0.05, 1.18, 0.38)
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	print("basis y:", b.y)
	print("hilt(+):", offs + b.y * 0.95)
	print("hilt(-):", offs - b.y * 0.95)
	quit(0)