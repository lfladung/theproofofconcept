extends Node3D
class_name InfusionPillarVisual

const IC := preload("res://scripts/infusion/infusion_constants.gd")

## V1 debug subscriber — not menu `pillar_root.gd`. Uses `pillar_state_changed` (threshold-only).

@export var tracked_pillar_id: StringName = IC.PILLAR_EDGE
@export var infusion_manager_path: NodePath

var _manager
var _last_thr: int = int(IC.InfusionThreshold.INACTIVE)


func _ready() -> void:
	_manager = _resolve_infusion_manager()
	if _manager == null:
		push_warning("InfusionPillarVisual: InfusionManager not found (set infusion_manager_path or parent under Player).")
		return
	_manager.pillar_state_changed.connect(_on_pillar_state_changed)
	_last_thr = int(_manager.call(&"get_pillar_threshold", tracked_pillar_id))
	_apply_visual_tier(_last_thr)


func _resolve_infusion_manager():
	if not infusion_manager_path.is_empty():
		return get_node_or_null(infusion_manager_path)
	var p: Node = get_parent()
	while p != null:
		var im = p.get_node_or_null(^"InfusionManager")
		if im != null:
			return im
		p = p.get_parent()
	return null


func _on_pillar_state_changed(pillar_id: StringName, _old_thr: int, new_thr: int) -> void:
	if pillar_id != tracked_pillar_id:
		return
	_last_thr = new_thr
	_apply_visual_tier(new_thr)


func _apply_visual_tier(tier: int) -> void:
	print("[InfusionPillarVisual] pillar=%s tier=%s" % [tracked_pillar_id, tier])
	visible = tier != int(IC.InfusionThreshold.INACTIVE)
	match tier:
		int(IC.InfusionThreshold.INACTIVE):
			scale = Vector3.ONE * 0.25
		int(IC.InfusionThreshold.BASELINE):
			scale = Vector3.ONE * 0.5
		int(IC.InfusionThreshold.ESCALATED):
			scale = Vector3.ONE * 0.75
		int(IC.InfusionThreshold.EXPRESSION):
			scale = Vector3.ONE
		_:
			scale = Vector3.ONE * 0.25
