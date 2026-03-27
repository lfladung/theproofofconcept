extends VBoxContainer

signal equip_requested(item_id: StringName)
signal tooltip_requested(tooltip_data: Dictionary)
signal tooltip_cleared()
signal expansion_changed(slot_id: StringName, expanded: bool)

const ITEM_ROW_SCENE := preload("res://scenes/ui/loadout/loadout_item_row.tscn")

@onready var _header_button: Button = $HeaderButton
@onready var _items_box: VBoxContainer = $ItemsBox

var _slot_id: StringName = &""
var _expanded := true
var _title := ""


func _ready() -> void:
	_header_button.pressed.connect(_on_header_pressed)


func configure(slot_id: StringName, title: String, item_rows: Array, expanded: bool) -> void:
	_slot_id = slot_id
	_title = title
	_expanded = expanded
	_header_button.text = "%s %s" % ["▼" if _expanded else "▶", _title]
	_clear_items()
	for row_data_v in item_rows:
		if row_data_v is not Dictionary:
			continue
		var row_data := row_data_v as Dictionary
		var item_definition: Dictionary = row_data.get("item_definition", {}) as Dictionary
		var tooltip_data: Dictionary = row_data.get("tooltip_data", {}) as Dictionary
		var equipped := bool(row_data.get("equipped", false))
		var row := ITEM_ROW_SCENE.instantiate()
		if row == null:
			continue
		_items_box.add_child(row)
		row.call(&"configure", item_definition, equipped, tooltip_data)
		if row.has_signal(&"equip_requested"):
			row.connect(&"equip_requested", _on_item_equip_requested)
		if row.has_signal(&"tooltip_requested"):
			row.connect(&"tooltip_requested", _on_item_tooltip_requested)
		if row.has_signal(&"tooltip_cleared"):
			row.connect(&"tooltip_cleared", _on_item_tooltip_cleared)
	_items_box.visible = _expanded


func _clear_items() -> void:
	for child in _items_box.get_children():
		child.queue_free()


func _on_header_pressed() -> void:
	_expanded = not _expanded
	_items_box.visible = _expanded
	_header_button.text = "%s %s" % ["▼" if _expanded else "▶", _title]
	expansion_changed.emit(_slot_id, _expanded)


func _on_item_equip_requested(item_id: StringName) -> void:
	equip_requested.emit(item_id)


func _on_item_tooltip_requested(tooltip_data: Dictionary) -> void:
	tooltip_requested.emit(tooltip_data)


func _on_item_tooltip_cleared() -> void:
	tooltip_cleared.emit()
