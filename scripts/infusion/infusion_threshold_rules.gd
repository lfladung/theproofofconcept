extends Resource
class_name InfusionThresholdRules

const _IC := preload("res://scripts/infusion/infusion_constants.gd")

## Stack cutoffs (effective stack, not instance count). Swap/subclass Resource in v2+ for inscriptions.
@export var baseline: float = 1.0
@export var escalated: float = 2.0
@export var expression: float = 3.0


## Returns `InfusionConstants.InfusionThreshold` as int.
func resolve_threshold(stack_value: float) -> int:
	if stack_value < baseline:
		return int(_IC.InfusionThreshold.INACTIVE)
	if stack_value < escalated:
		return int(_IC.InfusionThreshold.BASELINE)
	if stack_value < expression:
		return int(_IC.InfusionThreshold.ESCALATED)
	return int(_IC.InfusionThreshold.EXPRESSION)
