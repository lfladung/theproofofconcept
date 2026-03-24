extends CharacterBody2D
class_name EnemyBase

signal squashed

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")

@export var max_health := 50
@export var drops_coin_on_death := true
@export var show_damage_text := true
@export var damage_text_world_y := 2.8
@export var damage_text_rise := 1.6
@export var damage_text_duration := 0.7
@export var damage_text_font_size := 220

var _health := 0
var _dead := false


func _ready() -> void:
	_health = max_health


func configure_spawn(start_position: Vector2, _player_position: Vector2) -> void:
	global_position = start_position


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func set_aggro_enabled(_enabled: bool) -> void:
	pass


func take_hit(damage: int, knockback_dir: Vector2, knockback_strength: float) -> void:
	if damage <= 0 or _dead:
		return
	if show_damage_text:
		_show_floating_damage_text(damage)
	_health = maxi(0, _health - damage)
	if _health <= 0:
		squash()
		return
	_on_nonlethal_hit(knockback_dir, knockback_strength)


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	pass


func can_contact_damage() -> bool:
	return false


func squash() -> void:
	if _dead:
		return
	_dead = true
	squashed.emit()
	if drops_coin_on_death:
		_spawn_dropped_coin()
	queue_free()


func _spawn_dropped_coin() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var coin := DROPPED_COIN_SCENE.instantiate() as Node2D
	if coin == null:
		return
	parent.add_child(coin)
	coin.global_position = global_position


func _resolve_visual_world_3d() -> Node3D:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var direct := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
		if direct != null:
			return direct
	var n: Node = self
	while n != null:
		var par := n.get_parent()
		if par == null:
			break
		var gpr := par.get_parent()
		if gpr != null:
			var vw := gpr.get_node_or_null("VisualWorld3D") as Node3D
			if vw != null:
				return vw
		n = par
	return null


func _show_floating_damage_text(damage: int) -> void:
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	var text := Label3D.new()
	text.text = "-%s HP" % [damage]
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.font_size = damage_text_font_size
	text.outline_size = 16
	text.modulate = Color(1.0, 0.15, 0.15, 1.0)
	text.position = Vector3(global_position.x, damage_text_world_y, global_position.y)
	vw.add_child(text)
	var tween := text.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		text,
		"position",
		text.position + Vector3(0.0, damage_text_rise, 0.0),
		damage_text_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(text, "modulate:a", 0.0, damage_text_duration).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN
	)
	tween.chain().tween_callback(text.queue_free)
