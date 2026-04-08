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
	var scale_v: Variant = flow_clip_scale
	return {
		&"idle": {
			"scene": scene,
			"scene_scale": scale_v,
			"clip_hint": "",
			"keywords": [],
		},
		&"walk": {
			"scene": scene,
			"scene_scale": scale_v,
			"clip_hint": "",
			"keywords": [],
		},
	}
