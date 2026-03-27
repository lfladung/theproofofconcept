extends SceneTree

func _capture(path: String, output_path: String, yaw_deg: float, pitch_deg: float, distance: float) -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var scene: PackedScene = load(path) as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	root3d.add_child(inst)
	await process_frame
	var cam := Camera3D.new()
	cam.current = true
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var horiz := distance * cos(pitch)
	cam.position = Vector3(sin(yaw) * horiz, distance * sin(-pitch), cos(yaw) * horiz)
	root3d.add_child(cam)
	await process_frame
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 30, 0)
	root3d.add_child(light)
	await process_frame
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(output_path))
	root3d.queue_free()
	await process_frame

func _init() -> void:
	await _capture("res://art/equipment/helmet/Base_Model_V02_helmet.glb", "res://logs/captures/stills/raw_helmet_front.png", 180.0, 0.0, 4.0)
	await _capture("res://art/equipment/helmet/Base_Model_V02_helmet.glb", "res://logs/captures/stills/raw_helmet_side.png", 90.0, 0.0, 4.0)
	await _capture("res://art/equipment/helmet/Base_Model_V02_helmet.glb", "res://logs/captures/stills/raw_helmet_topdown.png", 145.0, -28.0, 6.0)
	quit(0)
