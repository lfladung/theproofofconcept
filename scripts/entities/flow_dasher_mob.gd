class_name FlowDasherMob
extends FlowModelDasherMob


func _flow_character_scene() -> PackedScene:
	return preload("res://art/characters/enemies/Dasher.glb")


func _body_collision_mask_on_spawn() -> int:
	return 4
