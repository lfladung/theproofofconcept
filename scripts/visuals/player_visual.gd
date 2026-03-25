extends Node3D

## Drives role-based animation clips (idle/run/melee/ranged/bomb).
## Clip selection prefers Knight_Animation_* paths when present, with fallback to existing imports.

@export var walk_speed_threshold := 8.0
@export var attack_duration_seconds := 0.2
@export var idle_clip_hint := "idle"
@export var run_clip_hint := "run"
@export var melee_clip_hint := "slash"
@export var ranged_clip_hint := "slash"
@export var bomb_clip_hint := "slash"

const _IDLE_GLB_CANDIDATES := [
	"res://art/characters/player/Knight_Animation_Idle_withSkin.glb",
	"res://art/characters/player/Cute_chibi_fantasy_kn_biped_Animation_Walking_withSkin.glb",
]
const _BASE_MODEL_GLB_CANDIDATES := [
	"res://art/characters/player/Knight_Animation_Idle_withSkin.glb",
	"res://art/characters/player/Knight_Animation_Running_withSkin.glb",
	"res://art/characters/player/Knight_Animation_Slash_withSkin.glb",
	"res://art/characters/player/player.glb",
	"res://art/characters/player/Cute_chibi_fantasy_kn_biped_Animation_Walking_withSkin.glb",
]
const _RUN_GLB_CANDIDATES := [
	"res://art/characters/player/Knight_Animation_Running_withSkin.glb",
	"res://art/characters/player/Cute_chibi_fantasy_kn_biped_Animation_Running_withSkin.glb",
]
const _SLASH_GLB_CANDIDATES := [
	"res://art/characters/player/Knight_Animation_Slash_withSkin.glb",
	"res://art/characters/player/Cute_chibi_fantasy_kn_biped_Animation_Attack_withSkin.glb",
]

var _anim: AnimationPlayer
var _attack_playing: bool = false
var _attack_nonce := 0
var _idle_clip: StringName = &""
var _run_clip: StringName = &""
var _melee_clip: StringName = &""
var _ranged_clip: StringName = &""
var _bomb_clip: StringName = &""
var _last_locomotion_moving := false
var _last_locomotion_speed_scale := 1.0


func _ready() -> void:
	_ensure_preferred_base_model()
	_anim = _find_animation_player(self)
	if _anim:
		_anim.active = true
		_merge_anim_libraries_from_candidates(_IDLE_GLB_CANDIDATES, &"knight_idle")
		_merge_anim_libraries_from_candidates(_RUN_GLB_CANDIDATES, &"knight_run")
		_merge_anim_libraries_from_candidates(_SLASH_GLB_CANDIDATES, &"knight_slash")
		_cache_role_clips()
		_play_locomotion(false, 1.0)


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null


func _first_existing_path(paths: Array) -> String:
	for p in paths:
		var path := String(p)
		if path.is_empty():
			continue
		if ResourceLoader.exists(path):
			return path
	return ""


func _ensure_preferred_base_model() -> void:
	var desired_path := _first_existing_path(_BASE_MODEL_GLB_CANDIDATES)
	if desired_path.is_empty():
		return
	var current := get_node_or_null("Meshy")
	if current != null and String(current.scene_file_path) == desired_path:
		return
	var desired_scene := load(desired_path) as PackedScene
	if desired_scene == null:
		return
	var desired_instance := desired_scene.instantiate()
	if desired_instance == null:
		return
	desired_instance.name = "Meshy"
	if current != null and current is Node3D and desired_instance is Node3D:
		(desired_instance as Node3D).transform = (current as Node3D).transform
	if current == null:
		add_child(desired_instance)
		return
	var insert_index := current.get_index()
	remove_child(current)
	current.free()
	add_child(desired_instance)
	move_child(desired_instance, insert_index)


func _merge_anim_libraries_from_glb(glb_path: String, library_prefix: StringName) -> void:
	if _anim == null:
		return
	var ps: PackedScene = load(glb_path) as PackedScene
	if ps == null:
		return
	var inst: Node = ps.instantiate()
	var tmp: AnimationPlayer = _find_animation_player(inst)
	if tmp == null:
		inst.free()
		return
	var idx := 0
	for lib_key in tmp.get_animation_library_list():
		var lib: AnimationLibrary = tmp.get_animation_library(lib_key)
		if lib == null:
			continue
		var new_name := String(library_prefix) + (("_" + str(idx)) if idx > 0 else "")
		idx += 1
		if _anim.has_animation_library(new_name):
			continue
		_anim.add_animation_library(new_name, lib.duplicate(true))
	inst.free()


func _merge_anim_libraries_from_candidates(
	glb_candidates: Array, library_prefix: StringName
) -> void:
	for path in glb_candidates:
		if not ResourceLoader.exists(path):
			continue
		_merge_anim_libraries_from_glb(path, library_prefix)
		return


func _find_clip_by_hint_or_keywords(hint: String, keywords: Array) -> StringName:
	if _anim == null or _anim.get_animation_list().is_empty():
		return &""
	var names := _anim.get_animation_list()
	var hint_l := hint.to_lower()
	if not hint_l.is_empty():
		for n in names:
			if hint_l in String(n).to_lower():
				return n
	for keyword in keywords:
		var key_l := String(keyword).to_lower()
		if key_l.is_empty():
			continue
		for n in names:
			if key_l in String(n).to_lower():
				return n
	for n in names:
		var lower := String(n).to_lower()
		if "reset" not in lower:
			return n
	return names[0]


func _cache_role_clips() -> void:
	_idle_clip = _find_clip_by_hint_or_keywords(idle_clip_hint, ["idle", "stand", "walk"])
	_run_clip = _find_clip_by_hint_or_keywords(run_clip_hint, ["run", "running", "sprint"])
	_melee_clip = _find_clip_by_hint_or_keywords(melee_clip_hint, ["slash", "attack"])
	_ranged_clip = _find_clip_by_hint_or_keywords(
		ranged_clip_hint, ["shoot", "ranged", "slash", "attack"]
	)
	_bomb_clip = _find_clip_by_hint_or_keywords(
		bomb_clip_hint, ["bomb", "throw", "slash", "attack"]
	)
	if _ranged_clip == &"":
		_ranged_clip = _melee_clip
	if _bomb_clip == &"":
		_bomb_clip = _melee_clip
	if _run_clip == &"":
		_run_clip = _idle_clip


func _pick_locomotion_clip(running: bool) -> StringName:
	if running and _run_clip != &"":
		return _run_clip
	if _idle_clip != &"":
		return _idle_clip
	if _anim == null or _anim.get_animation_list().is_empty():
		return &""
	var names := _anim.get_animation_list()
	for n in names:
		var lower := String(n).to_lower()
		if "reset" not in lower and "attack" not in lower:
			return n
	return names[0]


func _play_locomotion(moving: bool, speed_scale: float) -> void:
	if _anim == null or _attack_playing:
		return
	var clip := _pick_locomotion_clip(moving and speed_scale * 14.0 >= walk_speed_threshold)
	if clip == &"":
		return
	_last_locomotion_moving = moving and speed_scale * 14.0 >= walk_speed_threshold
	_last_locomotion_speed_scale = speed_scale
	if _anim.current_animation != String(clip) or not _anim.is_playing():
		_anim.play(clip)
	_anim.speed_scale = speed_scale if _last_locomotion_moving else 1.0


func set_locomotion_from_planar_speed(planar_speed: float, max_speed: float) -> void:
	if _attack_playing:
		return
	var moving := planar_speed > 0.05
	var t := clampf(planar_speed / max(max_speed, 0.001), 0.0, 2.5)
	_play_locomotion(moving, maxf(t, 0.35) if moving else 1.0)


func set_jump_tilt(vertical_velocity: float, jump_impulse: float) -> void:
	rotation.x = PI / 6.0 * vertical_velocity / jump_impulse


func _clip_for_attack_mode(mode: StringName) -> StringName:
	match String(mode).to_lower():
		"ranged", "gun":
			return _ranged_clip if _ranged_clip != &"" else _melee_clip
		"bomb":
			return _bomb_clip if _bomb_clip != &"" else _melee_clip
		_:
			return _melee_clip


func _clip_length_seconds(clip: StringName) -> float:
	if _anim == null or clip == &"":
		return 0.0
	var anim_res := _anim.get_animation(clip)
	if anim_res == null:
		return 0.0
	return maxf(0.0, anim_res.length)


func get_attack_duration_seconds_for_mode(mode: StringName = &"melee") -> float:
	if attack_duration_seconds > 0.0:
		return attack_duration_seconds
	return _clip_length_seconds(_clip_for_attack_mode(mode))


func get_attack_duration_seconds() -> float:
	return get_attack_duration_seconds_for_mode(&"melee")


func try_play_attack_for_mode(mode: StringName = &"melee") -> void:
	if _anim == null or _attack_playing:
		return
	var clip := _clip_for_attack_mode(mode)
	if clip == &"":
		_cache_role_clips()
		clip = _clip_for_attack_mode(mode)
	if clip == &"":
		return
	_attack_playing = true
	_attack_nonce += 1
	var attack_nonce := _attack_nonce
	_anim.play(clip)
	var target_duration := get_attack_duration_seconds_for_mode(mode)
	var anim_len := _clip_length_seconds(clip)
	if anim_len <= 0.0:
		_attack_playing = false
		return
	if anim_len > 0.0 and target_duration > 0.0:
		_anim.speed_scale = anim_len / target_duration
	else:
		target_duration = maxf(anim_len, 0.01)
	await get_tree().create_timer(maxf(target_duration, 0.01)).timeout
	if attack_nonce != _attack_nonce:
		return
	_attack_playing = false
	_play_locomotion(_last_locomotion_moving, _last_locomotion_speed_scale)


func try_play_attack() -> void:
	try_play_attack_for_mode(&"melee")
