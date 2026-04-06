extends Control

const IC := preload("res://scripts/infusion/infusion_constants.gd")

var _player: CharacterBody2D
var _modal: Control
var _tab_container: TabContainer
var _open := false
## Last-selected tab while the guide has been used this run (0 = Overview).
var _remembered_tab_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func is_infusion_guide_open() -> bool:
	return _open


func bind_player(player: CharacterBody2D) -> void:
	_player = player
	_sync_menu_block()


func _build_ui() -> void:
	_modal = Control.new()
	_modal.layout_mode = 1
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.visible = false
	_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal)

	var dim := ColorRect.new()
	dim.layout_mode = 1
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.05, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(dim)

	var panel := PanelContainer.new()
	panel.layout_mode = 1
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -400.0
	panel.offset_right = 400.0
	panel.offset_top = -290.0
	panel.offset_bottom = 290.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 14)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_right", 14)
	margin.add_theme_constant_override(&"margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Infusion guide"
	title.add_theme_font_size_override(&"font_size", 22)
	var hint := Label.new()
	hint.text = "  P toggle · Esc close"
	hint.add_theme_color_override(&"font_color", Color(0.65, 0.65, 0.7))
	header.add_child(title)
	header.add_child(hint)
	vbox.add_child(header)

	var legend_label := Label.new()
	legend_label.text = "Pillar colors (match HUD infusion dots)"
	legend_label.add_theme_font_size_override(&"font_size", 14)
	legend_label.add_theme_color_override(&"font_color", Color(0.35, 0.32, 0.28))
	vbox.add_child(legend_label)
	vbox.add_child(_make_pillar_legend_grid())

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.custom_minimum_size = Vector2(0, 420)
	vbox.add_child(_tab_container)

	_add_tab(&"Overview", _overview_bbcode())
	for pillar_id in IC.PILLAR_ORDER:
		_add_tab(pillar_id, _pillar_bbcode(pillar_id))


func _hex_srgb(c: Color) -> String:
	return c.to_html(false)


func _legend_name_color(pillar_id: StringName) -> Color:
	var c := IC.ui_pillar_dot_color(pillar_id)
	if pillar_id == IC.PILLAR_ANCHOR:
		return Color(0.32, 0.32, 0.36)
	return c


func _tier_header_hex(pillar_id: StringName) -> String:
	var c := IC.ui_pillar_dot_color(pillar_id).lerp(Color(1.0, 1.0, 1.0, 1.0), 0.42)
	return _hex_srgb(c)


func _pillar_heading_bb(pillar_id: StringName, display_title: String, rest_line: String) -> String:
	var h := _hex_srgb(IC.ui_pillar_dot_color(pillar_id))
	return "[color=#%s][b]%s[/b][/color]%s" % [h, display_title, rest_line]


func _tier_line_bb(pillar_id: StringName, label: String, body: String) -> String:
	var th := _tier_header_hex(pillar_id)
	return "[color=#%s][b]%s[/b][/color]\n%s\n\n" % [th, label, body]


func _make_pillar_dot_panel(pillar_id: StringName) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(13, 13)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = IC.ui_pillar_dot_color(pillar_id)
	sb.corner_radius_top_left = 32
	sb.corner_radius_top_right = 32
	sb.corner_radius_bottom_right = 32
	sb.corner_radius_bottom_left = 32
	sb.set_content_margin_all(0)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.45)
	p.add_theme_stylebox_override(&"panel", sb)
	return p


func _make_pillar_legend_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 6)
	for pillar_id in IC.PILLAR_ORDER:
		grid.add_child(_make_pillar_dot_panel(pillar_id))
		var name_lbl := Label.new()
		name_lbl.text = String(pillar_id).capitalize()
		name_lbl.add_theme_color_override(&"font_color", _legend_name_color(pillar_id))
		name_lbl.add_theme_font_size_override(&"font_size", 15)
		grid.add_child(name_lbl)
	return grid


func _add_tab(tab_key: StringName, bbcode: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = String(tab_key).capitalize()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.custom_minimum_size = Vector2(748, 0)
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.text = bbcode
	scroll.add_child(rtl)
	_tab_container.add_child(scroll)


func _overview_bbcode() -> String:
	var tier_note := (
		"[b]Stack and tiers[/b]\n"
		+ "Each pickup adds to that pillar's [i]stack[/i]. Your tier is derived from total stack "
		+ "(rules may change in future builds):\n"
		+ "• Below 1.0 — inactive\n"
		+ "• 1.0 up to 2.0 — [b]Baseline[/b] (tier 1)\n"
		+ "• 2.0 up to 3.0 — [b]Escalated[/b] (tier 2)\n"
		+ "• 3.0+ — [b]Expression[/b] (tier 3)\n\n"
		+ "A standard pillar pickup adds [b]1.0[/b] stack; smaller sources may add [b]0.5[/b]. "
		+ "Same-pillar pickups stack; thresholds unlock the next tier of that pillar's kit.\n\n"
		+ "Tabs use the same colors as the dots above."
	)
	return (
		"[b]What infusions are[/b]\n"
		+ "Run-long amplifiers tied to seven pillars. They do not grant raw stats by themselves; "
		+ "they scale and unlock behaviors that already exist on your gear and attacks.\n\n"
		+ tier_note
	)


func _pillar_bbcode(pillar_id: StringName) -> String:
	match pillar_id:
		IC.PILLAR_EDGE:
			return (
				_pillar_heading_bb(pillar_id, "Edge", " — precision, crits, execution windows.\n\n")
				+ _tier_line_bb(
					pillar_id,
					"Tier 1 · Sharpen (Baseline)",
					"Melee damage floor, stronger crit damage, and kill splashes that spread part of a killing hit to nearby foes."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 2 · Sever (Escalated)",
					"Overkill damage spills forward in a cone; crits can mark targets for bonus Edge damage, bleeds, and post-kill crit tempo."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 3 · Execution (Expression)",
					"Elite execution threshold on wounded foes; primed execution windows with bonus damage and a dramatic payoff when they drop."
				).strip_edges()
			)
		IC.PILLAR_FLOW:
			return (
				_pillar_heading_bb(pillar_id, "Flow", " — tempo, chains, and burst windows.\n\n")
				+ _tier_line_bb(
					pillar_id,
					"Tier 1 · Accelerate (Baseline)",
					"Higher baseline attack speed and a [i]tempo[/i] meter that builds from attacks and decays over time; tempo helps ability cooldowns tick faster during short aggression windows."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 2 · Chain (Escalated)",
					"A chain window rewards alternating melee, gun, and bomb actions with longer windows, extra attack speed, and melee hits that shave time off gun/bomb cooldowns."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 3 · Overdrive (Expression)",
					"Spend built tempo to enter Overdrive: big attack-speed and cooldown-tick surge, movement speed, snappier animations, and a small chance of echo-like follow-up melee damage."
				).strip_edges()
			)
		IC.PILLAR_MASS:
			return (
				_pillar_heading_bb(pillar_id, "Mass", " — weight, knockback, staggers, and impact payoffs.\n\n")
				+ _tier_line_bb(
					pillar_id,
					"Tier 1 · Heft (Baseline)",
					"Bonus melee damage, stronger knockback, longer hit stun, and stagger build that can down enemies when filled."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 2 · Crush (Escalated)",
					"Downed enemies become hazards (unstable burst), wall slams and carriers deal extra control, and shockwaves / area knockback themes deepen."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 3 · Cataclysm (Expression)",
					"Peak Mass scaling: larger knockback multipliers, heavier staggers, and the most dramatic impact and shockwave payoffs when collisions resolve."
				).strip_edges()
			)
		IC.PILLAR_ECHO:
			return (
				_pillar_heading_bb(pillar_id, "Echo", " — afterimages, imprint rhythm, and cascading hits.\n\n")
				+ _tier_line_bb(
					pillar_id,
					"Tier 1 · Reverberate (Baseline)",
					"Chance for melee afterimage damage; handgun shots can spawn a weaker twin projectile."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 2 · Chorus (Escalated)",
					"Melee leaves an [i]imprint[/i] on targets so follow-up hits are more reliable; repeated imprints can convert a proc into a tight burst of micro-hits and spill damage to a nearby foe."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 3 · Resonance Cascade (Expression)",
					"Controlled recursive echoes: echo hits can rarely spawn another generation of echo damage on the same target, capped so it stays readable in combat."
				).strip_edges()
			)
		IC.PILLAR_ANCHOR:
			return (
				_pillar_heading_bb(pillar_id, "Anchor", " — mitigation, delayed damage, and rooted power.\n\n")
				+ _tier_line_bb(
					pillar_id,
					"Tier 1 · Fortify (Baseline)",
					"Small flat damage reduction, a micro-shield that builds on hits up to a cap, and knockback immunity while you commit to an attack."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 2 · Brace (Escalated)",
					"Part of incoming damage is stored as [i]pressure[/i] and applied later instead of all at once; higher tiers increase how much is deferred and how safely it bleeds out."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 3 · Bastion (Expression)",
					"Strongest Brace ratios and Bastion fantasy: rooted defensive spikes and eruption-style payoffs when you stand your ground under pressure."
				).strip_edges()
			)
		IC.PILLAR_PHASE:
			return (
				_pillar_heading_bb(pillar_id, "Phase", " — reach, armor bypass, and impossible angles.\n\n")
				+ _tier_line_bb(
					pillar_id,
					"Tier 1 · Slip (Baseline)",
					"Slightly deeper melee reach, partial armor mitigation bypass on damage packets, and small collision forgiveness so swings feel crisp."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 2 · Skew (Escalated)",
					"Delayed [i]ghost[/i] strikes, facing warp tricks, and ranged behaviors that bend line-of-sight rules."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 3 · Fracture (Expression)",
					"Multi-origin flanking hits, stronger ghost damage, and limited ranged wall pierce — spatial rule-breaking at its highest tier."
				).strip_edges()
			)
		IC.PILLAR_SURGE:
			return (
				_pillar_heading_bb(pillar_id, "Surge", " — charge storage, overcharge melee, and protective fields.\n\n")
				+ _tier_line_bb(
					pillar_id,
					"Tier 1 · Primed Charge (Baseline)",
					"Flat melee bonus and extra damage when you release a fully primed melee charge."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 2 · Overcharge (Escalated)",
					"Hold melee past the normal cap to build overcharge that ramps damage; charge fields and ally-speed auras tick up with your charge fantasy."
				)
				+ _tier_line_bb(
					pillar_id,
					"Tier 3 · Overdrive (Expression)",
					"Longer overcharge holds, higher damage caps, and stronger field radii / uptime — the full Surge protection-and-burst loop."
				).strip_edges()
			)
		_:
			return "[i]Unknown pillar.[/i]"


func _toggle_guide() -> void:
	if _open:
		_close_guide()
	else:
		_open_guide()


func _open_guide() -> void:
	_open = true
	_modal.visible = true
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _tab_container != null:
		var n := _tab_container.get_tab_count()
		if n > 0:
			_tab_container.current_tab = clampi(_remembered_tab_index, 0, n - 1)
	_sync_menu_block()


func _close_guide() -> void:
	if _tab_container != null:
		_remembered_tab_index = _tab_container.current_tab
	_open = false
	_modal.visible = false
	_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_menu_block()


func _sync_menu_block() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method(&"set_menu_input_blocked"):
		return
	var block := _open
	if not block:
		var p := get_parent()
		if p != null:
			var lo := p.get_node_or_null("LoadoutOverlay")
			if lo != null and lo.has_method(&"is_loadout_panel_open") and bool(lo.call(&"is_loadout_panel_open")):
				block = true
	_player.call(&"set_menu_input_blocked", block)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if _open:
				_close_guide()
				get_viewport().set_input_as_handled()
			return


## Called from `dungeon_orchestrator` so P (`infusion_guide_toggle`) works even if this Control does not get `_unhandled_input`.
func request_toggle_from_world() -> void:
	_toggle_guide()


func _exit_tree() -> void:
	_open = false
	if _player != null and is_instance_valid(_player) and _player.has_method(&"set_menu_input_blocked"):
		_player.call(&"set_menu_input_blocked", false)
