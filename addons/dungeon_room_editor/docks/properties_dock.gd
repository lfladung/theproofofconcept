@tool
extends ScrollContainer

signal room_properties_changed(room_id: String, room_tags: PackedStringArray, enemy_groups: PackedStringArray, room_size_tiles: Vector2i)
signal selected_item_changed(payload: Dictionary)
signal export_json_requested(path: String)
signal import_json_requested(path: String)

@onready var _room_id_line: LineEdit = %RoomIdLine
@onready var _room_tags_line: LineEdit = %RoomTagsLine
@onready var _enemy_groups_line: LineEdit = %EnemyGroupsLine
@onready var _origin_mode_option: OptionButton = %OriginModeOption
@onready var _room_width_spin: SpinBox = %RoomWidthSpin
@onready var _room_height_spin: SpinBox = %RoomHeightSpin
@onready var _selected_piece_label: Label = %SelectedPieceLabel
@onready var _grid_x_spin: SpinBox = %GridXSpin
@onready var _grid_y_spin: SpinBox = %GridYSpin
@onready var _rotation_option: OptionButton = %RotationOption
@onready var _placement_layer_option: OptionButton = %PlacementLayerOption
@onready var _item_tags_line: LineEdit = %ItemTagsLine
@onready var _encounter_group_line: LineEdit = %EncounterGroupLine
@onready var _enemy_id_line: LineEdit = %EnemyIdLine
@onready var _blocks_movement_check: CheckBox = %BlocksMovementCheck
@onready var _blocks_projectiles_check: CheckBox = %BlocksProjectilesCheck
@onready var _status_label: Label = %StatusLabel
@onready var _export_button: Button = %ExportButton
@onready var _import_button: Button = %ImportButton

var _export_dialog: FileDialog
var _import_dialog: FileDialog

var _is_refreshing := false
var _selected_item_id := ""


func _ready() -> void:
	_origin_mode_option.clear()
	_origin_mode_option.add_item("Center", 0)
	_origin_mode_option.add_item("Top Left", 1)
	_rotation_option.clear()
	for label in ["0°", "90°", "180°", "270°"]:
		_rotation_option.add_item(label)
	_placement_layer_option.clear()
	_placement_layer_option.add_item("Ground", 0)
	_placement_layer_option.add_item("Overlay", 1)
	_connect_room_handlers()
	_connect_item_handlers()
	_export_button.pressed.connect(func() -> void: open_export_dialog("user://room_layout.json"))
	_import_button.pressed.connect(func() -> void: open_import_dialog("user://room_layout.json"))
func _exit_tree() -> void:
	if is_instance_valid(_export_dialog):
		_export_dialog.queue_free()
	if is_instance_valid(_import_dialog):
		_import_dialog.queue_free()


func _ensure_dialogs() -> void:
	if not is_instance_valid(_export_dialog):
		_export_dialog = FileDialog.new()
		_export_dialog.name = "ExportDialog"
		_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_export_dialog.filters = PackedStringArray(["*.json ; JSON"])
		_export_dialog.title = "Export Room Layout JSON"
		get_tree().root.add_child(_export_dialog)
		_export_dialog.file_selected.connect(func(path: String) -> void: export_json_requested.emit(path))
	if not is_instance_valid(_import_dialog):
		_import_dialog = FileDialog.new()
		_import_dialog.name = "ImportDialog"
		_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_import_dialog.filters = PackedStringArray(["*.json ; JSON"])
		_import_dialog.title = "Import Room Layout JSON"
		get_tree().root.add_child(_import_dialog)
		_import_dialog.file_selected.connect(func(path: String) -> void: import_json_requested.emit(path))


func refresh(session) -> void:
	_is_refreshing = true
	if session == null or session.layout == null:
		_room_id_line.text = ""
		_room_tags_line.text = ""
		_enemy_groups_line.text = ""
		_origin_mode_option.select(0)
		_room_width_spin.value = 24
		_room_height_spin.value = 24
		_selected_piece_label.text = "No selection"
		_grid_x_spin.value = 0
		_grid_y_spin.value = 0
		_rotation_option.select(0)
		_placement_layer_option.select(0)
		_item_tags_line.text = ""
		_encounter_group_line.text = ""
		_enemy_id_line.text = ""
		_enemy_id_line.editable = false
		_blocks_movement_check.button_pressed = false
		_blocks_projectiles_check.button_pressed = false
		_selected_item_id = ""
		_status_label.text = ""
		_is_refreshing = false
		return

	_room_id_line.text = session.layout.room_id
	_room_tags_line.text = ", ".join(session.layout.room_tags)
	_enemy_groups_line.text = ", ".join(session.layout.recommended_enemy_groups)
	_origin_mode_option.select(1 if session.room != null and String(session.room.origin_mode) == "top_left" else 0)
	_room_width_spin.value = session.room.room_size_tiles.x if session.room != null else 24
	_room_height_spin.value = session.room.room_size_tiles.y if session.room != null else 24
	var item = session.selected_item()
	var piece = session.selected_piece()
	_selected_item_id = item.item_id if item != null else ""
	if item != null and piece != null:
		_selected_piece_label.text = "%s (%s)" % [
			piece.display_name if piece.display_name != "" else String(piece.piece_id),
			String(piece.category),
		]
		_grid_x_spin.value = item.grid_position.x
		_grid_y_spin.value = item.grid_position.y
		_rotation_option.select(item.normalized_rotation_steps())
		_placement_layer_option.select(_placement_layer_option_index(item.resolved_placement_layer(piece)))
		_item_tags_line.text = ", ".join(item.tags)
		_encounter_group_line.text = String(item.encounter_group_id)
		var enemy_id_editable: bool = (
			piece.has_method(&"is_enemy_spawn_marker")
			and piece.is_enemy_spawn_marker()
		)
		_enemy_id_line.editable = enemy_id_editable
		_enemy_id_line.text = String(item.resolved_enemy_id(piece)) if enemy_id_editable else ""
		_blocks_movement_check.button_pressed = item.blocks_movement
		_blocks_projectiles_check.button_pressed = item.blocks_projectiles
	else:
		_selected_piece_label.text = "No selection"
		_grid_x_spin.value = 0
		_grid_y_spin.value = 0
		_rotation_option.select(0)
		_placement_layer_option.select(0)
		_item_tags_line.text = ""
		_encounter_group_line.text = ""
		_enemy_id_line.text = ""
		_enemy_id_line.editable = false
		_blocks_movement_check.button_pressed = false
		_blocks_projectiles_check.button_pressed = false
	_is_refreshing = false


func set_status(message: String) -> void:
	_status_label.text = message


func open_export_dialog(default_path: String) -> void:
	_ensure_dialogs()
	_export_dialog.current_path = default_path
	_export_dialog.popup_centered_ratio(0.75)


func open_import_dialog(default_path: String) -> void:
	_ensure_dialogs()
	_import_dialog.current_path = default_path
	_import_dialog.popup_centered_ratio(0.75)


func _connect_room_handlers() -> void:
	_connect_committed_line_edit(_room_id_line, _emit_room_properties_changed)
	_connect_committed_line_edit(_room_tags_line, _emit_room_properties_changed)
	_connect_committed_line_edit(_enemy_groups_line, _emit_room_properties_changed)
	_origin_mode_option.item_selected.connect(func(_index: int) -> void: _emit_room_properties_changed())
	_room_width_spin.value_changed.connect(func(_value: float) -> void: _emit_room_properties_changed())
	_room_height_spin.value_changed.connect(func(_value: float) -> void: _emit_room_properties_changed())


func _connect_item_handlers() -> void:
	_grid_x_spin.value_changed.connect(func(_value: float) -> void: _emit_selected_item_changed())
	_grid_y_spin.value_changed.connect(func(_value: float) -> void: _emit_selected_item_changed())
	_rotation_option.item_selected.connect(func(_index: int) -> void: _emit_selected_item_changed())
	_placement_layer_option.item_selected.connect(func(_index: int) -> void: _emit_selected_item_changed())
	_connect_committed_line_edit(_item_tags_line, _emit_selected_item_changed)
	_connect_committed_line_edit(_encounter_group_line, _emit_selected_item_changed)
	_connect_committed_line_edit(_enemy_id_line, _emit_selected_item_changed)
	_blocks_movement_check.toggled.connect(func(_pressed: bool) -> void: _emit_selected_item_changed())
	_blocks_projectiles_check.toggled.connect(func(_pressed: bool) -> void: _emit_selected_item_changed())


func _connect_committed_line_edit(line_edit: LineEdit, callable_target: Callable) -> void:
	line_edit.text_submitted.connect(func(_text: String) -> void: callable_target.call())
	line_edit.focus_exited.connect(func() -> void: callable_target.call())


func _emit_room_properties_changed(_unused: Variant = null) -> void:
	if _is_refreshing:
		return
	room_properties_changed.emit(
		_room_id_line.text.strip_edges(),
		_split_csv(_room_tags_line.text),
		_split_csv(_enemy_groups_line.text),
		Vector2i(
			maxi(1, int(_room_width_spin.value)),
			maxi(1, int(_room_height_spin.value))
		)
	)


func selected_origin_mode() -> String:
	return "top_left" if _origin_mode_option.selected == 1 else "center"


func _emit_selected_item_changed() -> void:
	if _is_refreshing or _selected_item_id == "":
		return
	selected_item_changed.emit(
		{
			"item_id": _selected_item_id,
			"grid_position": Vector2i(int(_grid_x_spin.value), int(_grid_y_spin.value)),
			"rotation_steps": _rotation_option.selected,
			"placement_layer": selected_placement_layer(),
			"tags": _split_csv(_item_tags_line.text),
			"encounter_group_id": StringName(_encounter_group_line.text.strip_edges()),
			"enemy_id": StringName(_enemy_id_line.text.strip_edges()),
			"blocks_movement": _blocks_movement_check.button_pressed,
			"blocks_projectiles": _blocks_projectiles_check.button_pressed,
		}
	)


func selected_placement_layer() -> StringName:
	return &"ground" if _placement_layer_option.selected == 0 else &"overlay"


func _placement_layer_option_index(layer: StringName) -> int:
	return 0 if String(layer) != "overlay" else 1


func _split_csv(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in text.split(","):
		var stripped := entry.strip_edges()
		if stripped != "":
			out.append(stripped)
	return out
