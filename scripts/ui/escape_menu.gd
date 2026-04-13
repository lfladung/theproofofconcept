extends Control
class_name EscapeMenu

signal back_to_main_screen_requested
signal return_to_hub_requested
signal visibility_changed_for_input_block(open: bool)

const GameSettingsScript = preload("res://scripts/settings/game_settings.gd")

@onready var _modal_root: Control = $ModalRoot
@onready var _root_menu: VBoxContainer = $ModalRoot/Panel/Margin/Rows/RootMenu
@onready var _options_menu: VBoxContainer = $ModalRoot/Panel/Margin/Rows/OptionsMenu
@onready var _return_to_hub_button: Button = $ModalRoot/Panel/Margin/Rows/RootMenu/ReturnToHubButton
@onready var _back_to_main_button: Button = $ModalRoot/Panel/Margin/Rows/RootMenu/BackToMainButton
@onready var _options_button: Button = $ModalRoot/Panel/Margin/Rows/RootMenu/OptionsButton
@onready var _options_back_button: Button = $ModalRoot/Panel/Margin/Rows/OptionsMenu/OptionsBackButton
@onready var _control_scheme_option: OptionButton = (
	$ModalRoot/Panel/Margin/Rows/OptionsMenu/TabContainer/Controls/ControlSchemeOption
)
@onready var _control_scheme_hint: Label = (
	$ModalRoot/Panel/Margin/Rows/OptionsMenu/TabContainer/Controls/ControlSchemeHint
)
@onready var _resolution_option: OptionButton = (
	$ModalRoot/Panel/Margin/Rows/OptionsMenu/TabContainer/General/ResolutionOption
)
@onready var _window_mode_option: OptionButton = (
	$ModalRoot/Panel/Margin/Rows/OptionsMenu/TabContainer/General/WindowModeOption
)

var _open := false
var _showing_options := false
var _return_to_hub_available := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.visible = false
	_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_options()
	_return_to_hub_button.pressed.connect(_on_return_to_hub_pressed)
	_back_to_main_button.pressed.connect(_on_back_to_main_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_options_back_button.pressed.connect(_on_options_back_pressed)
	_refresh_view()


func open_menu() -> void:
	if _open:
		return
	_open = true
	_showing_options = false
	_refresh_view()
	visibility_changed_for_input_block.emit(true)


func close_menu() -> void:
	if not _open:
		return
	_open = false
	_showing_options = false
	_refresh_view()
	visibility_changed_for_input_block.emit(false)


func is_menu_open() -> bool:
	return _open


func set_return_to_hub_available(available: bool) -> void:
	_return_to_hub_available = available
	_refresh_view()


func handle_escape() -> bool:
	if not _open:
		open_menu()
		return true
	if _showing_options:
		_set_showing_options(false)
		return true
	close_menu()
	return true


func _setup_options() -> void:
	var settings = _settings()
	if settings == null:
		return
	_control_scheme_option.add_item("Mouse")
	_control_scheme_option.add_item("WASD + Mouse")
	_control_scheme_option.item_selected.connect(_on_control_scheme_selected)
	for option in settings.get_resolution_options():
		_resolution_option.add_item(settings.resolution_display_name(option))
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_window_mode_option.add_item(
		settings.window_mode_display_name(GameSettingsScript.WindowMode.WINDOWED)
	)
	_window_mode_option.add_item(
		settings.window_mode_display_name(GameSettingsScript.WindowMode.BORDERED_FULLSCREEN)
	)
	_window_mode_option.add_item(
		settings.window_mode_display_name(GameSettingsScript.WindowMode.FULLSCREEN)
	)
	_window_mode_option.item_selected.connect(_on_window_mode_selected)
	_sync_control_scheme_option()
	_sync_display_options()


func _refresh_view() -> void:
	visible = _open
	_modal_root.visible = _open
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP if _open else Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_STOP if _open else Control.MOUSE_FILTER_IGNORE
	_root_menu.visible = _open and not _showing_options
	_options_menu.visible = _open and _showing_options
	_return_to_hub_button.visible = _return_to_hub_available
	if _open:
		var focus_target := _options_back_button if _showing_options else _root_focus_target()
		if focus_target != null:
			focus_target.grab_focus()


func _set_showing_options(show_options: bool) -> void:
	_showing_options = show_options
	if _showing_options:
		_sync_control_scheme_option()
		_sync_display_options()
	_refresh_view()


func _sync_control_scheme_option() -> void:
	var settings = _settings()
	if settings == null:
		return
	_control_scheme_option.set_block_signals(true)
	_control_scheme_option.select(1 if settings.is_wasd_mouse_scheme() else 0)
	_control_scheme_option.set_block_signals(false)
	_refresh_control_scheme_hint()


func _sync_display_options() -> void:
	var settings = _settings()
	if settings == null:
		return
	_resolution_option.set_block_signals(true)
	var resolution_index: int = settings.get_resolution_index()
	_resolution_option.select(maxi(resolution_index, 0))
	_resolution_option.set_block_signals(false)

	_window_mode_option.set_block_signals(true)
	_window_mode_option.select(settings.get_window_mode_index())
	_window_mode_option.set_block_signals(false)


func _refresh_control_scheme_hint() -> void:
	var settings = _settings()
	if settings != null and settings.is_wasd_mouse_scheme():
		_control_scheme_hint.text = (
			"WASD move · mouse aim · LMB attack · RMB block · Q bomb · Tab weapon · Space dash"
		)
	else:
		_control_scheme_hint.text = (
			"Hold LMB to move toward cursor · RMB attack · Q sword · Z block · F bomb · Tab weapon · Space dash"
		)


func _on_control_scheme_selected(index: int) -> void:
	var settings = _settings()
	if settings == null:
		return
	var scheme := (
		GameSettingsScript.ControlScheme.WASD_MOUSE
		if index == 1
		else GameSettingsScript.ControlScheme.MOUSE
	)
	settings.set_control_scheme(scheme)
	_refresh_control_scheme_hint()


func _on_resolution_selected(index: int) -> void:
	var settings = _settings()
	if settings == null:
		return
	var options: Array[Vector2i] = settings.get_resolution_options()
	if index < 0 or index >= options.size():
		return
	settings.set_resolution(options[index])


func _on_window_mode_selected(index: int) -> void:
	var settings = _settings()
	if settings == null:
		return
	match index:
		int(GameSettingsScript.WindowMode.BORDERED_FULLSCREEN):
			settings.set_window_mode(GameSettingsScript.WindowMode.BORDERED_FULLSCREEN)
		int(GameSettingsScript.WindowMode.FULLSCREEN):
			settings.set_window_mode(GameSettingsScript.WindowMode.FULLSCREEN)
		_:
			settings.set_window_mode(GameSettingsScript.WindowMode.WINDOWED)


func _settings() -> Node:
	return get_node_or_null("/root/GameSettings")


func _root_focus_target() -> Button:
	return _return_to_hub_button if _return_to_hub_available else _back_to_main_button


func _on_return_to_hub_pressed() -> void:
	return_to_hub_requested.emit()


func _on_back_to_main_pressed() -> void:
	back_to_main_screen_requested.emit()


func _on_options_pressed() -> void:
	_set_showing_options(true)


func _on_options_back_pressed() -> void:
	_set_showing_options(false)
