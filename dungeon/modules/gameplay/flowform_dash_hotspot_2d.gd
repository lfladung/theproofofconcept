class_name FlowformDashHotspot2D
extends Node2D
## Server-side lingering dash hazard: tick damage to player hurtboxes via Hitbox2D overlap queries.

const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")

@export var damage_per_tick := 2
@export var tick_interval_sec := 0.35
@export var lifetime_sec := 3.0

@onready var _hitbox: Hitbox2D = $Hitbox


func _ready() -> void:
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.amount = maxi(1, damage_per_tick)
	pkt.kind = &"contact"
	pkt.source_node = null
	pkt.origin = global_position
	pkt.direction = Vector2.ZERO
	pkt.knockback = 0.0
	pkt.apply_iframes = true
	pkt.blockable = true
	pkt.debug_label = &"flowform_trail"
	_hitbox.repeat_mode = Hitbox2D.RepeatMode.INTERVAL
	_hitbox.repeat_interval_sec = maxf(0.08, tick_interval_sec)
	_hitbox.activate(pkt, maxf(0.05, lifetime_sec))
	get_tree().create_timer(lifetime_sec + 0.08).timeout.connect(queue_free)
