class_name WardenMob
extends EnemyBase
## Mass / deep: slow nav boss that constricts space with a gravity aura, slam cadence, and collapse aftermath.

const EnemyStateVisualScript = preload("res://scripts/visuals/enemy_state_visual.gd")
const GroundAoeTelegraphMeshScript = preload("res://scripts/visuals/ground_aoe_telegraph_mesh.gd")
const WardenDamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const CallbackDamageReceiverComponentScript = preload(
	"res://scripts/combat/callback_damage_receiver_component.gd"
)
const PlayerSlowAuraScene = preload("res://dungeon/modules/gameplay/player_slow_aura_2d.tscn")
const MassGroundZoneScene = preload("res://dungeon/modules/gameplay/mass_ground_zone_2d.tscn")

enum Phase { CHASE, SLAM_WINDUP, SLAM_HIT, RECOVER, IMMUNE_PHASE, COLLAPSE }

@export var move_speed := 3.0
@export var stop_distance := 4.0
@export var slam_trigger_distance := 12.0
@export var repath_interval := 0.28
@export var target_refresh_interval := 0.4
@export var slam_windup_sec := 1.5
@export var slam_radius := 8.0
@export var slam_damage := 45
@export var slam_knockback := 18.0
@export var slam_hitbox_duration := 0.16
@export var slam_recover_sec := 0.55
@export var slam_cooldown_min := 3.0
@export var slam_cooldown_max := 4.0
@export var close_range_followup_cooldown_sec := 1.0
@export var gravity_radius := 8.0
@export var gravity_move_speed_multiplier := 0.6
@export var immunity_interval_sec := 30.0
@export var immunity_duration_sec := 4.0
@export var weak_point_offset := 2.1
@export var weak_point_radius := 0.95
@export var collapse_windup_sec := 0.65
@export var collapse_finish_sec := 0.45
@export var collapse_shockwave_radius := 8.5
@export var collapse_shockwave_damage := 24
@export var collapse_shockwave_knockback := 20.0
@export var collapse_zone_radius := 5.5
@export var collapse_zone_duration_sec := 5.0
@export var collapse_zone_move_speed_multiplier := 0.72
@export var mesh_ground_y := 0.42
@export var mesh_scale := Vector3(2.625, 2.625, 2.625)
@export var warden_clip_scale := 2.0
@export var telegraph_ground_y := 0.04375

var _visual: Node3D
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _target_player: Node2D
var _target_refresh_time_remaining := 0.0
var _repath_time_remaining := 0.0
var _speed_multiplier := 1.0
var _aggro_enabled := true
var _planar_facing := Vector2(0.0, -1.0)
var _phase := Phase.CHASE
var _phase_elapsed := 0.0
var _slam_cooldown_rem := 0.0
var _slam_anchor := Vector2.ZERO
var _immunity_interval_rem := 0.0
var _weak_point_triggered := false
var _collapse_origin := Vector2.ZERO
var _collapse_shockwave_done := false
var _collapse_zone_spawned := false
var _gravity_aura
var _collapse_zone
var _weak_point_hurtbox: Hurtbox2D
var _weak_point_receiver
var _weak_point_shape: CollisionShape2D
var _weak_point_visual: MeshInstance3D
var _immunity_ring_visual: MeshInstance3D

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _slam_hitbox: Hitbox2D = $SlamHitbox
@onready var _slam_shape_node: CollisionShape2D = $SlamHitbox/CollisionShape2D


func apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.01, multiplier)


func surge_infusion_bump_action_delay(seconds: float) -> void:
	if seconds <= 0.0 or not is_damage_authority():
		return
	_slam_cooldown_rem += seconds
	_immunity_interval_rem += seconds


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		_target_player = null
		velocity = Vector2.ZERO
		if _phase != Phase.COLLAPSE:
			_phase = Phase.CHASE
			_phase_elapsed = 0.0


func get_combat_planar_facing() -> Vector2:
	if _planar_facing.length_squared() > 1e-6:
		return _planar_facing.normalized()
	return super.get_combat_planar_facing()


func get_shadow_visual_root() -> Node3D:
	return _visual


func can_receive_callback_damage(_packet: DamagePacket, _hurtbox: Area2D = null) -> bool:
	return _phase == Phase.IMMUNE_PHASE and not _dead


func on_callback_damage_received(packet: DamagePacket, _hurtbox: Area2D = null) -> bool:
	if not can_receive_callback_damage(packet):
		return false
	if not is_damage_authority():
		return true
	_weak_point_triggered = true
	_exit_immunity_phase(false)
	return true


func _ready() -> void:
	super._ready()
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null:
		var vis = EnemyStateVisualScript.new()
		vis.name = &"WardenVisual"
		vis.mesh_ground_y = mesh_ground_y
		vis.mesh_scale = mesh_scale
		vis.facing_yaw_offset_deg = 0.0
		vis.configure_states(_build_visual_state_config())
		vw.add_child(vis)
		_visual = vis
		_create_telegraph_mesh(vw)
		_create_immunity_visuals(vw)
	_sync_visual()
	if _nav_agent != null:
		_nav_agent.path_desired_distance = 0.53125
		_nav_agent.target_desired_distance = stop_distance * 0.92
		_nav_agent.avoidance_enabled = false
	_refresh_slam_hitbox_shape()
	_roll_slam_cooldown()
	_immunity_interval_rem = immunity_interval_sec
	_ensure_gravity_aura()
	_ensure_weak_point_hurtbox()
	_set_weak_point_active(false)


func _exit_tree() -> void:
	super._exit_tree()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()
	if _gravity_aura != null and is_instance_valid(_gravity_aura):
		_gravity_aura.queue_free()
	if _collapse_zone != null and is_instance_valid(_collapse_zone):
		_collapse_zone.queue_free()
	if _weak_point_visual != null and is_instance_valid(_weak_point_visual):
		_weak_point_visual.queue_free()
	if _immunity_ring_visual != null and is_instance_valid(_immunity_ring_visual):
		_immunity_ring_visual.queue_free()


func _roll_slam_cooldown() -> void:
	_slam_cooldown_rem = randf_range(slam_cooldown_min, slam_cooldown_max)


func _build_visual_state_config() -> Dictionary:
	var scene := preload("res://art/characters/enemies/Warden.glb")
	return build_single_scene_visual_state_config(scene, warden_clip_scale)


func _refresh_slam_hitbox_shape() -> void:
	if _slam_shape_node != null and _slam_shape_node.shape is CircleShape2D:
		(_slam_shape_node.shape as CircleShape2D).radius = slam_radius


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		_update_remote_phase_effects()
		_update_slam_telegraph_visual()
		_sync_visual()
		return
	surge_infusion_tick_server_field_decay()
	var cooldown_tick := delta * surge_infusion_field_cooldown_tick_factor()
	_slam_cooldown_rem = maxf(0.0, _slam_cooldown_rem - cooldown_tick)
	if _phase != Phase.IMMUNE_PHASE and _phase != Phase.COLLAPSE:
		_immunity_interval_rem = maxf(0.0, _immunity_interval_rem - delta)
	if _phase != Phase.COLLAPSE and apply_universal_stagger_stop(delta, true):
		_enemy_network_server_broadcast(delta)
		_update_slam_telegraph_visual()
		_sync_visual()
		return
	if not _aggro_enabled and _phase != Phase.COLLAPSE:
		velocity = Vector2.ZERO
		_enemy_network_server_broadcast(delta)
		_update_slam_telegraph_visual()
		_sync_visual()
		return
	_refresh_target_player(delta, _phase == Phase.CHASE)
	if _is_player_downed_node(_target_player):
		_target_player = _pick_nearest_player_target()
	match _phase:
		Phase.CHASE:
			_tick_chase_slam(delta)
		Phase.SLAM_WINDUP:
			_tick_slam_windup(delta)
		Phase.SLAM_HIT:
			_tick_slam_hit()
		Phase.RECOVER:
			_tick_slam_recover(delta)
		Phase.IMMUNE_PHASE:
			_tick_immunity_phase(delta)
		Phase.COLLAPSE:
			_tick_collapse(delta)
	apply_hit_knockback_to_body_velocity()
	move_and_slide_with_mob_separation()
	mass_server_post_slide()
	tick_hit_knockback_timer(delta)
	_enemy_network_server_broadcast(delta)
	_update_slam_telegraph_visual()
	_sync_visual()


func _tick_chase_slam(delta: float) -> void:
	if _immunity_interval_rem <= 0.0:
		_enter_immunity_phase()
		return
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	_update_chase_velocity(delta)
	if _slam_cooldown_rem <= 0.0:
		var to_p := _target_player.global_position - global_position
		var attack_entry_distance := _slam_attack_entry_distance()
		if to_p.length_squared() <= attack_entry_distance * attack_entry_distance:
			_start_slam_windup()


func _slam_attack_entry_distance() -> float:
	return minf(slam_trigger_distance, slam_radius)


func _update_chase_velocity(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		velocity = Vector2.ZERO
		return
	_repath_time_remaining = maxf(0.0, _repath_time_remaining - delta)
	if _nav_agent != null and _repath_time_remaining <= 0.0:
		_nav_agent.target_position = _target_player.global_position
		_repath_time_remaining = repath_interval
	var desired := Vector2.ZERO
	if _nav_agent != null and _nav_agent.get_navigation_map() != RID():
		var next_pos := _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		if to_next.length_squared() > 0.001:
			desired = to_next.normalized()
	var to_target := _target_player.global_position - global_position
	if desired.length_squared() <= 0.0001 and to_target.length_squared() > 0.001:
		desired = to_target.normalized()
	if to_target.length_squared() <= stop_distance * stop_distance:
		velocity = Vector2.ZERO
	else:
		velocity = (
			desired
			* move_speed
			* _speed_multiplier
			* surge_infusion_field_move_speed_factor()
		)
	if velocity.length_squared() > 0.01:
		_planar_facing = velocity.normalized()
	elif to_target.length_squared() > 0.0001:
		_planar_facing = to_target.normalized()


func _start_slam_windup() -> void:
	_phase = Phase.SLAM_WINDUP
	_phase_elapsed = 0.0
	_slam_anchor = global_position
	velocity = Vector2.ZERO
	if _target_player != null and is_instance_valid(_target_player):
		var to_p := _target_player.global_position - global_position
		if to_p.length_squared() > 0.0001:
			_planar_facing = to_p.normalized()


func _tick_slam_windup(delta: float) -> void:
	global_position = _slam_anchor
	velocity = Vector2.ZERO
	if _target_player != null and is_instance_valid(_target_player):
		var to_p := _target_player.global_position - global_position
		if to_p.length_squared() > 0.0001:
			_planar_facing = to_p.normalized()
	_phase_elapsed += delta
	if _phase_elapsed >= slam_windup_sec:
		_phase = Phase.SLAM_HIT
		_phase_elapsed = 0.0


func _tick_slam_hit() -> void:
	_activate_slam_hitbox(slam_radius, slam_damage, slam_knockback, slam_hitbox_duration, &"warden_slam")
	mass_broadcast_combat_vfx(MassCombatVfxScript.Kind.SHOCKWAVE, global_position, Vector2.ZERO, slam_radius)
	_phase = Phase.RECOVER
	_phase_elapsed = 0.0
	_roll_slam_cooldown()
	if _target_player != null and is_instance_valid(_target_player):
		var to_p := _target_player.global_position - global_position
		var attack_entry_distance := _slam_attack_entry_distance()
		if to_p.length_squared() <= attack_entry_distance * attack_entry_distance:
			_slam_cooldown_rem = minf(_slam_cooldown_rem, close_range_followup_cooldown_sec)
	velocity = Vector2.ZERO


func _tick_slam_recover(delta: float) -> void:
	global_position = _slam_anchor
	velocity = Vector2.ZERO
	_phase_elapsed += delta
	if _phase_elapsed >= slam_recover_sec:
		_phase = Phase.CHASE
		_phase_elapsed = 0.0


func _tick_immunity_phase(delta: float) -> void:
	velocity = Vector2.ZERO
	_phase_elapsed += delta
	if _phase_elapsed >= immunity_duration_sec:
		_exit_immunity_phase(true)
		return
	if _target_player != null and is_instance_valid(_target_player):
		var to_p := _target_player.global_position - global_position
		if to_p.length_squared() > 0.0001:
			_planar_facing = to_p.normalized()


func _enter_immunity_phase() -> void:
	_phase = Phase.IMMUNE_PHASE
	_phase_elapsed = 0.0
	_weak_point_triggered = false
	velocity = Vector2.ZERO
	_set_body_damage_enabled(false)
	_set_weak_point_active(true)


func _exit_immunity_phase(trigger_slam: bool) -> void:
	_set_weak_point_active(false)
	_set_body_damage_enabled(true)
	_immunity_interval_rem = immunity_interval_sec
	if trigger_slam:
		_start_slam_windup()
	else:
		_phase = Phase.CHASE
		_phase_elapsed = 0.0


func _tick_collapse(delta: float) -> void:
	global_position = _collapse_origin
	velocity = Vector2.ZERO
	_phase_elapsed += delta
	if not _collapse_shockwave_done and _phase_elapsed >= collapse_windup_sec:
		_fire_collapse_shockwave()
	if _collapse_shockwave_done and _phase_elapsed >= collapse_windup_sec + collapse_finish_sec:
		super.squash()


func _fire_collapse_shockwave() -> void:
	_collapse_shockwave_done = true
	_spawn_collapse_zone()
	_activate_slam_hitbox(
		collapse_shockwave_radius,
		collapse_shockwave_damage,
		collapse_shockwave_knockback,
		slam_hitbox_duration,
		&"warden_collapse"
	)
	mass_broadcast_combat_vfx(
		MassCombatVfxScript.Kind.SHOCKWAVE,
		_collapse_origin,
		Vector2.ZERO,
		collapse_shockwave_radius
	)


func _activate_slam_hitbox(
	radius: float,
	damage: int,
	knockback: float,
	duration: float,
	debug_label: StringName
) -> void:
	if _slam_hitbox == null or not is_damage_authority():
		return
	if _slam_shape_node != null and _slam_shape_node.shape is CircleShape2D:
		(_slam_shape_node.shape as CircleShape2D).radius = radius
	var packet := WardenDamagePacketScript.new() as DamagePacket
	packet.amount = damage
	packet.kind = &"stomp"
	packet.source_node = self
	packet.source_uid = get_instance_id()
	packet.origin = global_position
	packet.direction = _planar_facing
	packet.knockback = knockback
	packet.apply_iframes = true
	packet.blockable = false
	packet.debug_label = debug_label
	_slam_hitbox.activate(packet, duration)


func cancel_active_attack_for_stagger() -> void:
	if _phase == Phase.SLAM_WINDUP or _phase == Phase.SLAM_HIT or _phase == Phase.RECOVER:
		_phase = Phase.CHASE
		_phase_elapsed = 0.0
		_slam_cooldown_rem = maxf(_slam_cooldown_rem, universal_stagger_duration)
		if _slam_hitbox != null:
			_slam_hitbox.deactivate()
		_update_slam_telegraph_visual()
	velocity = Vector2.ZERO


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ph": _phase,
		"pe": _phase_elapsed,
		"pf": _planar_facing,
		"sa": _slam_anchor,
		"cd": _slam_cooldown_rem,
		"im": _immunity_interval_rem,
		"co": _collapse_origin,
		"cs": _collapse_shockwave_done,
		"cw": _weak_point_triggered,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	var previous_phase := _phase
	_phase = int(state.get("ph", _phase)) as Phase
	_phase_elapsed = maxf(0.0, float(state.get("pe", 0.0)))
	var pf_v: Variant = state.get("pf", _planar_facing)
	if pf_v is Vector2:
		var pf := pf_v as Vector2
		if pf.length_squared() > 0.0001:
			_planar_facing = pf.normalized()
	var sa_v: Variant = state.get("sa", _slam_anchor)
	if sa_v is Vector2:
		_slam_anchor = sa_v as Vector2
	_slam_cooldown_rem = maxf(0.0, float(state.get("cd", 0.0)))
	_immunity_interval_rem = maxf(0.0, float(state.get("im", _immunity_interval_rem)))
	var co_v: Variant = state.get("co", _collapse_origin)
	if co_v is Vector2:
		_collapse_origin = co_v as Vector2
	_collapse_shockwave_done = bool(state.get("cs", _collapse_shockwave_done))
	_weak_point_triggered = bool(state.get("cw", _weak_point_triggered))
	if previous_phase != _phase:
		_on_remote_phase_changed(previous_phase, _phase)


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.set_high_detail_enabled(_should_use_high_detail_visuals())
	_visual.set_attack_shake_progress(_attack_shake_progress())
	var moving := _phase == Phase.CHASE and velocity.length_squared() > 0.04
	_visual.set_state(&"walk" if moving else &"idle")
	_visual.sync_from_2d(global_position, _planar_facing)
	_sync_immunity_visuals()


func _attack_shake_progress() -> float:
	match _phase:
		Phase.SLAM_WINDUP:
			return clampf(_phase_elapsed / maxf(0.01, slam_windup_sec), 0.0, 1.0)
		Phase.COLLAPSE:
			if not _collapse_shockwave_done:
				return clampf(_phase_elapsed / maxf(0.01, collapse_windup_sec), 0.0, 1.0)
	return 0.0


func _should_use_high_detail_visuals() -> bool:
	if _phase != Phase.CHASE:
		return true
	if _target_player != null and is_instance_valid(_target_player):
		return global_position.distance_squared_to(_target_player.global_position) <= 48.0 * 48.0
	return true


func _refresh_target_player(delta: float, allow_retarget: bool = true) -> void:
	var refresh := refresh_enemy_target_player(
		delta,
		_target_player,
		_target_refresh_time_remaining,
		target_refresh_interval,
		allow_retarget
	)
	_target_player = refresh.get("target", _target_player) as Node2D
	_target_refresh_time_remaining = float(
		refresh.get("refresh_time_remaining", _target_refresh_time_remaining)
	)


func _create_telegraph_mesh(parent: Node3D) -> void:
	_telegraph_mesh = MeshInstance3D.new()
	_telegraph_mesh.name = &"WardenTelegraph"
	_outline_mat = GroundAoeTelegraphMeshScript.create_outline_material(Color(0.05, 0.05, 0.05, 1.0))
	_fill_mat = GroundAoeTelegraphMeshScript.create_fill_material(Color(0.42, 0.3, 0.18, 0.62))
	_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph_mesh.visible = false
	parent.add_child(_telegraph_mesh)


func _create_immunity_visuals(parent: Node3D) -> void:
	_weak_point_visual = MeshInstance3D.new()
	_weak_point_visual.name = &"WardenWeakPointVisual"
	var sphere := SphereMesh.new()
	sphere.radius = 0.48
	sphere.height = 0.96
	_weak_point_visual.mesh = sphere
	var weak_mat := StandardMaterial3D.new()
	weak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	weak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	weak_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	weak_mat.albedo_color = Color(1.0, 0.4, 0.18, 0.88)
	weak_mat.emission_enabled = true
	weak_mat.emission = Color(1.0, 0.48, 0.22, 1.0)
	weak_mat.emission_energy_multiplier = 2.2
	_weak_point_visual.material_override = weak_mat
	_weak_point_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_weak_point_visual.visible = false
	parent.add_child(_weak_point_visual)

	_immunity_ring_visual = MeshInstance3D.new()
	_immunity_ring_visual.name = &"WardenImmunityRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 2.5
	ring.outer_radius = 2.85
	_immunity_ring_visual.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.albedo_color = Color(0.88, 0.84, 0.62, 0.46)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.96, 0.75, 1.0)
	ring_mat.emission_energy_multiplier = 1.5
	_immunity_ring_visual.material_override = ring_mat
	_immunity_ring_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_immunity_ring_visual.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_immunity_ring_visual.visible = false
	parent.add_child(_immunity_ring_visual)


func _slam_telegraph_progress() -> float:
	match _phase:
		Phase.SLAM_WINDUP:
			return clampf(_phase_elapsed / maxf(0.01, slam_windup_sec), 0.0, 1.0)
		Phase.COLLAPSE:
			if not _collapse_shockwave_done:
				return clampf(_phase_elapsed / maxf(0.01, collapse_windup_sec), 0.0, 1.0)
	return 0.0


func _update_slam_telegraph_visual() -> void:
	if _telegraph_mesh == null:
		return
	var active := _phase == Phase.SLAM_WINDUP or (_phase == Phase.COLLAPSE and not _collapse_shockwave_done)
	if not active:
		_telegraph_mesh.visible = false
		return
	var p := _slam_telegraph_progress()
	var telegraph_radius := slam_radius if _phase == Phase.SLAM_WINDUP else collapse_shockwave_radius
	var anchor := _slam_anchor if _phase == Phase.SLAM_WINDUP else _collapse_origin
	_telegraph_mesh.visible = true
	_telegraph_mesh.global_position = Vector3(anchor.x, telegraph_ground_y, anchor.y)
	_telegraph_mesh.rotation = Vector3.ZERO
	_telegraph_mesh.mesh = GroundAoeTelegraphMeshScript.build_crack_ring_mesh(
		p,
		telegraph_radius,
		32,
		_outline_mat,
		_fill_mat
	)


func _ensure_gravity_aura() -> void:
	if _gravity_aura != null and is_instance_valid(_gravity_aura):
		return
	var aura = PlayerSlowAuraScene.instantiate()
	if aura == null:
		return
	aura.name = &"GravityAura"
	aura.radius = gravity_radius
	aura.move_speed_multiplier = gravity_move_speed_multiplier
	aura.position = Vector2.ZERO
	add_child(aura)
	_gravity_aura = aura
	_update_gravity_aura_state()


func _update_gravity_aura_state() -> void:
	if _gravity_aura == null or not is_instance_valid(_gravity_aura):
		return
	_gravity_aura.radius = gravity_radius
	_gravity_aura.move_speed_multiplier = gravity_move_speed_multiplier
	_gravity_aura.set_enabled(_phase != Phase.COLLAPSE and not _dead)


func _ensure_weak_point_hurtbox() -> void:
	if _weak_point_hurtbox != null and is_instance_valid(_weak_point_hurtbox):
		return
	var receiver = CallbackDamageReceiverComponentScript.new()
	receiver.name = &"WeakPointDamageReceiver"
	receiver.callback_owner_path = NodePath("..")
	add_child(receiver)
	_weak_point_receiver = receiver

	var hurtbox := Hurtbox2D.new()
	hurtbox.name = &"WeakPointHurtbox"
	hurtbox.collision_layer = 16
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.monitorable = true
	hurtbox.receiver_path = NodePath("../WeakPointDamageReceiver")
	hurtbox.owner_path = NodePath("..")
	hurtbox.faction = &"enemy"
	hurtbox.debug_label = &"warden_weak_point"
	add_child(hurtbox)
	_weak_point_hurtbox = hurtbox

	var shape := CollisionShape2D.new()
	shape.name = &"CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = weak_point_radius
	shape.shape = circle
	hurtbox.add_child(shape)
	_weak_point_shape = shape
	_position_weak_point()


func _set_body_damage_enabled(enabled: bool) -> void:
	if _damage_receiver != null:
		_damage_receiver.set_active(enabled)
	if _hurtbox != null:
		_hurtbox.set_active(enabled)


func _set_weak_point_active(active: bool) -> void:
	if _weak_point_receiver != null:
		_weak_point_receiver.set_active(active)
	if _weak_point_hurtbox != null:
		_weak_point_hurtbox.set_active(active)
	_position_weak_point()
	_sync_immunity_visuals()


func _position_weak_point() -> void:
	if _weak_point_hurtbox == null or not is_instance_valid(_weak_point_hurtbox):
		return
	var facing := _planar_facing.normalized() if _planar_facing.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	_weak_point_hurtbox.position = -facing * weak_point_offset


func _sync_immunity_visuals() -> void:
	_position_weak_point()
	var weak_active := _phase == Phase.IMMUNE_PHASE
	if _weak_point_visual != null and is_instance_valid(_weak_point_visual):
		_weak_point_visual.visible = weak_active
		if weak_active:
			var weak_pos_2d := global_position + _weak_point_hurtbox.position
			_weak_point_visual.global_position = Vector3(weak_pos_2d.x, mesh_ground_y + 1.75, weak_pos_2d.y)
			var t := float(Time.get_ticks_msec()) * 0.001
			_weak_point_visual.scale = Vector3.ONE * (0.95 + sin(t * 7.2) * 0.12)
	if _immunity_ring_visual != null and is_instance_valid(_immunity_ring_visual):
		_immunity_ring_visual.visible = weak_active
		if weak_active:
			_immunity_ring_visual.global_position = Vector3(global_position.x, mesh_ground_y + 0.1, global_position.y)
			var t := float(Time.get_ticks_msec()) * 0.001
			_immunity_ring_visual.scale = Vector3.ONE * (0.96 + sin(t * 3.5) * 0.05)
	_update_gravity_aura_state()


func _spawn_collapse_zone() -> void:
	if _collapse_zone_spawned:
		return
	_collapse_zone_spawned = true
	var zone = MassGroundZoneScene.instantiate()
	if zone == null:
		return
	zone.name = &"WardenCollapseZone"
	zone.radius = collapse_zone_radius
	zone.move_speed_multiplier = collapse_zone_move_speed_multiplier
	zone.lifetime_sec = collapse_zone_duration_sec
	zone.global_position = _collapse_origin
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(zone)
	_collapse_zone = zone


func _update_remote_phase_effects() -> void:
	_update_gravity_aura_state()
	_sync_immunity_visuals()
	if _phase == Phase.COLLAPSE and _collapse_shockwave_done:
		_spawn_collapse_zone()


func _on_remote_phase_changed(previous_phase: Phase, next_phase: Phase) -> void:
	if previous_phase == Phase.COLLAPSE and next_phase != Phase.COLLAPSE:
		if _collapse_zone != null and is_instance_valid(_collapse_zone):
			_collapse_zone.queue_free()
			_collapse_zone = null
		_collapse_zone_spawned = false
	if next_phase == Phase.IMMUNE_PHASE:
		_set_body_damage_enabled(false)
		_set_weak_point_active(true)
	elif previous_phase == Phase.IMMUNE_PHASE:
		_set_weak_point_active(false)
		_set_body_damage_enabled(true)
	if next_phase == Phase.COLLAPSE and _collapse_shockwave_done:
		_spawn_collapse_zone()


func _should_defer_death(_packet: DamagePacket) -> bool:
	return true


func _begin_deferred_death(_packet: DamagePacket) -> void:
	_aggro_enabled = false
	_phase = Phase.COLLAPSE
	_phase_elapsed = 0.0
	_collapse_origin = global_position
	_collapse_shockwave_done = false
	_collapse_zone_spawned = false
	velocity = Vector2.ZERO
	_set_body_damage_enabled(false)
	_set_weak_point_active(false)
	_update_gravity_aura_state()
