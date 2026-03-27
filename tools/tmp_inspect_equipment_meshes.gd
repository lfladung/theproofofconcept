extends SceneTree

func _walk(node: Node, indent: String = "") -> void:
	print(indent, node.name, " [", node.get_class(), "]")
	if node is Node3D:
		var n3: Node3D = node as Node3D
		print(indent, "  pos=", n3.position, " rot=", n3.rotation_degrees, " scale=", n3.scale)
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			print(indent, "  aabb=", mi.mesh.get_aabb())
	for c in node.get_children():
		_walk(c, indent + "  ")

func _inspect(path: String) -> void:
	print("=== ", path, " ===")
	var ps := load(path) as PackedScene
	if ps == null:
		print("not a PackedScene")
		return
	var inst := ps.instantiate()
	if inst == null:
		print("instantiate failed")
		return
	_walk(inst)
	inst.free()

func _init() -> void:
	_inspect("res://art/equipment/weapons/Sword_texture.glb")
	_inspect("res://art/equipment/shields/Base_Model_V01_shield.glb")
	_inspect("res://art/equipment/helmet/Base_Model_V02_helmet.glb")
	quit(0)
