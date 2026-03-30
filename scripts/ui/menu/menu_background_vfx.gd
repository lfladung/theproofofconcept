@tool
extends Control
class_name MenuBackgroundVfx

# Full-screen menu background host. This keeps the pit art in 2D while the pillar
# itself renders in a transparent 3D SubViewport above it.
const PILLAR_MENU_SCENE := preload("res://scenes/ui/menu/pillar_menu_scene.tscn")

@export var pit_texture: Texture2D = preload("res://art/menu/theabyss.png"):
	set(value):
		pit_texture = value
		_apply_pit_settings()

@export var pit_modulate: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		pit_modulate = value
		_apply_pit_settings()

@export var pit_scale: Vector2 = Vector2.ONE:
	set(value):
		pit_scale = value
		_apply_pit_settings()

@export var pit_offset: Vector2 = Vector2.ZERO:
	set(value):
		pit_offset = value
		_apply_pit_settings()

@export_range(0.5, 1.0, 0.05) var viewport_resolution_scale: float = 1.0:
	set(value):
		viewport_resolution_scale = clampf(value, 0.5, 1.0)
		_update_layout()

@onready var _pit_background: TextureRect = $PitBackground
@onready var _pillar_viewport_container: SubViewportContainer = $PillarViewportContainer
@onready var _pillar_viewport: SubViewport = $PillarViewportContainer/PillarViewport


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_menu_scene_instance()
	_apply_pit_settings()
	_update_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


func _apply_pit_settings() -> void:
	if _pit_background == null:
		return
	_pit_background.texture = pit_texture
	_pit_background.modulate = pit_modulate
	_pit_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pit_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pit_background.position = pit_offset
	_pit_background.scale = pit_scale


func _update_layout() -> void:
	if _pillar_viewport == null:
		return
	if _pillar_viewport_container != null and _pillar_viewport_container.stretch:
		# With stretch enabled, the container owns the viewport sizing. Keep the
		# export around for future low-res viewport work, but do not resize here.
		return
	var scaled_size := size * viewport_resolution_scale
	scaled_size.x = maxf(scaled_size.x, 1.0)
	scaled_size.y = maxf(scaled_size.y, 1.0)
	_pillar_viewport.size = Vector2i(roundi(scaled_size.x), roundi(scaled_size.y))


func _ensure_menu_scene_instance() -> void:
	if _pillar_viewport == null:
		return
	if _pillar_viewport.get_node_or_null("MenuScene") != null:
		return
	var menu_scene := PILLAR_MENU_SCENE.instantiate()
	menu_scene.name = "MenuScene"
	_pillar_viewport.add_child(menu_scene)
