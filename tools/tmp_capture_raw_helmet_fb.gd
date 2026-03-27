extends SceneTree

func _capture(yaw_deg: float, output_path: String) -> void:
	var root3d := Node3D.new(); root.add_child(root3d)
	var scene: PackedScene = load("res://art/equipment/helmet/Base_Model_V02_helmet.glb") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	root3d.add_child(inst)
	var cam := Camera3D.new(); cam.current = true; root3d.add_child(cam)
	var dist := 4.0
	var yaw := deg_to_rad(yaw_deg)
	cam.position = Vector3(sin(yaw)*dist, 0.2, cos(yaw)*dist)
	await process_frame
	cam.look_at(Vector3(0,0.2,0), Vector3.UP)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-30,30,0); root3d.add_child(light)
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(output_path))
	root3d.queue_free(); await process_frame

func _init() -> void:
	await _capture(0.0, "res://logs/captures/stills/raw_helmet_yaw0.png")
	await _capture(180.0, "res://logs/captures/stills/raw_helmet_yaw180.png")
	quit(0)
