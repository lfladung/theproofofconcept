extends Control

## Black frame → red (missing HP) → green (current HP) on top.

@onready var _inner: Control = $Frame/Inner
@onready var _red: ColorRect = $Frame/Inner/Red
@onready var _green: ColorRect = $Frame/Inner/Green

var _ratio: float = 1.0


func _ready() -> void:
	_inner.resized.connect(_apply_fill_width)
	var p := get_tree().get_first_node_in_group(&"player")
	if p == null:
		return
	if p.has_signal(&"health_changed") and not p.health_changed.is_connected(_on_player_health_changed):
		p.health_changed.connect(_on_player_health_changed)
	var mx: Variant = p.get(&"max_health")
	var cur: Variant = p.get(&"health")
	var mxi := int(mx) if mx != null else 100
	var curi := int(cur) if cur != null else mxi
	_on_player_health_changed(curi, mxi)
	call_deferred(&"_apply_fill_width")


func _on_player_health_changed(current: int, maximum: int) -> void:
	var m := maxi(1, maximum)
	_ratio = clampf(float(current) / float(m), 0.0, 1.0)
	_apply_fill_width()


func _apply_fill_width() -> void:
	var w := _red.size.x
	var h := _red.size.y
	if w < 1.0 or h < 1.0:
		return
	_green.position = Vector2.ZERO
	_green.size = Vector2(w * _ratio, h)
