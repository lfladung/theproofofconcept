extends CanvasLayer

var _label: Label
var _dot_time := 0.0
var _dot_step := 0


func _ready() -> void:
	layer = 128
	visible = false

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 32)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_label.text = "Please Wait ."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_label)


func _process(delta: float) -> void:
	if not visible:
		return
	_dot_time += delta
	if _dot_time >= 1.0:
		_dot_time -= 1.0
		_dot_step = (_dot_step + 1) % 3
		match _dot_step:
			0:
				_label.text = "Please Wait ."
			1:
				_label.text = "Please Wait . ."
			2:
				_label.text = "Please Wait . . ."


func show_loading() -> void:
	_dot_time = 0.0
	_dot_step = 0
	_label.text = "Please Wait ."
	visible = true


func hide_loading() -> void:
	visible = false
