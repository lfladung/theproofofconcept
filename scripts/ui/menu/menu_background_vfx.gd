@tool
extends Control
class_name MenuBackgroundVfx

# Full-screen menu background host. This keeps the pit art in 2D while the pillar
# itself renders in a transparent 3D SubViewport above it.
const PILLAR_MENU_SCENE := preload("res://scenes/ui/menu/pillar_menu_scene.tscn")

@export var effects_enabled := false:
	set(value):
		effects_enabled = value
		_apply_effects_enabled()

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
	_apply_viewport_settings()
	_apply_effects_enabled()
	_ensure_menu_scene_instance()
	_apply_pit_settings()
	_update_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()
		call_deferred(&"_update_layout")


func set_display_transition_active(active: bool) -> void:
	visible = not active
	if _pillar_viewport == null:
		return
	if not effects_enabled:
		_pillar_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_pillar_viewport.render_target_update_mode = (
		SubViewport.UPDATE_DISABLED if active else SubViewport.UPDATE_ALWAYS
	)
	if not active:
		_apply_viewport_settings()
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
	if _pillar_viewport == null or not effects_enabled:
		return
	if _pillar_viewport_container != null and _pillar_viewport_container.stretch:
		# Match the container's size explicitly so transparent resize frames do not
		# sample stale render-target pixels before the stretch pass catches up.
		var container_size := _safe_viewport_size(_pillar_viewport_container.size)
		if _pillar_viewport.size != container_size:
			_pillar_viewport.size = container_size
		return
	var scaled_size := size * viewport_resolution_scale
	var next_size := _safe_viewport_size(scaled_size)
	if _pillar_viewport.size != next_size:
		_pillar_viewport.size = next_size


func _apply_viewport_settings() -> void:
	if _pillar_viewport == null:
		return
	_pillar_viewport.transparent_bg = true
	_pillar_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_pillar_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if effects_enabled else SubViewport.UPDATE_DISABLED
	)


func _apply_effects_enabled() -> void:
	if _pillar_viewport_container != null:
		_pillar_viewport_container.visible = effects_enabled
	if _pillar_viewport != null:
		_pillar_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if effects_enabled else SubViewport.UPDATE_DISABLED
		)
	if effects_enabled:
		_ensure_menu_scene_instance()
		_update_layout()


func _safe_viewport_size(source_size: Vector2) -> Vector2i:
	return Vector2i(maxi(roundi(source_size.x), 1), maxi(roundi(source_size.y), 1))


func _ensure_menu_scene_instance() -> void:
	if _pillar_viewport == null or not effects_enabled:
		return
	if _pillar_viewport.get_node_or_null("MenuScene") != null:
		return
	var menu_scene := PILLAR_MENU_SCENE.instantiate()
	menu_scene.name = "MenuScene"
	_pillar_viewport.add_child(menu_scene)
