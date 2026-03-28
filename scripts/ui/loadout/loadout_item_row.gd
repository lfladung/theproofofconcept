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
	text = "[%s]" % display_name if equipped else display_name
	self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	_apply_row_styles(equipped)


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


func _apply_row_styles(equipped: bool) -> void:
	if equipped:
		add_theme_stylebox_override("normal", _build_stylebox(Color(0.22, 0.36, 0.24, 0.96), Color(0.54, 0.82, 0.58, 1.0)))
		add_theme_stylebox_override("hover", _build_stylebox(Color(0.25, 0.40, 0.27, 0.98), Color(0.62, 0.90, 0.66, 1.0)))
		add_theme_stylebox_override("pressed", _build_stylebox(Color(0.18, 0.31, 0.20, 1.0), Color(0.50, 0.78, 0.54, 1.0)))
		add_theme_stylebox_override("focus", _build_stylebox(Color(0.25, 0.40, 0.27, 0.98), Color(0.70, 0.95, 0.74, 1.0), 2))
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")
		remove_theme_stylebox_override("pressed")
		remove_theme_stylebox_override("focus")


func _build_stylebox(fill_color: Color, border_color: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style
