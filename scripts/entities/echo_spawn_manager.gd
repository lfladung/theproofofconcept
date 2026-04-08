extends RefCounted
class_name EchoSpawnManager

var owner: EnemyBase
var children: Array[EnemyBase] = []
var had_active_children := false


func _init(next_owner: EnemyBase = null) -> void:
	owner = next_owner


func active_children() -> Array[EnemyBase]:
	var alive: Array[EnemyBase] = []
	for child in children:
		if child != null and is_instance_valid(child):
			alive.append(child)
	children = alive
	if not alive.is_empty():
		had_active_children = true
	return alive


func active_count() -> int:
	return active_children().size()


func can_spawn(max_children: int) -> bool:
	return active_count() < max_children


func track(child: EnemyBase) -> void:
	if child == null:
		return
	children.append(child)
	had_active_children = true


func should_trigger_empty_burst() -> bool:
	var count := active_count()
	if count == 0 and had_active_children:
		had_active_children = false
		return true
	return false


func clear_without_free() -> void:
	children.clear()
	had_active_children = false
