extends RefCounted
class_name InfusionInstance

const _IC := preload("res://scripts/infusion/infusion_constants.gd")

## Stable id assigned by InfusionManager.
var instance_id: int = -1
var pillar_id: StringName = &""
var stack_contribution: float = 0.0
## `InfusionConstants.SourceKind` (int).
var source_kind: int = _IC.SourceKind.NORMAL


func _init(
	p_id: StringName = &"",
	contrib: float = 0.0,
	source: int = _IC.SourceKind.NORMAL
) -> void:
	pillar_id = p_id
	stack_contribution = contrib
	source_kind = source
