extends RefCounted
class_name DamagePacket

## Typed damage payload shared by hitboxes, hurtboxes, and damage receivers.
var amount: int = 0
var kind: StringName = &"direct"
var source_node: Node = null
var source_uid: int = 0
var attack_instance_id: int = -1
var origin: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
var knockback: float = 0.0
var apply_iframes := true
var blockable := false
var debug_label: StringName = &""
## Player melee backstab (rear arc); also forces a crit when precision rules apply.
var from_backstab := false
## Melee/ranged precision crit (backstab counts as a guaranteed crit).
var is_critical := false
## Secondary Edge procs (splash / overkill spill) must not recurse into full Edge pipelines.
var suppress_edge_procs := false
## Mass impact pulse / shockwave / wall follow-ups must not recurse Mass stagger / unstable hooks.
var suppress_mass_procs := false
## Echo afterimages / twin projectiles / recursive echoes — must not recurse unbounded Echo procs.
var suppress_echo_procs := false
## True for Reverberate afterimages, twin bolts, and decayed recursive echoes (see `InfusionEcho`).
var is_echo := false
## 0 = primary swing; each Echo generation increments (Expression cap in `InfusionEcho`).
var echo_generation := 0


func duplicate_packet() -> DamagePacket:
	var copy := DamagePacket.new()
	copy.amount = amount
	copy.kind = kind
	copy.source_node = source_node
	copy.source_uid = source_uid
	copy.attack_instance_id = attack_instance_id
	copy.origin = origin
	copy.direction = direction
	copy.knockback = knockback
	copy.apply_iframes = apply_iframes
	copy.blockable = blockable
	copy.debug_label = debug_label
	copy.from_backstab = from_backstab
	copy.is_critical = is_critical
	copy.suppress_edge_procs = suppress_edge_procs
	copy.suppress_mass_procs = suppress_mass_procs
	copy.suppress_echo_procs = suppress_echo_procs
	copy.is_echo = is_echo
	copy.echo_generation = echo_generation
	return copy


func with_attack_instance(next_attack_instance_id: int) -> DamagePacket:
	var copy := duplicate_packet()
	copy.attack_instance_id = next_attack_instance_id
	return copy


func resolve_source_uid(fallback_uid: int = 0) -> int:
	if source_uid > 0:
		return source_uid
	if source_node != null and is_instance_valid(source_node):
		return source_node.get_instance_id()
	return fallback_uid


func describe() -> String:
	return "%s kind=%s amount=%s source=%s attack=%s" % [
		String(debug_label),
		String(kind),
		amount,
		resolve_source_uid(),
		attack_instance_id,
	]
