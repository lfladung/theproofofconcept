extends SceneTree

func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for c in node.get_children():
		var f := _find(c, name)
		if f != null:
			return f
	return null

func _walk(node: Node, indent := "") -> void:
	print(indent, node.name, " [", node.get_class(), "]")
	for c in node.get_children():
		_walk(c, indent + "  ")

func _init() -> void:
	var ps := load("res://scenes/visuals/player_visual.tscn") as PackedScene
	if ps == null:
		print("load failed")
		quit(1)
		return
	var inst := ps.instantiate()
	root.add_child(inst)
	await process_frame
	print("=== PlayerVisual tree ===")
	_walk(inst)
	var s := _find(inst, "SwordAttachment")
	if s == null:
		print("SwordAttachment not found")
	else:
		print("SwordAttachment parent=", s.get_parent().name, " child_count=", s.get_child_count(), " visible=", (s as Node3D).visible if s is Node3D else false)
		for c in s.get_children():
			print(" child=", c.name, " class=", c.get_class(), " child_count=", c.get_child_count())
	var sk := _find(inst, "Skeleton3D")
	if sk != null:
		print("Skeleton found as node name Skeleton3D")
	quit(0)
