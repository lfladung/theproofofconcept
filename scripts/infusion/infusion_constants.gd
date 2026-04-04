extends RefCounted
class_name InfusionConstants

## Seven infusion pillars from `ideas/EQUIPMENT_UPGRADES.md`. Not StatPillar2D / menu `pillar_root.gd`.

## Ordered threshold states (also `resolve_threshold` return values).
enum InfusionThreshold {
	INACTIVE = 0,
	BASELINE = 1,
	ESCALATED = 2,
	EXPRESSION = 3,
}

const PILLAR_EDGE: StringName = &"edge"
const PILLAR_FLOW: StringName = &"flow"
const PILLAR_MASS: StringName = &"mass"
const PILLAR_ECHO: StringName = &"echo"
const PILLAR_ANCHOR: StringName = &"anchor"
const PILLAR_PHASE: StringName = &"phase"
const PILLAR_SURGE: StringName = &"surge"

const PILLAR_ORDER: Array[StringName] = [
	PILLAR_EDGE,
	PILLAR_FLOW,
	PILLAR_MASS,
	PILLAR_ECHO,
	PILLAR_ANCHOR,
	PILLAR_PHASE,
	PILLAR_SURGE,
]

## V1 source kinds only (`add_infusion` passes int).
enum SourceKind {
	NORMAL = 0,
	MINI = 1,
}

## Typical stack contribution per instance (caller may pass explicitly).
const STACK_NORMAL: float = 1.0
const STACK_MINI: float = 0.5

static func is_known_pillar(pillar_id: StringName) -> bool:
	return pillar_id in PILLAR_ORDER


## RPC / serialization sometimes yields `String`; normalize so UI and lookups stay consistent.
static func coerce_pillar_id(value: Variant) -> StringName:
	if value is StringName:
		var sn: StringName = value
		if is_known_pillar(sn):
			return sn
		var ls := String(sn).strip_edges().to_lower()
		for p in PILLAR_ORDER:
			if String(p) == ls:
				return p
		return sn
	if value is String:
		var ls2 := (value as String).strip_edges().to_lower()
		for p in PILLAR_ORDER:
			if String(p) == ls2:
				return p
		return StringName(value as String)
	return &""


## String ids match `ArrowProjectile` / loadout `projectile_style_id` (texture set under `art/combat/projectiles/`).
static func handgun_projectile_style_id(pillar_id: StringName) -> StringName:
	if pillar_id == PILLAR_EDGE:
		return &"red"
	if pillar_id == PILLAR_FLOW:
		return &"green"
	if pillar_id == PILLAR_MASS:
		return &"orange"
	if pillar_id == PILLAR_ECHO:
		return &"purple"
	if pillar_id == PILLAR_ANCHOR:
		return &"pink"
	if pillar_id == PILLAR_PHASE:
		return &"blue"
	if pillar_id == PILLAR_SURGE:
		return &"yellow"
	return &"red"


## HUD dot / placeholder colors (sRGB). Anchor uses near-black for visibility on light UI.
static func ui_pillar_dot_color(pillar_id: StringName) -> Color:
	if pillar_id == PILLAR_EDGE:
		return Color(0.92, 0.2, 0.16, 1.0)
	if pillar_id == PILLAR_FLOW:
		return Color(0.2, 0.82, 0.35, 1.0)
	if pillar_id == PILLAR_MASS:
		return Color(0.95, 0.55, 0.12, 1.0)
	if pillar_id == PILLAR_ECHO:
		return Color(0.62, 0.28, 0.92, 1.0)
	if pillar_id == PILLAR_ANCHOR:
		return Color(0.1, 0.1, 0.12, 1.0)
	if pillar_id == PILLAR_PHASE:
		return Color(0.2, 0.56, 0.95, 1.0)
	if pillar_id == PILLAR_SURGE:
		return Color(0.95, 0.88, 0.22, 1.0)
	return Color(0.55, 0.58, 0.66, 1.0)
