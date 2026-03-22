extends Area2D
class_name TreasureChest2D

signal opened

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")

@export var coin_count := 10
@export var spew_radius_min := 0.45
@export var spew_radius_max := 3.2
@export var closed_color := Color(0.55, 0.35, 0.18, 1.0)
@export var open_color := Color(0.42, 0.38, 0.32, 1.0)

@onready var _visual: Polygon2D = $Visual

var _opened := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	if _visual:
		_visual.color = closed_color


func _on_body_entered(body: Node2D) -> void:
	if _opened or body == null or not body.is_in_group(&"player"):
		return
	_opened = true
	if _visual:
		_visual.color = open_color
	opened.emit()
	_spew_coins()


func _spew_coins() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var n := maxi(0, coin_count)
	if n <= 0:
		return
	for i in n:
		var coin := DROPPED_COIN_SCENE.instantiate() as Node2D
		if coin == null:
			continue
		var t := (float(i) + 0.5) / float(n)
		var ang := t * TAU + randf_range(-0.4, 0.4)
		var rad := randf_range(spew_radius_min, spew_radius_max)
		var offset := Vector2.from_angle(ang) * rad
		parent.add_child(coin)
		coin.global_position = global_position + offset
