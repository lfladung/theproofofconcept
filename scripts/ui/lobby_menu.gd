extends Control
class_name LobbyMenu

@onready var _main_menu_vbox: VBoxContainer = $Center/Margin/VBox/MainMenuVBox
@onready var _multiplayer_vbox: VBoxContainer = $Center/Margin/VBox/MultiplayerVBox
@onready var _options_vbox: VBoxContainer = $Center/Margin/VBox/OptionsVBox
@onready var _singleplayer_button: Button = $Center/Margin/VBox/MainMenuVBox/SingleplayerButton
@onready var _multiplayer_button: Button = $Center/Margin/VBox/MainMenuVBox/MultiplayerButton
@onready var _inventory_button: Button = $Center/Margin/VBox/MainMenuVBox/InventoryButton
@onready var _options_button: Button = $Center/Margin/VBox/MainMenuVBox/OptionsButton
@onready var _exit_button: Button = $Center/Margin/VBox/MainMenuVBox/ExitButton
@onready var _options_back_button: Button = $Center/Margin/VBox/OptionsVBox/OptionsBackButton
@onready var _control_scheme_option: OptionButton = (
	$Center/Margin/VBox/OptionsVBox/TabContainer/Controls/ControlSchemeOption
)
@onready var _control_scheme_hint: Label = (
	$Center/Margin/VBox/OptionsVBox/TabContainer/Controls/ControlSchemeHint
)
@onready var _back_button: Button = $Center/Margin/VBox/MultiplayerVBox/ButtonRow/BackButton
@onready var _session_code_input: LineEdit = $Center/Margin/VBox/MultiplayerVBox/CodeRow/SessionCodeInput
@onready var _join_code_button: Button = $Center/Margin/VBox/MultiplayerVBox/CodeRow/JoinCodeButton
@onready var _host_button: Button = $Center/Margin/VBox/MultiplayerVBox/ButtonRow/HostButton
@onready var _start_run_button: Button = $Center/Margin/VBox/MultiplayerVBox/ButtonRow/StartRunButton
@onready var _ready_button: Button = $Center/Margin/VBox/MultiplayerVBox/ButtonRow/ReadyButton
@onready var _disconnect_button: Button = $Center/Margin/VBox/MultiplayerVBox/ButtonRow/DisconnectButton
@onready var _status_label: Label = $Center/Margin/VBox/MultiplayerVBox/StatusLabel
@onready var _lobby_code_label: LineEdit = $Center/Margin/VBox/MultiplayerVBox/LobbyCodeLabel
@onready var _error_label: Label = $Center/Margin/VBox/MultiplayerVBox/ErrorLabel
@onready var _peers_list: ItemList = $Center/Margin/VBox/MultiplayerVBox/PeersList

const _InventoryScreenScene = preload("res://scripts/ui/inventory/inventory_screen.gd")

var _showing_multiplayer_menu: bool = false
var _showing_options: bool = false
var _showing_inventory: bool = false
var _inventory_screen: Control = null


func _ready() -> void:
	_error_label.text = ""

	_control_scheme_option.add_item("Mouse")
	_control_scheme_option.add_item("WASD + Mouse")
	_control_scheme_option.item_selected.connect(_on_control_scheme_selected)

	_singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	_multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_inventory_button.pressed.connect(_on_inventory_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)

	# Build inventory screen (full-screen overlay, not inside CenterContainer).
	_inventory_screen = Control.new()
	_inventory_screen.set_script(_InventoryScreenScene)
	_inventory_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_screen.visible = false
	add_child(_inventory_screen)
	_inventory_screen.back_pressed.connect(_on_inventory_back_pressed)
	_options_back_button.pressed.connect(_on_options_back_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_host_button.pressed.connect(_on_host_pressed)
	_join_code_button.pressed.connect(_on_join_code_pressed)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_run_button.pressed.connect(_on_start_run_pressed)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)

	NetworkSession.state_changed.connect(_on_session_state_changed)
	NetworkSession.role_changed.connect(_on_session_role_changed)
	NetworkSession.peer_slot_map_changed.connect(_on_peer_slot_map_changed)
	NetworkSession.transport_error.connect(_on_transport_error)
	NetworkSession.registry_lookup_result.connect(_on_registry_lookup_result)
	NetworkSession.session_code_changed.connect(_on_session_code_changed)
	NetworkSession.lobby_ready_changed.connect(_on_lobby_ready_changed)

	_refresh_ui()
	_rebuild_peer_list(NetworkSession.get_peer_slot_map())
	_set_showing_multiplayer_menu(false)
	_set_showing_options_menu(false)
	_sync_control_scheme_option()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo or k.keycode != KEY_ESCAPE:
		return
	if _showing_inventory:
		# Let inventory_screen handle its own ESC (sub-screen back nav).
		# Only close the overlay from here if inventory emits back_pressed.
		return
	elif _showing_options:
		_on_options_back_pressed()
		get_viewport().set_input_as_handled()
	elif _showing_multiplayer_menu:
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _refresh_root_menu_visibility() -> void:
	_options_vbox.visible = _showing_options and not _showing_inventory
	_multiplayer_vbox.visible = _showing_multiplayer_menu and not _showing_options and not _showing_inventory
	_main_menu_vbox.visible = not _showing_options and not _showing_multiplayer_menu and not _showing_inventory
	if _inventory_screen != null:
		_inventory_screen.visible = _showing_inventory
	# Hide the center container entirely when inventory is up (it needs full screen).
	$Center.visible = not _showing_inventory


func _set_showing_multiplayer_menu(show_multiplayer: bool) -> void:
	if show_multiplayer:
		_showing_options = false
	_showing_multiplayer_menu = show_multiplayer
	_refresh_root_menu_visibility()


func _set_showing_options_menu(show_options: bool) -> void:
	if show_options:
		_showing_multiplayer_menu = false
	_showing_options = show_options
	_refresh_root_menu_visibility()
	if show_options:
		_sync_control_scheme_option()


func _sync_control_scheme_option() -> void:
	_control_scheme_option.set_block_signals(true)
	_control_scheme_option.select(1 if GameSettings.is_wasd_mouse_scheme() else 0)
	_control_scheme_option.set_block_signals(false)
	_refresh_control_scheme_hint()


func _refresh_control_scheme_hint() -> void:
	if GameSettings.is_wasd_mouse_scheme():
		_control_scheme_hint.text = (
			"WASD move · mouse aim · LMB attack · RMB block · Q bomb · Tab weapon · Space dash"
		)
	else:
		_control_scheme_hint.text = (
			"Hold LMB to move toward cursor · RMB attack · Q sword · Z block · F bomb · Tab weapon · Space dash"
		)


func _on_control_scheme_selected(index: int) -> void:
	var scheme := (
		GameSettings.ControlScheme.WASD_MOUSE
		if index == 1
		else GameSettings.ControlScheme.MOUSE
	)
	GameSettings.set_control_scheme(scheme)
	_refresh_control_scheme_hint()


func _on_inventory_pressed() -> void:
	_error_label.text = ""
	_showing_inventory = true
	_refresh_root_menu_visibility()


func _on_inventory_back_pressed() -> void:
	_showing_inventory = false
	_refresh_root_menu_visibility()


func _on_options_pressed() -> void:
	_error_label.text = ""
	_set_showing_options_menu(true)


func _on_options_back_pressed() -> void:
	_error_label.text = ""
	_set_showing_options_menu(false)


func _on_singleplayer_pressed() -> void:
	_error_label.text = ""
	if not NetworkSession.start_offline_run():
		_refresh_ui()


func _on_multiplayer_pressed() -> void:
	_error_label.text = ""
	_set_showing_multiplayer_menu(true)


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	_error_label.text = ""
	_set_showing_multiplayer_menu(false)


func _on_host_pressed() -> void:
	_error_label.text = ""
	if not NetworkSession.request_lobby_from_registry():
		_refresh_ui()
	_refresh_ui()


func _on_join_code_pressed() -> void:
	_error_label.text = ""
	var code := _session_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_error_label.text = "Enter a session code first."
		return
	if not NetworkSession.join_lobby_via_session_code(code):
		_refresh_ui()


func _on_ready_pressed() -> void:
	_error_label.text = ""
	NetworkSession.toggle_local_peer_ready()


func _on_start_run_pressed() -> void:
	_error_label.text = ""
	NetworkSession.request_start_run_from_local_peer()


func _on_disconnect_pressed() -> void:
	_error_label.text = ""
	NetworkSession.disconnect_from_session()


func _on_transport_error(message: String) -> void:
	_error_label.text = message
	_refresh_ui()


func _on_registry_lookup_result(success: bool, message: String) -> void:
	if not success and not message.is_empty():
		_error_label.text = message
	elif success and (
		message.begins_with("Resolving")
		or message.begins_with("Finding")
		or message.begins_with("Found")
		or message.begins_with("Creating")
		or message.begins_with("Created")
	):
		_error_label.text = ""
	_refresh_ui()


func _on_session_state_changed(_previous_state: int, _current_state: int) -> void:
	_refresh_ui()


func _on_session_role_changed(_previous_role: int, _current_role: int) -> void:
	_refresh_ui()


func _on_peer_slot_map_changed(slot_map: Dictionary) -> void:
	_rebuild_peer_list(slot_map)
	_refresh_ui()


func _on_session_code_changed(_session_code: String) -> void:
	_refresh_ui()


func _on_lobby_ready_changed(_ready_map: Dictionary) -> void:
	_rebuild_peer_list(NetworkSession.get_peer_slot_map())
	_refresh_ui()


func _refresh_ui() -> void:
	var has_peer: bool = NetworkSession.has_active_peer()
	var is_lookup_pending: bool = NetworkSession.is_registry_lookup_in_progress()
	var is_create_pending: bool = NetworkSession.is_lobby_create_in_progress()
	var has_pending_request: bool = is_lookup_pending or is_create_pending
	var is_host: bool = (
		NetworkSession.session_role == NetworkSession.SessionRole.HOST
		or NetworkSession.session_role == NetworkSession.SessionRole.DEDICATED_SERVER
	)
	var is_dedicated: bool = NetworkSession.session_role == NetworkSession.SessionRole.DEDICATED_SERVER
	var in_lobby: bool = NetworkSession.session_state == NetworkSession.SessionState.LOBBY
	var is_connecting: bool = NetworkSession.session_state == NetworkSession.SessionState.CONNECTING
	var local_ready := NetworkSession.is_local_peer_ready()
	var ready_map: Dictionary = NetworkSession.get_lobby_ready_map()
	var slot_map: Dictionary = NetworkSession.get_peer_slot_map()
	var ready_total := slot_map.size()
	var ready_count := 0
	for key in slot_map.keys():
		if bool(ready_map.get(int(key), false)):
			ready_count += 1

	_singleplayer_button.disabled = has_peer or has_pending_request
	_multiplayer_button.disabled = has_pending_request
	_host_button.disabled = has_peer or has_pending_request
	_join_code_button.disabled = has_peer or has_pending_request
	_start_run_button.visible = has_peer and in_lobby and not is_dedicated
	_start_run_button.disabled = not (has_peer and in_lobby and not is_dedicated)
	_ready_button.visible = has_peer and in_lobby and not is_dedicated
	_ready_button.disabled = not (has_peer and in_lobby and not is_dedicated)
	_ready_button.text = "Unready" if local_ready else "Ready"
	_disconnect_button.disabled = not has_peer
	_back_button.disabled = has_pending_request
	_session_code_input.editable = not (has_peer or has_pending_request)

	var session_code := NetworkSession.get_session_code().strip_edges().to_upper()
	_lobby_code_label.text = session_code if not session_code.is_empty() else "-"
	if is_host and not session_code.is_empty():
		_session_code_input.text = session_code

	var status := "State: %s | Role: %s" % [NetworkSession.get_state_name(), NetworkSession.get_role_name()]
	if has_peer:
		status += " | Local Peer: %s" % NetworkSession.get_local_peer_id()
	if in_lobby and ready_total > 0:
		status += " | Ready: %s/%s" % [ready_count, ready_total]
	if is_connecting:
		status += " (connecting...)"
	elif is_create_pending:
		status += " (creating lobby...)"
	elif is_lookup_pending:
		status += " (resolving session code...)"
	_status_label.text = status


func _rebuild_peer_list(slot_map: Dictionary) -> void:
	_peers_list.clear()
	var ready_map: Dictionary = NetworkSession.get_lobby_ready_map()
	if not NetworkSession.has_active_peer():
		_peers_list.add_item("Offline. Create a lobby or join by session code.")
		return
	if slot_map.is_empty():
		_peers_list.add_item("Connected. Waiting for peers...")
		return
	var peer_ids := slot_map.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var peer_id_int := int(peer_id)
		var slot := int(slot_map[peer_id])
		var tag := ""
		if peer_id_int == NetworkSession.get_local_peer_id():
			tag = " (you)"
		var ready_text := "READY" if bool(ready_map.get(peer_id_int, false)) else "NOT READY"
		_peers_list.add_item("Peer %s -> Slot %s | %s%s" % [peer_id_int, slot, ready_text, tag])
