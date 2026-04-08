class_name EchoformMob
extends EdgeLungeMob


func _edge_character_scene() -> PackedScene:
	return preload("res://art/characters/enemies/Spawner.glb")
