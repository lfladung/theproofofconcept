class_name ScramblerMob
extends EnemyBase
## Rush surface: straight-line rush, weak stuck recovery, body contact damage (no dash).

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")

@export var move_speed := 14.0
@export var stuck_speed_threshold := 0.18
@export var stuck_time_to_retarget := 0.22
@export var contact_damage := 8
@export var contact_repeat_sec := 0.5
@export var target_refresh_interval := 0.35
@export var mesh_ground_y := 0.2
@export var mesh_scale := Vector3(1.85, 1.85, 1.85)
@export var scrambler_clip_scale := 2.5

var _visual: Node3D
var _vw: Node3D
var _spawn_start: Vector2 = Vector2.ZERO
var _spawn_target: Vector2 = Vector2.ZERO
var _has_spawn: bool = false
var _speed_multiplier := 1.0
var _aggro_enabled := true
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _locked_dir := Vector2(0.0, -1.0)
var _stuck_accum := 0.0
var _planar_facing := Vector2(0.0, -1.0)

@onready var _body_contact_hitbox: Hitbox2D = $BodyContactHitbox


func configure_spawn(start_position: Vector2, player_position: Vector2) -> void:
	_spawn_start = start_position
	_spawn_target = player_position
	_has_spawn = true


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		if _body_contact_hitbox != null:
			_body_contact_hitbox.deactivate()


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func _ready() -> void:
	super._ready()
	if not _has_spawn:
		push_warning("Scrambler entered tree without configure_spawn; removing.")
		queue_free()
		return
	global_position = _spawn_start
	var to_p := _spawn_target - _spawn_start
	_locked_dir = to_p.normalized() if to_p.length_squared() > 0.01 else Vector2(0.0, -1.0)
	_planar_facing = _locked_dir
	velocity = _locked_dir * move_speed * _speed_multiplier
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"ScramblerVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_sync_visual_from_body()
	_activate_contact_hitbox()
	if _has_spawn:
		set_deferred(&"collision_layer", 2)
		set_deferred(&"collision_mask", 7)
	_target_player = _pick_nearest_player_target()
	_target_refresh_time_remaining = 0.0


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Scrambler.glb")
	var scale_v: Variant = scrambler_clip_scale
	return {
		&"idle": {
			"scene": scene,
			"scene_scale": scale_v,
			"clip_hint": "",
			"keywords": [],
		},
		&"walk": {
			"scene": scene,
			"scene_scale": scale_v,
			"clip_hint": "",
			"keywords": [],
		},
	}


func _activate_contact_hitbox() -> void:
	if _body_contact_hitbox == null or not is_damage_authority():
		return
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.amount = contact_damage
	pkt.kind = &"contact"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = global_position
	pkt.direction = _locked_dir
	pkt.knockback = 0.0
	pkt.apply_iframes = true
	pkt.blockable = true
	pkt.debug_label = &"scrambler_contact"
	_body_contact_hitbox.repeat_mode = Hitbox2D.RepeatMode.INTERVAL
	_body_contact_hitbox.repeat_interval_sec = contact_repeat_sec
	_body_contact_hitbox.activate(pkt, -1.0)


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_sync_visual_from_body()
		return
	surge_infusion_tick_server_field_decay()
	if not _aggro_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		_enemy_network_server_broadcast(delta)
		_sync_visual_from_body()
		return
	_refresh_target_player(delta)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		move_and_slide()
		_enemy_network_server_broadcast(delta)
		_sync_visual_from_body()
		return
	var sp := move_speed * _speed_multiplier * surge_infusion_field_move_speed_factor()
	velocity = _locked_dir * sp
	move_and_slide()
	mass_server_post_slide()
	var spd := velocity.length()
	if spd < stuck_speed_threshold:
		_stuck_accum += delta
		if _stuck_accum >= stuck_time_to_retarget:
			_stuck_accum = 0.0
			var to_player := _target_player.global_position - global_position
			_locked_dir = to_player.normalized() if to_player.length_squared() > 0.01 else _locked_dir
	else:
		_stuck_accum = 0.0
	_planar_facing = _locked_dir
	_refresh_contact_hitbox_packet()
	_enemy_network_server_broadcast(delta)
	_sync_visual_from_body()


func _refresh_contact_hitbox_packet() -> void:
	if _body_contact_hitbox == null or not _body_contact_hitbox.is_active():
		return
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.amount = contact_damage
	pkt.kind = &"contact"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = global_position
	pkt.direction = _locked_dir
	pkt.knockback = 0.0
	pkt.apply_iframes = true
	pkt.blockable = true
	pkt.debug_label = &"scrambler_contact"
	_body_contact_hitbox.update_packet_template(pkt)


func _enemy_network_compact_state() -> Dictionary:
	return {"ag": _aggro_enabled, "ld": _locked_dir, "pf": _planar_facing}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	var ld_v: Variant = state.get("ld", _locked_dir)
	if ld_v is Vector2:
		var ld := ld_v as Vector2
		if ld.length_squared() > 0.0001:
			_locked_dir = ld.normalized()
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()


func _sync_visual_from_body() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	var moving := velocity.length_squared() > 0.04
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _planar_facing)


func _should_use_high_detail_visuals() -> bool:
	if _target_player != null and is_instance_valid(_target_player):
		return global_position.distance_squared_to(_target_player.global_position) <= 22.0 * 22.0
	return velocity.length_squared() > 0.04


func _refresh_target_player(delta: float) -> void:
	_target_refresh_time_remaining = maxf(0.0, _target_refresh_time_remaining - delta)
	if (
		_target_player == null
		or not is_instance_valid(_target_player)
		or _target_refresh_time_remaining <= 0.0
	):
		_target_player = _pick_nearest_player_target()
		_target_refresh_time_remaining = maxf(0.05, target_refresh_interval)


func take_hit(
	damage: int,
	knockback_dir: Vector2,
	knockback_strength: float,
	from_backstab: bool = false,
	is_critical: bool = false
) -> void:
	if damage <= 0:
		return
	super.take_hit(damage, knockback_dir, knockback_strength, from_backstab, is_critical)
