extends Node3D

## Drives Meshy locomotion clips; optional attack on player_attack.

@export var walk_speed_threshold := 8.0

const _RUN_GLB := "res://art/Meshy_AI_Cute_chibi_fantasy_kn_biped_Animation_Running_withSkin.glb"
const _ATK_GLB := "res://art/Meshy_AI_Cute_chibi_fantasy_kn_biped_Animation_Attack_withSkin.glb"

var _anim: AnimationPlayer
var _attack_playing: bool = false


func _ready() -> void:
	_anim = _find_animation_player(self)
	if _anim:
		_anim.active = true
		_merge_anim_libraries_from_glb(_RUN_GLB, &"meshy_run")
		_merge_anim_libraries_from_glb(_ATK_GLB, &"meshy_atk")
		_play_locomotion(false, 1.0)


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null


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


func _pick_locomotion_clip(running: bool) -> StringName:
	if _anim == null or _anim.get_animation_list().is_empty():
		return &""
	var names := _anim.get_animation_list()
	var want := "run" if running else "walk"
	for n in names:
		var nl := String(n).to_lower()
		if want in nl:
			return n
	for n in names:
		var nl2 := String(n).to_lower()
		if "reset" not in nl2 and "attack" not in nl2:
			return n
	return names[0]


func _play_locomotion(moving: bool, speed_scale: float) -> void:
	if _anim == null or _attack_playing:
		return
	var clip := _pick_locomotion_clip(moving and speed_scale * 14.0 >= walk_speed_threshold)
	if clip == &"":
		return
	if _anim.current_animation != String(clip) or not _anim.is_playing():
		_anim.play(clip)
	_anim.speed_scale = speed_scale


func set_locomotion_from_planar_speed(planar_speed: float, max_speed: float) -> void:
	if _attack_playing:
		return
	var moving := planar_speed > 0.05
	var t := clampf(planar_speed / max(max_speed, 0.001), 0.0, 2.5)
	_play_locomotion(moving, maxf(t, 0.35) if moving else 1.0)


func set_jump_tilt(vertical_velocity: float, jump_impulse: float) -> void:
	rotation.x = PI / 6.0 * vertical_velocity / jump_impulse


func try_play_attack() -> void:
	if _anim == null:
		return
	var clip: StringName = &""
	for n in _anim.get_animation_list():
		var lower := String(n).to_lower()
		if "attack" in lower:
			clip = n
			break
	if clip == &"":
		return
	_attack_playing = true
	_anim.play(clip)
	var anim_res := _anim.get_animation(clip)
	if anim_res == null:
		_attack_playing = false
		return
	var len := anim_res.length
	await get_tree().create_timer(len / maxf(_anim.speed_scale, 0.01)).timeout
	_attack_playing = false
	_play_locomotion(false, 1.0)
