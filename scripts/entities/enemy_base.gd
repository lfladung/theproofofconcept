extends CharacterBody2D
class_name EnemyBase

signal squashed
signal coin_drop_requested(spawn_position: Vector2, coin_value: int)

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const InfusionEdgeRef = preload("res://scripts/infusion/infusion_edge.gd")
const InfusionMassRef = preload("res://scripts/infusion/infusion_mass.gd")
const InfusionConstantsRef = preload("res://scripts/infusion/infusion_constants.gd")
const MassCombatVfxScript = preload("res://scripts/vfx/mass_combat_vfx.gd")
const DAMAGE_TEXT_STYLE_HP := &"hp"
const DAMAGE_TEXT_STYLE_BLOCK := &"block"
const DAMAGE_TEXT_STYLE_ARMOR := &"armor"
const DAMAGE_TEXT_STYLE_STAGGER := &"stagger"
const DAMAGE_TEXT_HP_COLOR := Color(1.0, 0.15, 0.15, 1.0)
const DAMAGE_TEXT_BLOCK_COLOR := Color(0.25, 0.62, 1.0, 1.0)
const DAMAGE_TEXT_ARMOR_COLOR := Color(1.0, 0.86, 0.14, 1.0)
const DAMAGE_TEXT_STAGGER_COLOR := Color(1.0, 0.95, 0.25, 1.0)
const DAMAGE_TEXT_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const _PLAYER_ROSTER_CACHE_INTERVAL_USEC := 100000
const _MOB_ROSTER_CACHE_INTERVAL_USEC := 100000
const DEFAULT_ARMOR_HEALTH_MULTIPLIER := 1.5

static var _cached_player_nodes: Array = []
static var _cached_player_tree_id := 0
static var _cached_player_snapshot_usec := 0
static var _cached_mob_nodes: Array = []
static var _cached_mob_tree_id := 0
static var _cached_mob_snapshot_usec := 0


## Rotate a planar unit direction toward a target by at most `max_step_radians` this frame.
## Matches gameplay/3D yaw convention (see AGENTS.md: visual yaw uses atan2(x, y)).
static func step_planar_facing_toward(
	from_dir: Vector2, to_dir: Vector2, max_step_radians: float
) -> Vector2:
	if max_step_radians <= 0.0:
		return (
			from_dir.normalized()
			if from_dir.length_squared() > 1e-6
			else Vector2(0.0, -1.0)
		)
	if to_dir.length_squared() <= 1e-6:
		return (
			from_dir.normalized()
			if from_dir.length_squared() > 1e-6
			else Vector2(0.0, -1.0)
		)
	var from_n := from_dir.normalized() if from_dir.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	var to_n := to_dir.normalized()
	var delta := from_n.angle_to(to_n)
	if absf(delta) <= max_step_radians or is_zero_approx(delta):
		return to_n
	return from_n.rotated(signf(delta) * max_step_radians).normalized()

@export var max_health := 50
@export var drops_coin_on_death := true
@export var coin_drop_value := 1
@export var show_damage_text := true
@export var damage_text_world_y := 2.8
@export var damage_text_rise := 1.6
@export var damage_text_duration := 0.7
@export var damage_text_font_size := 220
@export var universal_stagger_duration := 0.3
@export var armor_health_multiplier := DEFAULT_ARMOR_HEALTH_MULTIPLIER
@export var armor_glow_center_y := 1.15
@export var armor_glow_sphere_radius := 1.65
@export var armor_glow_pulse_hz := 0.85
## Edge Sever mark: pulsing red glow in VisualWorld3D (body center height in 3D, xz from 2D pos).
@export var edge_mark_glow_center_y := 1.05
@export var edge_mark_glow_sphere_radius := 1.45
@export var edge_mark_glow_pulse_hz := 0.65
@export var network_sync_interval := 0.05
@export var remote_interpolation_lerp_rate := 14.0
@export var remote_interpolation_snap_distance := 6.0
## Planar knockback impulse = `knockback_strength * knockback_impulse_scale` while `hit_knockback_duration` elapses.
@export var knockback_impulse_scale := 1.3
@export var hit_knockback_duration := 0.22
## Convert top-down rectangles into footprint circles large enough to cover the visible body.
@export_range(0.5, 1.5, 0.05) var topdown_collision_radius_scale := 1.0
## Mob-to-mob steering buffer added on top of footprint radii to reduce crowd jams while chasing players.
@export var mob_separation_extra_margin := 0.3
@export_range(0.0, 2.0, 0.05) var mob_separation_strength := 0.85
@export_range(0.0, 1.0, 0.05) var mob_slide_bias := 0.4
@export_range(0.0, 1.0, 0.05) var mob_min_forward_bias := 0.2
## Gentle post-slide pair separation so rear mobs can squeeze pressure through the front line.
@export_range(0.0, 0.5, 0.01) var mob_squeeze_min_push := 0.06
@export_range(0.0, 0.5, 0.01) var mob_squeeze_max_push := 0.18
@export_range(0.0, 1.0, 0.05) var mob_squeeze_transfer_ratio := 0.8
@export_range(0.0, 1.0, 0.05) var mob_squeeze_velocity_factor := 0.35

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _damage_receiver: DamageReceiverComponent = $DamageReceiver
@onready var _hurtbox: Hurtbox2D = $EnemyHurtbox

var _health := 0
var _dead := false
var _death_deferred := false
var _last_authoritative_hit_event_id := -1
var _network_sync_time_accum := 0.0
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _remote_has_state := false
## HP before the latest incoming hit (authoritative combat); used for Edge overkill math.
var _edge_hp_before_last_hit: int = 0
var _edge_mark_until_msec: int = 0
## Execution (Expression): crit-applied prime window — bonus Edge damage + primed death overkill burst.
var _edge_primed_until_msec: int = 0
var _edge_bleed_until_msec: int = 0
var _edge_bleed_tick_damage: int = 0
var _edge_bleed_timer: Timer
var _edge_mark_glow_mi: MeshInstance3D
var _edge_mark_glow_mat: StandardMaterial3D
## Mass (Crush+): stagger → downed window, unstable launch tag, last melee source for wall/carrier procs.
var _mass_stagger_accum: float = 0.0
var _mass_downed_until_msec: int = 0
var _mass_unstable_until_msec: int = 0
var _mass_stun_mult_this_hit: float = 1.0
var _mass_last_melee_source: Node = null
## Echo Chorus: short window after a hit; next hit treats the enemy as “imprinted.”
var _echo_imprint_until_msec: int = 0
## Surge charge field: refreshed by authoritative players; TTL so order vs physics tick stays stable.
var _surge_field_speed_mult: float = 1.0
var _surge_field_expire_msec: int = 0
var _surge_field_cooldown_tick_mult: float = 1.0
var _surge_field_cooldown_expire_msec: int = 0
## Shared hit knockback window (Dasher / Robot / Sentinel); turrets opt out via `mass_infusion_receives_knockback`.
var _hit_knockback_vel := Vector2.ZERO
var _hit_knockback_time_rem := 0.0
var _mass_wall_carrier_cooldown_until_msec: int = 0
var _stagger_time_rem := 0.0
var _armor_spawn_config_enabled := false
var _armor_glow_mi: MeshInstance3D
var _armor_glow_mat: StandardMaterial3D


func get_combat_hurtbox() -> Hurtbox2D:
	return _hurtbox


func echo_infusion_imprint_active() -> bool:
	return Time.get_ticks_msec() < _echo_imprint_until_msec


func echo_infusion_refresh_imprint(duration_sec: float) -> void:
	if duration_sec <= 0.0 or not is_damage_authority():
		return
	var until := Time.get_ticks_msec() + int(duration_sec * 1000.0)
	_echo_imprint_until_msec = maxi(_echo_imprint_until_msec, until)


func _ready() -> void:
	_normalize_topdown_collision_footprint()
	if _health_component != null:
		_health_component.max_health = max_health
		_health_component.starting_health = max_health
		_health_component.set_current_health(max_health)
		_health_component.health_changed.connect(_on_health_component_changed)
		_health_component.armor_changed.connect(_on_health_component_armor_changed)
		_health_component.armor_damaged.connect(_on_health_component_armor_damaged)
		_health_component.armor_depleted.connect(_on_health_component_armor_depleted)
		_health_component.depleted.connect(_on_health_component_depleted)
		_health = _health_component.current_health
	if _damage_receiver != null:
		_damage_receiver.damage_applied.connect(_on_receiver_damage_applied)
		_damage_receiver.damage_rejected.connect(_on_receiver_damage_rejected)
	if _multiplayer_active() and not _is_server_peer():
		# Client enemy nodes are visual proxies only; server owns gameplay collisions.
		set_deferred(&"collision_layer", 0)
		set_deferred(&"collision_mask", 0)
		if _hurtbox != null:
			_hurtbox.set_active(false)
	elif _hurtbox != null:
		_hurtbox.set_active(true)
	_edge_bleed_timer = Timer.new()
	_edge_bleed_timer.wait_time = 0.45
	_edge_bleed_timer.one_shot = false
	_edge_bleed_timer.timeout.connect(_on_edge_bleed_timer_tick)
	add_child(_edge_bleed_timer)


func _exit_tree() -> void:
	_edge_mark_glow_free()
	_armor_glow_free()


func _process(_delta: float) -> void:
	_edge_mark_update_glow()
	_armor_update_glow()


func is_damage_authority() -> bool:
	return not _multiplayer_active() or _is_server_peer()


func _multiplayer_api_safe() -> MultiplayerAPI:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_multiplayer()


func _multiplayer_active() -> bool:
	var mp := _multiplayer_api_safe()
	return mp != null and mp.multiplayer_peer != null


func _is_server_peer() -> bool:
	var mp := _multiplayer_api_safe()
	return mp != null and mp.multiplayer_peer != null and mp.is_server()


func _can_broadcast_world_replication() -> bool:
	if not _multiplayer_active():
		return false
	if not _is_server_peer():
		return true
	var session := get_node_or_null("/root/NetworkSession")
	if session != null and session.has_method("can_broadcast_world_replication"):
		return bool(session.call("can_broadcast_world_replication"))
	return true


func _enemy_network_compact_state() -> Dictionary:
	var state := {}
	_armor_network_merge_into(state)
	return state


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_armor_network_read_from(state)


func _enemy_network_server_broadcast(delta: float) -> void:
	if not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_network_sync_time_accum += delta
	if _network_sync_time_accum < network_sync_interval:
		return
	_network_sync_time_accum = 0.0
	var cs := _enemy_network_compact_state()
	_edge_network_merge_mark_and_prime_into(cs)
	var net_id := _enemy_network_id()
	if net_id <= 0:
		return
	var orchestrator := _resolve_network_orchestrator()
	if orchestrator == null or not orchestrator.has_method(&"broadcast_enemy_transform_state"):
		return
	orchestrator.call(&"broadcast_enemy_transform_state", net_id, global_position, velocity, cs)


func _enemy_network_id() -> int:
	if has_meta(&"enemy_network_id"):
		return int(get_meta(&"enemy_network_id", 0))
	return 0


func _resolve_network_orchestrator() -> Node:
	var world := get_parent()
	if world == null:
		return null
	return world.get_parent()


func apply_remote_enemy_transform_state(
	world_pos: Vector2, planar_velocity: Vector2, compact_state: Dictionary
) -> void:
	if _is_server_peer():
		return
	_remote_target_position = world_pos
	_remote_target_velocity = planar_velocity
	_remote_has_state = true
	_edge_network_read_mark_and_prime_from(compact_state)
	_enemy_network_apply_remote_state(compact_state)


func _enemy_network_client_interpolate(delta: float) -> void:
	if not _remote_has_state:
		return
	var dist_to_target := global_position.distance_to(_remote_target_position)
	if dist_to_target >= remote_interpolation_snap_distance:
		global_position = _remote_target_position
		velocity = _remote_target_velocity
		return
	var alpha := clampf(delta * remote_interpolation_lerp_rate, 0.0, 1.0)
	global_position = global_position.lerp(_remote_target_position, alpha)
	velocity = velocity.lerp(_remote_target_velocity, alpha)


func configure_spawn(start_position: Vector2, _player_position: Vector2) -> void:
	global_position = start_position


func apply_enemy_spawn_config(spawn_config: Dictionary) -> void:
	if spawn_config.is_empty():
		return
	if not bool(spawn_config.get("armored", false)):
		return
	var max_armor := int(spawn_config.get("max_armor", 0))
	var current_armor := int(spawn_config.get("armor", max_armor))
	if max_armor <= 0:
		var multiplier := float(spawn_config.get("armor_multiplier", armor_health_multiplier))
		max_armor = _default_armor_amount(multiplier)
	if current_armor < 0 or not spawn_config.has("armor"):
		current_armor = max_armor
	_set_armor_amount(max_armor)
	if _health_component != null:
		_health_component.current_armor = clampi(current_armor, 0, max_armor)
		if _health_component.is_inside_tree():
			_health_component.set_current_armor(current_armor)
	_update_process_enabled()


func get_enemy_spawn_config() -> Dictionary:
	var config := {}
	if _is_armor_configured():
		config["armored"] = true
		config["armor"] = _current_armor_value()
		config["max_armor"] = _max_armor_value()
		config["armor_multiplier"] = armor_health_multiplier
	return config


func move_and_slide_with_mob_separation() -> bool:
	apply_universal_stagger_stop(get_physics_process_delta_time(), false)
	_apply_mob_separation_to_velocity()
	var collided := move_and_slide()
	_apply_mob_contact_squeeze()
	return collided


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func surge_infusion_tick_server_field_decay() -> void:
	if not is_damage_authority():
		return
	var now := Time.get_ticks_msec()
	if now > _surge_field_expire_msec:
		_surge_field_speed_mult = 1.0
	if now > _surge_field_cooldown_expire_msec:
		_surge_field_cooldown_tick_mult = 1.0


func surge_infusion_refresh_charge_field(
	move_speed_mult: float, cooldown_tick_mult: float, ttl_msec: int
) -> void:
	if not is_damage_authority():
		return
	var now := Time.get_ticks_msec()
	var until := now + maxi(1, ttl_msec)
	_surge_field_speed_mult = minf(_surge_field_speed_mult, clampf(move_speed_mult, 0.1, 1.0))
	_surge_field_expire_msec = maxi(_surge_field_expire_msec, until)
	_surge_field_cooldown_tick_mult = minf(
		_surge_field_cooldown_tick_mult, clampf(cooldown_tick_mult, 0.15, 1.0)
	)
	_surge_field_cooldown_expire_msec = maxi(_surge_field_cooldown_expire_msec, until)


func surge_infusion_field_move_speed_factor() -> float:
	return _surge_field_speed_mult


func surge_infusion_field_cooldown_tick_factor() -> float:
	return _surge_field_cooldown_tick_mult


func surge_infusion_bump_action_delay(_seconds: float) -> void:
	pass


func set_aggro_enabled(_enabled: bool) -> void:
	pass


func refresh_enemy_target_player(
	delta: float,
	current_target: Variant,
	refresh_time_remaining: float,
	target_refresh_interval_sec: float,
	allow_retarget: bool = true,
	picker: Callable = Callable()
) -> Dictionary:
	var next_refresh_time_remaining := maxf(0.0, refresh_time_remaining - delta)
	var target: Node2D = null
	if current_target != null and is_instance_valid(current_target) and current_target is Node2D:
		target = current_target as Node2D
	var target_invalid := target == null
	if target_invalid or (allow_retarget and next_refresh_time_remaining <= 0.0):
		var pick_target := picker
		if not pick_target.is_valid():
			pick_target = Callable(self, "_pick_nearest_player_target")
		var picked: Variant = pick_target.call()
		target = picked as Node2D if picked != null and is_instance_valid(picked) and picked is Node2D else null
		next_refresh_time_remaining = maxf(0.05, target_refresh_interval_sec)
	return {
		"target": target,
		"refresh_time_remaining": next_refresh_time_remaining,
	}


func build_single_scene_visual_state_config(
	scene: PackedScene,
	scene_scale: Variant = null,
	idle_keywords: Array = [],
	walk_keywords: Array = []
) -> Dictionary:
	if scene == null:
		return {}
	var idle_state := {
		"scene": scene,
		"keywords": idle_keywords.duplicate(),
	}
	var walk_state := {
		"scene": scene,
		"keywords": walk_keywords.duplicate(),
	}
	if scene_scale != null:
		idle_state["scene_scale"] = scene_scale
		walk_state["scene_scale"] = scene_scale
	return {
		&"idle": idle_state,
		&"walk": walk_state,
	}


## Planar forward used for combat hooks (e.g. backstab); override when visuals use dedicated facing state.
func get_combat_planar_facing() -> Vector2:
	if velocity.length_squared() > 1e-4:
		return velocity.normalized()
	var p := _pick_nearest_player_target()
	if p != null:
		var to_p := p.global_position - global_position
		if to_p.length_squared() > 1e-6:
			return to_p.normalized()
	return Vector2(0.0, -1.0)


func apply_authoritative_hit_event(
	hit_event_id: int,
	damage: int,
	knockback_dir: Vector2,
	knockback_strength: float,
	from_backstab: bool = false,
	is_critical: bool = false
) -> bool:
	if hit_event_id >= 0 and hit_event_id <= _last_authoritative_hit_event_id:
		return false
	if hit_event_id >= 0:
		_last_authoritative_hit_event_id = hit_event_id
	var packet := _build_damage_packet(
		damage,
		&"player_attack",
		global_position - knockback_dir.normalized(),
		knockback_dir,
		knockback_strength,
		false,
		hit_event_id,
		from_backstab,
		is_critical
	)
	_receive_packet(packet)
	return true


func take_hit(
	damage: int,
	knockback_dir: Vector2,
	knockback_strength: float,
	from_backstab: bool = false,
	is_critical: bool = false
) -> void:
	var packet := _build_damage_packet(
		damage,
		&"player_attack",
		global_position - knockback_dir.normalized(),
		knockback_dir,
		knockback_strength,
		false,
		-1,
		from_backstab,
		is_critical
	)
	_receive_packet(packet)


## Splash / overkill spill entry (suppress_edge_procs expected on `packet`).
func take_direct_damage_packet(packet: DamagePacket) -> void:
	_receive_packet(packet)


func _receive_packet(packet: DamagePacket) -> void:
	if _damage_receiver == null:
		return
	if is_damage_authority() and packet != null:
		_edge_snap_hp_before_hit()
		if not packet.suppress_edge_procs:
			_edge_preprocess_incoming(packet)
		if not packet.suppress_mass_procs:
			_mass_preprocess_incoming(packet)
		_apply_base_player_knockback_mass_gate(packet)
	_damage_receiver.receive_damage(packet, _hurtbox)


func _resolve_player_mass_knockback_source(packet: DamagePacket) -> Node:
	if packet == null:
		return null
	var src: Node = packet.source_node
	if src == null or not is_instance_valid(src):
		return null
	if src.has_method(&"_infusion_mass_threshold"):
		return src
	if src.has_method(&"get_knockback_attribution_owner"):
		var o: Variant = src.call(&"get_knockback_attribution_owner")
		if is_instance_valid(o) and o is Node:
			return o as Node
	return null


## Zero baseline player knockback until Mass is attuned; Dasher mobs still get displaced.
func _apply_base_player_knockback_mass_gate(packet: DamagePacket) -> void:
	if packet == null:
		return
	if packet.knockback <= 0.0001:
		return
	if self is DasherMob:
		return
	var attacker := _resolve_player_mass_knockback_source(packet)
	if attacker == null or not attacker.has_method(&"_infusion_mass_threshold"):
		return
	var mt: int = int(attacker.call(&"_infusion_mass_threshold"))
	if InfusionMassRef.is_mass_attuned(mt):
		return
	packet.knockback = 0.0


func _build_damage_packet(
	damage: int,
	kind: StringName,
	origin: Vector2,
	direction: Vector2,
	knockback_strength: float,
	blockable: bool,
	attack_instance_id: int = -1,
	from_backstab: bool = false,
	is_critical: bool = false
) -> DamagePacket:
	var packet := DamagePacketScript.new() as DamagePacket
	packet.amount = damage
	packet.kind = kind
	packet.origin = origin
	packet.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO
	packet.knockback = knockback_strength
	packet.blockable = blockable
	packet.apply_iframes = false
	packet.attack_instance_id = attack_instance_id
	packet.debug_label = &"enemy_receive"
	packet.from_backstab = from_backstab
	packet.is_critical = is_critical
	return packet


func _on_receiver_damage_applied(packet: DamagePacket, hp_damage: int, _hurtbox_area: Area2D) -> void:
	if hp_damage <= 0:
		return
	_health = _health_component.current_health if _health_component != null else _health
	if show_damage_text:
		var from_splash := packet.debug_label == &"edge_kill_splash"
		_show_floating_damage_text(
			hp_damage, packet.from_backstab, packet.is_critical, from_splash
		)
		_broadcast_damage_text(
			hp_damage, DAMAGE_TEXT_STYLE_HP, packet.from_backstab, packet.is_critical, from_splash
		)
	if is_damage_authority():
		_mass_stun_mult_this_hit = _mass_resolve_stun_mult_for_packet(packet)
		_mass_note_last_melee_source(packet)
		_edge_after_damage_applied(packet)
		_edge_apply_sever_mark_after_crit(packet)
		_mass_after_melee_damage_applied(packet, hp_damage)
	if _health > 0 and not has_active_armor():
		_on_nonlethal_hit(packet.direction, packet.knockback)
	if is_damage_authority():
		_mass_stun_mult_this_hit = 1.0


func _on_receiver_damage_rejected(
	packet: DamagePacket, reason: StringName, _hurtbox_area: Area2D
) -> void:
	if reason != &"blocked_guard" or packet == null:
		return
	var blocked_damage := maxi(0, int(packet.amount))
	if blocked_damage <= 0:
		return
	if show_damage_text:
		_show_floating_damage_text_at(blocked_damage, global_position, DAMAGE_TEXT_STYLE_BLOCK)
		_broadcast_damage_text(blocked_damage, DAMAGE_TEXT_STYLE_BLOCK)


func _on_health_component_changed(current: int, _maximum: int) -> void:
	_health = current


func _on_health_component_armor_changed(current: int, maximum: int) -> void:
	_broadcast_armor_state(current, maximum)
	_update_process_enabled()


func _on_health_component_armor_damaged(
	packet: DamagePacket, armor_damage: int, current: int, _maximum: int
) -> void:
	if armor_damage <= 0 or packet == null:
		return
	if show_damage_text:
		var armor_text := "-%s ARMOR" % [armor_damage]
		_show_floating_combat_text_at(armor_text, DAMAGE_TEXT_ARMOR_COLOR, global_position)
		_broadcast_combat_text(armor_text, DAMAGE_TEXT_STYLE_ARMOR)
	if current <= 0 and show_damage_text:
		_show_floating_combat_text_at("ARMOR BREAK", DAMAGE_TEXT_ARMOR_COLOR, global_position)
		_broadcast_combat_text("ARMOR BREAK", DAMAGE_TEXT_STYLE_ARMOR)
	_update_process_enabled()


func _on_health_component_armor_depleted(_packet: DamagePacket) -> void:
	_update_process_enabled()


func _on_health_component_depleted(packet: DamagePacket) -> void:
	_health = 0
	if is_damage_authority():
		_edge_on_lethal(packet)
	if _should_defer_death(packet):
		_death_deferred = true
		_begin_deferred_death(packet)
		return
	squash()


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	_begin_universal_stagger()
	_apply_hit_knockback_impulse(knockback_dir, knockback_strength)


func has_active_armor() -> bool:
	return _health_component != null and _health_component.current_armor > 0


func is_universally_staggered() -> bool:
	return _stagger_time_rem > 0.0


func tick_universal_stagger(delta: float) -> void:
	if _stagger_time_rem <= 0.0:
		return
	_stagger_time_rem = maxf(0.0, _stagger_time_rem - delta)


func apply_universal_stagger_stop(delta: float, use_knockback: bool = true) -> bool:
	tick_universal_stagger(delta)
	if not is_universally_staggered():
		return false
	if use_knockback:
		tick_hit_knockback_timer(delta)
		if apply_hit_knockback_to_body_velocity():
			return true
	velocity = Vector2.ZERO
	return true


func cancel_active_attack_for_stagger() -> void:
	pass


func _begin_universal_stagger() -> void:
	if has_active_armor():
		return
	cancel_active_attack_for_stagger()
	_stagger_time_rem = maxf(_stagger_time_rem, universal_stagger_duration * _mass_stun_mult_this_hit)
	if show_damage_text:
		_show_floating_combat_text_at("STAGGER", DAMAGE_TEXT_STAGGER_COLOR, global_position)
		_broadcast_combat_text("STAGGER", DAMAGE_TEXT_STYLE_STAGGER)


func _default_armor_amount(multiplier: float = DEFAULT_ARMOR_HEALTH_MULTIPLIER) -> int:
	return maxi(1, int(roundf(float(maxi(1, max_health)) * maxf(0.0, multiplier))))


func _set_armor_amount(amount: int) -> void:
	if _health_component == null:
		_health_component = get_node_or_null("HealthComponent") as HealthComponent
	if _health_component == null:
		return
	var armor_amount := maxi(0, amount)
	_armor_spawn_config_enabled = armor_amount > 0
	_health_component.max_armor = armor_amount
	_health_component.starting_armor = armor_amount
	_health_component.current_armor = armor_amount
	if _health_component.is_inside_tree():
		_health_component.set_max_armor_value(armor_amount, false)
	_update_process_enabled()


func _is_armor_configured() -> bool:
	return _armor_spawn_config_enabled or _max_armor_value() > 0


func _current_armor_value() -> int:
	return _health_component.current_armor if _health_component != null else 0


func _max_armor_value() -> int:
	return _health_component.max_armor if _health_component != null else 0


func _armor_network_merge_into(state: Dictionary) -> void:
	if not _is_armor_configured():
		return
	state["ar"] = _current_armor_value()
	state["am"] = _max_armor_value()


func _armor_network_read_from(state: Dictionary) -> void:
	if not state.has("am"):
		return
	var max_armor := maxi(0, int(state.get("am", 0)))
	var current_armor := clampi(int(state.get("ar", max_armor)), 0, max_armor)
	if max_armor <= 0:
		return
	_set_armor_amount(max_armor)
	if _health_component != null:
		_health_component.current_armor = current_armor
		if _health_component.is_inside_tree():
			_health_component.set_current_armor(current_armor)
	_update_process_enabled()


func _update_process_enabled() -> void:
	if has_active_armor() or _edge_mark_active() or _edge_primed_active():
		set_process(true)


func mass_infusion_receives_knockback() -> bool:
	return true


func is_hit_knockback_active() -> bool:
	return _hit_knockback_time_rem > 0.0


func get_hit_knockback_velocity() -> Vector2:
	return _hit_knockback_vel


func apply_hit_knockback_to_body_velocity() -> bool:
	if _hit_knockback_time_rem <= 0.0:
		return false
	velocity = _hit_knockback_vel
	return true


func tick_hit_knockback_timer(delta: float) -> void:
	if _hit_knockback_time_rem <= 0.0:
		return
	_hit_knockback_time_rem = maxf(0.0, _hit_knockback_time_rem - delta)
	if _hit_knockback_time_rem <= 0.0:
		_hit_knockback_vel = Vector2.ZERO


func _apply_hit_knockback_impulse(knockback_dir: Vector2, knockback_strength: float) -> void:
	if not mass_infusion_receives_knockback():
		return
	if knockback_strength <= 0.0001:
		return
	if knockback_dir.length_squared() <= 0.0001:
		return
	var dir := knockback_dir.normalized()
	_hit_knockback_vel = dir * knockback_strength * knockback_impulse_scale
	_hit_knockback_time_rem = hit_knockback_duration


func mass_server_post_slide() -> void:
	if not is_damage_authority():
		return
	if _hit_knockback_time_rem <= 0.0:
		return
	if _hit_knockback_vel.length_squared() < 9.0:
		return
	var now := Time.get_ticks_msec()
	if now < _mass_wall_carrier_cooldown_until_msec:
		return
	var kb_n := _hit_knockback_vel.normalized()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider: Variant = col.get_collider()
		if collider == null:
			continue
		var n := col.get_normal()
		if kb_n.dot(n) > -0.12:
			continue
		if collider is CharacterBody2D and collider.is_in_group(&"mob") and collider is EnemyBase:
			_mass_dispatch_wall_carrier_impact(collider as EnemyBase, false, col)
			_mass_wall_carrier_cooldown_until_msec = now + 280
			return
		if collider is Area2D:
			continue
		_mass_dispatch_wall_carrier_impact(null, true, col)
		_mass_wall_carrier_cooldown_until_msec = now + 280
		return


func _mass_dispatch_wall_carrier_impact(other: EnemyBase, is_wall: bool, col: KinematicCollision2D) -> void:
	var src := _mass_last_melee_source
	if src == null or not is_instance_valid(src):
		return
	if not src.has_method(&"mass_infusion_dispatch_wall_carrier_impact"):
		return
	var impact := global_position
	var wn := Vector2.ZERO
	if col != null and col is KinematicCollision2D:
		var kc := col as KinematicCollision2D
		impact = kc.get_position()
		wn = kc.get_normal()
	src.call(&"mass_infusion_dispatch_wall_carrier_impact", self, other, is_wall, impact, wn)


func mass_broadcast_combat_vfx(kind: int, pos2: Vector2, dir2: Vector2, param: float = 0.0) -> void:
	_mass_combat_vfx_play_local(kind, pos2, dir2, param)
	if not _multiplayer_active() or not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_mass_combat_vfx.rpc(kind, pos2, dir2, param)


func _mass_combat_vfx_play_local(kind: int, pos2: Vector2, dir2: Vector2, param: float) -> void:
	if OS.has_feature("dedicated_server"):
		return
	var vw := _resolve_visual_world_3d()
	MassCombatVfxScript.play_on_visual_world(vw, kind, pos2, dir2, param)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_mass_combat_vfx(kind: int, pos2: Vector2, dir2: Vector2, param: float) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	_mass_combat_vfx_play_local(kind, pos2, dir2, param)


func edge_infusion_apply_sever_mark(edge_threshold: int) -> void:
	if not is_damage_authority():
		return
	var dur := InfusionEdgeRef.sever_mark_duration_sec(edge_threshold)
	if dur <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(dur * 1000.0)
	_edge_mark_until_msec = maxi(_edge_mark_until_msec, until)
	set_process(true)


func edge_infusion_apply_execution_prime(edge_threshold: int) -> void:
	if not is_damage_authority():
		return
	var dur := InfusionEdgeRef.execution_prime_duration_sec(edge_threshold)
	if dur <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(dur * 1000.0)
	_edge_primed_until_msec = maxi(_edge_primed_until_msec, until)
	set_process(true)


func _edge_mark_active() -> bool:
	return Time.get_ticks_msec() < _edge_mark_until_msec


func _edge_primed_active() -> bool:
	return Time.get_ticks_msec() < _edge_primed_until_msec


func edge_infusion_current_hp_for_chain() -> int:
	if _health_component != null:
		return _health_component.current_health
	return _health


func _edge_network_merge_mark_and_prime_into(s: Dictionary) -> void:
	if _edge_mark_active():
		s["em"] = maxf(0.0, float(_edge_mark_until_msec - Time.get_ticks_msec()) / 1000.0)
	else:
		s["em"] = 0.0
	if _edge_primed_active():
		s["ep"] = maxf(0.0, float(_edge_primed_until_msec - Time.get_ticks_msec()) / 1000.0)
	else:
		s["ep"] = 0.0


func _edge_network_read_mark_and_prime_from(s: Dictionary) -> void:
	var rem := float(s.get("em", 0.0))
	if rem <= 0.0001:
		_edge_mark_until_msec = 0
	else:
		_edge_mark_until_msec = Time.get_ticks_msec() + int(rem * 1000.0)
	var prem := float(s.get("ep", 0.0))
	if prem <= 0.0001:
		_edge_primed_until_msec = 0
	else:
		_edge_primed_until_msec = Time.get_ticks_msec() + int(prem * 1000.0)
	if _edge_mark_active() or _edge_primed_active():
		set_process(true)


func _edge_mark_glow_free() -> void:
	if _edge_mark_glow_mi != null and is_instance_valid(_edge_mark_glow_mi):
		_edge_mark_glow_mi.queue_free()
	_edge_mark_glow_mi = null
	_edge_mark_glow_mat = null


func _edge_mark_glow_ensure() -> void:
	if _edge_mark_glow_mi != null and is_instance_valid(_edge_mark_glow_mi):
		return
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = &"EdgeSeverMarkGlow"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.22, 0.15, 1.0)
	mat.emission_energy_multiplier = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	vw.add_child(mi)
	_edge_mark_glow_mi = mi
	_edge_mark_glow_mat = mat


func _edge_mark_update_glow() -> void:
	if not _edge_mark_active() and not _edge_primed_active():
		if _edge_mark_glow_mi != null and is_instance_valid(_edge_mark_glow_mi):
			_edge_mark_glow_mi.visible = false
		if not has_active_armor():
			set_process(false)
		return
	_edge_mark_glow_ensure()
	if _edge_mark_glow_mi == null or _edge_mark_glow_mat == null:
		return
	_edge_mark_glow_mi.visible = true
	var p2 := global_position
	_edge_mark_glow_mi.global_position = Vector3(p2.x, edge_mark_glow_center_y, p2.y)
	var t := float(Time.get_ticks_msec()) / 1000.0
	var breathe := 0.5 + 0.5 * sin(t * TAU * edge_mark_glow_pulse_hz)
	var em_mult := 0.4 + breathe * 1.85
	var alpha := 0.1 + breathe * 0.32
	_edge_mark_glow_mat.emission_energy_multiplier = em_mult
	_edge_mark_glow_mat.albedo_color = Color(1.0, 0.08 + breathe * 0.12, 0.05, alpha)
	var prim_scale := 2.0 if _edge_primed_active() else 1.0
	var s := edge_mark_glow_sphere_radius * lerpf(0.9, 1.12, breathe) * prim_scale
	_edge_mark_glow_mi.scale = Vector3(s, s, s)


func _armor_glow_free() -> void:
	if _armor_glow_mi != null and is_instance_valid(_armor_glow_mi):
		_armor_glow_mi.queue_free()
	_armor_glow_mi = null
	_armor_glow_mat = null


func _armor_glow_ensure() -> void:
	if _armor_glow_mi != null and is_instance_valid(_armor_glow_mi):
		return
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = &"ArmorDebugGlow"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.albedo_color = Color(1.0, 0.82, 0.05, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.82, 0.05, 1.0)
	mat.emission_energy_multiplier = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	vw.add_child(mi)
	_armor_glow_mi = mi
	_armor_glow_mat = mat


func _armor_update_glow() -> void:
	if not has_active_armor():
		if _armor_glow_mi != null and is_instance_valid(_armor_glow_mi):
			_armor_glow_mi.visible = false
		if not _edge_mark_active() and not _edge_primed_active():
			set_process(false)
		return
	_armor_glow_ensure()
	if _armor_glow_mi == null or _armor_glow_mat == null:
		return
	_armor_glow_mi.visible = true
	var p2 := global_position
	_armor_glow_mi.global_position = Vector3(p2.x, armor_glow_center_y, p2.y)
	var t := float(Time.get_ticks_msec()) / 1000.0
	var breathe := 0.5 + 0.5 * sin(t * TAU * armor_glow_pulse_hz)
	_armor_glow_mat.emission_energy_multiplier = 0.75 + breathe * 1.35
	_armor_glow_mat.albedo_color = Color(1.0, 0.72 + breathe * 0.18, 0.05, 0.13 + breathe * 0.18)
	var armor_ratio := 1.0
	if _health_component != null and _health_component.max_armor > 0:
		armor_ratio = clampf(
			float(_health_component.current_armor) / float(_health_component.max_armor),
			0.0,
			1.0
		)
	var s := armor_glow_sphere_radius * lerpf(0.92, 1.08, breathe) * lerpf(0.82, 1.0, armor_ratio)
	_armor_glow_mi.scale = Vector3(s, s, s)


func _edge_snap_hp_before_hit() -> void:
	if _health_component != null:
		_edge_hp_before_last_hit = _health_component.current_health
	else:
		_edge_hp_before_last_hit = _health


func _edge_preprocess_incoming(packet: DamagePacket) -> void:
	if packet == null:
		return
	var atk := packet.source_node
	if atk == null or not atk.has_method(&"_infusion_edge_threshold"):
		return
	var edge_t := int(atk.call(&"_infusion_edge_threshold"))
	if InfusionEdgeRef.is_edge_attuned(edge_t) and _edge_mark_active():
		var mm := InfusionEdgeRef.sever_mark_damage_multiplier(edge_t)
		if mm > 1.0001:
			packet.amount = maxi(1, int(roundf(float(packet.amount) * mm)))
	if (
		InfusionEdgeRef.is_edge_attuned(edge_t)
		and _edge_primed_active()
		and edge_t >= int(InfusionConstantsRef.InfusionThreshold.EXPRESSION)
	):
		var pm := InfusionEdgeRef.execution_prime_edge_damage_multiplier(edge_t)
		if pm > 1.0001:
			packet.amount = maxi(1, int(roundf(float(packet.amount) * pm)))
	var exec_frac := InfusionEdgeRef.execution_base_hp_fraction(edge_t)
	if exec_frac <= 0.0001 or _health_component == null:
		return
	var mx := maxi(1, _health_component.max_health)
	var hp := _health_component.current_health
	if float(hp) / float(mx) <= exec_frac:
		packet.amount = maxi(packet.amount, maxi(1, hp))


func _edge_after_damage_applied(packet: DamagePacket) -> void:
	if packet == null or packet.suppress_edge_procs:
		return
	if packet.is_echo:
		return
	if packet.kind == &"edge_bleed":
		return
	if packet.is_critical:
		_edge_try_apply_bleed(packet)


func _is_player_melee_packet(packet: DamagePacket) -> bool:
	return (
		packet.kind == &"melee"
		or packet.kind == &"player_attack"
		or String(packet.debug_label) == "player_melee"
	)


## When Mass infusion is active, outgoing melee knockback is multiplied by this (higher = lighter / more displacement).
func mass_infusion_knockback_size_factor() -> float:
	return 1.0


func mass_infusion_is_downed() -> bool:
	return Time.get_ticks_msec() < _mass_downed_until_msec


func mass_infusion_consume_unstable_burst_if_active() -> bool:
	if Time.get_ticks_msec() >= _mass_unstable_until_msec:
		return false
	_mass_unstable_until_msec = 0
	return true


func mass_infusion_add_bonus_stun(_seconds: float) -> void:
	pass


func _mass_preprocess_incoming(packet: DamagePacket) -> void:
	if packet == null or not mass_infusion_is_downed():
		return
	if not _is_player_melee_packet(packet):
		return
	var atk: Node = packet.source_node
	if atk == null or not atk.has_method(&"_infusion_mass_threshold"):
		return
	var mt: int = int(atk.call(&"_infusion_mass_threshold"))
	var mm := InfusionMassRef.downed_melee_damage_multiplier(mt)
	if mm > 1.0001:
		packet.amount = maxi(1, int(roundf(float(packet.amount) * mm)))


func _mass_resolve_stun_mult_for_packet(packet: DamagePacket) -> float:
	if packet == null or packet.suppress_mass_procs:
		return 1.0
	if not _is_player_melee_packet(packet):
		return 1.0
	var atk: Node = packet.source_node
	if atk == null or not atk.has_method(&"_infusion_mass_threshold"):
		return 1.0
	var mt: int = int(atk.call(&"_infusion_mass_threshold"))
	return InfusionMassRef.hit_stun_duration_multiplier(mt)


func _mass_note_last_melee_source(packet: DamagePacket) -> void:
	if packet == null or packet.suppress_mass_procs:
		return
	if not _is_player_melee_packet(packet):
		return
	_mass_last_melee_source = packet.source_node


func _mass_after_melee_damage_applied(packet: DamagePacket, hp_damage: int) -> void:
	if hp_damage <= 0 or packet == null or packet.suppress_mass_procs:
		return
	if not _is_player_melee_packet(packet):
		return
	var atk: Node = packet.source_node
	if atk == null or not atk.has_method(&"_infusion_mass_threshold"):
		return
	var mt: int = int(atk.call(&"_infusion_mass_threshold"))
	var build := InfusionMassRef.stagger_build_per_melee_hit(mt)
	if build <= 0.0:
		return
	_mass_stagger_accum += build
	if mt < int(InfusionConstantsRef.InfusionThreshold.ESCALATED):
		return
	var th := InfusionMassRef.stagger_downed_threshold()
	if _mass_stagger_accum >= th:
		_mass_stagger_accum = 0.0
		var dur := InfusionMassRef.downed_duration_sec(mt)
		if dur > 0.0:
			var until := Time.get_ticks_msec() + int(dur * 1000.0)
			_mass_downed_until_msec = maxi(_mass_downed_until_msec, until)
			mass_infusion_add_bonus_stun(dur)
	var ukt := InfusionMassRef.unstable_launch_knockback_threshold(mt)
	if packet.knockback >= ukt:
		var uw := InfusionMassRef.unstable_window_sec(mt)
		if uw > 0.0:
			var u_until := Time.get_ticks_msec() + int(uw * 1000.0)
			_mass_unstable_until_msec = maxi(_mass_unstable_until_msec, u_until)


func _edge_apply_sever_mark_after_crit(packet: DamagePacket) -> void:
	if _health <= 0:
		return
	if packet == null or packet.suppress_edge_procs or packet.is_echo or not packet.is_critical:
		return
	if not _is_player_melee_packet(packet):
		return
	var atk := packet.source_node
	if atk == null or not atk.has_method(&"_infusion_edge_threshold"):
		return
	var edge_t := int(atk.call(&"_infusion_edge_threshold"))
	if edge_t < int(InfusionConstantsRef.InfusionThreshold.ESCALATED):
		return
	edge_infusion_apply_sever_mark(edge_t)
	if edge_t >= int(InfusionConstantsRef.InfusionThreshold.EXPRESSION):
		edge_infusion_apply_execution_prime(edge_t)


func _edge_try_apply_bleed(packet: DamagePacket) -> void:
	if _health <= 0:
		return
	if packet.suppress_edge_procs or not packet.is_critical:
		return
	var atk := packet.source_node
	if atk == null or not atk.has_method(&"_infusion_edge_threshold"):
		return
	var edge_t := int(atk.call(&"_infusion_edge_threshold"))
	var dps := InfusionEdgeRef.sever_bleed_dps(edge_t)
	var dur := InfusionEdgeRef.sever_bleed_duration_sec(edge_t)
	if dps <= 0 or dur <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(dur * 1000.0)
	_edge_bleed_until_msec = maxi(_edge_bleed_until_msec, until)
	_edge_bleed_tick_damage = maxi(_edge_bleed_tick_damage, dps)
	if _edge_bleed_timer != null and not _edge_bleed_timer.is_stopped():
		return
	_edge_bleed_timer.start()


func _on_edge_bleed_timer_tick() -> void:
	if not is_damage_authority() or _dead:
		_edge_bleed_timer.stop()
		return
	var now := Time.get_ticks_msec()
	if now >= _edge_bleed_until_msec or _edge_bleed_tick_damage <= 0:
		_edge_bleed_timer.stop()
		_edge_bleed_until_msec = 0
		_edge_bleed_tick_damage = 0
		return
	if _health_component == null or _damage_receiver == null:
		_edge_bleed_timer.stop()
		return
	var p := DamagePacketScript.new() as DamagePacket
	p.amount = maxi(1, _edge_bleed_tick_damage)
	p.kind = &"edge_bleed"
	p.source_node = null
	p.apply_iframes = false
	p.suppress_edge_procs = true
	p.debug_label = &"edge_bleed"
	_damage_receiver.receive_damage(p, _hurtbox)


func _edge_on_lethal(packet: DamagePacket) -> void:
	if packet == null or packet.suppress_edge_procs or packet.is_echo:
		return
	var atk := packet.source_node
	if atk == null:
		return
	var was_primed := _edge_primed_active()
	if atk.has_method(&"edge_infusion_dispatch_kill_procs"):
		atk.call(
			&"edge_infusion_dispatch_kill_procs", self, packet, _edge_hp_before_last_hit, was_primed
		)


func can_contact_damage() -> bool:
	return false


func _should_defer_death(_packet: DamagePacket) -> bool:
	return false


func _begin_deferred_death(_packet: DamagePacket) -> void:
	squash()


func is_death_deferred() -> bool:
	return _death_deferred


func squash() -> void:
	if _dead:
		return
	_dead = true
	_death_deferred = false
	squashed.emit()
	if drops_coin_on_death:
		_spawn_dropped_coin()
	queue_free()


func _spawn_dropped_coin() -> void:
	if not coin_drop_requested.get_connections().is_empty():
		coin_drop_requested.emit(global_position, maxi(1, coin_drop_value))
		return
	var parent := get_parent()
	if parent == null:
		return
	var coin := DROPPED_COIN_SCENE.instantiate() as Node2D
	if coin == null:
		return
	# add_child during body_entered / physics flush mutates Area2D state; defer to next idle/safe frame.
	coin.position = parent.to_local(global_position)
	parent.call_deferred("add_child", coin)


func _resolve_visual_world_3d() -> Node3D:
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		var direct := tree.current_scene.get_node_or_null("VisualWorld3D") as Node3D
		if direct != null:
			return direct
	var n: Node = self
	while n != null:
		var par := n.get_parent()
		if par == null:
			break
		var gpr := par.get_parent()
		if gpr != null:
			var vw := gpr.get_node_or_null("VisualWorld3D") as Node3D
			if vw != null:
				return vw
		n = par
	return null


func _show_floating_damage_text(
	damage: int,
	from_backstab: bool = false,
	is_critical: bool = false,
	from_splash: bool = false
) -> void:
	_show_floating_damage_text_at(
		damage, global_position, DAMAGE_TEXT_STYLE_HP, from_backstab, is_critical, from_splash
	)


func _show_floating_damage_text_at(
	damage: int,
	world_pos: Vector2,
	style_id: StringName = DAMAGE_TEXT_STYLE_HP,
	from_backstab: bool = false,
	is_critical: bool = false,
	from_splash: bool = false
) -> void:
	var text := "-%s HP" % [damage]
	var color := DAMAGE_TEXT_HP_COLOR
	if style_id == DAMAGE_TEXT_STYLE_BLOCK:
		text = "-%s BLOCK" % [damage]
		color = DAMAGE_TEXT_BLOCK_COLOR
	elif from_backstab or is_critical:
		text += " CRIT"
	if from_splash:
		text += " SPL"
	_show_floating_combat_text_at(text, color, world_pos)


func _show_floating_combat_text_at(text_value: String, color: Color, world_pos: Vector2) -> void:
	var vw := _resolve_visual_world_3d()
	if vw == null:
		return
	var text := Label3D.new()
	text.text = text_value
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.font_size = damage_text_font_size
	text.outline_size = 64
	text.outline_modulate = DAMAGE_TEXT_OUTLINE_COLOR
	text.modulate = color
	text.position = Vector3(world_pos.x, damage_text_world_y, world_pos.y)
	vw.add_child(text)
	var tween := text.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		text,
		"position",
		text.position + Vector3(0.0, damage_text_rise, 0.0),
		damage_text_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(text, "modulate:a", 0.0, damage_text_duration).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN
	)
	tween.chain().tween_callback(text.queue_free)


func _broadcast_damage_text(
	damage: int,
	style_id: StringName = DAMAGE_TEXT_STYLE_HP,
	from_backstab: bool = false,
	is_critical: bool = false,
	from_splash: bool = false
) -> void:
	if not _multiplayer_active() or not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_show_damage_text.rpc(
		damage, global_position, style_id, from_backstab, is_critical, from_splash
	)


func _broadcast_combat_text(text_value: String, style_id: StringName = DAMAGE_TEXT_STYLE_HP) -> void:
	if not _multiplayer_active() or not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_show_combat_text.rpc(text_value, global_position, style_id)


func _broadcast_armor_state(current: int, maximum: int) -> void:
	if not _multiplayer_active() or not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_apply_armor_state.rpc(current, maximum)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_show_damage_text(
	damage: int,
	world_pos: Vector2,
	style_id: StringName = DAMAGE_TEXT_STYLE_HP,
	from_backstab: bool = false,
	is_critical: bool = false,
	from_splash: bool = false
) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	_show_floating_damage_text_at(
		damage, world_pos, style_id, from_backstab, is_critical, from_splash
	)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_show_combat_text(
	text_value: String, world_pos: Vector2, style_id: StringName = DAMAGE_TEXT_STYLE_HP
) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	var color := DAMAGE_TEXT_HP_COLOR
	if style_id == DAMAGE_TEXT_STYLE_ARMOR:
		color = DAMAGE_TEXT_ARMOR_COLOR
	elif style_id == DAMAGE_TEXT_STYLE_STAGGER:
		color = DAMAGE_TEXT_STAGGER_COLOR
	elif style_id == DAMAGE_TEXT_STYLE_BLOCK:
		color = DAMAGE_TEXT_BLOCK_COLOR
	_show_floating_combat_text_at(text_value, color, world_pos)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_apply_armor_state(current: int, maximum: int) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
		return
	if maximum <= 0:
		return
	_set_armor_amount(maximum)
	if _health_component != null:
		_health_component.current_armor = clampi(current, 0, maximum)
		if _health_component.is_inside_tree():
			_health_component.set_current_armor(current)
	_update_process_enabled()


func _is_player_downed_node(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not candidate is Node2D:
		return false
	var player := candidate as Node2D
	if player.has_method(&"is_downed"):
		return bool(player.call(&"is_downed"))
	return false


func _is_targetable_player(candidate: Variant) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not candidate is Node2D:
		return false
	return not _is_player_downed_node(candidate)


func _peer_id_for_player_candidate(candidate: Variant) -> int:
	if candidate == null or not is_instance_valid(candidate) or not candidate is Node2D:
		return 0
	var player := candidate as Node2D
	var peer_id := int(player.get_meta(&"peer_id", 0))
	if peer_id <= 0 and player.has_meta(&"network_owner_peer_id"):
		peer_id = int(player.get_meta(&"network_owner_peer_id", 0))
	return peer_id


func _is_better_player_target_choice(
	candidate_d2: float,
	candidate_peer_id: int,
	candidate_name: String,
	best_d2: float,
	best_peer_id: int,
	best_name: String
) -> bool:
	if not is_equal_approx(candidate_d2, best_d2):
		return candidate_d2 < best_d2
	if candidate_peer_id != best_peer_id:
		return candidate_peer_id < best_peer_id
	return candidate_name < best_name


func _pick_nearest_player_target() -> Node2D:
	var best_node: Node2D = null
	var best_d2 := INF
	var best_peer_id := 0
	var best_name := ""
	for candidate in _targetable_player_candidates():
		if not _is_targetable_player(candidate):
			continue
		var candidate_d2 := global_position.distance_squared_to(candidate.global_position)
		var candidate_peer_id := _peer_id_for_player_candidate(candidate)
		var candidate_name := String(candidate.name)
		if (
			best_node == null
			or _is_better_player_target_choice(
				candidate_d2,
				candidate_peer_id,
				candidate_name,
				best_d2,
				best_peer_id,
				best_name
			)
		):
			best_node = candidate
			best_d2 = candidate_d2
			best_peer_id = candidate_peer_id
			best_name = candidate_name
	return best_node


func _targetable_player_candidates() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return out
	var tree_id := tree.get_instance_id()
	var now_usec := Time.get_ticks_usec()
	if (
		tree_id != _cached_player_tree_id
		or now_usec - _cached_player_snapshot_usec >= _PLAYER_ROSTER_CACHE_INTERVAL_USEC
	):
		_cached_player_nodes.clear()
		for node in tree.get_nodes_in_group(&"player"):
			if is_instance_valid(node) and node is Node2D:
				_cached_player_nodes.append(node)
		_cached_player_tree_id = tree_id
		_cached_player_snapshot_usec = now_usec
	for node in _cached_player_nodes:
		if is_instance_valid(node) and node is Node2D:
			out.append(node as Node2D)
	return out


func ignore_player_body_collisions() -> void:
	for candidate in _targetable_player_candidates():
		if is_instance_valid(candidate) and candidate is CollisionObject2D:
			add_collision_exception_with(candidate as CollisionObject2D)


func _normalize_topdown_collision_footprint() -> void:
	var body_shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape_node != null:
		_convert_shape_node_to_footprint_circle(body_shape_node)
	if _hurtbox != null:
		var hurtbox_shape_node := _hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurtbox_shape_node != null:
			_convert_shape_node_to_footprint_circle(hurtbox_shape_node)


func _convert_shape_node_to_footprint_circle(shape_node: CollisionShape2D) -> void:
	if shape_node == null or shape_node.shape == null:
		return
	var shape := shape_node.shape
	if shape is CircleShape2D:
		var circle := shape as CircleShape2D
		var footprint := circle.duplicate() as CircleShape2D
		footprint.radius = maxf(0.05, circle.radius * topdown_collision_radius_scale)
		shape_node.shape = footprint
		return
	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		var radius := maxf(rect.size.x, rect.size.y) * 0.5 * topdown_collision_radius_scale
		var footprint := CircleShape2D.new()
		footprint.radius = maxf(0.05, radius)
		shape_node.shape = footprint


func _apply_mob_separation_to_velocity() -> void:
	if not is_damage_authority():
		return
	if velocity.length_squared() <= 0.0001:
		return
	var desired_speed := velocity.length()
	var desired_dir := velocity / desired_speed
	var steer := desired_dir + _mob_separation_vector(desired_dir) * mob_separation_strength
	if steer.length_squared() <= 0.0001:
		return
	steer = steer.normalized()
	if steer.dot(desired_dir) < mob_min_forward_bias:
		steer = (desired_dir * mob_min_forward_bias + steer).normalized()
	velocity = steer * desired_speed


func _mob_separation_vector(desired_dir: Vector2) -> Vector2:
	if desired_dir.length_squared() <= 0.0001:
		return Vector2.ZERO
	var my_radius := _body_footprint_radius()
	if my_radius <= 0.0:
		return Vector2.ZERO
	var steer := Vector2.ZERO
	for candidate in _targetable_mob_candidates():
		if candidate == self or not is_instance_valid(candidate):
			continue
		if candidate is CollisionObject2D and (candidate as CollisionObject2D).collision_layer == 0:
			continue
		var delta := global_position - candidate.global_position
		if delta.length_squared() <= 0.000001:
			var deterministic_sign := -1.0 if get_instance_id() < candidate.get_instance_id() else 1.0
			delta = Vector2(deterministic_sign, 0.0)
		var other_radius := _mob_footprint_radius_for(candidate)
		if other_radius <= 0.0:
			continue
		var interaction_radius := my_radius + other_radius + mob_separation_extra_margin
		var dist_sq := delta.length_squared()
		if dist_sq >= interaction_radius * interaction_radius:
			continue
		var dist := sqrt(dist_sq)
		var away := delta / maxf(dist, 0.0001)
		var proximity := clampf((interaction_radius - dist) / interaction_radius, 0.0, 1.0)
		steer += away * proximity
		var tangent := Vector2(-away.y, away.x)
		if tangent.dot(desired_dir) < 0.0:
			tangent = -tangent
		steer += tangent * proximity * mob_slide_bias
	return steer


func _apply_mob_contact_squeeze() -> void:
	if not is_damage_authority():
		return
	if velocity.length_squared() <= 0.0001:
		return
	var my_radius := _body_footprint_radius()
	if my_radius <= 0.0:
		return
	var desired_speed := velocity.length()
	var squeeze_from_speed := desired_speed * get_physics_process_delta_time() * mob_squeeze_velocity_factor
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var other_v: Variant = collision.get_collider()
		if other_v == null or other_v is not EnemyBase:
			continue
		var other := other_v as EnemyBase
		if other == self or not is_instance_valid(other):
			continue
		if other.get_instance_id() < get_instance_id():
			continue
		if not other.is_damage_authority():
			continue
		var other_radius := other._body_footprint_radius()
		if other_radius <= 0.0:
			continue
		var separation_axis := collision.get_normal()
		if separation_axis.length_squared() <= 0.0001:
			separation_axis = global_position - other.global_position
		if separation_axis.length_squared() <= 0.0001:
			var deterministic_sign := -1.0 if get_instance_id() < other.get_instance_id() else 1.0
			separation_axis = Vector2(deterministic_sign, 0.0)
		separation_axis = separation_axis.normalized()
		var center_delta := other.global_position - global_position
		var center_dist := center_delta.length()
		var overlap := my_radius + other_radius - center_dist
		var squeeze_amount := clampf(
			maxf(mob_squeeze_min_push, overlap * 0.5 + squeeze_from_speed),
			0.0,
			mob_squeeze_max_push
		)
		if squeeze_amount <= 0.0:
			continue
		var other_share := clampf(mob_squeeze_transfer_ratio, 0.0, 1.0)
		var self_share := 1.0 - other_share
		global_position += separation_axis * squeeze_amount * self_share
		other.global_position -= separation_axis * squeeze_amount * other_share


func _body_footprint_radius() -> float:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	return _footprint_radius_for_shape_node(shape_node)


func _mob_footprint_radius_for(candidate: Node2D) -> float:
	if candidate == null:
		return 0.0
	if candidate.has_method("_body_footprint_radius"):
		return float(candidate.call("_body_footprint_radius"))
	var shape_node := candidate.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return _footprint_radius_for_shape_node(shape_node)


func _footprint_radius_for_shape_node(shape_node: CollisionShape2D) -> float:
	if shape_node == null or shape_node.shape == null:
		return 0.0
	var shape := shape_node.shape
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius * _max_abs_component(shape_node.global_scale)
	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		return minf(rect.size.x, rect.size.y) * 0.5 * _max_abs_component(shape_node.global_scale)
	return 0.0


func _targetable_mob_candidates() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return out
	var tree_id := tree.get_instance_id()
	var now_usec := Time.get_ticks_usec()
	if (
		tree_id != _cached_mob_tree_id
		or now_usec - _cached_mob_snapshot_usec >= _MOB_ROSTER_CACHE_INTERVAL_USEC
	):
		_cached_mob_nodes.clear()
		for node in tree.get_nodes_in_group(&"mob"):
			if is_instance_valid(node) and node is Node2D:
				_cached_mob_nodes.append(node)
		_cached_mob_tree_id = tree_id
		_cached_mob_snapshot_usec = now_usec
	for node in _cached_mob_nodes:
		if is_instance_valid(node) and node is Node2D:
			out.append(node as Node2D)
	return out


func _max_abs_component(v: Vector2) -> float:
	return maxf(absf(v.x), absf(v.y))
