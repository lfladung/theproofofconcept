extends SceneTree


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _load_animation_names_from_glb(path: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return names
	var inst: Node = scene.instantiate()
	var anim: AnimationPlayer = _find_animation_player(inst)
	if anim != null:
		names = anim.get_animation_list()
	inst.free()
	return names


func _strip_library_prefix(name: StringName) -> StringName:
	var raw: String = String(name)
	var slash_idx: int = raw.find("/")
	if slash_idx < 0:
		return name
	return StringName(raw.substr(slash_idx + 1))


func _contains_name(candidates: PackedStringArray, target: StringName) -> bool:
	var normalized_target: StringName = _strip_library_prefix(target)
	for value in candidates:
		if StringName(value) == normalized_target:
			return true
	return false


func _print_result(label: String, clip: StringName, candidates: PackedStringArray) -> void:
	var match: bool = _contains_name(candidates, clip)
	print("%s clip=%s replacement_match=%s replacement_names=%s" % [label, String(clip), str(match), str(candidates)])


func _init() -> void:
	var player_visual_scene: PackedScene = load("res://scenes/visuals/player_visual.tscn") as PackedScene
	if player_visual_scene == null:
		print("[VERIFY] failed to load player_visual.tscn")
		quit(1)
		return

	var inst: Node = player_visual_scene.instantiate()
	root.add_child(inst)
	await process_frame

	var run_replacement_names: PackedStringArray = _load_animation_names_from_glb(
		"res://art/characters/player/replacements/Base_Model_V01_Walking_Replacement.glb"
	)
	var attack_replacement_names: PackedStringArray = _load_animation_names_from_glb(
		"res://art/characters/player/replacements/Base_Model_V01_Attack_Replacement.glb"
	)
	var defend_replacement_names: PackedStringArray = _load_animation_names_from_glb(
		"res://art/characters/player/replacements/Base_Model_V01_Defend_Replacement.glb"
	)

	var run_clip: StringName = inst.get("_run_clip")
	var melee_clip: StringName = inst.get("_melee_clip")
	var defend_clip: StringName = inst.get("_defend_clip")

	print("[VERIFY] resolved role clips:")
	_print_result("run", run_clip, run_replacement_names)
	_print_result("melee", melee_clip, attack_replacement_names)
	_print_result("defend", defend_clip, defend_replacement_names)

	inst.free()
	quit(0)
