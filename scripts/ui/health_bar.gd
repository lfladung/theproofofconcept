extends Control

## Black frame → red (missing HP) → green (current HP) on top.

@onready var _inner: Control = $Frame/Inner
@onready var _red: ColorRect = $Frame/Inner/Red
@onready var _green: ColorRect = $Frame/Inner/Green

var _ratio: float = 1.0
var _bound_player: Node


func _ready() -> void:
	_inner.resized.connect(_apply_fill_width)
	_try_bind_local_player()
	call_deferred(&"_apply_fill_width")


func _process(_delta: float) -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		_try_bind_local_player()
		return
	if multiplayer.multiplayer_peer != null:
		if _bound_player is CharacterBody2D and not (_bound_player as CharacterBody2D).is_multiplayer_authority():
			_try_bind_local_player()
		elif _bound_player is not CharacterBody2D:
			_try_bind_local_player()


func _try_bind_local_player() -> void:
	var p := _find_local_player()
	if p == null:
		return
	if _bound_player != null and _bound_player.has_signal(&"health_changed") and _bound_player.health_changed.is_connected(
		_on_player_health_changed
	):
		_bound_player.health_changed.disconnect(_on_player_health_changed)
	_bound_player = p
	if _bound_player.has_signal(&"health_changed") and not _bound_player.health_changed.is_connected(
		_on_player_health_changed
	):
		_bound_player.health_changed.connect(_on_player_health_changed)
	var mx: Variant = _bound_player.get(&"max_health")
	var cur: Variant = _bound_player.get(&"health")
	var mxi := int(mx) if mx != null else 100
	var curi := int(cur) if cur != null else mxi
	_on_player_health_changed(curi, mxi)


func _find_local_player() -> Node:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return null
	if multiplayer.multiplayer_peer == null:
		return players[0]
	for node in players:
		if node is CharacterBody2D and (node as CharacterBody2D).is_multiplayer_authority():
			return node
	return null


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
