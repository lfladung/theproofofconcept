extends SceneTree
func _init() -> void:
	var b := BoneAttachment3D.new()
	print("use_external_skeleton=", b.get("use_external_skeleton"))
	print("external_skeleton=", b.get("external_skeleton"))
	print("bone_name=", b.get("bone_name"), " bone_idx=", b.get("bone_idx"))
	quit(0)
