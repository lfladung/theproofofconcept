extends CharacterBody2D
class_name EnemyBase

signal squashed
signal coin_drop_requested(spawn_position: Vector2, coin_value: int)

const DROPPED_COIN_SCENE := preload("res://dungeon/modules/gameplay/dropped_coin.tscn")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const InfusionEdgeRef = preload("res://scripts/infusion/infusion_edge.gd")
const InfusionMassRef = preload("res://scripts/infusion/infusion_mass.gd")
const InfusionConstantsRef = preload("res://scripts/infusion/infusion_constants.gd")
const DAMAGE_TEXT_STYLE_HP := &"hp"
const DAMAGE_TEXT_STYLE_BLOCK := &"block"
const DAMAGE_TEXT_HP_COLOR := Color(1.0, 0.15, 0.15, 1.0)
const DAMAGE_TEXT_BLOCK_COLOR := Color(0.25, 0.62, 1.0, 1.0)
const DAMAGE_TEXT_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const _PLAYER_ROSTER_CACHE_INTERVAL_USEC := 100000

static var _cached_player_nodes: Array = []
static var _cached_player_tree_id := 0
static var _cached_player_snapshot_usec := 0


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
## Edge Sever mark: pulsing red glow in VisualWorld3D (body center height in 3D, xz from 2D pos).
@export var edge_mark_glow_center_y := 1.05
@export var edge_mark_glow_sphere_radius := 1.45
@export var edge_mark_glow_pulse_hz := 0.65
@export var network_sync_interval := 0.05
@export var remote_interpolation_lerp_rate := 14.0
@export var remote_interpolation_snap_distance := 6.0

@onready var _health_component: HealthComponent = $HealthComponent
@onready var _damage_receiver: DamageReceiverComponent = $DamageReceiver
@onready var _hurtbox: Hurtbox2D = $EnemyHurtbox

var _health := 0
var _dead := false
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


func _ready() -> void:
	if _health_component != null:
		_health_component.max_health = max_health
		_health_component.starting_health = max_health
		_health_component.set_current_health(max_health)
		_health_component.health_changed.connect(_on_health_component_changed)
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


func _process(_delta: float) -> void:
	_edge_mark_update_glow()


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
	return {}


func _enemy_network_apply_remote_state(_state: Dictionary) -> void:
	pass


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
	_rpc_receive_enemy_transform_state.rpc(global_position, velocity, cs)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_enemy_transform_state(
	world_pos: Vector2, planar_velocity: Vector2, compact_state: Dictionary
) -> void:
	if _is_server_peer():
		return
	var mp := _multiplayer_api_safe()
	if mp == null or mp.get_remote_sender_id() != 1:
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


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func set_aggro_enabled(_enabled: bool) -> void:
	pass


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
	_damage_receiver.receive_damage(packet, _hurtbox)


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
	if _health > 0:
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


func _on_health_component_depleted(packet: DamagePacket) -> void:
	_health = 0
	if is_damage_authority():
		_edge_on_lethal(packet)
	squash()


func _on_nonlethal_hit(_knockback_dir: Vector2, _knockback_strength: float) -> void:
	pass


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
	if packet == null or packet.suppress_edge_procs or not packet.is_critical:
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
	if packet == null or packet.suppress_edge_procs:
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


func squash() -> void:
	if _dead:
		return
	_dead = true
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


func _is_player_downed_node(candidate: Node2D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if candidate.has_method(&"is_downed"):
		return bool(candidate.call(&"is_downed"))
	return false


func _is_targetable_player(candidate: Node2D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	return not _is_player_downed_node(candidate)


func _peer_id_for_player_candidate(candidate: Node2D) -> int:
	if candidate == null:
		return 0
	var peer_id := int(candidate.get_meta(&"peer_id", 0))
	if peer_id <= 0 and candidate.has_meta(&"network_owner_peer_id"):
		peer_id = int(candidate.get_meta(&"network_owner_peer_id", 0))
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
			if node is Node2D and is_instance_valid(node):
				_cached_player_nodes.append(node)
		_cached_player_tree_id = tree_id
		_cached_player_snapshot_usec = now_usec
	for node in _cached_player_nodes:
		if node is Node2D and is_instance_valid(node):
			out.append(node as Node2D)
	return out
