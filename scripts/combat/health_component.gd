extends Node
class_name HealthComponent

signal health_changed(current: int, maximum: int)
signal damaged(packet: DamagePacket, amount: int, current: int, maximum: int)
signal damage_rejected(packet: DamagePacket, reason: StringName)
signal depleted(packet: DamagePacket)
signal invulnerability_started(duration: float)
signal invulnerability_ended()

@export var max_health := 100
@export var starting_health := 100
@export var invulnerability_duration := 0.4
@export var debug_logging := false
@export var debug_label: StringName = &""

var current_health := 100
var _invulnerability_time_remaining := 0.0


func _ready() -> void:
	max_health = maxi(1, max_health)
	if current_health <= 0:
		current_health = clampi(starting_health, 1, max_health)
	else:
		current_health = clampi(current_health, 0, max_health)
	_emit_health_changed()
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


func set_current_health(value: int) -> void:
	current_health = clampi(value, 0, max_health)
	_emit_health_changed()


func heal_to_full() -> void:
	set_current_health(max_health)


func reset_runtime(current: int = -1) -> void:
	clear_invulnerability()
	if current >= 0:
		set_current_health(current)
	else:
		set_current_health(clampi(starting_health, 1, max_health))


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


func apply_damage(packet: DamagePacket, amount_override: int = -1) -> Dictionary:
	var amount := amount_override if amount_override >= 0 else packet.amount
	if amount <= 0:
		return _reject(packet, &"non_positive", false)
	if current_health <= 0:
		return _reject(packet, &"depleted", true)
	if packet.apply_iframes and is_invulnerable():
		return _reject(packet, &"iframed", true)
	current_health = maxi(0, current_health - amount)
	_emit_health_changed()
	if packet.apply_iframes and current_health > 0:
		_start_invulnerability()
	damaged.emit(packet, amount, current_health, max_health)
	_log("applied %s current=%s/%s" % [packet.describe(), current_health, max_health])
	if current_health <= 0:
		depleted.emit(packet)
	return {
		"accepted": true,
		"consume_hit": true,
		"reason": &"applied",
		"hp_damage": amount,
		"current_health": current_health,
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


func _log(message: String) -> void:
	if not debug_logging:
		return
	print("[Combat][Health][%s] %s" % [String(debug_label), message])
