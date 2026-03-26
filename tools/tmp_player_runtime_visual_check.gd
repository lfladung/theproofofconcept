extends SceneTree

func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		print(mi.get_path(), " global=", mi.global_position, " scale=", mi.global_basis.get_scale(), " vis=", mi.visible)
	for c in node.get_children():
		_walk(c)

func _find(node: Node, n: String) -> Node:
	if node.name == n:
		return node
	for c in node.get_children():
		var f := _find(c, n)
		if f != null:
			return f
	return null

func _init() -> void:
	var root3d := Node3D.new()
	root3d.name = "VisualWorld3D"
	root.add_child(root3d)
	var world2d := Node2D.new()
	world2d.name = "GameWorld2D"
	root.add_child(world2d)
	var ps := load("res://scenes/entities/player.tscn") as PackedScene
	var p := ps.instantiate() as Node2D
	p.name = "Player"
	world2d.add_child(p)
	p.position = Vector2(0,0)
	for i in range(12):
		await physics_frame
		await process_frame
	var pv := _find(root, "PlayerVisual_Player")
	if pv == null:
		print("PlayerVisual not found")
		quit(1)
		return
	print("=== player runtime visual tree ===")
	_walk(pv)
	quit(0)
