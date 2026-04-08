@tool
extends "res://scripts/visuals/player_visual_internals.gd"

## Editor/live per-frame tick: bone follow, smear, head-hide, editor preview triggers.

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	if _attack_playing:
		_attack_profile_elapsed = min(_attack_profile_elapsed + _delta, _attack_profile_duration)
	if (
		_defending_hold_active
		and _anim != null
		and not _is_animation_tree_active()
		and not _anim.is_playing()
		and _defend_clip != &""
	):
		_anim.play(_defend_clip)
		_anim.speed_scale = 1.0
	if Engine.is_editor_hint() and editor_preview_apply:
		editor_preview_apply = false
		_apply_editor_animation_preview()
	if Engine.is_editor_hint() and editor_lock_current_placement_to_rig:
		_lock_current_placement_to_rig()
		editor_lock_current_placement_to_rig = false
		return
	if Engine.is_editor_hint() and not _effective_editor_live_bone_follow():
		return
	_enforce_head_hide_pose()
	_apply_sword_state_offset_profile()
	_update_melee_smear_projectile_spawn()
	_update_sword_manual_bone_follow()
	_update_modular_equipment_bone_follow()
	_sync_charge_bar_world_pose()


func _apply_editor_animation_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if _anim == null:
		_anim = _find_animation_player(self)
	if _anim == null:
		return

	match editor_preview_animation:
		EditorAnimationPreview.IDLE:
			set_downed_state(false)
			set_defending_state(false)
			_play_locomotion(false, 1.0)
		EditorAnimationPreview.WALK:
			set_downed_state(false)
			set_defending_state(false)
			_play_locomotion(true, maxf(editor_preview_walk_speed_scale, 0.1))
		EditorAnimationPreview.MELEE:
			set_downed_state(false)
			set_defending_state(false)
			try_play_attack_for_mode(&"melee")
		EditorAnimationPreview.RANGED:
			set_downed_state(false)
			set_defending_state(false)
			try_play_attack_for_mode(&"ranged")
		EditorAnimationPreview.BOMB:
			set_downed_state(false)
			set_defending_state(false)
			try_play_attack_for_mode(&"bomb")
		EditorAnimationPreview.DEFEND:
			set_downed_state(false)
			set_defending_state(true)
		EditorAnimationPreview.DOWNED:
			set_defending_state(false)
			set_downed_state(true)
