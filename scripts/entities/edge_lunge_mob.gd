class_name EdgeLungeMob
extends DasherMob
## Edge family: lunge attack like Dasher, but model-only (no clips) and shake telegraph instead of ground arrow.

@export var edge_clip_scale: float = 1.0


func _edge_character_scene() -> PackedScene:
	return null


func _build_visual_state_config() -> Dictionary:
	var scene := _edge_character_scene()
	if scene == null:
		return super._build_visual_state_config()
	var scale_v: Variant = edge_clip_scale
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


func _sync_visual_from_body() -> void:
	if _visual != null:
		var shake := 0.0
		if _is_telegraphing:
			shake = clampf(_telegraph_time / maxf(0.01, telegraph_duration), 0.0, 1.0)
		_visual.set_attack_shake_progress(shake)
	super._sync_visual_from_body()


func _update_telegraph_visual() -> void:
	if _telegraph_mesh != null:
		_telegraph_mesh.visible = false
		_telegraph_progress_step = -1
