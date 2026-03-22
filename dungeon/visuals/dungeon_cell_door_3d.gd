extends Node3D
class_name DungeonCellDoor3D

@onready var _content: Node3D = $Content
@onready var _hinge: Node3D = $Content/HingePivot
@onready var _cell_door: Node3D = $Content/HingePivot/CellDoor
@onready var _door_frame: Node = $Content/DoorFrame

@export var open_angle_deg: float = 78.0
## Small shift along Content Z to separate panel from frame after hinge fit.
@export var door_panel_depth: float = 0.035
## Purple/black tint and swing for combat room doors only; other rooms keep mesh textures.
@export var use_combat_lock_visuals: bool = true
## Disabled by default because it can hide a one-mesh frame asset.
@export var hide_frame_meshes_overlapping_panel: bool = false
## Rare fallback for degenerate imports; subtree filtering below is preferred.
@export var keep_largest_cell_door_mesh_only: bool = false
## If the imported CellDoor contains multiple door sub-roots, keep only one.
@export var keep_primary_cell_door_subtree_only: bool = true

var _open_rotation_y: float = 0.0
var _swing_sign: float = 1.0
var _swing_tween: Tween
var _wall_direction: String = "west"


func _ready() -> void:
	_prep_cell_for_alignment()
	_suppress_redundant_cell_door_subtrees()
	_suppress_redundant_cell_door_meshes()
	_apply_hinge_alignment()
	_hide_static_panel_meshes_in_frame_if_overlapping()
	if use_combat_lock_visuals:
		set_combat_locked(false, false)
	else:
		_hinge.rotation.y = _open_rotation_y


func configure_for_socket(wall_direction: String) -> void:
	_wall_direction = wall_direction
	match wall_direction:
		"west":
			rotation_degrees.y = 0.0
			_swing_sign = -1.0
		"east":
			rotation_degrees.y = 180.0
			_swing_sign = 1.0
		"north":
			rotation_degrees.y = 90.0
			_swing_sign = -1.0
		"south":
			rotation_degrees.y = -90.0
			_swing_sign = 1.0
		_:
			rotation_degrees.y = 0.0
			_swing_sign = 1.0
	_open_rotation_y = deg_to_rad(open_angle_deg) * _swing_sign
	if is_node_ready():
		_prep_cell_for_alignment()
		_suppress_redundant_cell_door_subtrees()
		_suppress_redundant_cell_door_meshes()
		_apply_hinge_alignment()
		_hide_static_panel_meshes_in_frame_if_overlapping()
		if use_combat_lock_visuals:
			set_combat_locked(false, false)
		else:
			_hinge.rotation.y = _open_rotation_y


func set_combat_locked(locked: bool, animate: bool = true) -> void:
	if not use_combat_lock_visuals:
		return
	var closed_y := 0.0
	var target_y := closed_y if locked else _open_rotation_y
	if not is_node_ready():
		return
	if animate:
		if _swing_tween != null:
			_swing_tween.kill()
		_swing_tween = create_tween()
		_swing_tween.tween_property(_hinge, "rotation:y", target_y, 0.5).set_trans(Tween.TRANS_SINE).set_ease(
			Tween.EASE_IN_OUT
		)
	else:
		_hinge.rotation.y = target_y


func _prep_cell_for_alignment() -> void:
	if _hinge == null or _cell_door == null:
		return
	_hinge.position = Vector3.ZERO
	_hinge.rotation = Vector3.ZERO
	_cell_door.rotation = Vector3.ZERO
	_cell_door.scale = Vector3.ONE
	_cell_door.position = Vector3.ZERO


func _suppress_redundant_cell_door_meshes() -> void:
	if not keep_largest_cell_door_mesh_only or _cell_door == null:
		return
	var meshes: Array[MeshInstance3D] = []
	for n in _cell_door.find_children("*", "MeshInstance3D", true, false):
		if n is MeshInstance3D:
			meshes.append(n as MeshInstance3D)
	if meshes.size() < 2:
		return
	var scored: Array[Dictionary] = []
	for mi in meshes:
		if mi.mesh == null:
			continue
		var lx := _cell_door.global_transform.affine_inverse() * mi.global_transform
		var vaabb := _transform_aabb(lx, mi.mesh.get_aabb())
		var v := _aabb_volume(vaabb)
		if v < 1e-10:
			continue
		scored.append({"mi": mi, "v": v})
	if scored.size() < 2:
		return
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ma := a["mi"] as MeshInstance3D
		var mb := b["mi"] as MeshInstance3D
		var ta := _count_surfaces_with_albedo_texture(ma)
		var tb := _count_surfaces_with_albedo_texture(mb)
		if ta != tb:
			return ta > tb
		return (a["v"] as float) > (b["v"] as float)
	)
	for i in range(1, scored.size()):
		(scored[i]["mi"] as MeshInstance3D).visible = false


func _suppress_redundant_cell_door_subtrees() -> void:
	if not keep_primary_cell_door_subtree_only or _cell_door == null:
		return
	var scored: Array[Dictionary] = []
	for c in _cell_door.get_children():
		if not c is Node3D:
			continue
		var child_root := c as Node3D
		var stats := _subtree_mesh_stats(child_root)
		if int(stats["mesh_count"]) == 0:
			continue
		scored.append({"root": child_root, "stats": stats})
	if scored.size() < 2:
		return
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := a["stats"] as Dictionary
		var sb := b["stats"] as Dictionary
		var ta := int(sa["textured"])
		var tb := int(sb["textured"])
		if ta != tb:
			return ta > tb
		return float(sa["volume"]) > float(sb["volume"])
	)
	for i in range(1, scored.size()):
		(scored[i]["root"] as Node3D).visible = false


func _subtree_mesh_stats(root: Node3D) -> Dictionary:
	var total_volume := 0.0
	var textured := 0
	var mesh_count := 0
	var inv := _cell_door.global_transform.affine_inverse()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		mesh_count += 1
		var lx := inv * mi.global_transform
		var vaabb := _transform_aabb(lx, mi.mesh.get_aabb())
		total_volume += _aabb_volume(vaabb)
		textured += _count_surfaces_with_albedo_texture(mi)
	return {"volume": total_volume, "textured": textured, "mesh_count": mesh_count}


static func _count_surfaces_with_albedo_texture(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	var n := 0
	for s in range(mi.mesh.get_surface_count()):
		var mat := mi.get_active_material(s)
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
			n += 1
	return n


func _apply_hinge_alignment() -> void:
	if _hinge == null or _cell_door == null:
		return
	var aabb := _merged_mesh_aabb_in_parent_space(_cell_door)
	if aabb.size.length_squared() < 1e-8:
		return
	var use_max_width_edge := _wall_direction == "east" or _wall_direction == "south"
	var c := aabb.get_center()
	var h := c
	var use_x := aabb.size.x >= aabb.size.z
	if use_x:
		h.x = aabb.position.x + (aabb.size.x if use_max_width_edge else 0.0)
	else:
		h.z = aabb.position.z + (aabb.size.z if use_max_width_edge else 0.0)
	_cell_door.position = -h
	var hinge_pos := h - c
	var zpush := door_panel_depth
	if use_max_width_edge:
		zpush = -door_panel_depth
	hinge_pos += Vector3(0, 0, zpush)
	_hinge.position = hinge_pos


func _hide_static_panel_meshes_in_frame_if_overlapping() -> void:
	if not hide_frame_meshes_overlapping_panel or _door_frame == null or _cell_door == null:
		return
	var frame_meshes: Array[MeshInstance3D] = []
	for n in _door_frame.find_children("*", "MeshInstance3D", true, false):
		if n is MeshInstance3D:
			frame_meshes.append(n as MeshInstance3D)
	var panel_aabb := _merged_global_mesh_aabb(_cell_door)
	var panel_v := _aabb_volume(panel_aabb)
	if panel_v < 1e-8:
		return
	for mi in frame_meshes:
		if not mi.visible or mi.mesh == null:
			continue
		var maabb := _transform_aabb(mi.global_transform, mi.mesh.get_aabb())
		var mv := _aabb_volume(maabb)
		if mv < 1e-8:
			continue
		if mv < 0.03 * panel_v or mv > 5.0 * panel_v:
			continue
		var inter_v := _aabb_intersection_volume(panel_aabb, maabb)
		var den := minf(panel_v, mv)
		if den < 1e-8:
			continue
		var ratio := inter_v / den
		var hide := ratio > 0.30
		if frame_meshes.size() < 2:
			hide = ratio > 0.52
		if hide:
			mi.visible = false


static func _aabb_volume(a: AABB) -> float:
	return a.size.x * a.size.y * a.size.z


static func _aabb_intersection_volume(a: AABB, b: AABB) -> float:
	if not a.intersects(b):
		return 0.0
	var p1 := a.position.max(b.position)
	var p2 := (a.position + a.size).min(b.position + b.size)
	var s := p2 - p1
	if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
		return 0.0
	return s.x * s.y * s.z


func _merged_global_mesh_aabb(root: Node3D) -> AABB:
	var merged: AABB
	var any := false
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not mi is MeshInstance3D:
			continue
		var mesh_inst := mi as MeshInstance3D
		if not mesh_inst.visible or mesh_inst.mesh == null:
			continue
		var maabb := _transform_aabb(mesh_inst.global_transform, mesh_inst.mesh.get_aabb())
		if not any:
			merged = maabb
			any = true
		else:
			merged = merged.merge(maabb)
	return merged if any else AABB()


func _merged_mesh_aabb_in_parent_space(root: Node3D) -> AABB:
	var merged: AABB
	var any := false
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not mi is MeshInstance3D:
			continue
		var mesh_inst := mi as MeshInstance3D
		if not mesh_inst.visible or mesh_inst.mesh == null:
			continue
		var local_xf := root.global_transform.affine_inverse() * mesh_inst.global_transform
		var maabb := _transform_aabb(local_xf, mesh_inst.mesh.get_aabb())
		if not any:
			merged = maabb
			any = true
		else:
			merged = merged.merge(maabb)
	return merged if any else AABB()


static func _transform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
	var p := aabb.position
	var s := aabb.size
	var corners: Array[Vector3] = [
		Vector3(p.x, p.y, p.z),
		Vector3(p.x + s.x, p.y, p.z),
		Vector3(p.x, p.y + s.y, p.z),
		Vector3(p.x, p.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z),
		Vector3(p.x + s.x, p.y, p.z + s.z),
		Vector3(p.x, p.y + s.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z + s.z),
	]
	var out: AABB
	var first := true
	for corner in corners:
		var w := xf * corner
		if first:
			out = AABB(w, Vector3.ZERO)
			first = false
		else:
			out = out.expand(w)
	return out
