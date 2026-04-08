class_name SpawnerMob
extends EdgeLungeMob


func _edge_character_scene() -> PackedScene:
	return preload("res://art/characters/enemies/Spawner.glb")
