extends SceneTree
func _init():
	var scene: PackedScene = load("res://scenes/visuals/player_visual.tscn") as PackedScene
	var inst: Node = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var found: Array[Node] = inst.find_children("*", "AnimationPlayer", true, false)
	var anim := found[0] as AnimationPlayer if not found.is_empty() else null
	if anim == null:
		print("NO_ANIM")
		quit(1)
		return
	for clip_name in anim.get_animation_list():
		var lower := String(clip_name).to_lower()
		if lower.contains("block") or lower.contains("running") or lower.contains("idle"):
			print("CLIP:", clip_name)
			var a := anim.get_animation(clip_name)
			for i in range(min(a.get_track_count(), 20)):
				print("  TRACK:", a.track_get_path(i))
	quit()
