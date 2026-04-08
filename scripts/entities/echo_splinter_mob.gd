class_name EchoSplinterMob
extends ScramblerMob


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Splitter.glb")
	return build_single_scene_visual_state_config(scene, 1.25)
