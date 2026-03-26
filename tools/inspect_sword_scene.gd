extends SceneTree

func _walk(node: Node, indent := "") -> void:
	print(indent, node.name, " [", node.get_class(), "]")
	if node is Node3D:
		var n3 := node as Node3D
		print(indent, "  pos=", n3.position, " rot=", n3.rotation_degrees, " scale=", n3.scale)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			print(indent, "  aabb=", mi.mesh.get_aabb())
	for c in node.get_children():
		_walk(c, indent + "  ")

func _init() -> void:
var path := "res://art/equipment/weapons/Sword_texture.glb"
	print("=== ", path, " ===")
	var ps := load(path) as PackedScene
	if ps == null:
		print("not a PackedScene")
		quit(1)
		return
	var inst := ps.instantiate()
	if inst == null:
		print("instantiate failed")
		quit(1)
		return
	_walk(inst)
	inst.free()
	quit(0)
