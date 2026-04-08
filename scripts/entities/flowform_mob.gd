class_name FlowformMob
extends FlowModelDasherMob

const FLOWFORM_MODEL := preload("res://art/characters/enemies/Flowform.glb")
const SCRAMBLER_SCENE := preload("res://scenes/entities/scrambler.tscn")
const HOTSPOT_SCENE := preload("res://dungeon/modules/gameplay/flowform_dash_hotspot_2d.tscn")

@export var trail_spawn_interval := 0.1
@export var trail_damage_per_tick := 2

var _trail_timer: Timer
var _was_dashing := false


func _flow_character_scene() -> PackedScene:
	return FLOWFORM_MODEL


func _ready() -> void:
	super._ready()
	if _visual != null:
		_visual.facing_yaw_offset_deg = 90.0
	_trail_timer = Timer.new()
	_trail_timer.wait_time = maxf(0.04, trail_spawn_interval)
	_trail_timer.one_shot = false
	_trail_timer.timeout.connect(_on_trail_timer_timeout)
	add_child(_trail_timer)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _multiplayer_active() and not _is_server_peer():
		return
	if not is_damage_authority():
		return
	if _is_dashing and not _was_dashing:
		_trail_timer.wait_time = maxf(0.04, trail_spawn_interval)
		_trail_timer.start()
	elif not _is_dashing and _was_dashing:
		_trail_timer.stop()
	_was_dashing = _is_dashing


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	if _is_dashing:
		_apply_hit_knockback_impulse(knockback_dir, knockback_strength)
		return
	super._on_nonlethal_hit(knockback_dir, knockback_strength)


func squash() -> void:
	if _squash_applied:
		return
	if is_damage_authority():
		_request_spawn_scrambler_splits()
	super.squash()


func _on_trail_timer_timeout() -> void:
	if not is_damage_authority() or not _is_dashing:
		return
	var parent := get_parent()
	if parent == null:
		return
	var spot := HOTSPOT_SCENE.instantiate()
	if spot is FlowformDashHotspot2D:
		(spot as FlowformDashHotspot2D).damage_per_tick = trail_damage_per_tick
	parent.add_child(spot)
	spot.global_position = global_position


func _request_spawn_scrambler_splits() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null or not scene_root.has_method(&"server_enqueue_enemy_spawn"):
		return
	var encounter_id := get_meta(&"encounter_id", &"") as StringName
	var target := _pick_nearest_player_target()
	var tpos := target.global_position if target != null else global_position
	var offsets: Array[Vector2] = [Vector2(-0.55, 0.0), Vector2(0.55, 0.0)]
	for off in offsets:
		scene_root.call(
			&"server_enqueue_enemy_spawn",
			encounter_id,
			global_position + off,
			tpos,
			_speed_multiplier,
			SCRAMBLER_SCENE
		)
