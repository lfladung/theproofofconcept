class_name GlaiverMob
extends EdgeLungeMob


func _ready() -> void:
	super._ready()
	if _visual != null:
		_visual.facing_yaw_offset_deg = 90.0


func _edge_character_scene() -> PackedScene:
	return preload("res://art/characters/enemies/Glavier.glb")
