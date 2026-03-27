extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var ps: PackedScene = load("res://scenes/visuals/player_visual.tscn") as PackedScene
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	print("strict:", inst.get("strict_hand_attachment"))
	print("follow_idx:", inst.get("_sword_follow_bone_idx"))
	print("has_skel:", inst.get("_sword_follow_skeleton") != null)
	print("local_from_bone:", inst.get("_sword_local_from_bone"))
	quit(0)