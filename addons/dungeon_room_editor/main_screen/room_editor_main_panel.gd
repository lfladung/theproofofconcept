@tool
extends Control

signal mode_requested(mode: int)
signal box_paint_toggled(enabled: bool)
signal placement_rotation_selected(rotation_steps: int)
signal visible_layer_requested(layer_filter: StringName)
signal center_view_requested()
signal popout_preview_toggled(open_requested: bool)
signal playtest_requested()

@onready var _place_button: Button = %PlaceButton
@onready var _box_paint_check: CheckBox = %BoxPaintCheck
@onready var _placement_rotation_label: Label = %PlacementRotationLabel
@onready var _placement_rotation_option: OptionButton = %PlacementRotationOption
@onready var _select_button: Button = %SelectButton
@onready var _erase_button: Button = %EraseButton
@onready var _rotate_button: Button = %RotateButton
@onready var _visible_layer_option: OptionButton = %VisibleLayerOption
@onready var _center_view_button: Button = %CenterViewButton
@onready var _popout_preview_button: Button = %PopoutPreviewButton
@onready var _playtest_button: Button = %PlaytestButton
@onready var _room_canvas: Control = %RoomCanvas
@onready var _palette_dock: Control = %PaletteDock
@onready var _properties_dock: ScrollContainer = %PropertiesDock
@onready var _preview_dock: Control = %PreviewDock


func _ready() -> void:
	_place_button.pressed.connect(func() -> void: mode_requested.emit(0))
	_box_paint_check.toggled.connect(func(enabled: bool) -> void: box_paint_toggled.emit(enabled))
	_placement_rotation_option.clear()
	for label in ["0° North", "90° East", "180° South", "270° West"]:
		_placement_rotation_option.add_item(label)
	_placement_rotation_option.item_selected.connect(
		func(index: int) -> void: placement_rotation_selected.emit(index)
	)
	_select_button.pressed.connect(func() -> void: mode_requested.emit(1))
	_erase_button.pressed.connect(func() -> void: mode_requested.emit(2))
	_rotate_button.pressed.connect(func() -> void: mode_requested.emit(3))
	_visible_layer_option.clear()
	_visible_layer_option.add_item("All", 0)
	_visible_layer_option.add_item("Ground", 1)
	_visible_layer_option.add_item("Overlay", 2)
	_visible_layer_option.item_selected.connect(
		func(index: int) -> void:
			match index:
				1:
					visible_layer_requested.emit(&"ground")
				2:
					visible_layer_requested.emit(&"overlay")
				_:
					visible_layer_requested.emit(&"all")
	)
	_center_view_button.pressed.connect(func() -> void: center_view_requested.emit())
	_popout_preview_button.toggled.connect(
		func(open_requested: bool) -> void: popout_preview_toggled.emit(open_requested)
	)
	_playtest_button.pressed.connect(func() -> void: playtest_requested.emit())


func get_room_canvas() -> Control:
	return _room_canvas


func get_palette_dock() -> Control:
	return _palette_dock


func get_properties_dock() -> ScrollContainer:
	return _properties_dock


func get_preview_dock() -> Control:
	return _preview_dock


func set_mode(mode: int) -> void:
	_place_button.button_pressed = mode == 0
	_select_button.button_pressed = mode == 1
	_erase_button.button_pressed = mode == 2
	_rotate_button.button_pressed = mode == 3
	_box_paint_check.visible = mode == 0
	_box_paint_check.disabled = mode != 0
	_placement_rotation_label.visible = mode == 0
	_placement_rotation_option.visible = mode == 0
	_placement_rotation_option.disabled = mode != 0


func set_box_paint_enabled(enabled: bool) -> void:
	_box_paint_check.set_pressed_no_signal(enabled)


func set_placement_rotation_option_steps(rotation_steps: int) -> void:
	var s := posmod(rotation_steps, 4)
	if _placement_rotation_option.selected == s:
		return
	_placement_rotation_option.set_block_signals(true)
	_placement_rotation_option.select(s)
	_placement_rotation_option.set_block_signals(false)


func set_popout_preview_open(open_requested: bool) -> void:
	_popout_preview_button.set_pressed_no_signal(open_requested)


func set_visible_layer_filter(layer_filter: StringName) -> void:
	match String(layer_filter):
		"ground":
			_visible_layer_option.select(1)
		"overlay":
			_visible_layer_option.select(2)
		_:
			_visible_layer_option.select(0)
