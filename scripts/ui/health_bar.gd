extends Control

## Infusion dots (one per pickup), then blue stamina, then green health.

const IC := preload("res://scripts/infusion/infusion_constants.gd")

@onready var _infusion_row: HBoxContainer = $Bars/InfusionRow
@onready var _stamina_inner: Control = $Bars/StaminaFrame/Inner
@onready var _stamina_fill: ColorRect = $Bars/StaminaFrame/Inner/StaminaFill
@onready var _health_inner: Control = $Bars/HealthFrame/Inner
@onready var _health_fill: ColorRect = $Bars/HealthFrame/Inner/HealthFill

var _health_ratio := 1.0
var _stamina_ratio := 1.0
var _bound_player: Node
var _bound_player_is_downed := false
var _bound_infusion_manager: InfusionManager = null


func _ready() -> void:
	_stamina_inner.resized.connect(_apply_fill_widths)
	_health_inner.resized.connect(_apply_fill_widths)
	_try_bind_local_player()
	call_deferred(&"_apply_fill_widths")


func _process(_delta: float) -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		_try_bind_local_player()
		return
	if multiplayer.multiplayer_peer != null:
		if _bound_player is CharacterBody2D and not (_bound_player as CharacterBody2D).is_multiplayer_authority():
			_try_bind_local_player()
		elif _bound_player is not CharacterBody2D:
			_try_bind_local_player()


func _disconnect_bound_player_signals() -> void:
	if _bound_player == null:
		return
	if _bound_player.has_signal(&"health_changed") and _bound_player.health_changed.is_connected(
		_on_player_health_changed
	):
		_bound_player.health_changed.disconnect(_on_player_health_changed)
	if _bound_player.has_signal(&"stamina_changed") and _bound_player.stamina_changed.is_connected(
		_on_player_stamina_changed
	):
		_bound_player.stamina_changed.disconnect(_on_player_stamina_changed)
	if (
		_bound_player.has_signal(&"downed_state_changed")
		and _bound_player.downed_state_changed.is_connected(_on_player_downed_state_changed)
	):
		_bound_player.downed_state_changed.disconnect(_on_player_downed_state_changed)
	_disconnect_infusion_manager_signals()


func _disconnect_infusion_manager_signals() -> void:
	if _bound_infusion_manager != null and is_instance_valid(_bound_infusion_manager):
		if _bound_infusion_manager.infusion_added.is_connected(_on_infusion_manager_ui_refresh_added):
			_bound_infusion_manager.infusion_added.disconnect(_on_infusion_manager_ui_refresh_added)
		if _bound_infusion_manager.infusion_removed.is_connected(_on_infusion_manager_ui_refresh_removed):
			_bound_infusion_manager.infusion_removed.disconnect(_on_infusion_manager_ui_refresh_removed)
	_bound_infusion_manager = null


func _on_infusion_manager_ui_refresh_added(
	_instance_id: int, _pillar_id: StringName, _stack: float, _source_kind: int
) -> void:
	## Defer so layout runs outside combat/damage stack (avoids stale HBox children from `queue_free`).
	call_deferred(&"_refresh_infusion_display")


func _on_infusion_manager_ui_refresh_removed(
	_instance_id: int, _pillar_id: StringName, _stack: float
) -> void:
	call_deferred(&"_refresh_infusion_display")


func _try_bind_local_player() -> void:
	var p := _find_local_player()
	if p == null:
		if _bound_player != null:
			_disconnect_bound_player_signals()
			_bound_player = null
			_refresh_infusion_display()
		return
	if _bound_player == p and is_instance_valid(_bound_player):
		_refresh_from_bound_player()
		return
	_disconnect_bound_player_signals()
	_bound_player = p
	if _bound_player.has_signal(&"health_changed") and not _bound_player.health_changed.is_connected(
		_on_player_health_changed
	):
		_bound_player.health_changed.connect(_on_player_health_changed)
	if _bound_player.has_signal(&"stamina_changed") and not _bound_player.stamina_changed.is_connected(
		_on_player_stamina_changed
	):
		_bound_player.stamina_changed.connect(_on_player_stamina_changed)
	if _bound_player.has_signal(&"downed_state_changed") and not _bound_player.downed_state_changed.is_connected(
		_on_player_downed_state_changed
	):
		_bound_player.downed_state_changed.connect(_on_player_downed_state_changed)
	_bind_infusion_manager_signals()
	_refresh_from_bound_player()


func _refresh_from_bound_player() -> void:
	var health_max_v: Variant = _bound_player.get(&"max_health") if _bound_player != null else 100
	var health_cur_v: Variant = _bound_player.get(&"health") if _bound_player != null else health_max_v
	var stamina_max_v: Variant = _bound_player.get(&"max_stamina") if _bound_player != null else 100.0
	var stamina_cur_v: Variant = _bound_player.get(&"stamina") if _bound_player != null else stamina_max_v
	var health_max_i := int(health_max_v) if health_max_v != null else 100
	var health_cur_i := int(health_cur_v) if health_cur_v != null else health_max_i
	var stamina_max_f := float(stamina_max_v) if stamina_max_v != null else 100.0
	var stamina_cur_f := float(stamina_cur_v) if stamina_cur_v != null else stamina_max_f
	_bound_player_is_downed = false
	if _bound_player != null and _bound_player.has_method(&"is_downed"):
		_bound_player_is_downed = bool(_bound_player.call(&"is_downed"))
	_on_player_health_changed(health_cur_i, health_max_i)
	_on_player_stamina_changed(stamina_cur_f, stamina_max_f)
	_refresh_infusion_display()


func _bind_infusion_manager_signals() -> void:
	_disconnect_infusion_manager_signals()
	if _bound_player == null:
		return
	var im := _bound_player.get_node_or_null(^"InfusionManager") as InfusionManager
	if im == null:
		_refresh_infusion_display()
		return
	_bound_infusion_manager = im
	im.infusion_added.connect(_on_infusion_manager_ui_refresh_added)
	im.infusion_removed.connect(_on_infusion_manager_ui_refresh_removed)


func _color_for_infusion_pillar(pillar_id: Variant) -> Color:
	return IC.ui_pillar_dot_color(IC.coerce_pillar_id(pillar_id))


func _make_infusion_dot(pillar_id: Variant) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(14, 14)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = _color_for_infusion_pillar(pillar_id)
	sb.corner_radius_top_left = 32
	sb.corner_radius_top_right = 32
	sb.corner_radius_bottom_right = 32
	sb.corner_radius_bottom_left = 32
	sb.set_content_margin_all(0)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.4)
	p.add_theme_stylebox_override(&"panel", sb)
	return p


func _refresh_infusion_display() -> void:
	if _infusion_row == null:
		return
	for c in _infusion_row.get_children():
		_infusion_row.remove_child(c)
		c.queue_free()
	if _bound_player == null or not is_instance_valid(_bound_player):
		_infusion_row.visible = false
		_infusion_row.custom_minimum_size = Vector2(0, 0)
		return
	var im := _bound_player.get_node_or_null(^"InfusionManager") as InfusionManager
	if im == null:
		_infusion_row.visible = false
		_infusion_row.custom_minimum_size = Vector2(0, 0)
		return
	var entries: Array[Dictionary] = im.list_infusions_for_ui()
	if entries.is_empty():
		_infusion_row.visible = false
		_infusion_row.custom_minimum_size = Vector2(0, 0)
		return
	_infusion_row.visible = true
	_infusion_row.custom_minimum_size = Vector2(0, 18)
	for e in entries:
		if e is Dictionary:
			_infusion_row.add_child(_make_infusion_dot((e as Dictionary).get("pillar_id", &"")))


func _find_local_player() -> Node:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return null
	if multiplayer.multiplayer_peer == null:
		return players[0]
	for node in players:
		if node is CharacterBody2D and (node as CharacterBody2D).is_multiplayer_authority():
			return node
	return null


func _on_player_health_changed(current: int, maximum: int) -> void:
	var m := maxi(1, maximum)
	_health_ratio = clampf(float(current) / float(m), 0.0, 1.0)
	if _bound_player_is_downed:
		_health_ratio = 0.0
	_apply_fill_widths()


func _on_player_stamina_changed(current: float, maximum: float) -> void:
	var m := maxf(1.0, maximum)
	_stamina_ratio = clampf(current / m, 0.0, 1.0)
	_apply_fill_widths()


func _on_player_downed_state_changed(is_downed: bool) -> void:
	_bound_player_is_downed = is_downed
	_refresh_from_bound_player()


func _apply_fill_width(fill: ColorRect, inner: Control, ratio: float) -> void:
	var w := inner.size.x
	var h := inner.size.y
	if w < 1.0 or h < 1.0:
		return
	fill.position = Vector2.ZERO
	fill.size = Vector2(w * ratio, h)


func _apply_fill_widths() -> void:
	_apply_fill_width(_stamina_fill, _stamina_inner, _stamina_ratio)
	_apply_fill_width(_health_fill, _health_inner, _health_ratio)
