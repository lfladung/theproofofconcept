class_name FlowModelDasherMob
extends DasherMob
## Rush/Flow mid+deep: Dasher gameplay with a single static GLB for idle/walk (no shardlings).

@export var flow_clip_scale: float = 2.5


func _flow_character_scene() -> PackedScene:
	return null


func _build_visual_state_config() -> Dictionary:
	var scene := _flow_character_scene()
	if scene == null:
		return super._build_visual_state_config()
	return build_single_scene_visual_state_config(scene, flow_clip_scale)
