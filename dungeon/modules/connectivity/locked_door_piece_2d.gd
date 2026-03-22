extends DungeonPiece2D
class_name LockedDoorPiece2D

@export var locked := true
@export var locked_color := Color(0.50, 0.16, 0.70, 1.0)
@export var unlocked_color := Color(0.62, 0.26, 0.86, 1.0)
## When set, a player with this key can enter the trigger zone to open the door (see `dungeon_gameplay_host` group).
@export var key_id: StringName = &""
@export var consume_key_on_unlock := true

var _unlock_zone: Area2D


func _ready() -> void:
	super._ready()
	_apply_lock_state()
	_setup_unlock_zone_if_keyed()


func _setup_unlock_zone_if_keyed() -> void:
	if Engine.is_editor_hint():
		return
	if key_id == &"":
		return
	if _unlock_zone != null:
		return
	_unlock_zone = Area2D.new()
	_unlock_zone.name = &"UnlockZone"
	_unlock_zone.collision_layer = 0
	_unlock_zone.collision_mask = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = get_world_size() + Vector2(4.0, 4.0)
	cs.shape = rect
	_unlock_zone.add_child(cs)
	add_child(_unlock_zone)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not locked or key_id == &"" or _unlock_zone == null:
		return
	var host := get_tree().get_first_node_in_group(&"dungeon_gameplay_host")
	if host == null or not host.has_method(&"try_unlock_keyed_door"):
		return
	for body in _unlock_zone.get_overlapping_bodies():
		if body is Node2D and (body as Node2D).is_in_group(&"player"):
			if host.try_unlock_keyed_door(key_id, consume_key_on_unlock):
				unlock()
			return


func set_locked(value: bool) -> void:
	locked = value
	_apply_lock_state()


func lock() -> void:
	set_locked(true)


func unlock() -> void:
	set_locked(false)


func _apply_lock_state() -> void:
	set_blocks_movement(locked)
	display_color = locked_color if locked else unlocked_color
	_rebuild_piece_geometry()
