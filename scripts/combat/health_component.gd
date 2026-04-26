extends Node
class_name HealthComponent

signal health_changed(current: int, maximum: int)
signal armor_changed(current: int, maximum: int)
signal armor_damaged(packet: DamagePacket, amount: int, current: int, maximum: int)
signal armor_depleted(packet: DamagePacket)
signal damaged(packet: DamagePacket, amount: int, current: int, maximum: int)
signal damage_rejected(packet: DamagePacket, reason: StringName)
signal depleted(packet: DamagePacket)
signal invulnerability_started(duration: float)
signal invulnerability_ended()

@export var max_health := 100
@export var starting_health := 100
@export var max_armor := 0
@export var starting_armor := 0
@export var invulnerability_duration := 0.4
## Subtracted from incoming damage after `mitigation_ignore_ratio` splits the hit (enemies with armor).
@export var flat_damage_mitigation := 0
@export var debug_logging := false
@export var debug_label: StringName = &""

var current_health := 100
var current_armor := 0
var _invulnerability_time_remaining := 0.0


func _ready() -> void:
	max_health = maxi(1, max_health)
	max_armor = maxi(0, max_armor)
	starting_armor = clampi(starting_armor, 0, max_armor)
	if current_health <= 0:
		current_health = clampi(starting_health, 1, max_health)
	else:
		current_health = clampi(current_health, 0, max_health)
	current_armor = clampi(current_armor if current_armor > 0 else starting_armor, 0, max_armor)
	_emit_health_changed()
	_emit_armor_changed()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _invulnerability_time_remaining <= 0.0:
		return
	_invulnerability_time_remaining = maxf(0.0, _invulnerability_time_remaining - delta)
	if _invulnerability_time_remaining <= 0.0:
		invulnerability_ended.emit()


func set_max_health_value(value: int, preserve_current: bool = true) -> void:
	var next_max := maxi(1, value)
	if max_health == next_max and preserve_current:
		return
	max_health = next_max
	if preserve_current:
		current_health = clampi(current_health, 0, max_health)
	else:
		current_health = max_health
	_emit_health_changed()


func set_max_armor_value(value: int, preserve_current: bool = true) -> void:
	var next_max := maxi(0, value)
	if max_armor == next_max and preserve_current:
		return
	max_armor = next_max
	if preserve_current:
		current_armor = clampi(current_armor, 0, max_armor)
	else:
		current_armor = max_armor
	starting_armor = clampi(starting_armor, 0, max_armor)
	_emit_armor_changed()


func set_current_health(value: int) -> void:
	current_health = clampi(value, 0, max_health)
	_emit_health_changed()


func set_current_armor(value: int) -> void:
	current_armor = clampi(value, 0, max_armor)
	_emit_armor_changed()


func heal_to_full() -> void:
	set_current_health(max_health)


func reset_runtime(current: int = -1) -> void:
	clear_invulnerability()
	if current >= 0:
		set_current_health(current)
	else:
		set_current_health(clampi(starting_health, 1, max_health))
	set_current_armor(starting_armor)


func clear_invulnerability() -> void:
	var had_invulnerability := _invulnerability_time_remaining > 0.0
	_invulnerability_time_remaining = 0.0
	if had_invulnerability:
		invulnerability_ended.emit()


func get_invulnerability_remaining() -> float:
	return _invulnerability_time_remaining


func is_invulnerable() -> bool:
	return _invulnerability_time_remaining > 0.0


func is_depleted() -> bool:
	return current_health <= 0


func has_armor() -> bool:
	return current_armor > 0


func apply_damage(packet: DamagePacket, amount_override: int = -1) -> Dictionary:
	var amount := amount_override if amount_override >= 0 else packet.amount
	amount = _apply_mitigation_to_amount(amount, packet)
	if amount <= 0:
		return _reject(packet, &"non_positive", false)
	if current_health <= 0:
		return _reject(packet, &"depleted", true)
	if packet.apply_iframes and is_invulnerable():
		return _reject(packet, &"iframed", true)
	var split := _split_damage_against_armor(amount, packet)
	var armor_damage := int(split.get("armor_damage", 0))
	var hp_damage := int(split.get("hp_damage", 0))
	if armor_damage > 0:
		current_armor = maxi(0, current_armor - armor_damage)
		_emit_armor_changed()
		armor_damaged.emit(packet, armor_damage, current_armor, max_armor)
		_log(
			"armor applied %s armor=%s/%s" % [packet.describe(), current_armor, max_armor]
		)
		if current_armor <= 0:
			armor_depleted.emit(packet)
	if hp_damage > 0:
		current_health = maxi(0, current_health - hp_damage)
		_emit_health_changed()
	if packet.apply_iframes and current_health > 0:
		_start_invulnerability()
	if hp_damage > 0:
		damaged.emit(packet, hp_damage, current_health, max_health)
	_log("applied %s current=%s/%s" % [packet.describe(), current_health, max_health])
	if current_health <= 0:
		depleted.emit(packet)
	return {
		"accepted": true,
		"consume_hit": true,
		"reason": &"applied",
		"hp_damage": hp_damage,
		"armor_damage": armor_damage,
		"current_health": current_health,
		"current_armor": current_armor,
	}


func _start_invulnerability() -> void:
	_invulnerability_time_remaining = maxf(0.0, invulnerability_duration)
	if _invulnerability_time_remaining > 0.0:
		invulnerability_started.emit(_invulnerability_time_remaining)


func _reject(packet: DamagePacket, reason: StringName, consume_hit: bool) -> Dictionary:
	damage_rejected.emit(packet, reason)
	_log("rejected %s reason=%s" % [packet.describe(), String(reason)])
	return {
		"accepted": false,
		"consume_hit": consume_hit,
		"reason": reason,
		"hp_damage": 0,
		"current_health": current_health,
	}


func _emit_health_changed() -> void:
	health_changed.emit(current_health, max_health)


func _emit_armor_changed() -> void:
	armor_changed.emit(current_armor, max_armor)


func _apply_mitigation_to_amount(amount: int, packet: DamagePacket) -> int:
	if amount <= 0:
		return 0
	var mit := maxi(0, flat_damage_mitigation)
	if mit <= 0 or packet == null:
		return amount
	var ign := clampf(packet.mitigation_ignore_ratio, 0.0, 1.0)
	if ign <= 0.0:
		return maxi(0, amount - mit)
	var bypass := int(roundf(float(amount) * ign))
	var armored := amount - bypass
	var reduced := maxi(0, armored - mit)
	return maxi(0, bypass + reduced)


func _split_damage_against_armor(amount: int, packet: DamagePacket) -> Dictionary:
	if amount <= 0:
		return {"armor_damage": 0, "hp_damage": 0}
	if current_armor <= 0 or packet == null:
		return {"armor_damage": 0, "hp_damage": amount}
	var ignore_ratio := clampf(packet.mitigation_ignore_ratio, 0.0, 1.0)
	var bypass_damage := clampi(int(roundf(float(amount) * ignore_ratio)), 0, amount)
	var armor_lane_damage := amount - bypass_damage
	var armor_damage := mini(current_armor, armor_lane_damage)
	var overflow_damage := maxi(0, armor_lane_damage - armor_damage)
	return {
		"armor_damage": armor_damage,
		"hp_damage": bypass_damage + overflow_damage,
	}


func _log(message: String) -> void:
	if not debug_logging:
		return
	print("[Combat][Health][%s] %s" % [String(debug_label), message])
