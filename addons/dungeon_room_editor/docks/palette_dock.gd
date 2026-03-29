@tool
extends VBoxContainer

signal piece_selected(piece_id: StringName)

const _CATEGORY_ORDER := [
	"floor",
	"wall",
	"door",
	"spawn",
	"exit",
	"prop",
	"trap",
	"treasure",
]
const _ALL_CATEGORIES: StringName = &"all"
const _PREVIEW_CAMERA_PITCH_DEG := -38.0
const _PREVIEW_CAMERA_YAW_DEG := 180.0
const _PREVIEW_CAMERA_MIN_DISTANCE := 10.0
const _PREVIEW_CAMERA_DISTANCE_SCALE := 2.4
const _PREVIEW_CAMERA_MIN_SIZE := 1.8
const _PREVIEW_CAMERA_SIZE_SCALE := 0.62
const DUNGEON_BG_COLOR := Color(0.035, 0.04, 0.055, 1.0)
const DUNGEON_AMBIENT_COLOR := Color(0.62, 0.58, 0.52, 1.0)
const DUNGEON_AMBIENT_ENERGY := 0.5
const DUNGEON_SUN_ROTATION_DEG := Vector3(-63.8, 60.0, 0.0)
const DUNGEON_SUN_ENERGY := 1.0
const DUNGEON_SUN_SHADOW_BIAS := 0.04
const DUNGEON_SUN_SHADOW_BLUR := 1.5
const DUNGEON_SUN_MAX_DISTANCE := 260.0

@onready var _search_line: LineEdit = %SearchLine
@onready var _category_filter: OptionButton = %CategoryFilter
@onready var _piece_tree: Tree = %PieceTree
@onready var _piece_preview_viewport: SubViewport = %PiecePreviewViewport
@onready var _piece_preview_content: Node3D = %PiecePreviewContent
@onready var _piece_preview_environment: WorldEnvironment = %PiecePreviewEnvironment
@onready var _piece_preview_camera_pivot: Node3D = %PiecePreviewCameraPivot
@onready var _piece_preview_camera: Camera3D = %PiecePreviewCamera
@onready var _key_light: DirectionalLight3D = %KeyLight
@onready var _fill_light: DirectionalLight3D = %FillLight

var _catalog
var _category_values: Array[StringName] = []
var _is_programmatic_selection := false
var _selected_piece_id: StringName = &""
var _selected_category_filter: StringName = _ALL_CATEGORIES


func _ready() -> void:
	_piece_tree.hide_root = true
	_piece_tree.item_selected.connect(_on_piece_tree_item_selected)
	_search_line.text_changed.connect(func(_text: String) -> void: _rebuild_tree())
	_category_filter.item_selected.connect(_on_category_filter_selected)
	_configure_piece_preview()
	_refresh_piece_preview(null)


func set_catalog(catalog) -> void:
	_catalog = catalog
	_populate_category_filter()
	_rebuild_tree()
	_refresh_piece_preview(_catalog.find_piece(_selected_piece_id) if _catalog != null else null)


func set_active_piece(piece_id: StringName) -> void:
	if _catalog == null:
		return
	var piece = _catalog.find_piece(piece_id)
	if piece != null:
		_ensure_piece_category_visible(piece)
	if _piece_tree.get_root() != null:
		var selected := _piece_tree.get_selected()
		if selected != null and selected.get_metadata(0) == piece_id:
			_selected_piece_id = piece_id
			_refresh_piece_preview(piece)
			return
		_is_programmatic_selection = true
		_select_piece_in_tree(_piece_tree.get_root(), piece_id)
		_is_programmatic_selection = false
	_selected_piece_id = piece_id
	_refresh_piece_preview(piece)


func _populate_category_filter() -> void:
	_category_filter.clear()
	_category_values.clear()
	_category_values.append(_ALL_CATEGORIES)
	_category_filter.add_item("All Categories")
	if _catalog == null:
		_selected_category_filter = _ALL_CATEGORIES
		return
	for category in _ordered_categories():
		_category_values.append(StringName(category))
		_category_filter.add_item(_display_category_name(StringName(category)))
	if not _category_values.has(_selected_category_filter):
		_selected_category_filter = _ALL_CATEGORIES
	_select_category_filter(_selected_category_filter)


func _rebuild_tree() -> void:
	_piece_tree.clear()
	var root := _piece_tree.create_item()
	if _catalog == null:
		return
	var filter_text := _search_line.text.strip_edges().to_lower()
	var visible_count := 0
	for category in _ordered_categories():
		var category_name := StringName(category)
		if _selected_category_filter != _ALL_CATEGORIES and category_name != _selected_category_filter:
			continue
		var entries = _catalog.pieces_in_category(category_name)
		var category_item: TreeItem
		for piece in entries:
			if piece == null:
				continue
			var label = piece.display_name if piece.display_name != "" else String(piece.piece_id)
			if filter_text != "" and label.to_lower().find(filter_text) == -1:
				continue
			if category_item == null:
				category_item = _piece_tree.create_item(root)
				category_item.set_text(0, _display_category_name(category_name))
				category_item.set_selectable(0, false)
				category_item.collapsed = false
			var piece_item := _piece_tree.create_item(category_item)
			piece_item.set_text(0, label)
			piece_item.set_metadata(0, piece.piece_id)
			visible_count += 1
	if visible_count == 0:
		var empty_item := _piece_tree.create_item(root)
		empty_item.set_text(0, "No pieces match the current filter.")
		empty_item.set_selectable(0, false)
		return
	if _selected_piece_id != &"":
		_is_programmatic_selection = true
		_select_piece_in_tree(root, _selected_piece_id)
		_is_programmatic_selection = false


func _ordered_categories() -> PackedStringArray:
	var categories := PackedStringArray()
	if _catalog == null:
		return categories
	var seen: Dictionary = {}
	for category in _CATEGORY_ORDER:
		if _catalog.categories().has(category):
			seen[category] = true
			categories.append(category)
	for category in _catalog.categories():
		if seen.has(category):
			continue
		categories.append(category)
	return categories


func _display_category_name(category: StringName) -> String:
	return String(category).capitalize()


func _select_piece_in_tree(item: TreeItem, piece_id: StringName) -> bool:
	var current := item
	while current != null:
		if current.get_metadata(0) == piece_id:
			current.select(0)
			_piece_tree.scroll_to_item(current)
			return true
		if current.get_first_child() != null and _select_piece_in_tree(current.get_first_child(), piece_id):
			return true
		current = current.get_next()
	return false


func _on_category_filter_selected(index: int) -> void:
	if index < 0 or index >= _category_values.size():
		_selected_category_filter = _ALL_CATEGORIES
	else:
		_selected_category_filter = _category_values[index]
	_rebuild_tree()


func _select_category_filter(category_filter: StringName) -> void:
	_selected_category_filter = category_filter
	for index in range(_category_values.size()):
		if _category_values[index] == category_filter:
			_category_filter.select(index)
			return
	_category_filter.select(0)
	_selected_category_filter = _ALL_CATEGORIES


func _ensure_piece_category_visible(piece) -> void:
	if piece == null:
		return
	if _selected_category_filter == _ALL_CATEGORIES or piece.category == _selected_category_filter:
		return
	_select_category_filter(piece.category)
	_rebuild_tree()


func _on_piece_tree_item_selected() -> void:
	if _is_programmatic_selection:
		return
	var selected := _piece_tree.get_selected()
	if selected == null:
		return
	var piece_id := selected.get_metadata(0)
	if piece_id == null:
		return
	var next_piece_id := piece_id as StringName
	if _selected_piece_id == next_piece_id:
		return
	_selected_piece_id = next_piece_id
	_refresh_piece_preview(_catalog.find_piece(next_piece_id) if _catalog != null else null)
	piece_selected.emit(next_piece_id)


func _configure_piece_preview() -> void:
	_configure_preview_environment()
	_piece_preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_piece_preview_camera_pivot.rotation_degrees = Vector3(
		_PREVIEW_CAMERA_PITCH_DEG,
		_PREVIEW_CAMERA_YAW_DEG,
		0.0
	)
	_piece_preview_camera.position = Vector3(0.0, 0.0, _PREVIEW_CAMERA_MIN_DISTANCE)
	_piece_preview_camera.far = 250.0
	_key_light.rotation_degrees = DUNGEON_SUN_ROTATION_DEG
	_key_light.light_energy = DUNGEON_SUN_ENERGY
	_key_light.shadow_bias = DUNGEON_SUN_SHADOW_BIAS
	_key_light.shadow_blur = DUNGEON_SUN_SHADOW_BLUR
	_key_light.directional_shadow_max_distance = DUNGEON_SUN_MAX_DISTANCE
	_fill_light.visible = false


func _configure_preview_environment() -> void:
	if _piece_preview_environment == null:
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = DUNGEON_BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = DUNGEON_AMBIENT_COLOR
	environment.ambient_light_energy = DUNGEON_AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.sdfgi_enabled = false
	_piece_preview_environment.environment = environment


func _refresh_piece_preview(piece) -> void:
	_clear_piece_preview()
	if piece == null:
		_piece_preview_camera.size = _PREVIEW_CAMERA_MIN_SIZE
		_piece_preview_camera.position = Vector3(0.0, 0.0, _PREVIEW_CAMERA_MIN_DISTANCE)
		_piece_preview_camera_pivot.position = Vector3.ZERO
		_piece_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return

	if piece.preview_scene == null:
		_piece_preview_camera.size = _PREVIEW_CAMERA_MIN_SIZE
		_piece_preview_camera.position = Vector3(0.0, 0.0, _PREVIEW_CAMERA_MIN_DISTANCE)
		_piece_preview_camera_pivot.position = Vector3.ZERO
		_piece_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return

	var instance = piece.preview_scene.instantiate() as Node3D
	if instance == null:
		_piece_preview_camera.size = _PREVIEW_CAMERA_MIN_SIZE
		_piece_preview_camera.position = Vector3(0.0, 0.0, _PREVIEW_CAMERA_MIN_DISTANCE)
		_piece_preview_camera_pivot.position = Vector3.ZERO
		_piece_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return

	_piece_preview_content.add_child(instance)
	_fit_piece_preview(instance)
	_piece_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _clear_piece_preview() -> void:
	for child in _piece_preview_content.get_children():
		child.free()


func _fit_piece_preview(instance: Node3D) -> void:
	var bounds := _merged_mesh_aabb_in_root(instance)
	if bounds.size.length_squared() <= 0.0001:
		_piece_preview_camera.size = _PREVIEW_CAMERA_MIN_SIZE
		_piece_preview_camera.position = Vector3(0.0, 0.0, _PREVIEW_CAMERA_MIN_DISTANCE)
		_piece_preview_camera_pivot.position = Vector3.ZERO
		return

	instance.position += Vector3(
		-bounds.get_center().x,
		-bounds.position.y,
		-bounds.get_center().z
	)
	var centered_bounds := _merged_mesh_aabb_in_root(instance)
	var span := maxf(
		maxf(centered_bounds.size.x, centered_bounds.size.z),
		centered_bounds.size.y
	)
	_piece_preview_camera.size = maxf(span * _PREVIEW_CAMERA_SIZE_SCALE, _PREVIEW_CAMERA_MIN_SIZE)
	_piece_preview_camera.position = Vector3(
		0.0,
		0.0,
		maxf(span * _PREVIEW_CAMERA_DISTANCE_SCALE, _PREVIEW_CAMERA_MIN_DISTANCE)
	)
	_piece_preview_camera_pivot.position = Vector3(0.0, centered_bounds.size.y * 0.42, 0.0)


func _merged_mesh_aabb_in_root(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var merged := AABB()
	var has_any := false
	var mesh_roots: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		mesh_roots.append(root as MeshInstance3D)
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance != null:
			mesh_roots.append(mesh_instance)
	for mesh_instance in mesh_roots:
		if mesh_instance.mesh == null:
			continue
		var root_to_mesh := _transform_to_ancestor(mesh_instance, root)
		var transformed := _transform_aabb(root_to_mesh, mesh_instance.mesh.get_aabb())
		if not has_any:
			merged = transformed
			has_any = true
		else:
			merged = merged.merge(transformed)
	return merged if has_any else AABB()


static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform_to_ancestor := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform_to_ancestor = (current as Node3D).transform * transform_to_ancestor
		current = current.get_parent()
	return transform_to_ancestor


static func _transform_aabb(transform_to_apply: Transform3D, aabb: AABB) -> AABB:
	var position := aabb.position
	var size := aabb.size
	var corners: Array[Vector3] = [
		Vector3(position.x, position.y, position.z),
		Vector3(position.x + size.x, position.y, position.z),
		Vector3(position.x, position.y + size.y, position.z),
		Vector3(position.x, position.y, position.z + size.z),
		Vector3(position.x + size.x, position.y + size.y, position.z),
		Vector3(position.x + size.x, position.y, position.z + size.z),
		Vector3(position.x, position.y + size.y, position.z + size.z),
		Vector3(position.x + size.x, position.y + size.y, position.z + size.z),
	]
	var transformed := AABB()
	var has_point := false
	for corner in corners:
		var transformed_corner := transform_to_apply * corner
		if not has_point:
			transformed = AABB(transformed_corner, Vector3.ZERO)
			has_point = true
		else:
			transformed = transformed.expand(transformed_corner)
	return transformed if has_point else AABB()
