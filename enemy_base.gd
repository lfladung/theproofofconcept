extends CharacterBody2D
class_name EnemyBase

signal squashed

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")

@export var max_health := 50
@export var drops_coin_on_death := true

var _health := 0
var _dead := false


func _ready() -> void:
	_health = max_health


func configure_spawn(start_position: Vector2, _player_position: Vector2) -> void:
	global_position = start_position


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func take_hit(damage: int, knockback_dir: Vector2, knockback_strength: float) -> void:
	if damage <= 0 or _dead:
		return
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
