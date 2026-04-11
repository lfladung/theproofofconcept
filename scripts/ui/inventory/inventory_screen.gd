extends Control

## Full-screen inventory UI shown in the lobby before a run begins.
## Contains 3 sub-screens: Loadout, Gear Detail, Gem Management.
## Built entirely in code (no .tscn) to avoid scene merge conflicts.

const _MetaConstants = preload("res://scripts/meta_progression/meta_progression_constants.gd")
const _GearItemData = preload("res://scripts/meta_progression/gear_item_data.gd")
const _GemItemData = preload("res://scripts/meta_progression/gem_item_data.gd")
const _LoadoutConstants = preload("res://scripts/loadout/loadout_constants.gd")
const _InfusionConstants = preload("res://scripts/infusion/infusion_constants.gd")
const _CATEGORY_SECTION_SCENE = preload("res://scenes/ui/loadout/loadout_category_section.tscn")

signal back_pressed

## Which sub-screen is showing.
enum Screen { LOADOUT, GEAR_DETAIL, GEM_MANAGEMENT }

var _current_screen: Screen = Screen.LOADOUT
var _selected_gear: _GearItemData = null  # For gear detail screen
var _player_id: StringName = &"local"

# Node references (built in _ready).
var _back_button: Button
var _screen_title: Label
var _loadout_container: Control
var _gear_detail_container: Control
var _gem_manage_container: Control

# Loadout screen nodes.
var _gear_category_vbox: VBoxContainer
var _gem_bar_hbox: HBoxContainer
var _materials_vbox: VBoxContainer
var _stats_label: Label
var _loadout_tooltip_panel: PanelContainer
var _loadout_tooltip_label: Label
var _category_expanded_by_slot: Dictionary = {}  # slot_id → bool

# Gear detail nodes.
var _detail_name_label: Label
var _detail_tier_label: Label
var _detail_pillar_label: Label
var _detail_attunement_label: Label
var _detail_familiarity_label: Label
var _detail_promotion_bar: ProgressBar
var _detail_inscriptions_vbox: VBoxContainer
var _detail_sockets_hbox: HBoxContainer
var _detail_evolve_button: Button
var _detail_evolve_status: Label

# Gem management nodes.
var _gem_equipped_hbox: HBoxContainer
var _gem_inventory_grid: GridContainer
var _gem_detail_label: Label


func _ready() -> void:
	_ensure_meta_store_loaded()
	_build_ui()
	_show_screen(Screen.LOADOUT)


func _ensure_meta_store_loaded() -> void:
	var meta_store := get_node_or_null("/root/MetaProgressionStore")
	if meta_store == null:
		return
	if not bool(meta_store.call(&"is_initialized", _player_id)):
		meta_store.call(&"load_local", _player_id)


func _get_meta_store() -> Node:
	return get_node_or_null("/root/MetaProgressionStore")


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Full-screen dark background.
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.95)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main margin.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(root_vbox)

	# Header row.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header)

	_back_button = Button.new()
	_back_button.text = "< Back"
	_back_button.pressed.connect(_on_back_pressed)
	header.add_child(_back_button)

	_screen_title = Label.new()
	_screen_title.text = "Loadout"
	_screen_title.add_theme_font_size_override("font_size", 24)
	_screen_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_screen_title)

	# Separator.
	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	# Screen containers (only one visible at a time).
	_loadout_container = _build_loadout_screen()
	root_vbox.add_child(_loadout_container)

	_gear_detail_container = _build_gear_detail_screen()
	root_vbox.add_child(_gear_detail_container)

	_gem_manage_container = _build_gem_management_screen()
	root_vbox.add_child(_gem_manage_container)


func _build_loadout_screen() -> Control:
	# Initialize expansion state once.
	for slot_id in _LoadoutConstants.SLOT_ORDER:
		if not _category_expanded_by_slot.has(slot_id):
			_category_expanded_by_slot[slot_id] = true

	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 0)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(hbox)

	# Left column: gear categories + gem bar.
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 1.6
	hbox.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_vbox)

	var gear_title := Label.new()
	gear_title.text = "Equipment"
	gear_title.add_theme_font_size_override("font_size", 18)
	left_vbox.add_child(gear_title)

	_gear_category_vbox = VBoxContainer.new()
	_gear_category_vbox.add_theme_constant_override("separation", 4)
	left_vbox.add_child(_gear_category_vbox)

	# Gem bar.
	var gem_title := Label.new()
	gem_title.text = "Gems"
	gem_title.add_theme_font_size_override("font_size", 18)
	left_vbox.add_child(gem_title)

	_gem_bar_hbox = HBoxContainer.new()
	_gem_bar_hbox.add_theme_constant_override("separation", 4)
	left_vbox.add_child(_gem_bar_hbox)

	# Right column: stats + materials.
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 12)
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_vbox)

	var stats_title := Label.new()
	stats_title.text = "Stats"
	stats_title.add_theme_font_size_override("font_size", 18)
	right_vbox.add_child(stats_title)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	right_vbox.add_child(_stats_label)

	var materials_title := Label.new()
	materials_title.text = "Materials"
	materials_title.add_theme_font_size_override("font_size", 18)
	right_vbox.add_child(materials_title)

	_materials_vbox = VBoxContainer.new()
	_materials_vbox.add_theme_constant_override("separation", 4)
	right_vbox.add_child(_materials_vbox)

	# Floating tooltip panel (positioned in _process).
	_loadout_tooltip_panel = PanelContainer.new()
	_loadout_tooltip_panel.visible = false
	_loadout_tooltip_panel.z_index = 10
	var tooltip_margin := MarginContainer.new()
	tooltip_margin.add_theme_constant_override("margin_left", 8)
	tooltip_margin.add_theme_constant_override("margin_top", 6)
	tooltip_margin.add_theme_constant_override("margin_right", 8)
	tooltip_margin.add_theme_constant_override("margin_bottom", 6)
	_loadout_tooltip_panel.add_child(tooltip_margin)
	_loadout_tooltip_label = Label.new()
	_loadout_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout_tooltip_label.custom_minimum_size.x = 200
	tooltip_margin.add_child(_loadout_tooltip_label)
	# Tooltip is added to the root control so it floats above everything.
	add_child.call_deferred(_loadout_tooltip_panel)

	return outer_vbox


func _build_gear_detail_screen() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_detail_name_label = Label.new()
	_detail_name_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_detail_name_label)

	_detail_tier_label = Label.new()
	vbox.add_child(_detail_tier_label)

	_detail_pillar_label = Label.new()
	vbox.add_child(_detail_pillar_label)

	_detail_attunement_label = Label.new()
	vbox.add_child(_detail_attunement_label)

	_detail_familiarity_label = Label.new()
	vbox.add_child(_detail_familiarity_label)

	# Promotion progress.
	var promo_hbox := HBoxContainer.new()
	promo_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(promo_hbox)

	var promo_label := Label.new()
	promo_label.text = "Promotion:"
	promo_hbox.add_child(promo_label)

	_detail_promotion_bar = ProgressBar.new()
	_detail_promotion_bar.min_value = 0.0
	_detail_promotion_bar.max_value = 1.0
	_detail_promotion_bar.custom_minimum_size.x = 200
	_detail_promotion_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promo_hbox.add_child(_detail_promotion_bar)

	# Inscriptions.
	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	var insc_title := Label.new()
	insc_title.text = "Inscriptions"
	insc_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(insc_title)

	_detail_inscriptions_vbox = VBoxContainer.new()
	_detail_inscriptions_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(_detail_inscriptions_vbox)

	# Gem sockets.
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var sockets_title := Label.new()
	sockets_title.text = "Gem Sockets"
	sockets_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(sockets_title)

	_detail_sockets_hbox = HBoxContainer.new()
	_detail_sockets_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_detail_sockets_hbox)

	# Evolution action.
	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	_detail_evolve_button = Button.new()
	_detail_evolve_button.text = "Evolve"
	_detail_evolve_button.pressed.connect(_on_evolve_pressed)
	vbox.add_child(_detail_evolve_button)

	_detail_evolve_status = Label.new()
	_detail_evolve_status.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	vbox.add_child(_detail_evolve_status)

	return scroll


func _build_gem_management_screen() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var eq_title := Label.new()
	eq_title.text = "Equipped Gems"
	eq_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(eq_title)

	_gem_equipped_hbox = HBoxContainer.new()
	_gem_equipped_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_gem_equipped_hbox)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var inv_title := Label.new()
	inv_title.text = "Inventory Gems"
	inv_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(inv_title)

	_gem_inventory_grid = GridContainer.new()
	_gem_inventory_grid.columns = 6
	_gem_inventory_grid.add_theme_constant_override("h_separation", 6)
	_gem_inventory_grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(_gem_inventory_grid)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	_gem_detail_label = Label.new()
	_gem_detail_label.text = "Select a gem for details."
	_gem_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_gem_detail_label)

	return scroll


# ---------------------------------------------------------------------------
# Screen Navigation
# ---------------------------------------------------------------------------

func _show_screen(screen: Screen) -> void:
	_current_screen = screen
	_loadout_container.visible = (screen == Screen.LOADOUT)
	_gear_detail_container.visible = (screen == Screen.GEAR_DETAIL)
	_gem_manage_container.visible = (screen == Screen.GEM_MANAGEMENT)
	match screen:
		Screen.LOADOUT:
			_screen_title.text = "Loadout"
			_refresh_loadout_screen()
		Screen.GEAR_DETAIL:
			_screen_title.text = "Gear Detail"
			_refresh_gear_detail_screen()
		Screen.GEM_MANAGEMENT:
			_screen_title.text = "Gem Management"
			_refresh_gem_management_screen()


func _on_back_pressed() -> void:
	match _current_screen:
		Screen.GEAR_DETAIL, Screen.GEM_MANAGEMENT:
			_show_screen(Screen.LOADOUT)
		Screen.LOADOUT:
			back_pressed.emit()


func _process(_delta: float) -> void:
	if _loadout_tooltip_panel != null and _loadout_tooltip_panel.visible:
		_update_loadout_tooltip_position()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_back_pressed()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Loadout Screen Refresh
# ---------------------------------------------------------------------------

func _refresh_loadout_screen() -> void:
	var meta_store := _get_meta_store()
	if meta_store == null:
		return

	_clear_children(_gear_category_vbox)
	_clear_children(_gem_bar_hbox)
	_clear_children(_materials_vbox)

	# Build one category section per slot, showing equipped + stash gear.
	for slot_id in _LoadoutConstants.SLOT_ORDER:
		var equipped_gear_v: Variant = meta_store.call(&"get_equipped_gear", _player_id, slot_id)
		var equipped_gear: _GearItemData = equipped_gear_v as _GearItemData if equipped_gear_v is _GearItemData else null
		var equipped_instance_id := equipped_gear.instance_id if equipped_gear != null else &""

		var stash_v: Variant = meta_store.call(&"get_stash_gear", _player_id, slot_id)
		var stash_gear: Array = stash_v as Array if stash_v is Array else []

		# Build item_rows — one for each owned gear piece in this slot.
		var item_rows: Array = []
		var all_slot_gear: Array[_GearItemData] = []
		var all_gear_v: Variant = meta_store.call(&"get_all_gear_instances", _player_id)
		var all_gear: Array = all_gear_v as Array if all_gear_v is Array else []
		for g_v in all_gear:
			if g_v is _GearItemData:
				var g := g_v as _GearItemData
				if g.slot_id == slot_id:
					all_slot_gear.append(g)

		for gear in all_slot_gear:
			item_rows.append({
				"item_definition": _gear_to_item_definition(gear),
				"tooltip_data": _gear_tooltip(gear),
				"equipped": gear.instance_id == equipped_instance_id,
			})

		var section = _CATEGORY_SECTION_SCENE.instantiate()
		_gear_category_vbox.add_child(section)
		section.call(
			&"configure",
			slot_id,
			_LoadoutConstants.slot_display_name(slot_id),
			item_rows,
			bool(_category_expanded_by_slot.get(slot_id, true))
		)
		if section.has_signal(&"equip_requested"):
			section.connect(&"equip_requested", _on_gear_equip_requested)
		if section.has_signal(&"tooltip_requested"):
			section.connect(&"tooltip_requested", _on_loadout_tooltip_show)
		if section.has_signal(&"tooltip_cleared"):
			section.connect(&"tooltip_cleared", _on_loadout_tooltip_hide)
		if section.has_signal(&"expansion_changed"):
			section.connect(&"expansion_changed", _on_category_expansion_changed)

	# Gem bar.
	var gem_count: int = int(meta_store.call(&"get_gem_slot_count", _player_id))
	var socketed_v: Variant = meta_store.call(&"get_socketed_gems", _player_id)
	var socketed: Array = socketed_v as Array if socketed_v is Array else []
	for i in range(gem_count):
		var gem: _GemItemData = socketed[i] as _GemItemData if i < socketed.size() and socketed[i] is _GemItemData else null
		var gem_btn := _create_gem_slot_button(gem, i)
		_gem_bar_hbox.add_child(gem_btn)

	# Stats summary.
	_stats_label.text = _build_stats_summary()

	# Materials.
	var materials: Dictionary = meta_store.call(&"get_materials", _player_id) as Dictionary
	for pillar_id in _InfusionConstants.PILLAR_ORDER:
		var amount := float(materials.get(String(pillar_id), 0.0))
		var mat_label := Label.new()
		mat_label.text = "%s: %d" % [String(pillar_id).capitalize(), int(amount)]
		mat_label.add_theme_color_override("font_color", _InfusionConstants.ui_pillar_dot_color(pillar_id))
		_materials_vbox.add_child(mat_label)
	var dust_label := Label.new()
	dust_label.text = "Resonant Dust: %d" % int(meta_store.call(&"get_resonant_dust", _player_id))
	dust_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_materials_vbox.add_child(dust_label)


## Builds the item_definition dict used by loadout_item_row.configure().
## Uses instance_id as the item_id so equip_requested returns the instance_id.
func _gear_to_item_definition(gear: _GearItemData) -> Dictionary:
	var tier_str := _tier_display(gear.tier)
	var pillar_str := ""
	if gear.pillar_alignment != &"":
		pillar_str = "  [%s]" % String(gear.pillar_alignment).capitalize()
	var fam_str := _MetaConstants.familiarity_display_name(
		_MetaConstants.familiarity_level_for_xp(gear.familiarity_xp)
	)
	return {
		"item_id": gear.instance_id,
		"display_name": "%s  %s%s  |  %s" % [
			_LoadoutConstants.item_display_name(gear.base_item_id),
			tier_str,
			pillar_str,
			fam_str,
		],
		"slot_id": gear.slot_id,
		"stat_modifiers": {},
		"description": "",
	}


func _gear_tooltip(gear: _GearItemData) -> Dictionary:
	var tier_mult := _MetaConstants.tier_stat_multiplier(gear.tier)
	var fam_bonus := gear.familiarity_stat_bonus()
	var body_lines := PackedStringArray()
	body_lines.append("Slot: %s" % _LoadoutConstants.slot_display_name(gear.slot_id))
	body_lines.append("Tier: %s  (x%.2f stats)" % [_tier_display(gear.tier), tier_mult])
	if gear.pillar_alignment != &"":
		body_lines.append("Pillar: %s" % String(gear.pillar_alignment).capitalize())
	body_lines.append("Familiarity: %s (+%d%%)" % [
		_MetaConstants.familiarity_display_name(_MetaConstants.familiarity_level_for_xp(gear.familiarity_xp)),
		int(fam_bonus * 100.0),
	])
	body_lines.append("Promotion: %d%%" % int(gear.promotion_progress * 100.0))
	if not gear.inscriptions.is_empty():
		body_lines.append("Inscriptions: %d" % gear.inscriptions.size())
	return {
		"title": _LoadoutConstants.item_display_name(gear.base_item_id),
		"body_lines": body_lines,
	}


func _create_gem_slot_button(gem: _GemItemData, slot_index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(52, 52)
	if gem != null and not gem.is_broken:
		btn.text = String(gem.gem_type_id).substr(0, 3).to_upper()
		btn.add_theme_color_override("font_color", _InfusionConstants.ui_pillar_dot_color(gem.pillar_id))
		btn.tooltip_text = "%s\n%s\nDurability: %d%%" % [
			String(gem.gem_type_id).replace("_", " ").capitalize(),
			String(gem.effect_key).replace("_", " ").capitalize(),
			int(gem.durability * 100.0),
		]
	else:
		btn.text = "--"
		btn.tooltip_text = "Empty gem slot"
	btn.pressed.connect(_on_gem_bar_slot_clicked.bind(slot_index))
	return btn


func _build_stats_summary() -> String:
	var meta_store := _get_meta_store()
	if meta_store == null:
		return ""
	var lines := PackedStringArray()
	for slot_id in _LoadoutConstants.SLOT_ORDER:
		var gear_v: Variant = meta_store.call(&"get_equipped_gear", _player_id, slot_id)
		if gear_v is _GearItemData:
			var gear := gear_v as _GearItemData
			var tier_mult := _MetaConstants.tier_stat_multiplier(gear.tier)
			var fam_bonus := gear.familiarity_stat_bonus()
			if tier_mult > 1.0 or fam_bonus > 0.0:
				lines.append("%s: x%.2f tier, +%d%% familiarity" % [
					_LoadoutConstants.slot_display_name(slot_id),
					tier_mult,
					int(fam_bonus * 100.0),
				])
	if lines.is_empty():
		lines.append("All gear at base tier.")
	return "\n".join(lines)


func _on_gear_equip_requested(instance_id: StringName) -> void:
	var meta_store := _get_meta_store()
	if meta_store == null:
		return
	# Find the gear instance. If it's already equipped → open detail screen.
	# If it's in stash → equip it.
	var all_gear_v: Variant = meta_store.call(&"get_all_gear_instances", _player_id)
	var target_gear: _GearItemData = null
	if all_gear_v is Array:
		for g_v in (all_gear_v as Array):
			if g_v is _GearItemData:
				var g := g_v as _GearItemData
				if g.instance_id == instance_id:
					target_gear = g
					break
	if target_gear == null:
		return
	# Check if this is already equipped.
	var equipped_v: Variant = meta_store.call(&"get_equipped_gear", _player_id, target_gear.slot_id)
	var already_equipped := equipped_v is _GearItemData and (equipped_v as _GearItemData).instance_id == instance_id
	if already_equipped:
		_selected_gear = target_gear
		_show_screen(Screen.GEAR_DETAIL)
	else:
		meta_store.call(&"equip_gear", _player_id, instance_id)
		_refresh_loadout_screen()


func _on_loadout_tooltip_show(tooltip_data: Dictionary) -> void:
	if _loadout_tooltip_panel == null:
		return
	var title := String(tooltip_data.get("title", ""))
	var body_lines: Array = tooltip_data.get("body_lines", [])
	var lines := PackedStringArray()
	if not title.is_empty():
		lines.append(title)
	if not (body_lines as Array).is_empty():
		lines.append("")
		for line in body_lines:
			lines.append(String(line))
	_loadout_tooltip_label.text = "\n".join(lines)
	_loadout_tooltip_panel.visible = true
	_update_loadout_tooltip_position()


func _on_loadout_tooltip_hide() -> void:
	if _loadout_tooltip_panel != null:
		_loadout_tooltip_panel.visible = false


func _update_loadout_tooltip_position() -> void:
	if _loadout_tooltip_panel == null or not _loadout_tooltip_panel.visible:
		return
	var vp_rect := get_viewport_rect()
	var mouse_pos := get_viewport().get_mouse_position()
	var panel_size := _loadout_tooltip_panel.size
	var target := mouse_pos + Vector2(18.0, 18.0)
	target.x = minf(target.x, vp_rect.size.x - panel_size.x - 10.0)
	target.y = minf(target.y, vp_rect.size.y - panel_size.y - 10.0)
	_loadout_tooltip_panel.position = target


func _on_category_expansion_changed(slot_id: StringName, expanded: bool) -> void:
	_category_expanded_by_slot[slot_id] = expanded


func _on_gem_bar_slot_clicked(_slot_index: int) -> void:
	_show_screen(Screen.GEM_MANAGEMENT)


# ---------------------------------------------------------------------------
# Gear Detail Screen Refresh
# ---------------------------------------------------------------------------

func _refresh_gear_detail_screen() -> void:
	if _selected_gear == null:
		_show_screen(Screen.LOADOUT)
		return
	var gear := _selected_gear
	_detail_name_label.text = _LoadoutConstants.item_display_name(gear.base_item_id)
	_detail_tier_label.text = "Tier: %s" % _tier_display(gear.tier)
	_detail_pillar_label.text = "Pillar: %s" % (
		String(gear.pillar_alignment).capitalize() if gear.pillar_alignment != &"" else "Unaligned"
	)
	if gear.pillar_alignment != &"":
		_detail_pillar_label.add_theme_color_override("font_color",
			_InfusionConstants.ui_pillar_dot_color(gear.pillar_alignment))
	else:
		_detail_pillar_label.remove_theme_color_override("font_color")
	_detail_attunement_label.text = "Attunement: %s" % (
		"%s %s" % [String(gear.attunement_pillar).capitalize(), _roman(gear.attunement_level)]
		if gear.attunement_pillar != &"" else "None"
	)
	var fam_level := _MetaConstants.familiarity_level_for_xp(gear.familiarity_xp)
	_detail_familiarity_label.text = "Familiarity: %s (%.0f XP, +%d%%)" % [
		_MetaConstants.familiarity_display_name(fam_level),
		gear.familiarity_xp,
		int(gear.familiarity_stat_bonus() * 100.0),
	]
	_detail_promotion_bar.value = gear.promotion_progress

	# Inscriptions.
	_clear_children(_detail_inscriptions_vbox)
	if gear.inscriptions.is_empty():
		var none_label := Label.new()
		none_label.text = "No inscriptions yet."
		none_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		_detail_inscriptions_vbox.add_child(none_label)
	else:
		for entry in gear.inscriptions:
			var insc_label := Label.new()
			insc_label.text = "%s %s" % [
				String(entry.get("pillar_id", "")).capitalize(),
				_roman(int(entry.get("level", 1))),
			]
			_detail_inscriptions_vbox.add_child(insc_label)

	# Gem sockets.
	_clear_children(_detail_sockets_hbox)
	var max_sockets := gear.max_gem_sockets()
	for i in range(max_sockets):
		var socket_btn := Button.new()
		socket_btn.custom_minimum_size = Vector2(48, 48)
		if i < gear.socketed_gem_instance_ids.size():
			var gem_iid := gear.socketed_gem_instance_ids[i]
			socket_btn.text = String(gem_iid).substr(0, 4)
			socket_btn.tooltip_text = String(gem_iid)
		else:
			socket_btn.text = "[ ]"
			socket_btn.tooltip_text = "Empty socket"
		_detail_sockets_hbox.add_child(socket_btn)

	# Evolve button.
	var can_evolve := gear.is_eligible_for_evolution()
	_detail_evolve_button.disabled = not can_evolve
	if gear.tier >= _MetaConstants.TIER_SPECIALIZED:
		_detail_evolve_button.text = "Fully Evolved"
		_detail_evolve_button.disabled = true
		_detail_evolve_status.text = ""
	elif can_evolve:
		var cost_mats := _MetaConstants.evolution_material_cost(gear.tier)
		var cost_dust := _MetaConstants.evolution_dust_cost(gear.tier)
		_detail_evolve_button.text = "Evolve to %s" % _tier_display(gear.tier + 1)
		_detail_evolve_status.text = "Cost: %d pillar materials + %d resonant dust" % [int(cost_mats), int(cost_dust)]
	else:
		_detail_evolve_button.text = "Evolve (locked)"
		_detail_evolve_status.text = "Promotion progress: %d%%" % int(gear.promotion_progress * 100.0)


func _on_evolve_pressed() -> void:
	if _selected_gear == null:
		return
	var meta_store := _get_meta_store()
	if meta_store == null:
		return
	# For tier 1→2, the player must choose a pillar. For now, use a default based on the
	# pillar with the most materials. Full pillar selection UI can be added later.
	var target_pillar := _selected_gear.pillar_alignment
	if target_pillar == &"" and _selected_gear.tier == _MetaConstants.TIER_BASE:
		target_pillar = _pick_best_pillar_for_evolution()
	var result: Dictionary = meta_store.call(&"evolve_gear", _player_id, _selected_gear.instance_id, target_pillar) as Dictionary
	if bool(result.get("ok", false)):
		_detail_evolve_status.text = "Evolution successful!"
		_refresh_gear_detail_screen()
	else:
		_detail_evolve_status.text = String(result.get("message", "Failed."))


func _pick_best_pillar_for_evolution() -> StringName:
	var meta_store := _get_meta_store()
	if meta_store == null:
		return _InfusionConstants.PILLAR_EDGE
	var materials: Dictionary = meta_store.call(&"get_materials", _player_id) as Dictionary
	var best_pillar := _InfusionConstants.PILLAR_EDGE
	var best_amount := -1.0
	for pillar_id in _InfusionConstants.PILLAR_ORDER:
		var amount := float(materials.get(String(pillar_id), 0.0))
		if amount > best_amount:
			best_amount = amount
			best_pillar = pillar_id
	return best_pillar


# ---------------------------------------------------------------------------
# Gem Management Screen Refresh
# ---------------------------------------------------------------------------

func _refresh_gem_management_screen() -> void:
	var meta_store := _get_meta_store()
	if meta_store == null:
		return

	_clear_children(_gem_equipped_hbox)
	_clear_children(_gem_inventory_grid)

	# Equipped gem bar.
	var gem_count: int = int(meta_store.call(&"get_gem_slot_count", _player_id))
	var socketed: Array = []
	var socketed_v: Variant = meta_store.call(&"get_socketed_gems", _player_id)
	if socketed_v is Array:
		socketed = socketed_v as Array
	for i in range(gem_count):
		var gem: _GemItemData = socketed[i] as _GemItemData if i < socketed.size() and socketed[i] is _GemItemData else null
		var btn := _create_gem_manage_button(gem, i, true)
		_gem_equipped_hbox.add_child(btn)

	# All gems in inventory.
	var all_gems: Array = []
	var all_gems_v: Variant = meta_store.call(&"get_all_gem_instances", _player_id)
	if all_gems_v is Array:
		all_gems = all_gems_v as Array
	if all_gems.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No gems in inventory."
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		_gem_inventory_grid.add_child(empty_label)
	else:
		for gem_v in all_gems:
			if gem_v is _GemItemData:
				var gem := gem_v as _GemItemData
				var btn := _create_gem_manage_button(gem, -1, false)
				_gem_inventory_grid.add_child(btn)

	_gem_detail_label.text = "Select a gem for details."


func _create_gem_manage_button(gem: _GemItemData, slot_index: int, is_equipped: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(64, 64)
	if gem != null:
		var pillar_color := _InfusionConstants.ui_pillar_dot_color(gem.pillar_id)
		var type_name := String(gem.gem_type_id).replace("_", " ").capitalize()
		btn.text = type_name.substr(0, 5)
		btn.add_theme_color_override("font_color", pillar_color)
		if gem.is_broken:
			btn.text += "\n(broken)"
			btn.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
		btn.tooltip_text = "%s\n%s\nDurability: %d%%\nPillar: %s" % [
			type_name,
			String(gem.effect_key).replace("_", " ").capitalize(),
			int(gem.durability * 100.0),
			String(gem.pillar_id).capitalize(),
		]
		btn.pressed.connect(_on_gem_selected.bind(gem))
	else:
		btn.text = "--"
		if is_equipped:
			btn.tooltip_text = "Empty slot %d" % slot_index
		else:
			btn.tooltip_text = "Empty"
	return btn


func _on_gem_selected(gem: _GemItemData) -> void:
	_gem_detail_label.text = "%s\nEffect: %s\nPillar: %s\nDurability: %d%%\nBroken: %s" % [
		String(gem.gem_type_id).replace("_", " ").capitalize(),
		String(gem.effect_key).replace("_", " ").capitalize(),
		String(gem.pillar_id).capitalize(),
		int(gem.durability * 100.0),
		"Yes" if gem.is_broken else "No",
	]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _tier_display(tier: int) -> String:
	match tier:
		_MetaConstants.TIER_BASE:
			return "T1 Base"
		_MetaConstants.TIER_ALIGNED:
			return "T2 Aligned"
		_MetaConstants.TIER_SPECIALIZED:
			return "T3 Specialized"
	return "T%d" % tier


func _roman(level: int) -> String:
	match level:
		1: return "I"
		2: return "II"
		3: return "III"
	return str(level)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
