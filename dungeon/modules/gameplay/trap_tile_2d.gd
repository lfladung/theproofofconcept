extends Node2D
class_name TrapTile2D

@export var damage := 18
@export var hit_cooldown_sec := 1.1
@export var trap_color := Color(1.0, 0.89, 0.10, 0.92)
@export var footprint := Vector2(6.0, 6.0)

@onready var _visual: Polygon2D = $Visual
@onready var _hurtbox: Area2D = $Hurtbox

var _next_hit_time: Dictionary = {}


func _ready() -> void:
	_rebuild_visual()
	_setup_hurtbox()
	_hurtbox.body_exited.connect(_on_hurtbox_body_exited)


func _rebuild_visual() -> void:
	if _visual == null:
		return
	var half := footprint * 0.5
	_visual.color = trap_color
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


func _setup_hurtbox() -> void:
	var cs := _hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	if cs == null or not cs.shape is RectangleShape2D:
		return
	var r := cs.shape as RectangleShape2D
	r.size = footprint


func _physics_process(_delta: float) -> void:
	for body in _hurtbox.get_overlapping_bodies():
		if body is Node2D and body.is_in_group(&"player"):
			_try_damage(body as Node2D)


func _on_hurtbox_body_exited(body: Node2D) -> void:
	if body != null:
		_next_hit_time.erase(body.get_instance_id())


func _try_damage(body: Node2D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var id := body.get_instance_id()
	var due: float = float(_next_hit_time.get(id, 0.0))
	if now < due:
		return
	if body.has_method(&"take_damage"):
		body.call(&"take_damage", damage)
	_next_hit_time[id] = now + hit_cooldown_sec
