extends Control

const LoadoutConstants = preload("res://scripts/loadout/loadout_constants.gd")
const CATEGORY_SECTION_SCENE := preload("res://scenes/ui/loadout/loadout_category_section.tscn")

@onready var _open_button: Button = $OpenButton
@onready var _panel_root: PanelContainer = $LoadoutPanel
@onready var _owned_scroll: ScrollContainer = $LoadoutPanel/LoadoutMargin/LoadoutVBox/OwnedScroll
@onready var _category_list: VBoxContainer = $LoadoutPanel/LoadoutMargin/LoadoutVBox/OwnedScroll/CategoryList
@onready var _status_label: Label = $LoadoutPanel/LoadoutMargin/LoadoutVBox/StatusLabel
@onready var _tooltip_panel: PanelContainer = $TooltipPanel
@onready var _tooltip_label: Label = $TooltipPanel/TooltipMargin/TooltipLabel

var _player: CharacterBody2D
var _room_type_provider: Callable = Callable()
var _category_expanded_by_slot: Dictionary = {}
var _panel_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open_button.pressed.connect(_toggle_panel)
	_panel_root.visible = false
	_tooltip_panel.visible = false
	_status_label.text = ""
	for slot_id in LoadoutConstants.SLOT_ORDER:
		_category_expanded_by_slot[slot_id] = true


func bind_player(player: CharacterBody2D, room_type_provider: Callable) -> void:
	if _player != null:
		if _player.has_signal(&"loadout_changed") and _player.is_connected(&"loadout_changed", _on_loadout_changed):
			_player.disconnect(&"loadout_changed", _on_loadout_changed)
		if _player.has_signal(&"loadout_request_failed") and _player.is_connected(
			&"loadout_request_failed",
			_on_loadout_request_failed
		):
			_player.disconnect(&"loadout_request_failed", _on_loadout_request_failed)
		if _player.has_method(&"set_menu_input_blocked"):
			_player.call(&"set_menu_input_blocked", false)
	_player = player
	_room_type_provider = room_type_provider
	if _player != null:
		if _player.has_signal(&"loadout_changed") and not _player.is_connected(&"loadout_changed", _on_loadout_changed):
			_player.connect(&"loadout_changed", _on_loadout_changed)
		if _player.has_signal(&"loadout_request_failed") and not _player.is_connected(
			&"loadout_request_failed",
			_on_loadout_request_failed
		):
			_player.connect(&"loadout_request_failed", _on_loadout_request_failed)
	_sync_player_input_block_state()
	_refresh_from_player()


func _process(_delta: float) -> void:
	var can_open := _can_open_loadout()
	_open_button.visible = can_open or _panel_open
	if _panel_open and not can_open:
		_close_panel()
	if _tooltip_panel.visible:
		_update_tooltip_position()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"loadout_toggle"):
		if _panel_open or _can_open_loadout():
			_toggle_panel()
			get_viewport().set_input_as_handled()


func _toggle_panel() -> void:
	if _panel_open:
		_close_panel()
	else:
		_open_panel()


func _open_panel() -> void:
	if not _can_open_loadout():
		return
	_panel_open = true
	_panel_root.visible = true
	_status_label.text = ""
	_sync_player_input_block_state()
	_refresh_from_player()


func _close_panel() -> void:
	_panel_open = false
	_panel_root.visible = false
	_tooltip_panel.visible = false
	_sync_player_input_block_state()


func _can_open_loadout() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if not _room_type_provider.is_valid():
		return false
	var room_type_v: Variant = _room_type_provider.call(_player.global_position)
	return String(room_type_v) == "safe"


func _refresh_from_player() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method(&"get_loadout_view_model"):
		_clear_dynamic_ui()
		return
	var preserve_scroll := _panel_open and _category_list.get_child_count() > 0
	var previous_scroll := _owned_scroll.scroll_vertical if preserve_scroll else 0
	var snapshot_v: Variant = _player.call(&"get_loadout_view_model")
	if snapshot_v is not Dictionary:
		_clear_dynamic_ui()
		return
	_rebuild_from_snapshot(snapshot_v as Dictionary)
	if preserve_scroll:
		call_deferred("_restore_scroll_position", previous_scroll)


func _clear_dynamic_ui() -> void:
	for child in _category_list.get_children():
		child.queue_free()


func _rebuild_from_snapshot(snapshot: Dictionary) -> void:
	_clear_dynamic_ui()
	var equipped_slots: Dictionary = snapshot.get("equipped_slots", {}) as Dictionary
	var definitions_by_id: Dictionary = snapshot.get("item_definitions", {}) as Dictionary
	var owned_items_by_slot: Dictionary = snapshot.get("owned_items_by_slot", {}) as Dictionary
	for slot_id in LoadoutConstants.SLOT_ORDER:
		var equipped_item_id := String(equipped_slots.get(String(slot_id), ""))
		var category_rows: Array = []
		var owned_item_ids: Array = owned_items_by_slot.get(String(slot_id), []) as Array
		for item_id_v in owned_item_ids:
			var item_id := String(item_id_v)
			var item_definition: Dictionary = definitions_by_id.get(item_id, {}) as Dictionary
			category_rows.append(
				{
					"item_definition": item_definition,
					"tooltip_data": _make_item_tooltip(item_definition),
					"equipped": item_id == equipped_item_id,
				}
			)
		var category_section := CATEGORY_SECTION_SCENE.instantiate()
		if category_section == null:
			continue
		_category_list.add_child(category_section)
		category_section.call(
			&"configure",
			slot_id,
			LoadoutConstants.slot_display_name(slot_id),
			category_rows,
			bool(_category_expanded_by_slot.get(slot_id, true))
		)
		if category_section.has_signal(&"equip_requested"):
			category_section.connect(&"equip_requested", _on_item_equip_requested)
		if category_section.has_signal(&"tooltip_requested"):
			category_section.connect(&"tooltip_requested", _show_tooltip)
		if category_section.has_signal(&"tooltip_cleared"):
			category_section.connect(&"tooltip_cleared", _hide_tooltip)
		if category_section.has_signal(&"expansion_changed"):
			category_section.connect(&"expansion_changed", _on_category_expansion_changed)


func _on_item_equip_requested(item_id: StringName) -> void:
	if _player != null and _player.has_method(&"request_equip_item"):
		_player.call(&"request_equip_item", item_id)


func _on_loadout_changed(_snapshot: Dictionary) -> void:
	_status_label.text = ""
	_refresh_from_player()


func _on_loadout_request_failed(message: String) -> void:
	_status_label.text = message


func _on_category_expansion_changed(slot_id: StringName, expanded: bool) -> void:
	_category_expanded_by_slot[slot_id] = expanded


func _make_item_tooltip(item_definition: Dictionary) -> Dictionary:
	var title := String(item_definition.get("display_name", "Item"))
	var slot_id := StringName(String(item_definition.get("slot_id", "")))
	var stat_lines := LoadoutConstants.format_stat_modifier_lines(
		item_definition.get("stat_modifiers", {}) as Dictionary
	)
	var body_lines := PackedStringArray(
		[
			"Slot: %s" % LoadoutConstants.slot_display_name(slot_id),
		]
	)
	for line in stat_lines:
		body_lines.append(line)
	var description := String(item_definition.get("description", ""))
	if not description.is_empty():
		body_lines.append(description)
	return {
		"title": title,
		"body_lines": body_lines,
	}


func _show_tooltip(tooltip_data: Dictionary) -> void:
	var title := String(tooltip_data.get("title", ""))
	var body_lines: PackedStringArray = tooltip_data.get("body_lines", PackedStringArray()) as PackedStringArray
	var lines: PackedStringArray = PackedStringArray()
	if not title.is_empty():
		lines.append(title)
	if not body_lines.is_empty():
		lines.append("")
		for line in body_lines:
			lines.append(String(line))
	_tooltip_label.text = "\n".join(lines)
	_tooltip_panel.visible = true
	_update_tooltip_position()


func _hide_tooltip() -> void:
	_tooltip_panel.visible = false


func _update_tooltip_position() -> void:
	var viewport_rect := get_viewport_rect()
	var mouse_pos := get_viewport().get_mouse_position()
	var panel_size := _tooltip_panel.size
	var target := mouse_pos + Vector2(18.0, 18.0)
	target.x = minf(target.x, viewport_rect.size.x - panel_size.x - 10.0)
	target.y = minf(target.y, viewport_rect.size.y - panel_size.y - 10.0)
	_tooltip_panel.position = target


func _sync_player_input_block_state() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method(&"set_menu_input_blocked"):
		_player.call(&"set_menu_input_blocked", _panel_open)


func _restore_scroll_position(scroll_value: int) -> void:
	if _owned_scroll == null or not is_instance_valid(_owned_scroll):
		return
	_owned_scroll.scroll_vertical = maxi(0, scroll_value)


func _exit_tree() -> void:
	_panel_open = false
	_sync_player_input_block_state()
