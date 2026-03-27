extends Button

signal equip_requested(item_id: StringName)
signal tooltip_requested(tooltip_data: Dictionary)
signal tooltip_cleared()

var _item_id: StringName = &""
var _tooltip_data: Dictionary = {}


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func configure(item_definition: Dictionary, equipped: bool, tooltip_data: Dictionary) -> void:
	_item_id = StringName(String(item_definition.get("item_id", "")))
	_tooltip_data = tooltip_data.duplicate(true)
	var display_name := String(item_definition.get("display_name", "Unknown Item"))
	text = "%s%s" % ["[Equipped] " if equipped else "", display_name]
	self_modulate = Color(0.92, 1.0, 0.92, 1.0) if equipped else Color(1.0, 1.0, 1.0, 1.0)


func _on_pressed() -> void:
	if _item_id == &"":
		return
	equip_requested.emit(_item_id)


func _on_mouse_entered() -> void:
	if _tooltip_data.is_empty():
		return
	tooltip_requested.emit(_tooltip_data)


func _on_mouse_exited() -> void:
	tooltip_cleared.emit()
