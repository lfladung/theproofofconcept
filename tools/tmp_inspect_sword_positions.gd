extends SceneTree

func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for c in node.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null

func _init() -> void:
	var ps := load("res://scenes/visuals/player_visual.tscn") as PackedScene
	var inst := ps.instantiate() as Node3D
	root.add_child(inst)
	for i in range(20):
		await process_frame
	var sword_root := _find(inst, "SwordAttachment") as Node3D
	var sword_proxy := _find(inst, "SwordDebugProxy") as MeshInstance3D
	var beacon := _find(inst, "SwordModeBeacon") as MeshInstance3D
	if sword_root:
		print("SwordRoot global=", sword_root.global_position, " vis=", sword_root.visible)
	if sword_proxy:
		print("SwordDebugProxy global=", sword_proxy.global_position, " vis=", sword_proxy.visible)
	if beacon:
		print("SwordModeBeacon global=", beacon.global_position, " vis=", beacon.visible)
	quit(0)
