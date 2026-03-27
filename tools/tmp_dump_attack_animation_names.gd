extends SceneTree

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null

func _dump(path: String) -> void:
	print("=== ", path, " ===")
	var ps := load(path) as PackedScene
	if ps == null:
		print("not a PackedScene")
		return
	var inst := ps.instantiate()
	if inst == null:
		print("instantiate failed")
		return
	var ap := _find_animation_player(inst)
	if ap == null:
		print("no AnimationPlayer")
		inst.free()
		return
	for lib_key in ap.get_animation_library_list():
		print("library=", lib_key)
		var lib := ap.get_animation_library(lib_key)
		if lib == null:
			continue
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			print("  ", anim_name, " len=", anim.length if anim != null else -1)
	inst.free()

func _init() -> void:
	_dump("res://art/characters/player/Attack_left_slash.glb")
	_dump("res://art/characters/player/Model_Attack.glb")
	quit(0)
