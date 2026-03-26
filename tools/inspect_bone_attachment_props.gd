extends SceneTree
func _init() -> void:
	var b := BoneAttachment3D.new()
	print("BoneAttachment3D properties:")
	for p in b.get_property_list():
		var d := p as Dictionary
		var n := String(d.get("name", ""))
		if n.find("bone") >= 0 or n.find("skeleton") >= 0:
			print(" - ", n)
	quit(0)
