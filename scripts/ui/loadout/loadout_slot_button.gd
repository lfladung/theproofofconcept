extends Button

signal unequip_requested(slot_id: StringName)
signal tooltip_requested(tooltip_data: Dictionary)
signal tooltip_cleared()

var _slot_id: StringName = &""
var _has_item := false
var _tooltip_data: Dictionary = {}


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func configure(
	slot_id: StringName,
	slot_label: String,
	equipped_item_definition: Dictionary,
	tooltip_data: Dictionary
) -> void:
	_slot_id = slot_id
	_tooltip_data = tooltip_data.duplicate(true)
	_has_item = not equipped_item_definition.is_empty()
	var item_name := String(equipped_item_definition.get("display_name", "Empty"))
	text = "%s\n%s" % [slot_label, item_name]
	disabled = false
	self_modulate = Color(1.0, 1.0, 1.0, 1.0) if _has_item else Color(0.8, 0.8, 0.8, 1.0)


func _on_pressed() -> void:
	if not _has_item:
		return
	unequip_requested.emit(_slot_id)


func _on_mouse_entered() -> void:
	if _tooltip_data.is_empty():
		return
	tooltip_requested.emit(_tooltip_data)


func _on_mouse_exited() -> void:
	tooltip_cleared.emit()
