extends RefCounted
class_name ArrowProjectilePool

const _PROJECTILE_SCENE_PATH := "res://scenes/entities/arrow_projectile.tscn"
const _MAX_POOLED_PROJECTILES := 96

static var _projectile_scene: PackedScene
static var _available_projectiles: Array = []


static func acquire_projectile(parent: Node) -> ArrowProjectile:
	if parent == null:
		return null
	_prune_invalid_projectiles()
	var projectile: ArrowProjectile = null
	while projectile == null and not _available_projectiles.is_empty():
		var candidate_v: Variant = _available_projectiles.pop_back()
		if is_instance_valid(candidate_v) and candidate_v is ArrowProjectile:
			projectile = candidate_v as ArrowProjectile
	if projectile == null:
		var scene := _ensure_projectile_scene()
		if scene == null:
			return null
		projectile = scene.instantiate() as ArrowProjectile
		if projectile == null:
			return null
	var current_parent := projectile.get_parent()
	if current_parent != parent:
		if current_parent != null:
			current_parent.remove_child(projectile)
		parent.add_child(projectile)
	projectile.set_pooled_enabled(true)
	projectile.reactivate_from_pool()
	return projectile


static func release_projectile(projectile: ArrowProjectile) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	if _available_projectiles.has(projectile):
		return
	if _available_projectiles.size() >= _MAX_POOLED_PROJECTILES:
		projectile.set_pooled_enabled(false)
		projectile.queue_free()
		return
	projectile.deactivate_for_pool()
	_available_projectiles.append(projectile)


static func _ensure_projectile_scene() -> PackedScene:
	if _projectile_scene != null:
		return _projectile_scene
	var loaded := load(_PROJECTILE_SCENE_PATH)
	if loaded is PackedScene:
		_projectile_scene = loaded as PackedScene
	return _projectile_scene


static func _prune_invalid_projectiles() -> void:
	if _available_projectiles.is_empty():
		return
	var kept: Array = []
	for projectile_v in _available_projectiles:
		if is_instance_valid(projectile_v) and projectile_v is ArrowProjectile:
			kept.append(projectile_v)
	_available_projectiles = kept
