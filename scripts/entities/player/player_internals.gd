extends CharacterBody2D

## Gameplay, networking, combat, infusion, loadout. Debug mesh builders and `_physics_process` live in `player.gd`.


signal hit
signal health_changed(current: int, max_health: int)
signal stamina_changed(current: float, max_stamina: float)
signal weapon_mode_changed(display_name: String)
signal downed_state_changed(is_downed: bool)
signal loadout_changed(snapshot: Dictionary)
signal loadout_request_failed(message: String)

const ArrowProjectilePoolScript = preload("res://scripts/entities/arrow_projectile_pool.gd")
const PLAYER_BOMB_SCENE := preload("res://scenes/entities/player_bomb.tscn")
const PLAYER_VISUAL_SCENE := preload("res://scenes/visuals/player_visual.tscn")
const LoadoutConstantsRef = preload("res://scripts/loadout/loadout_constants.gd")
const InfusionConstantsRef = preload("res://scripts/infusion/infusion_constants.gd")
const InfusionEdgeRef = preload("res://scripts/infusion/infusion_edge.gd")
const InfusionFlowRef = preload("res://scripts/infusion/infusion_flow.gd")
const InfusionPhaseRef = preload("res://scripts/infusion/infusion_phase.gd")
const InfusionMassRef = preload("res://scripts/infusion/infusion_mass.gd")
const InfusionEchoRef = preload("res://scripts/infusion/infusion_echo.gd")
const InfusionAnchorRef = preload("res://scripts/infusion/infusion_anchor.gd")
const InfusionSurgeRef = preload("res://scripts/infusion/infusion_surge.gd")
const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")
const MassCombatVfxRef = preload("res://scripts/vfx/mass_combat_vfx.gd")
const _MULTIPLAYER_DEBUG_LOGGING := false
const REVIVE_HEALTH := 50

enum WeaponMode { SWORD, GUN, BOMB }

## Horizontal speed (matches former 3D XZ plane).
@export var speed := 14.0
## Feet stay grounded in this combat milestone.
@export var height := 0.0
## Max planar center distance for a kill; filters spurious Area2D body_entered at large separation.
@export var mob_kill_max_planar_dist := 6.5
@export var max_health := 100
@export var mob_hit_damage := 999
@export var hit_invulnerability_duration := 0.4
## Extra transparency during flash (0 = opaque, 1 = invisible). Alternates with fully opaque.
@export var hit_flash_transparency := 0.42
@export var hit_flash_blink_interval := 0.1

## Melee hit box along planar facing: starts just outside body circle, then depth × width (centered).
@export var melee_start_beyond_body := 0.03
@export var melee_depth := 6.0
@export var melee_width := 6.0
@export var attack_hitbox_visual_duration := 0.2
@export var melee_facing_lock_fallback_duration := 0.25
@export var melee_attack_cooldown := 0.5
@export var melee_attack_damage := 10
@export var melee_knockback_strength := 11.0
@export var melee_charge_commit_delay := 0.25
@export var melee_charge_max_time := 0.72
## Extra charge cap at Flow expression (combo window).
@export var flow_expression_combo_charge_bonus := 0.18
@export var melee_charge_min_ratio := 0.08
@export var melee_charge_damage_min_mult := 0.55
@export var melee_charge_damage_max_mult := 1.4
@export var melee_charge_knockback_min_mult := 0.72
@export var melee_charge_knockback_max_mult := 1.12
## Crit damage multiplier for melee (rear “backstab” counts as a guaranteed crit and uses this too).
@export var melee_backstab_damage_multiplier := 1.5
## Backstab if dot(from_enemy_to_attacker, enemy combat facing) <= this (0 = rear 180°).
@export var melee_backstab_facing_dot_threshold := 0.0
## Rolled crit chance before loadout `crit_chance_bonus` and Edge Sever windows.
@export var melee_base_crit_chance := 0.08
## Ground Y for debug mesh (XZ play plane ↔ 3D).
@export var melee_debug_ground_y := 0.04
@export var show_melee_hit_debug := false
## Y offset on XZ plane for body collision overlays (below melee quad so layers read clearly).
@export var hitbox_debug_ground_y := 0.028
@export var show_player_hitbox_debug := false
@export var show_mob_hitbox_debug := false
@export var show_shield_block_debug := false
@export var debug_visual_update_interval := 0.05
@export var hitbox_debug_circle_segments := 40
@export var dodge_speed := 50.0
@export var dodge_duration := 0.3
@export var dodge_cooldown := 1
@export var dash_stamina_cost := 5.0
@export var sprint_stamina_per_second := 1.0
@export var sprint_move_speed_multiplier := 1.35
@export var defend_move_speed_multiplier := 0.42
@export var defend_damage_multiplier := 1.0
@export var max_stamina := 100.0
@export var block_arc_degrees := 120.0
@export var stamina_regen_per_second := 10.0
@export var stamina_regen_delay := 1.0
@export var stamina_break_regen_delay := 5.0
## Ranged (gun) — aligned loosely with arrow towers.
@export var ranged_cooldown := 0.45
@export var ranged_damage := 15
@export var ranged_knockback := 8.0
@export var ranged_speed := 24.0
@export var ranged_max_tiles := 8.0
@export var ranged_spawn_beyond_body := 0.75
@export var ranged_charge_max_scale := 1.25
@export var world_units_per_tile := 3.0
## Thrown bomb: Tab cycles weapons (see project input map; Space is dodge).
@export var bomb_damage := 30
@export var bomb_cooldown := 2.0
@export var bomb_landing_distance := 14.0
@export var bomb_aoe_radius := 5.0
@export var bomb_flight_time := 0.48
@export var bomb_arc_start_height := 4.0
@export var bomb_knockback_strength := 0.0
## Milestone 3: movement input stream + server state replication.
@export var network_sync_interval := 0.05
@export var prediction_correction_snap_distance := 1.8
@export var prediction_correction_lerp_rate := 18.0
@export var remote_interpolation_lerp_rate := 14.0
@export var remote_interpolation_snap_distance := 6.0

@onready var _visual: Node3D
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _health_component: HealthComponent = $HealthComponent
@onready var _damage_receiver: PlayerDamageReceiverComponent = $DamageReceiver
@onready var _player_hurtbox: Hurtbox2D = $PlayerHurtbox
@onready var _melee_hitbox: Hitbox2D = $PlayerMeleeHitbox
@onready var _melee_hitbox_shape: CollisionShape2D = $PlayerMeleeHitbox/CollisionShape2D
## Infusion V1: debug F9/F10/F11 (debug builds). Future: `receive_infusion_*` + `_rpc_*` like `receive_pillar_bonus`.
@onready var infusion_manager = $InfusionManager

var health: int = 100
var stamina := 100.0
var _invuln_time_remaining := 0.0
var _stamina_regen_cooldown_remaining := 0.0
var _stamina_broken := false
## Last planar facing (2D x,y ↔ 3D x,z); default “forward” for attacks when idle.
var _facing_planar := Vector2(0.0, -1.0)

var _melee_debug_mi: MeshInstance3D
var _melee_debug_mat: StandardMaterial3D
var _player_hitbox_mi: MeshInstance3D
var _player_hitbox_mat: StandardMaterial3D
var _mob_hitboxes_mi: MeshInstance3D
var _mob_hitbox_mat: StandardMaterial3D
var _shield_block_debug_mi: MeshInstance3D
var _shield_block_debug_mat: StandardMaterial3D
var _cached_visual_mesh_instances: Array[MeshInstance3D] = []
var _debug_visual_refresh_time_remaining := 0.0
var _last_invulnerability_flash_state := -1
var _dodge_time_remaining := 0.0
var _dodge_cooldown_remaining := 0.0
var _dodge_direction := Vector2.ZERO
var _sprint_latch_after_dodge := false
var _is_dead := false
var _is_defending := false
var _attack_hitbox_visual_time_remaining := 0.0
var _facing_lock_time_remaining := 0.0
var _facing_lock_planar := Vector2(0.0, -1.0)
var _active_melee_attack_facing := Vector2(0.0, -1.0)
var _melee_attack_cooldown_remaining := 0.0
var weapon_mode: WeaponMode = WeaponMode.SWORD
var _ranged_cooldown_remaining := 0.0
var _bomb_cooldown_remaining := 0.0
var _rmb_down := false
var _lmb_down := false
var _external_move_speed_multipliers: Dictionary = {}
const _MELEE_CHARGE_SRC_NONE := 0
const _MELEE_CHARGE_SRC_MELEE_ACTION := 1
const _MELEE_CHARGE_SRC_MOUSE_PRIMARY := 2
var _melee_charging := false
var _melee_charge_pre_hold_time := 0.0
var _melee_charge_past_commit_delay := false
var _melee_charge_time := 0.0
var _melee_charge_input_source := _MELEE_CHARGE_SRC_NONE
var _ranged_charging := false
var _ranged_charge_pre_hold_time := 0.0
var _ranged_charge_past_commit_delay := false
var _ranged_charge_time := 0.0
var _ranged_charge_input_source := _MELEE_CHARGE_SRC_NONE
## Right-click attacks: face mouse this frame, resolve attack next physics frame.
var _pending_rmb_kind: StringName = &""
var _pending_rmb_facing := Vector2(0.0, -1.0)
var network_owner_peer_id := 1
var _remote_planar_speed := 0.0
var _net_sync_time_accum := 0.0
var _input_sequence := 0
var _last_acknowledged_input_sequence := -1
var _pending_input_commands: Array[Dictionary] = []
var _local_prev_dodge_down := false
var _server_last_input_sequence := -1
var _server_input_move_active := false
var _server_input_target_world := Vector2.ZERO
var _server_input_aim_planar := Vector2.ZERO
var _server_input_dodge_down := false
var _server_prev_dodge_down := false
var _server_input_defend_down := false
var _server_has_received_input := false
var _local_weapon_switch_request_sequence := 0
var _server_last_weapon_switch_request_sequence := -1
var _local_melee_request_sequence := 0
var _server_last_melee_request_sequence := -1
var _server_melee_event_sequence := 0
var _server_melee_hit_event_sequence := 0
var _last_applied_melee_event_sequence := -1
var _local_ranged_request_sequence := 0
var _server_last_ranged_request_sequence := -1
var _server_ranged_event_sequence := 0
var _last_applied_ranged_event_sequence := -1
var _remote_ranged_projectiles_by_event_id: Dictionary = {}
var _local_bomb_request_sequence := 0
var _server_last_bomb_request_sequence := -1
var _server_bomb_event_sequence := 0
var _last_applied_bomb_event_sequence := -1
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _remote_has_state := false
var _reconcile_target_position := Vector2.ZERO
var _reconcile_target_velocity := Vector2.ZERO
var _reconcile_target_facing := Vector2(0.0, -1.0)
var _reconcile_target_dodge_time_remaining := 0.0
var _reconcile_target_dodge_cooldown_remaining := 0.0
var _reconcile_target_dodge_direction := Vector2.ZERO
var _reconcile_target_sprint_latch_after_dodge := false
var _reconcile_target_facing_lock_time_remaining := 0.0
var _reconcile_target_facing_lock_planar := Vector2(0.0, -1.0)
var _reconcile_target_external_dash_blocked := false
var _reconcile_target_external_movement_rooted := false
var _reconcile_target_external_root_origin := Vector2.ZERO
var _reconcile_target_external_root_pull_used := false
var _reconcile_target_leecher_escape_progress := 0.0
var _reconcile_target_latched_enemy_id := 0
var _reconcile_has_target := false
var _authoritative_weapon_mode_id := int(WeaponMode.SWORD)
var _authoritative_melee_cooldown_remaining := 0.0
var _authoritative_ranged_cooldown_remaining := 0.0
var _authoritative_bomb_cooldown_remaining := 0.0
var _authoritative_is_defending := false
var _authoritative_stamina := 100.0
var _authoritative_stamina_broken := false
var _loadout_host: Node
var _loadout_owner_id: StringName = &""
var _loadout_snapshot: Dictionary = {}
var _loadout_room_type_provider: Callable = Callable()
var _menu_input_blocked := false
var _cached_mouse_world_physics_frame := -1
var _cached_mouse_world := Vector2.ZERO
var _local_loadout_request_sequence := 0
var _server_last_loadout_request_sequence := -1
var _base_speed := 0.0
var _base_max_health := 0
var _base_melee_attack_damage := 0
var _base_ranged_damage := 0
var _base_bomb_damage := 0
var _base_defend_damage_multiplier := 1.0
## Accumulated stat bonuses granted by in-world pillars during the current run.
var _runtime_stat_bonuses: Dictionary = {}
## When non-empty, handgun shots use this style (latest infusion pickup); cleared when no infusions remain.
var _handgun_infusion_projectile_style: StringName = &""
## Edge Sever — post-kill precision window (server).
var _edge_sever_kill_window_until_sec: float = -1.0
var _edge_sever_kill_window_stored_bonus: float = 0.0
## Flow infusion — tempo / chain / Overdrive (decay on all peers; advances server-only in MP).
var _flow_tempo := 0.0
var _flow_chain_remaining := 0.0
var _flow_overdrive_remaining := 0.0
var _flow_aggression_remaining := 0.0
var _flow_last_action_kind := -1
## Mass Expression — melee hits that consumed a target build toward a shockwave proc.
var _mass_shockwave_hit_stacks := 0
## Anchor infusion — delayed damage reserve, micro-shield, bastion rooted state (server / offline authority).
var _anchor_pressure := 0.0
var _anchor_micro_shield := 0.0
var _anchor_bastion_charge := 0.0
var _anchor_rooted := false
var _anchor_critical_bastion := false
## Enemy-applied control states (server / offline authority).
var _external_dash_blocked := false
var _external_movement_rooted := false
var _external_root_origin_position := Vector2.ZERO
var _external_root_pull_used := false
var _external_leecher_escape_progress := 0.0
var _external_latched_enemy_id := 0
var _external_root_source_id := 0
var _external_leecher_break_count := 0
var _external_leecher_break_target := 0
var _external_dash_block_sources: Dictionary = {}
## Surge — charge-field debuffs, melee overcharge, overdrive (authoritative sim + mirrored field RPC).
var _surge_energy: float = 0.0
var _surge_melee_overcharge_time: float = 0.0
var _surge_overdrive_active: bool = false
var _surge_overdrive_energy_sink: float = 0.0
var _surge_field_pulse_accum: float = 0.0
var _surge_field_report_accum: float = 0.0
var _surge_server_field_active: bool = false
var _surge_server_field_charge_r: float = 0.0
var _surge_server_field_over_n: float = 0.0
var _surge_server_field_until_msec: int = 0
## Phase — slip body collision, skew ghost / dash / chip, fracture flank (server / offline authority).
var _phase_saved_body_collision_mask := -1
var _phase_slip_body_time_remaining := 0.0
var _phase_dash_trail_cooldown_remaining := 0.0
var _phase_contact_chip_cooldown_remaining := 0.0
var _last_phase_melee_snapshot_damage := 0
var _last_phase_melee_snapshot_knockback := 0.0
var _phase_aux_attack_serial := 0


func _ready() -> void:
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_visual = _resolve_or_create_visual_root(vw)
	if vw:
		_melee_debug_mi = MeshInstance3D.new()
		_melee_debug_mi.name = &"MeleeHitDebugMesh"
		_melee_debug_mat = StandardMaterial3D.new()
		_melee_debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_melee_debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_melee_debug_mat.albedo_color = Color(1.0, 0.35, 0.08, 0.42)
		_melee_debug_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_melee_debug_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vw.add_child(_melee_debug_mi)

		_player_hitbox_mi = MeshInstance3D.new()
		_player_hitbox_mi.name = &"PlayerHitboxDebugMesh"
		_player_hitbox_mat = StandardMaterial3D.new()
		_player_hitbox_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_player_hitbox_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_player_hitbox_mat.albedo_color = Color(0.55, 0.98, 0.62, 0.48)
		_player_hitbox_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_player_hitbox_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vw.add_child(_player_hitbox_mi)

		_mob_hitboxes_mi = MeshInstance3D.new()
		_mob_hitboxes_mi.name = &"MobHitboxesDebugMesh"
		_mob_hitbox_mat = StandardMaterial3D.new()
		_mob_hitbox_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mob_hitbox_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mob_hitbox_mat.albedo_color = Color(1.0, 0.52, 0.12, 0.48)
		_mob_hitbox_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mob_hitboxes_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vw.add_child(_mob_hitboxes_mi)

		_shield_block_debug_mi = MeshInstance3D.new()
		_shield_block_debug_mi.name = &"ShieldBlockDebugMesh"
		_shield_block_debug_mat = StandardMaterial3D.new()
		_shield_block_debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shield_block_debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shield_block_debug_mat.albedo_color = Color(0.18, 0.48, 1.0, 0.4)
		_shield_block_debug_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shield_block_debug_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shield_block_debug_mi.visible = false
		_shield_block_debug_mi.material_override = _shield_block_debug_mat
		vw.add_child(_shield_block_debug_mi)

	_capture_base_stats()
	_configure_health_runtime()
	stamina = _max_stamina_value()
	stamina_changed.emit(stamina, _max_stamina_value())
	network_owner_peer_id = get_multiplayer_authority()
	_authoritative_weapon_mode_id = int(weapon_mode)
	_authoritative_melee_cooldown_remaining = 0.0
	_authoritative_ranged_cooldown_remaining = 0.0
	_authoritative_bomb_cooldown_remaining = 0.0
	_authoritative_is_defending = false
	_authoritative_stamina = stamina
	_authoritative_stamina_broken = false
	_apply_visual_downed_state()
	_apply_visual_defending_state()
	_sync_sword_visual()
	call_deferred("_sync_sword_visual")
	_rebuild_visual_mesh_instance_cache()
	_sync_player_hurtbox_runtime()
	_sync_melee_hitbox_geometry()
	if infusion_manager != null:
		if not infusion_manager.infusion_added.is_connected(_on_infusion_added_handgun_visual):
			infusion_manager.infusion_added.connect(_on_infusion_added_handgun_visual)
		if not infusion_manager.infusion_removed.is_connected(_on_infusion_removed_handgun_visual):
			infusion_manager.infusion_removed.connect(_on_infusion_removed_handgun_visual)


func _on_infusion_added_handgun_visual(
	_instance_id: int, pillar_id: StringName, _stack: float, _source_kind: int
) -> void:
	_handgun_infusion_projectile_style = InfusionConstantsRef.handgun_projectile_style_id(pillar_id)


func _on_infusion_removed_handgun_visual(
	_instance_id: int, _pillar_id: StringName, _stack: float
) -> void:
	if infusion_manager == null or not infusion_manager.has_method(&"list_infusions_for_ui"):
		_handgun_infusion_projectile_style = &""
		return
	var lst: Array = infusion_manager.call(&"list_infusions_for_ui")
	if lst.is_empty():
		_handgun_infusion_projectile_style = &""
		return
	var last: Dictionary = lst[lst.size() - 1]
	_handgun_infusion_projectile_style = InfusionConstantsRef.handgun_projectile_style_id(
		StringName(String(last.get("pillar_id", &"")))
	)


func _configure_health_runtime() -> void:
	if _health_component != null:
		_health_component.max_health = max_health
		_health_component.starting_health = max_health
		_health_component.invulnerability_duration = hit_invulnerability_duration
		_health_component.debug_logging = show_player_hitbox_debug
		_health_component.health_changed.connect(_on_health_component_changed)
		_health_component.depleted.connect(_on_health_component_depleted)
		_health_component.invulnerability_started.connect(_on_health_component_invulnerability_started)
		_health_component.invulnerability_ended.connect(_on_health_component_invulnerability_ended)
		_health_component.set_current_health(max_health)
		health = _health_component.current_health
	else:
		health = max_health
		health_changed.emit(health, max_health)
	if _damage_receiver != null:
		_damage_receiver.owner_path = NodePath("..")
		_damage_receiver.health_component_path = NodePath("../HealthComponent")
		_damage_receiver.player_path = NodePath("..")
		_damage_receiver.debug_logging = show_player_hitbox_debug
	if _player_hurtbox != null:
		_player_hurtbox.receiver_path = NodePath("../DamageReceiver")
		_player_hurtbox.owner_path = NodePath("..")
		_player_hurtbox.debug_draw_enabled = show_player_hitbox_debug
	if _melee_hitbox != null:
		_melee_hitbox.debug_draw_enabled = show_melee_hit_debug
		_melee_hitbox.debug_logging = show_melee_hit_debug
		if not _melee_hitbox.target_resolved.is_connected(_on_melee_hitbox_target_resolved):
			_melee_hitbox.target_resolved.connect(_on_melee_hitbox_target_resolved)


func _sync_health_component_state() -> void:
	if _health_component == null:
		return
	_health_component.max_health = max_health
	_health_component.invulnerability_duration = hit_invulnerability_duration
	_health_component.set_current_health(health)


func _on_health_component_changed(current: int, maximum: int) -> void:
	health = current
	max_health = maximum
	health_changed.emit(health, max_health)


func _on_health_component_depleted(_packet: DamagePacket) -> void:
	_invuln_time_remaining = 0.0
	die()


func _on_health_component_invulnerability_started(duration: float) -> void:
	_invuln_time_remaining = maxf(0.0, duration)
	if _invuln_time_remaining > 0.0:
		_update_invulnerability_flash_visual()


func _on_health_component_invulnerability_ended() -> void:
	_invuln_time_remaining = 0.0
	_reset_player_visual_transparency()


func is_damage_authority() -> bool:
	return not _multiplayer_active() or _is_server_peer()


func _sync_player_hurtbox_runtime() -> void:
	if _player_hurtbox == null:
		return
	_player_hurtbox.set_active(is_damage_authority())


func _sync_melee_hitbox_geometry() -> void:
	if _melee_hitbox == null or _melee_hitbox_shape == null or _melee_hitbox_shape.shape is not RectangleShape2D:
		return
	var rect := _melee_hitbox_shape.shape as RectangleShape2D
	var sz := _melee_hit_effective_width_depth()
	rect.size = sz
	var facing := _resolve_melee_hit_facing()
	var center_offset := facing * (_melee_range_start() + sz.y * 0.5)
	_melee_hitbox.position = center_offset
	_melee_hitbox.rotation = facing.angle() + PI * 0.5


func _resolve_melee_hit_facing() -> Vector2:
	if _melee_hitbox != null and _melee_hitbox.is_active():
		return _normalized_attack_facing(_active_melee_attack_facing)
	return _normalized_attack_facing(_facing_planar)


func _build_incoming_damage_packet(
	amount: int,
	kind: StringName,
	source_position: Vector2,
	incoming_direction: Vector2,
	blockable: bool,
	attack_instance_id: int = -1,
	source_uid: int = 0,
	source_node: Node = null,
	knockback: float = 0.0
) -> DamagePacket:
	var packet := DamagePacketScript.new() as DamagePacket
	packet.amount = amount
	packet.kind = kind
	packet.source_node = source_node
	packet.source_uid = source_uid
	packet.attack_instance_id = attack_instance_id
	packet.origin = source_position
	packet.direction = incoming_direction.normalized() if incoming_direction.length_squared() > 0.0001 else Vector2.ZERO
	packet.knockback = knockback
	packet.apply_iframes = true
	packet.blockable = blockable
	packet.debug_label = &"player_receive"
	return packet


func bind_loadout_runtime(loadout_host: Node, room_type_provider: Callable, owner_id: StringName = &"") -> void:
	_loadout_host = loadout_host
	_loadout_room_type_provider = room_type_provider
	if owner_id != &"":
		_loadout_owner_id = owner_id
	elif network_owner_peer_id > 0:
		_loadout_owner_id = StringName("peer_%s" % [network_owner_peer_id])
	if _loadout_host != null and _loadout_host.has_method(&"get_player_loadout_snapshot"):
		var snapshot_v: Variant = _loadout_host.call(&"get_player_loadout_snapshot", self)
		if snapshot_v is Dictionary:
			apply_authoritative_loadout_snapshot(snapshot_v as Dictionary)


func set_menu_input_blocked(blocked: bool) -> void:
	_menu_input_blocked = blocked
	if _menu_input_blocked:
		_clear_pending_rmb_attack()
		_set_defending_state(false)
		velocity = Vector2.ZERO
		_rmb_down = true
		_lmb_down = true
	else:
		_rmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		_lmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func request_equip_item(item_id: StringName) -> void:
	if _loadout_host == null:
		loadout_request_failed.emit("Loadout backend is unavailable.")
		return
	var normalized_item_id := StringName(String(item_id))
	if normalized_item_id == &"":
		loadout_request_failed.emit("Choose an item to equip.")
		return
	if _is_server_peer() or not _multiplayer_active():
		_request_local_or_server_loadout_change(&"equip", normalized_item_id)
		return
	_local_loadout_request_sequence += 1
	_rpc_request_loadout_equip.rpc_id(1, _local_loadout_request_sequence, normalized_item_id)


func request_unequip_slot(slot_id: StringName) -> void:
	if _loadout_host == null:
		loadout_request_failed.emit("Loadout backend is unavailable.")
		return
	var normalized_slot_id := StringName(String(slot_id))
	if normalized_slot_id == &"":
		loadout_request_failed.emit("Choose a slot to unequip.")
		return
	if _is_server_peer() or not _multiplayer_active():
		_request_local_or_server_loadout_change(&"unequip", normalized_slot_id)
		return
	_local_loadout_request_sequence += 1
	_rpc_request_loadout_unequip.rpc_id(1, _local_loadout_request_sequence, normalized_slot_id)


func get_loadout_view_model() -> Dictionary:
	return _loadout_snapshot.duplicate(true)


func apply_authoritative_loadout_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_loadout_snapshot = snapshot.duplicate(true)
	if _loadout_owner_id == &"":
		_loadout_owner_id = StringName(String(_loadout_snapshot.get("owner_id", "")))
	_apply_loadout_stats(_loadout_snapshot.get("aggregated_stats", {}) as Dictionary)
	if _visual != null and is_instance_valid(_visual) and _visual.has_method(&"apply_loadout_visuals"):
		_visual.call(&"apply_loadout_visuals", _loadout_snapshot)
	_rebuild_visual_mesh_instance_cache()
	_coerce_weapon_mode_to_available(true)
	_sync_sword_visual()
	loadout_changed.emit(_loadout_snapshot.duplicate(true))


## Called by a StatPillar2D on the server when the player destroys it.
## Propagates the bonus to the owning client if running in multiplayer.
func receive_pillar_bonus(stat_key: StringName, amount: float) -> void:
	_apply_runtime_stat_bonus(stat_key, amount)
	if _multiplayer_active() and _is_server_peer() and network_owner_peer_id != _local_peer_id():
		_rpc_receive_pillar_bonus.rpc_id(network_owner_peer_id, stat_key, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_pillar_bonus(stat_key: StringName, amount: float) -> void:
	if _multiplayer_active() and multiplayer.get_remote_sender_id() != 1:
		return
	_apply_runtime_stat_bonus(stat_key, amount)


## Server: InfusionPillar2D. Owning client mirrors like `receive_pillar_bonus`.
func receive_infusion_pickup(pillar_id: StringName, stack_contribution: float, source_kind: int) -> void:
	if infusion_manager == null or not infusion_manager.has_method(&"add_infusion"):
		return
	var new_id: Variant = infusion_manager.call(
		&"add_infusion", pillar_id, stack_contribution, source_kind, false
	)
	if int(new_id) < 0:
		return
	if _multiplayer_active() and _is_server_peer() and network_owner_peer_id != _local_peer_id():
		_rpc_receive_infusion_pickup.rpc_id(
			network_owner_peer_id, pillar_id, stack_contribution, source_kind
		)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_infusion_pickup(
	pillar_id: StringName, stack_contribution: float, source_kind: int
) -> void:
	if _multiplayer_active() and multiplayer.get_remote_sender_id() != 1:
		return
	if infusion_manager == null or not infusion_manager.has_method(&"add_infusion"):
		return
	infusion_manager.call(&"add_infusion", pillar_id, stack_contribution, source_kind, true)


func _apply_runtime_stat_bonus(stat_key: StringName, amount: float) -> void:
	var current := float(_runtime_stat_bonuses.get(stat_key, 0.0))
	_runtime_stat_bonuses[stat_key] = current + amount
	_apply_loadout_stats(_loadout_snapshot.get("aggregated_stats", {}) as Dictionary)


func set_network_owner_peer_id(peer_id: int) -> void:
	network_owner_peer_id = max(1, peer_id)
	set_multiplayer_authority(network_owner_peer_id, true)
	if _loadout_owner_id == &"":
		_loadout_owner_id = StringName("peer_%s" % [network_owner_peer_id])
	if OS.is_debug_build() and _MULTIPLAYER_DEBUG_LOGGING:
		var has_peer := multiplayer.multiplayer_peer != null
		var local_peer := multiplayer.get_unique_id() if has_peer else 1
		var local_authority := is_multiplayer_authority() if has_peer else network_owner_peer_id == local_peer
		print(
			"[M2][PlayerAuthority] node=%s owner_peer=%s local_peer=%s is_local_authority=%s" % [
				name,
				network_owner_peer_id,
				local_peer,
				local_authority,
			]
		)


func _capture_base_stats() -> void:
	_base_speed = speed
	_base_max_health = max_health
	_base_melee_attack_damage = melee_attack_damage
	_base_ranged_damage = ranged_damage
	_base_bomb_damage = bomb_damage
	_base_defend_damage_multiplier = defend_damage_multiplier


func _resolve_or_create_visual_root(vw: Node3D) -> Node3D:
	if vw == null:
		return null
	var vis := PLAYER_VISUAL_SCENE.instantiate() as Node3D
	if vis == null:
		return null
	vis.name = "PlayerVisual_%s" % [name]
	vis.set_meta(&"owned_by_player", true)
	vw.add_child(vis)
	return vis


func suppress_placeholder_visual() -> void:
	# Dedicated-session placeholder players should not own/claim any visible 3D proxy.
	_free_world_debug_meshes()
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.queue_free()
	_visual = null


func set_spawn_position_immediate(world_pos: Vector2, mark_initialized: bool = true) -> void:
	global_position = world_pos
	velocity = Vector2.ZERO
	_remote_target_position = world_pos
	_remote_target_velocity = Vector2.ZERO
	if not _is_local_owner_peer():
		_remote_has_state = true
	if mark_initialized:
		set_meta(&"spawn_initialized", true)
	if _visual != null and is_instance_valid(_visual):
		_update_visual_from_planar_speed(0.0)


func _multiplayer_active() -> bool:
	return multiplayer.multiplayer_peer != null


func _local_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


func _is_server_peer() -> bool:
	return _multiplayer_active() and multiplayer.is_server()


func _can_broadcast_world_replication() -> bool:
	if not _multiplayer_active():
		return false
	var session := get_node_or_null("/root/NetworkSession")
	if session != null and session.has_method("can_broadcast_world_replication"):
		return bool(session.call("can_broadcast_world_replication"))
	if not _is_server_peer():
		return true
	return true


func _is_local_owner_peer() -> bool:
	return network_owner_peer_id == _local_peer_id()


func _is_safe_room_for_loadout() -> bool:
	if not _loadout_room_type_provider.is_valid():
		return false
	var room_type_v: Variant = _loadout_room_type_provider.call(global_position)
	return String(room_type_v) == "safe"


func _loadout_request_context() -> Dictionary:
	return {
		"safe_room_only": true,
		"is_safe_room": _is_safe_room_for_loadout(),
	}


func _request_local_or_server_loadout_change(action: StringName, value: StringName) -> void:
	if _loadout_host == null:
		loadout_request_failed.emit("Loadout backend is unavailable.")
		return
	if not _loadout_host.has_method(&"handle_player_loadout_request"):
		loadout_request_failed.emit("Loadout backend is missing request handling.")
		return
	var result_v: Variant = _loadout_host.call(&"handle_player_loadout_request", self, action, value)
	if result_v is not Dictionary:
		loadout_request_failed.emit("Loadout backend returned an invalid response.")
		return
	var result: Dictionary = result_v as Dictionary
	if not bool(result.get("ok", false)):
		var failure_message := String(result.get("message", "Loadout request rejected."))
		if _multiplayer_active() and _is_server_peer() and network_owner_peer_id != _local_peer_id():
			_rpc_receive_loadout_request_failed.rpc_id(network_owner_peer_id, failure_message)
		else:
			loadout_request_failed.emit(failure_message)
		var failed_snapshot_v: Variant = result.get("snapshot", {})
		if failed_snapshot_v is Dictionary and not (failed_snapshot_v as Dictionary).is_empty():
			apply_authoritative_loadout_snapshot(failed_snapshot_v as Dictionary)
		return
	var snapshot_v: Variant = result.get("snapshot", {})
	if snapshot_v is Dictionary:
		apply_authoritative_loadout_snapshot(snapshot_v as Dictionary)


func _loadout_slot_item_id(slot_id: StringName) -> StringName:
	if _loadout_snapshot.is_empty():
		return &""
	var equipped_slots_v: Variant = _loadout_snapshot.get("equipped_slots", {})
	if equipped_slots_v is not Dictionary:
		return &""
	return StringName(String((equipped_slots_v as Dictionary).get(String(slot_id), "")))


func _loadout_item_definition(item_id: StringName) -> Dictionary:
	if _loadout_snapshot.is_empty():
		return {}
	var definitions_v: Variant = _loadout_snapshot.get("item_definitions", {})
	if definitions_v is not Dictionary:
		return {}
	return ((definitions_v as Dictionary).get(String(item_id), {}) as Dictionary)


func _loadout_item_stat_total(stat_key: StringName) -> float:
	if _loadout_snapshot.is_empty():
		return 0.0
	var stats_v: Variant = _loadout_snapshot.get("aggregated_stats", {})
	if stats_v is not Dictionary:
		return 0.0
	var stats: Dictionary = stats_v as Dictionary
	if stats.has(stat_key):
		return float(stats.get(stat_key, 0.0))
	if stats.has(String(stat_key)):
		return float(stats.get(String(stat_key), 0.0))
	return 0.0


func _has_equipped_item(slot_id: StringName) -> bool:
	if _loadout_snapshot.is_empty():
		return true
	return _loadout_slot_item_id(slot_id) != &""


func _has_equipped_sword() -> bool:
	return _has_equipped_item(LoadoutConstantsRef.SLOT_SWORD)


func _has_equipped_handgun() -> bool:
	return _has_equipped_item(LoadoutConstantsRef.SLOT_HANDGUN)


func _has_equipped_shield() -> bool:
	return _has_equipped_item(LoadoutConstantsRef.SLOT_SHIELD)


func _has_equipped_bomb() -> bool:
	return _has_equipped_item(LoadoutConstantsRef.SLOT_BOMB)


func _can_defend_in_current_mode() -> bool:
	if _is_dead or not _has_equipped_shield():
		return false
	match weapon_mode:
		WeaponMode.SWORD:
			return _has_equipped_sword()
		WeaponMode.GUN:
			return _has_equipped_handgun()
		_:
			return false


func _equipped_handgun_projectile_style() -> StringName:
	if _handgun_infusion_projectile_style != &"":
		return _handgun_infusion_projectile_style
	var handgun_item_id := _loadout_slot_item_id(LoadoutConstantsRef.SLOT_HANDGUN)
	if handgun_item_id == &"":
		return LoadoutConstantsRef.PROJECTILE_STYLE_RED
	var definition := _loadout_item_definition(handgun_item_id)
	var visual_v: Variant = definition.get("visual", {})
	if visual_v is Dictionary:
		return StringName(String((visual_v as Dictionary).get("projectile_style_id", "red")))
	return LoadoutConstantsRef.PROJECTILE_STYLE_RED


func _equipped_bomb_visual_style() -> StringName:
	var bomb_item_id := _loadout_slot_item_id(LoadoutConstantsRef.SLOT_BOMB)
	if bomb_item_id == &"":
		return LoadoutConstantsRef.PROJECTILE_STYLE_RED
	var definition := _loadout_item_definition(bomb_item_id)
	var visual_v: Variant = definition.get("visual", {})
	if visual_v is Dictionary:
		return StringName(String((visual_v as Dictionary).get("projectile_style_id", "red")))
	return LoadoutConstantsRef.PROJECTILE_STYLE_RED


func _available_main_weapon_modes() -> Array:
	var modes: Array = []
	if _has_equipped_sword():
		modes.append(WeaponMode.SWORD)
	if _has_equipped_handgun():
		modes.append(WeaponMode.GUN)
	return modes


func _coerce_weapon_mode_to_available(force_emit: bool = false) -> void:
	var previous_mode := weapon_mode
	var available_modes: Array = _available_main_weapon_modes()
	if available_modes.is_empty():
		if previous_mode != WeaponMode.SWORD:
			weapon_mode = WeaponMode.SWORD
		if _is_defending and not _can_defend_in_current_mode():
			_set_defending_state(false)
		if previous_mode != weapon_mode or force_emit:
			weapon_mode_changed.emit(get_weapon_mode_display())
		_sync_sword_visual()
		return
	if available_modes.find(weapon_mode) < 0:
		weapon_mode = available_modes[0]
	if _is_defending and not _can_defend_in_current_mode():
		_set_defending_state(false)
	if previous_mode != weapon_mode or force_emit:
		weapon_mode_changed.emit(get_weapon_mode_display())
	_sync_sword_visual()


func _apply_loadout_stats(aggregated_stats: Dictionary) -> void:
	var previous_max_health := maxi(1, max_health)
	var previous_health := clampi(health, 0, previous_max_health)
	var totals := aggregated_stats.duplicate(true)
	for key in _runtime_stat_bonuses:
		var current := float(totals.get(key, 0.0))
		totals[key] = current + float(_runtime_stat_bonuses.get(key, 0.0))
	speed = maxf(0.0, _base_speed + _loadout_stat_from_totals(totals, LoadoutConstantsRef.STAT_SPEED))
	melee_attack_damage = maxi(
		0,
		int(roundf(_base_melee_attack_damage + _loadout_stat_from_totals(totals, LoadoutConstantsRef.STAT_MELEE_DAMAGE)))
	)
	ranged_damage = maxi(
		0,
		int(roundf(_base_ranged_damage + _loadout_stat_from_totals(totals, LoadoutConstantsRef.STAT_RANGED_DAMAGE)))
	)
	bomb_damage = maxi(
		0,
		int(roundf(_base_bomb_damage + _loadout_stat_from_totals(totals, LoadoutConstantsRef.STAT_BOMB_DAMAGE)))
	)
	defend_damage_multiplier = clampf(
		_base_defend_damage_multiplier
			+ _loadout_stat_from_totals(totals, LoadoutConstantsRef.STAT_DEFEND_DAMAGE_MULTIPLIER),
		0.1,
		4.0
	)
	var next_max_health := maxi(
		1,
		int(roundf(_base_max_health + _loadout_stat_from_totals(totals, LoadoutConstantsRef.STAT_MAX_HEALTH)))
	)
	if max_health != next_max_health:
		max_health = next_max_health
		if previous_health <= 0:
			health = 0
		elif previous_health >= previous_max_health:
			health = max_health
		else:
			var health_ratio := float(previous_health) / float(previous_max_health)
			health = clampi(int(roundf(health_ratio * float(max_health))), 1, max_health)
		_sync_health_component_state()
	_sync_melee_hitbox_geometry()


func _loadout_stat_from_totals(totals: Dictionary, stat_key: StringName) -> float:
	if totals.has(stat_key):
		return float(totals.get(stat_key, 0.0))
	if totals.has(String(stat_key)):
		return float(totals.get(String(stat_key), 0.0))
	return 0.0


func _stat_totals_merged() -> Dictionary:
	var totals := (_loadout_snapshot.get("aggregated_stats", {}) as Dictionary).duplicate(true)
	for key in _runtime_stat_bonuses:
		var add_v := float(_runtime_stat_bonuses.get(key, 0.0))
		totals[key] = float(totals.get(key, 0.0)) + add_v
	return totals


func _update_remote_proxy_visual() -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, height, global_position.y)
	var visual_facing := _resolve_visual_facing_planar()
	_visual.rotation.y = atan2(visual_facing.x, visual_facing.y)
	if _visual.has_method(&"set_locomotion_from_planar_speed"):
		_visual.set_locomotion_from_planar_speed(_remote_planar_speed, speed)


func _update_visual_from_planar_speed(planar_speed: float) -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, height, global_position.y)
	var visual_facing := _resolve_visual_facing_planar()
	_visual.rotation.y = atan2(visual_facing.x, visual_facing.y)
	if _visual.has_method(&"set_locomotion_from_planar_speed"):
		_visual.set_locomotion_from_planar_speed(planar_speed, speed)


func _apply_visual_downed_state() -> void:
	if _visual == null:
		return
	if _visual.has_method(&"set_downed_state"):
		_visual.call(&"set_downed_state", _is_dead)


func _apply_visual_defending_state() -> void:
	if _visual == null:
		return
	if _visual.has_method(&"set_defending_state"):
		_visual.call(&"set_defending_state", _is_defending)


func _sync_sword_visual() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	if _visual.has_method(&"set_sword_active"):
		_visual.call(&"set_sword_active", weapon_mode == WeaponMode.SWORD and _has_equipped_sword())
	if _visual.has_method(&"set_handgun_active"):
		_visual.call(&"set_handgun_active", weapon_mode == WeaponMode.GUN and _has_equipped_handgun())


func _set_defending_state(next_defending: bool) -> void:
	var resolved_defending: bool = next_defending and _can_defend_in_current_mode()
	if _is_defending == resolved_defending:
		return
	_is_defending = resolved_defending
	if _is_defending:
		_sprint_latch_after_dodge = false
	_apply_visual_defending_state()


func _set_downed_state(next_downed: bool, emit_hit_signal: bool = false) -> void:
	if _is_dead == next_downed:
		return
	_is_dead = next_downed
	if _is_dead:
		clear_all_external_move_speed_multipliers()
		_clear_enemy_control_states()
		_set_defending_state(false)
	if _is_dead:
		velocity = Vector2.ZERO
		height = 0.0
		_dodge_time_remaining = 0.0
		_dodge_cooldown_remaining = 0.0
		_sprint_latch_after_dodge = false
		_facing_lock_time_remaining = 0.0
		_invuln_time_remaining = 0.0
		_attack_hitbox_visual_time_remaining = 0.0
		_rmb_down = false
		_lmb_down = false
		_clear_pending_rmb_attack()
		_flow_tempo = 0.0
		_flow_chain_remaining = 0.0
		_flow_overdrive_remaining = 0.0
		_flow_aggression_remaining = 0.0
		_flow_last_action_kind = -1
		_anchor_reset_pressure_state()
		_surge_reset_combat_state()
	else:
		_invuln_time_remaining = 0.0
	if _body_shape != null:
		_body_shape.disabled = _is_dead
	if _player_hurtbox != null:
		_player_hurtbox.set_active(not _is_dead and is_damage_authority())
	if _health_component != null:
		_health_component.clear_invulnerability()
	_reset_player_visual_transparency()
	_apply_visual_downed_state()
	if emit_hit_signal and _is_dead:
		hit.emit()
	downed_state_changed.emit(_is_dead)

func die() -> void:
	_set_downed_state(true, true)


func _resolve_melee_facing_lock_duration() -> float:
	if _visual != null and _visual.has_method(&"get_attack_duration_seconds"):
		var duration_v: Variant = _visual.call(&"get_attack_duration_seconds")
		var duration := float(duration_v)
		if duration > 0.0:
			return duration
	return maxf(melee_facing_lock_fallback_duration, attack_hitbox_visual_duration)


func _resolve_visual_facing_lock_duration(mode: StringName = &"melee") -> float:
	var base_d := 0.0
	if _visual != null and _visual.has_method(&"get_attack_duration_seconds_for_mode"):
		var duration_v: Variant = _visual.call(&"get_attack_duration_seconds_for_mode", mode)
		var duration := float(duration_v)
		if duration > 0.0:
			base_d = duration
	if base_d <= 0.0:
		if String(mode).to_lower() == "melee":
			base_d = _resolve_melee_facing_lock_duration()
		else:
			base_d = melee_facing_lock_fallback_duration
	var anim_m := InfusionFlowRef.flow_animation_time_multiplier(
		_flow_overdrive_remaining, _infusion_flow_threshold()
	)
	return maxf(0.02, base_d * anim_m)


func _start_facing_lock(direction: Vector2, duration_seconds: float = -1.0) -> void:
	# Keep the 3D presentation snapped to the attack direction without freezing the
	# live gameplay-facing updates that movement/aim continue to use.
	var lock_dir := _normalized_attack_facing(direction)
	_facing_lock_planar = lock_dir
	_facing_planar = lock_dir
	_facing_lock_time_remaining = (
		duration_seconds
		if duration_seconds >= 0.0
		else _resolve_melee_facing_lock_duration()
	)
	_sync_melee_hitbox_geometry()


func _tick_facing_lock(delta: float) -> void:
	_facing_lock_time_remaining = maxf(0.0, _facing_lock_time_remaining - delta)


func _is_facing_locked() -> bool:
	return false


func _resolve_visual_facing_planar() -> Vector2:
	if _facing_lock_time_remaining > 0.0 and _facing_lock_planar.length_squared() > 1e-6:
		return _facing_lock_planar.normalized()
	return _normalized_attack_facing(_facing_planar)


func _max_stamina_value() -> float:
	return maxf(1.0, max_stamina)


func _set_stamina_value(next_stamina: float) -> void:
	var resolved := clampf(next_stamina, 0.0, _max_stamina_value())
	var changed := not is_equal_approx(stamina, resolved)
	stamina = resolved
	_stamina_broken = stamina <= 0.001
	if _stamina_broken:
		_sprint_latch_after_dodge = false
	if not _multiplayer_active() or _is_server_peer():
		_authoritative_stamina = stamina
		_authoritative_stamina_broken = _stamina_broken
	if changed:
		stamina_changed.emit(stamina, _max_stamina_value())


func _restore_stamina_to_full() -> void:
	_stamina_regen_cooldown_remaining = 0.0
	_set_stamina_value(_max_stamina_value())


func _dash_stamina_cost_value() -> float:
	return maxf(0.0, dash_stamina_cost)


func _can_spend_stamina(amount: float) -> bool:
	var cost := maxf(0.0, amount)
	return cost <= 0.0 or stamina + 0.001 >= cost


func _spend_stamina(amount: float, regen_delay: float = -1.0) -> void:
	var cost := maxf(0.0, amount)
	if cost <= 0.0:
		return
	_set_stamina_value(stamina - cost)
	var delay := regen_delay
	if delay < 0.0:
		delay = stamina_regen_delay
	_stamina_regen_cooldown_remaining = maxf(
		_stamina_regen_cooldown_remaining,
		maxf(0.0, delay)
	)


func _resolve_attack_origin_direction(
	source_position: Vector2, incoming_direction: Vector2 = Vector2.ZERO
) -> Vector2:
	if incoming_direction.length_squared() > 0.0001:
		return (-incoming_direction).normalized()
	var to_source := source_position - global_position
	if to_source.length_squared() > 0.0001:
		return to_source.normalized()
	return Vector2.ZERO


func _is_attack_inside_block_arc(
	source_position: Vector2, incoming_direction: Vector2 = Vector2.ZERO
) -> bool:
	if not _is_defending or not _can_defend_in_current_mode() or stamina <= 0.0:
		return false
	var attack_origin_dir := _resolve_attack_origin_direction(source_position, incoming_direction)
	if attack_origin_dir.length_squared() <= 0.0001:
		return false
	var guard_facing := _facing_planar
	if guard_facing.length_squared() <= 0.0001:
		guard_facing = Vector2(0.0, -1.0)
	else:
		guard_facing = guard_facing.normalized()
	var half_arc_radians := deg_to_rad(clampf(block_arc_degrees, 0.0, 360.0) * 0.5)
	return guard_facing.dot(attack_origin_dir) >= cos(half_arc_radians)


func _apply_guard_stamina_damage(amount: int) -> void:
	if amount <= 0:
		return
	var scaled_amount := maxf(1.0, float(amount) * maxf(0.1, defend_damage_multiplier))
	var broke_guard := stamina - scaled_amount <= 0.0
	_set_stamina_value(stamina - scaled_amount)
	_stamina_regen_cooldown_remaining = (
		maxf(0.0, stamina_break_regen_delay) if broke_guard else maxf(0.0, stamina_regen_delay)
	)


func _apply_health_damage(amount: int) -> void:
	if _health_component == null:
		health = maxi(0, health - amount)
		health_changed.emit(health, max_health)
		if health <= 0:
			_reset_player_visual_transparency()
			die()
			return
		_invuln_time_remaining = hit_invulnerability_duration
		_update_invulnerability_flash_visual()
		return
	var packet := _build_incoming_damage_packet(amount, &"direct", global_position, Vector2.ZERO, false)
	_health_component.apply_damage(packet, amount)


func _tick_stamina_regen(delta: float) -> void:
	if _is_dead or _is_defending or stamina >= _max_stamina_value():
		return
	if _stamina_regen_cooldown_remaining > 0.0:
		_stamina_regen_cooldown_remaining = maxf(0.0, _stamina_regen_cooldown_remaining - delta)
		return
	var regen_amount := maxf(0.0, stamina_regen_per_second) * maxf(0.0, delta)
	if regen_amount <= 0.0:
		return
	_set_stamina_value(stamina + regen_amount)


# --- Network: replication, prediction, authoritative movement ---
func _broadcast_server_state(delta: float) -> void:
	if not _is_server_peer():
		return
	if not _can_broadcast_world_replication():
		return
	_net_sync_time_accum += delta
	if _net_sync_time_accum < network_sync_interval:
		return
	_net_sync_time_accum = 0.0
	_rpc_receive_server_state.rpc(
		global_position,
		velocity,
		_facing_planar,
		health,
		stamina,
		int(weapon_mode),
		_is_dead,
		_dodge_time_remaining,
		_dodge_cooldown_remaining,
		_dodge_direction,
		_facing_lock_time_remaining,
		_melee_attack_cooldown_remaining,
		_ranged_cooldown_remaining,
		_bomb_cooldown_remaining,
		_server_last_input_sequence,
		_is_defending,
		_flow_tempo,
		_flow_chain_remaining,
		_flow_overdrive_remaining,
		_flow_aggression_remaining,
		_flow_last_action_kind,
		_anchor_pressure,
		_anchor_micro_shield,
		_anchor_bastion_charge,
		1 if _anchor_rooted else 0,
		1 if _anchor_critical_bastion else 0,
		1 if _external_dash_blocked else 0,
		1 if _external_movement_rooted else 0,
		_external_root_origin_position,
		1 if _external_root_pull_used else 0,
		_external_leecher_escape_progress,
		_external_latched_enemy_id,
		1 if _sprint_latch_after_dodge else 0
	)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_submit_movement_input(
	sequence: int,
	move_active: bool,
	target_world: Vector2,
	dodge_down: bool,
	defend_down: bool,
	aim_planar: Vector2 = Vector2.ZERO,
) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if sequence < _server_last_input_sequence:
		return
	_server_has_received_input = true
	_server_last_input_sequence = sequence
	_server_input_move_active = move_active
	_server_input_target_world = target_world
	_server_input_aim_planar = aim_planar
	_server_input_dodge_down = dodge_down
	_server_input_defend_down = defend_down


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_receive_server_state(
	world_pos: Vector2,
	planar_velocity: Vector2,
	facing_planar: Vector2,
	health_value: int,
	stamina_value: float,
	weapon_value: int,
	dead_state: bool,
	dodge_time_remaining_value: float,
	dodge_cooldown_remaining_value: float,
	dodge_direction_value: Vector2,
	facing_lock_time_remaining_value: float,
	melee_cooldown_remaining_value: float,
	ranged_cooldown_remaining_value: float,
	bomb_cooldown_remaining_value: float,
	ack_input_sequence: int,
	defending_state: bool,
	flow_tempo: float = 0.0,
	flow_chain_remaining: float = 0.0,
	flow_overdrive_remaining: float = 0.0,
	flow_aggression_remaining: float = 0.0,
	flow_last_action_kind: int = -1,
	anchor_pressure: float = 0.0,
	anchor_micro_shield: float = 0.0,
	anchor_bastion_charge: float = 0.0,
	anchor_rooted_i: int = 0,
	anchor_critical_i: int = 0,
	external_dash_blocked_i: int = 0,
	external_movement_rooted_i: int = 0,
	external_root_origin: Vector2 = Vector2.ZERO,
	external_root_pull_used_i: int = 0,
	leecher_escape_progress: float = 0.0,
	latched_enemy_id: int = 0,
	sprint_latch_after_dodge_i: int = 0
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if facing_planar.length_squared() > 1e-6:
		_facing_planar = facing_planar.normalized()
	_flow_merge_state_from_network(
		flow_tempo,
		flow_chain_remaining,
		flow_overdrive_remaining,
		flow_aggression_remaining,
		flow_last_action_kind
	)
	_anchor_pressure = maxf(0.0, anchor_pressure)
	_anchor_micro_shield = maxf(0.0, anchor_micro_shield)
	_anchor_bastion_charge = clampf(anchor_bastion_charge, 0.0, 1.0)
	_anchor_rooted = anchor_rooted_i != 0
	_anchor_critical_bastion = anchor_critical_i != 0
	_external_dash_blocked = external_dash_blocked_i != 0
	_external_movement_rooted = external_movement_rooted_i != 0
	_external_root_origin_position = external_root_origin
	_external_root_pull_used = external_root_pull_used_i != 0
	_external_leecher_escape_progress = clampf(leecher_escape_progress, 0.0, 1.0)
	_external_latched_enemy_id = maxi(0, latched_enemy_id)
	_sprint_latch_after_dodge = sprint_latch_after_dodge_i != 0
	var normalized_health := clampi(health_value, 0, max_health)
	if health != normalized_health:
		health = normalized_health
		if _health_component != null:
			_health_component.set_current_health(health)
		else:
			health_changed.emit(health, max_health)
	var normalized_stamina := clampf(stamina_value, 0.0, _max_stamina_value())
	_authoritative_stamina = normalized_stamina
	_authoritative_stamina_broken = normalized_stamina <= 0.001
	_set_stamina_value(normalized_stamina)
	var next_weapon := weapon_mode
	match weapon_value:
		1:
			next_weapon = WeaponMode.GUN
		2:
			next_weapon = WeaponMode.BOMB
		_:
			next_weapon = WeaponMode.SWORD
	weapon_mode = next_weapon
	_authoritative_weapon_mode_id = int(next_weapon)
	_authoritative_melee_cooldown_remaining = maxf(0.0, melee_cooldown_remaining_value)
	_authoritative_ranged_cooldown_remaining = maxf(0.0, ranged_cooldown_remaining_value)
	_authoritative_bomb_cooldown_remaining = maxf(0.0, bomb_cooldown_remaining_value)
	_authoritative_is_defending = defending_state
	_set_downed_state(dead_state)
	_set_defending_state(defending_state)
	_coerce_weapon_mode_to_available(true)
	_facing_lock_time_remaining = maxf(0.0, facing_lock_time_remaining_value)
	if _facing_lock_time_remaining > 0.0:
		_facing_lock_planar = _facing_planar
	if _is_local_owner_peer():
		_reconcile_target_position = world_pos
		_reconcile_target_velocity = planar_velocity
		_reconcile_target_facing = _facing_planar
		_reconcile_target_dodge_time_remaining = maxf(0.0, dodge_time_remaining_value)
		_reconcile_target_dodge_cooldown_remaining = maxf(0.0, dodge_cooldown_remaining_value)
		_reconcile_target_dodge_direction = dodge_direction_value.normalized()
		_reconcile_target_sprint_latch_after_dodge = _sprint_latch_after_dodge
		_reconcile_target_facing_lock_time_remaining = _facing_lock_time_remaining
		_reconcile_target_facing_lock_planar = _facing_lock_planar
		_reconcile_target_external_dash_blocked = _external_dash_blocked
		_reconcile_target_external_movement_rooted = _external_movement_rooted
		_reconcile_target_external_root_origin = _external_root_origin_position
		_reconcile_target_external_root_pull_used = _external_root_pull_used
		_reconcile_target_leecher_escape_progress = _external_leecher_escape_progress
		_reconcile_target_latched_enemy_id = _external_latched_enemy_id
		_reconcile_has_target = true
		_last_acknowledged_input_sequence = max(_last_acknowledged_input_sequence, ack_input_sequence)
		_prune_acknowledged_pending_inputs(_last_acknowledged_input_sequence)
		return
	_remote_target_position = world_pos
	_remote_target_velocity = planar_velocity
	_remote_has_state = true


func _prune_acknowledged_pending_inputs(ack_sequence: int) -> void:
	if _pending_input_commands.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for command in _pending_input_commands:
		var seq_v: Variant = command.get("seq", -1)
		var seq := int(seq_v)
		if seq > ack_sequence:
			remaining.append(command)
	_pending_input_commands = remaining


func _apply_local_reconciliation(_delta: float) -> void:
	if not _reconcile_has_target:
		return
	if _is_dead:
		global_position = _reconcile_target_position
		velocity = Vector2.ZERO
		_pending_input_commands.clear()
		_reconcile_has_target = false
		return
	# Reconciliation for owner client: reset to authoritative server state, then replay
	# still-pending local commands so responsiveness remains while staying correct.
	global_position = _reconcile_target_position
	velocity = _reconcile_target_velocity
	_facing_planar = _reconcile_target_facing
	_dodge_time_remaining = _reconcile_target_dodge_time_remaining
	_dodge_cooldown_remaining = _reconcile_target_dodge_cooldown_remaining
	_dodge_direction = _reconcile_target_dodge_direction
	_sprint_latch_after_dodge = _reconcile_target_sprint_latch_after_dodge
	_facing_lock_time_remaining = _reconcile_target_facing_lock_time_remaining
	_facing_lock_planar = _reconcile_target_facing_lock_planar
	_external_dash_blocked = _reconcile_target_external_dash_blocked
	_external_movement_rooted = _reconcile_target_external_movement_rooted
	_external_root_origin_position = _reconcile_target_external_root_origin
	_external_root_pull_used = _reconcile_target_external_root_pull_used
	_external_leecher_escape_progress = _reconcile_target_leecher_escape_progress
	_external_latched_enemy_id = _reconcile_target_latched_enemy_id
	for command in _pending_input_commands:
		var move_active := bool(command.get("move_active", false))
		var target_world_variant: Variant = command.get("target_world", global_position)
		var target_world: Vector2 = (
			target_world_variant if target_world_variant is Vector2 else global_position
		)
		var aim_v: Variant = command.get("aim_planar", Vector2.ZERO)
		var aim_planar: Vector2 = aim_v as Vector2 if aim_v is Vector2 else Vector2.ZERO
		var dodge_pressed := bool(command.get("dodge_pressed", false))
		var dodge_down := bool(command.get("dodge_down", false))
		var defend_down := bool(command.get("defend_down", false))
		var command_delta := float(command.get("delta", 1.0 / maxf(1.0, float(Engine.physics_ticks_per_second))))
		_apply_movement_step(command_delta, move_active, target_world, dodge_pressed, dodge_down, defend_down, aim_planar)
	_reconcile_has_target = false


func _apply_movement_step(
	delta: float,
	move_active: bool,
	target_world: Vector2,
	dodge_pressed: bool,
	dodge_down: bool,
	defend_down: bool,
	aim_planar: Vector2 = Vector2.ZERO,
) -> float:
	if (_is_server_peer() or not _multiplayer_active()) and is_damage_authority():
		if _anchor_rooted and (move_active or dodge_pressed):
			_anchor_release_bastion()
	if not dodge_down:
		_sprint_latch_after_dodge = false
	var rooted_by_enemy := _external_movement_rooted
	var dash_blocked := _external_dash_blocked
	if rooted_by_enemy and move_active:
		move_active = false
	if rooted_by_enemy and dodge_pressed:
		if is_damage_authority():
			_enemy_control_consume_root_pull_attempt()
		dodge_pressed = false
	if rooted_by_enemy:
		_sprint_latch_after_dodge = false
	if dash_blocked and dodge_pressed:
		enemy_control_register_latch_break_input()
		dodge_pressed = false
	if dash_blocked:
		_sprint_latch_after_dodge = false
	var direction := Vector2.ZERO
	if move_active:
		var to_target := target_world - global_position
		if to_target.length_squared() > 0.01:
			direction = to_target.normalized()
	_update_facing_planar(
		direction, false, _resolve_facing_aim_for_move_step(aim_planar, direction, defend_down)
	)
	var wants_defending: bool = defend_down and _can_defend_in_current_mode() and _dodge_time_remaining <= 0.0
	_set_defending_state(wants_defending)
	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	if rooted_by_enemy:
		_dodge_time_remaining = 0.0
	if _dodge_time_remaining > 0.0:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
	elif dodge_pressed and _dodge_cooldown_remaining <= 0.0 and not _is_defending:
		if _can_spend_stamina(_dash_stamina_cost_value()):
			_spend_stamina(_dash_stamina_cost_value())
			_dodge_direction = _resolve_dodge_direction(direction)
			_dodge_time_remaining = dodge_duration
			_dodge_cooldown_remaining = dodge_cooldown
			_sprint_latch_after_dodge = dodge_down
			if is_damage_authority():
				_phase_try_dash_trail_burst(global_position, _dodge_direction)
		else:
			_sprint_latch_after_dodge = false
	var planar_speed := 0.0
	if _dodge_time_remaining > 0.0:
		velocity = _dodge_direction * dodge_speed
		planar_speed = dodge_speed
	elif direction != Vector2.ZERO:
		var resolved_speed := speed
		resolved_speed *= InfusionFlowRef.overdrive_move_speed_multiplier(
			_flow_overdrive_remaining, _infusion_flow_threshold()
		)
		if _surge_overdrive_active and InfusionSurgeRef.is_surge_attuned(_infusion_surge_threshold()):
			resolved_speed *= InfusionSurgeRef.overdrive_player_move_speed_mult()
		if _is_defending:
			resolved_speed *= clampf(defend_move_speed_multiplier, 0.0, 1.0)
		if _sprint_latch_after_dodge and dodge_down and stamina > 0.0:
			resolved_speed *= maxf(1.0, sprint_move_speed_multiplier)
			_spend_stamina(maxf(0.0, sprint_stamina_per_second) * maxf(0.0, delta))
		resolved_speed *= _external_move_speed_factor()
		velocity = direction * resolved_speed
		planar_speed = resolved_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_update_visual_from_planar_speed(planar_speed)
	if (_is_server_peer() or not _multiplayer_active()) and is_damage_authority():
		_anchor_bastion_charge_tick(delta, move_active, dodge_pressed, wants_defending)
	return planar_speed


func set_external_move_speed_multiplier(source_key: Variant, multiplier: float) -> void:
	var key := StringName(str(source_key))
	if key == &"":
		return
	_external_move_speed_multipliers[key] = clampf(multiplier, 0.05, 1.0)


func enemy_control_apply_dash_lock(source_id: int) -> void:
	if not is_damage_authority() or source_id == 0:
		return
	_external_dash_block_sources[source_id] = true
	_refresh_enemy_control_dash_blocked()


func enemy_control_clear_dash_lock(source_id: int) -> void:
	if not is_damage_authority() or source_id == 0:
		return
	_external_dash_block_sources.erase(source_id)
	_refresh_enemy_control_dash_blocked()


func enemy_control_apply_root(source_id: int, root_origin_position: Vector2) -> void:
	if not is_damage_authority() or source_id == 0:
		return
	_external_movement_rooted = true
	_external_root_source_id = source_id
	_external_root_origin_position = root_origin_position
	_external_root_pull_used = false
	_dodge_time_remaining = 0.0
	velocity = Vector2.ZERO


func enemy_control_clear_root(source_id: int = 0) -> void:
	if not is_damage_authority():
		return
	if source_id != 0 and _external_root_source_id != source_id:
		return
	_external_movement_rooted = false
	_external_root_source_id = 0
	_external_root_origin_position = Vector2.ZERO
	_external_root_pull_used = false


func enemy_control_begin_latch(enemy: Node, break_target: int) -> void:
	if not is_damage_authority() or enemy == null or not is_instance_valid(enemy):
		return
	_external_latched_enemy_id = enemy.get_instance_id()
	_external_leecher_break_target = maxi(1, break_target)
	_external_leecher_break_count = 0
	_update_leecher_escape_progress()
	enemy_control_apply_dash_lock(_external_latched_enemy_id)


func enemy_control_end_latch(enemy: Node = null) -> void:
	if not is_damage_authority():
		return
	var enemy_id := 0
	if enemy != null and is_instance_valid(enemy):
		enemy_id = enemy.get_instance_id()
	if enemy_id != 0 and enemy_id != _external_latched_enemy_id:
		return
	if _external_latched_enemy_id != 0:
		enemy_control_clear_dash_lock(_external_latched_enemy_id)
	_external_latched_enemy_id = 0
	_external_leecher_break_target = 0
	_external_leecher_break_count = 0
	_update_leecher_escape_progress()


func enemy_control_register_latch_break_input() -> void:
	if _external_latched_enemy_id == 0:
		return
	_external_leecher_break_count = mini(
		_external_leecher_break_target,
		_external_leecher_break_count + 1
	)
	_update_leecher_escape_progress()


func enemy_control_latch_break_ready() -> bool:
	return (
		_external_latched_enemy_id != 0
		and _external_leecher_break_target > 0
		and _external_leecher_break_count >= _external_leecher_break_target
	)


func enemy_control_latch_escape_progress() -> float:
	return _external_leecher_escape_progress


func enemy_control_latched_enemy_id() -> int:
	return _external_latched_enemy_id


func enemy_control_is_movement_rooted() -> bool:
	return _external_movement_rooted


func enemy_control_root_pull_used() -> bool:
	return _external_root_pull_used


func enemy_control_root_origin_position() -> Vector2:
	return _external_root_origin_position


func _enemy_control_consume_root_pull_attempt() -> void:
	if not _external_movement_rooted or _external_root_pull_used:
		return
	_external_root_pull_used = true
	global_position = _external_root_origin_position
	velocity = Vector2.ZERO


func _refresh_enemy_control_dash_blocked() -> void:
	_external_dash_blocked = not _external_dash_block_sources.is_empty()
	if _external_dash_blocked:
		_dodge_time_remaining = 0.0


func _update_leecher_escape_progress() -> void:
	if _external_latched_enemy_id == 0 or _external_leecher_break_target <= 0:
		_external_leecher_escape_progress = 0.0
		return
	_external_leecher_escape_progress = clampf(
		float(_external_leecher_break_count) / float(_external_leecher_break_target),
		0.0,
		1.0
	)


func _clear_enemy_control_states() -> void:
	_external_dash_block_sources.clear()
	_external_dash_blocked = false
	_external_movement_rooted = false
	_external_root_origin_position = Vector2.ZERO
	_external_root_pull_used = false
	_external_root_source_id = 0
	_external_leecher_escape_progress = 0.0
	_external_latched_enemy_id = 0
	_external_leecher_break_count = 0
	_external_leecher_break_target = 0


func clear_external_move_speed_multiplier(source_key: Variant) -> void:
	var key := StringName(str(source_key))
	if key == &"":
		return
	_external_move_speed_multipliers.erase(key)


func clear_all_external_move_speed_multipliers() -> void:
	_external_move_speed_multipliers.clear()


func _external_move_speed_factor() -> float:
	var multiplier := 1.0
	for value in _external_move_speed_multipliers.values():
		if value is float or value is int:
			multiplier = minf(multiplier, clampf(float(value), 0.05, 1.0))
	return multiplier


func _server_authoritative_step(delta: float) -> void:
	var move_active := false
	var target_world := global_position
	var aim_planar := Vector2.ZERO
	var dodge_down := false
	var defend_down := false
	if _is_local_owner_peer() and not _menu_input_blocked:
		var intent := _local_move_steering_intent()
		move_active = bool(intent.get("move_active", false))
		var tw: Variant = intent.get("target_world", global_position)
		target_world = tw as Vector2 if tw is Vector2 else global_position
		var av: Variant = intent.get("aim_planar", Vector2.ZERO)
		aim_planar = av as Vector2 if av is Vector2 else Vector2.ZERO
		dodge_down = Input.is_action_pressed(&"dodge")
		defend_down = Input.is_action_pressed(&"defend")
		_server_last_input_sequence += 1
	elif _server_has_received_input:
		move_active = _server_input_move_active
		target_world = _server_input_target_world
		aim_planar = _server_input_aim_planar
		dodge_down = _server_input_dodge_down
		defend_down = _server_input_defend_down
	var dodge_pressed := dodge_down and not _server_prev_dodge_down
	_server_prev_dodge_down = dodge_down
	_apply_movement_step(delta, move_active, target_world, dodge_pressed, dodge_down, defend_down, aim_planar)
	_tick_stamina_regen(delta)
	_broadcast_server_state(delta)


func _client_predicted_step(delta: float) -> void:
	var move_active := false
	var target_world := global_position
	var aim_planar := Vector2.ZERO
	var dodge_down := false
	var defend_down := false
	if not _menu_input_blocked:
		var intent := _local_move_steering_intent()
		move_active = bool(intent.get("move_active", false))
		var tw: Variant = intent.get("target_world", global_position)
		target_world = tw as Vector2 if tw is Vector2 else global_position
		var av: Variant = intent.get("aim_planar", Vector2.ZERO)
		aim_planar = av as Vector2 if av is Vector2 else Vector2.ZERO
		dodge_down = Input.is_action_pressed(&"dodge")
		defend_down = Input.is_action_pressed(&"defend")
	var dodge_pressed := dodge_down and not _local_prev_dodge_down
	_local_prev_dodge_down = dodge_down
	var sequence := _input_sequence
	_input_sequence += 1
	var command: Dictionary = {
		"seq": sequence,
		"move_active": move_active,
		"target_world": target_world,
		"aim_planar": aim_planar,
		"dodge_down": dodge_down,
		"defend_down": defend_down,
		"dodge_pressed": dodge_pressed,
		"delta": delta,
	}
	_pending_input_commands.append(command)
	_apply_movement_step(delta, move_active, target_world, dodge_pressed, dodge_down, defend_down, aim_planar)
	if _can_broadcast_world_replication():
		_rpc_submit_movement_input.rpc(sequence, move_active, target_world, dodge_down, defend_down, aim_planar)
	_apply_local_reconciliation(delta)


func _client_remote_step(delta: float) -> void:
	if not _remote_has_state:
		_update_remote_proxy_visual()
		return
	var dist_to_target := global_position.distance_to(_remote_target_position)
	if dist_to_target >= remote_interpolation_snap_distance:
		global_position = _remote_target_position
		velocity = _remote_target_velocity
		if velocity.length_squared() > 1e-6 and not _is_facing_locked():
			_facing_planar = velocity.normalized()
		_remote_planar_speed = velocity.length()
		_update_remote_proxy_visual()
		return
	var alpha := clampf(delta * remote_interpolation_lerp_rate, 0.0, 1.0)
	global_position = global_position.lerp(_remote_target_position, alpha)
	velocity = velocity.lerp(_remote_target_velocity, alpha)
	if velocity.length_squared() > 1e-6 and not _is_facing_locked():
		_facing_planar = velocity.normalized()
	_remote_planar_speed = velocity.length()
	_update_remote_proxy_visual()


# --- Combat: weapons, RPCs, projectiles, melee resolution ---
func _run_shared_cooldown_and_debug_tick(delta: float) -> void:
	_tick_facing_lock(delta)
	_flow_decay_step(delta)
	var cd_tick_m := InfusionFlowRef.cooldown_tick_multiplier(
		_flow_aggression_remaining, _flow_overdrive_remaining, _infusion_flow_threshold()
	)
	_melee_attack_cooldown_remaining = maxf(0.0, _melee_attack_cooldown_remaining - delta * cd_tick_m)
	_ranged_cooldown_remaining = maxf(0.0, _ranged_cooldown_remaining - delta * cd_tick_m)
	_bomb_cooldown_remaining = maxf(0.0, _bomb_cooldown_remaining - delta * cd_tick_m)
	if _is_server_peer() or not _multiplayer_active():
		_authoritative_weapon_mode_id = int(weapon_mode)
		_authoritative_melee_cooldown_remaining = _melee_attack_cooldown_remaining
		_authoritative_ranged_cooldown_remaining = _ranged_cooldown_remaining
		_authoritative_bomb_cooldown_remaining = _bomb_cooldown_remaining
		_authoritative_is_defending = _is_defending
		_authoritative_stamina = stamina
		_authoritative_stamina_broken = _stamina_broken
	else:
		_authoritative_melee_cooldown_remaining = maxf(
			0.0, _authoritative_melee_cooldown_remaining - delta
		)
		_authoritative_ranged_cooldown_remaining = maxf(
			0.0, _authoritative_ranged_cooldown_remaining - delta
		)
		_authoritative_bomb_cooldown_remaining = maxf(
			0.0, _authoritative_bomb_cooldown_remaining - delta
		)
	_attack_hitbox_visual_time_remaining = maxf(0.0, _attack_hitbox_visual_time_remaining - delta)
	if (not _multiplayer_active() or _is_server_peer()) and is_damage_authority():
		_anchor_decay_step(delta)
		_surge_authoritative_tick(delta)
		_phase_dash_trail_cooldown_remaining = maxf(0.0, _phase_dash_trail_cooldown_remaining - delta)
		_phase_contact_chip_cooldown_remaining = maxf(0.0, _phase_contact_chip_cooldown_remaining - delta)
		_phase_slip_body_physics_tick(delta)
	_refresh_debug_visuals(delta)
	if _health_component != null:
		_invuln_time_remaining = _health_component.get_invulnerability_remaining()
	if _invuln_time_remaining > 0.0:
		_update_invulnerability_flash_visual()


func _play_melee_attack_presentation() -> void:
	_set_visual_attack_planar_direction(_normalized_attack_facing(_facing_planar))
	_play_attack_animation_presentation(&"melee")
	_attack_hitbox_visual_time_remaining = maxf(
		_attack_hitbox_visual_time_remaining,
		attack_hitbox_visual_duration
	)


func _play_attack_animation_presentation(mode: StringName = &"melee") -> void:
	_start_facing_lock(_facing_planar, _resolve_visual_facing_lock_duration(mode))
	if _visual == null:
		return
	if _visual.has_method(&"try_play_attack_for_mode"):
		_visual.call(&"try_play_attack_for_mode", mode)
	elif _visual.has_method(&"try_play_attack"):
		_visual.call(&"try_play_attack")


func _set_visual_attack_planar_direction(planar_direction: Vector2) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	if not _visual.has_method(&"set_attack_planar_direction"):
		return
	_visual.call(&"set_attack_planar_direction", planar_direction)


func _normalized_attack_facing(facing: Vector2) -> Vector2:
	if facing.length_squared() > 1e-6:
		return facing.normalized()
	if _facing_planar.length_squared() > 1e-6:
		return _facing_planar.normalized()
	return Vector2(0.0, -1.0)


func _compute_ranged_spawn(facing: Vector2) -> Vector2:
	return global_position + facing * (_get_player_body_radius() + ranged_spawn_beyond_body)


## Echo handgun twin: roll once before spawning the primary so server RPC matches simulation.
func _echo_handgun_build_twin_plan(
	primary_spawn: Vector2, facing: Vector2, primary_projectile_event_id: int
) -> Dictionary:
	var echo_th := _infusion_echo_threshold()
	var plan := {
		"active": false,
		"twin_id": 0,
		"twin_spawn": Vector2.ZERO,
		"twin_ratio": 1.0,
	}
	if not InfusionEchoRef.is_echo_attuned(echo_th):
		return plan
	if randf() >= InfusionEchoRef.projectile_twin_chance(echo_th):
		return plan
	var fn := facing.normalized() if facing.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	var back := InfusionEchoRef.projectile_twin_behind_distance(echo_th)
	plan["active"] = true
	plan["twin_id"] = (
		primary_projectile_event_id + 1000000000
		if primary_projectile_event_id > 0
		else -2
	)
	plan["twin_spawn"] = primary_spawn - fn * back
	plan["twin_ratio"] = InfusionEchoRef.projectile_twin_damage_ratio(echo_th)
	return plan


func _echo_handgun_spawn_twin_from_plan(
	plan: Dictionary,
	facing: Vector2,
	projectile_style_id: StringName,
	charge_size_mult: float,
	infusion_geometry_scale: float,
	authoritative_damage: bool
) -> void:
	if not bool(plan.get("active", false)):
		return
	_spawn_player_ranged_arrow(
		plan["twin_spawn"] as Vector2,
		facing,
		authoritative_damage,
		false,
		int(plan["twin_id"]),
		projectile_style_id,
		charge_size_mult,
		infusion_geometry_scale,
		float(plan["twin_ratio"]),
		true
	)


func _spawn_player_ranged_arrow(
	spawn_position: Vector2,
	facing: Vector2,
	authoritative_damage: bool,
	apply_cooldown: bool,
	projectile_event_id: int = -1,
	projectile_style_id: StringName = LoadoutConstantsRef.PROJECTILE_STYLE_RED,
	charge_size_mult: float = 1.0,
	infusion_geometry_scale: float = 0.0,
	damage_ratio: float = 1.0,
	echo_twin_visual: bool = false
) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	if not authoritative_damage and projectile_event_id > 0:
		var existing_v: Variant = _remote_ranged_projectiles_by_event_id.get(projectile_event_id, null)
		if existing_v is ArrowProjectile and is_instance_valid(existing_v):
			return true
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	var arrow := ArrowProjectilePoolScript.acquire_projectile(parent)
	if arrow == null:
		return false
	var dr := maxf(0.05, damage_ratio)
	arrow.damage = maxi(
		1, int(roundf(float(ranged_damage) * _phase_outgoing_damage_multiplier() * dr))
	)
	arrow.speed = ranged_speed
	arrow.max_distance = ranged_max_tiles * world_units_per_tile
	arrow.knockback_strength = ranged_knockback
	var expr_m := (
		infusion_geometry_scale
		if infusion_geometry_scale > 0.001
		else _infusion_edge_expression_geometry_mult()
	)
	var echo_vis := 0.82 if echo_twin_visual else 1.0
	arrow.mesh_scale = Vector3(1.6, 1.6, 1.6) * expr_m * echo_vis
	if arrow.has_method(&"set_authoritative_damage"):
		arrow.call(&"set_authoritative_damage", authoritative_damage)
	arrow.configure(
		spawn_position,
		facing,
		vw,
		true,
		projectile_style_id,
		projectile_event_id,
		charge_size_mult * expr_m,
		InfusionPhaseRef.ranged_wall_pierce_hits(_infusion_phase_threshold()),
		self,
		echo_twin_visual
	)
	if authoritative_damage and _is_server_peer() and projectile_event_id > 0 and arrow.has_signal(&"projectile_finished"):
		arrow.projectile_finished.connect(
			_on_server_authoritative_ranged_projectile_finished.bind(projectile_event_id),
			CONNECT_ONE_SHOT
		)
	elif not authoritative_damage and projectile_event_id > 0:
		_remote_ranged_projectiles_by_event_id[projectile_event_id] = arrow
	if apply_cooldown:
		_ranged_cooldown_remaining = _flow_effective_ranged_cooldown()
	return true


func _spawn_player_bomb(
	spawn_position: Vector2,
	facing: Vector2,
	authoritative_damage: bool,
	apply_cooldown: bool,
	visual_style_id: StringName = LoadoutConstantsRef.PROJECTILE_STYLE_RED,
	attack_event_id: int = -1,
	expression_size_mult: float = 0.0
) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	var bomb := PLAYER_BOMB_SCENE.instantiate() as PlayerBomb
	if bomb == null:
		return false
	var geom := (
		expression_size_mult
		if expression_size_mult > 0.001
		else _infusion_edge_expression_geometry_mult()
	)
	var bomb_dmg := maxi(1, int(roundf(float(bomb_damage) * _phase_outgoing_damage_multiplier())))
	bomb.configure(
		spawn_position,
		facing,
		vw,
		bomb_dmg,
		bomb_aoe_radius,
		bomb_landing_distance,
		bomb_flight_time,
		bomb_arc_start_height,
		bomb_knockback_strength,
		authoritative_damage,
		visual_style_id,
		attack_event_id,
		geom
	)
	parent.add_child(bomb)
	if apply_cooldown:
		_bomb_cooldown_remaining = _flow_effective_bomb_cooldown()
	return true


func _try_execute_server_melee_attack(
	requested_facing: Vector2,
	charge_ratio: float = 1.0,
	apply_charge_scaling: bool = true,
	surge_overcharge_norm: float = 0.0
) -> bool:
	if not _is_server_peer() or _is_dead:
		return false
	if _is_defending:
		return false
	if weapon_mode != WeaponMode.SWORD or not _has_equipped_sword():
		return false
	if _melee_attack_cooldown_remaining > 0.0:
		return false
	var cr := clampf(charge_ratio, 0.0, 1.0)
	if apply_charge_scaling and cr < melee_charge_min_ratio:
		return false
	var ovn := _surge_validate_server_overcharge_norm(surge_overcharge_norm)
	var resolved_facing := requested_facing
	if resolved_facing.length_squared() > 1e-6:
		_facing_planar = resolved_facing.normalized()
	_phase_maybe_skew_melee_facing_warp()
	_start_facing_lock(_facing_planar)
	_play_melee_attack_presentation()
	_server_melee_hit_event_sequence += 1
	var hit_event_id := _server_melee_hit_event_sequence
	var st_surge := _infusion_surge_threshold()
	var od_full := _surge_overdrive_active and InfusionSurgeRef.is_surge_attuned(st_surge)
	var hit_count := _squash_mobs_in_melee_hit(
		hit_event_id, cr, apply_charge_scaling, ovn, od_full
	)
	var full_chg := (not apply_charge_scaling) or cr >= 0.999 or od_full
	if InfusionSurgeRef.is_surge_attuned(st_surge):
		var gain := InfusionSurgeRef.surge_energy_gain_from_melee(
			st_surge, hit_count, cr, full_chg, ovn
		)
		_surge_energy = minf(
			InfusionSurgeRef.surge_energy_max(), _surge_energy + maxf(0.0, gain)
		)
	if (
		hit_count > 0
		and InfusionSurgeRef.can_start_overdrive(st_surge, ovn, _surge_energy)
		and not _surge_overdrive_active
	):
		_surge_energy = maxf(0.0, _surge_energy - InfusionSurgeRef.overdrive_entry_energy_cost())
		_surge_overdrive_active = true
		_surge_overdrive_energy_sink = 0.0
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.MELEE)
	_flow_pulse_ability_cooldowns_after_melee()
	_melee_attack_cooldown_remaining = _flow_effective_melee_cooldown()
	if hit_count > 0:
		_anchor_maybe_timing_purge(false)
	_server_melee_event_sequence += 1
	var event_sequence := _server_melee_event_sequence
	_last_applied_melee_event_sequence = max(_last_applied_melee_event_sequence, event_sequence)
	var ph_t_melee_fx := _infusion_phase_threshold()
	var phase_ghost_delay := 0.0
	var phase_ghost_planar := Vector2.ZERO
	if InfusionPhaseRef.is_skew_or_higher(ph_t_melee_fx):
		phase_ghost_delay = (
			InfusionPhaseRef.ghost_strike_delay_min_sec(ph_t_melee_fx)
			+ InfusionPhaseRef.ghost_strike_delay_max_sec(ph_t_melee_fx)
		) * 0.5
		phase_ghost_planar = global_position
	if phase_ghost_delay > 0.001 and _visual != null and _visual.has_method(&"show_phase_spatial_cue"):
		_visual.call(&"show_phase_spatial_cue", phase_ghost_planar, phase_ghost_delay)
	if _can_broadcast_world_replication():
		_rpc_receive_melee_attack_event.rpc(
			event_sequence,
			_facing_planar,
			hit_count,
			_flow_tempo,
			_flow_chain_remaining,
			_flow_overdrive_remaining,
			_flow_aggression_remaining,
			_flow_last_action_kind,
			phase_ghost_planar,
			phase_ghost_delay
		)
	if OS.is_debug_build():
		print(
			"[M4][Melee] peer=%s attack_event=%s hit_event=%s hits=%s" % [
				network_owner_peer_id,
				event_sequence,
				hit_event_id,
				hit_count,
			]
		)
	return true


func _ranged_projectile_charge_size_mult(
	charge_ratio: float, apply_charge_scaling: bool
) -> float:
	if not apply_charge_scaling:
		return 1.0
	return lerpf(1.0, ranged_charge_max_scale, clampf(charge_ratio, 0.0, 1.0))


func _try_execute_server_ranged_attack(
	requested_facing: Vector2, charge_ratio: float = 1.0, apply_charge_scaling: bool = true
) -> bool:
	if not _is_server_peer() or _is_dead:
		return false
	if _is_defending:
		return false
	if weapon_mode != WeaponMode.GUN or not _has_equipped_handgun():
		return false
	if _ranged_cooldown_remaining > 0.0:
		return false
	var cr := clampf(charge_ratio, 0.0, 1.0)
	if apply_charge_scaling and cr < melee_charge_min_ratio:
		return false
	var resolved_facing := _normalized_attack_facing(requested_facing)
	_facing_planar = resolved_facing
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"ranged")
	var spawn := _compute_ranged_spawn(_facing_planar)
	var sz := _ranged_projectile_charge_size_mult(cr, apply_charge_scaling)
	_server_ranged_event_sequence += 1
	var event_sequence := _server_ranged_event_sequence
	var projectile_style_id := _equipped_handgun_projectile_style()
	var twin_plan := _echo_handgun_build_twin_plan(spawn, _facing_planar, event_sequence)
	var twin_event_id: int = int(twin_plan["twin_id"]) if bool(twin_plan["active"]) else 0
	var twin_spawn: Vector2 = twin_plan["twin_spawn"]
	var twin_ratio: float = float(twin_plan["twin_ratio"])
	if not _spawn_player_ranged_arrow(
		spawn,
		_facing_planar,
		true,
		true,
		event_sequence,
		projectile_style_id,
		sz,
		0.0,
		1.0
	):
		return false
	_echo_handgun_spawn_twin_from_plan(
		twin_plan, _facing_planar, projectile_style_id, sz, 0.0, true
	)
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.RANGED)
	_last_applied_ranged_event_sequence = max(_last_applied_ranged_event_sequence, event_sequence)
	if _can_broadcast_world_replication():
		_rpc_receive_ranged_attack_event.rpc(
			event_sequence,
			spawn,
			_facing_planar,
			String(projectile_style_id),
			cr,
			apply_charge_scaling,
			_infusion_edge_expression_geometry_mult(),
			_flow_tempo,
			_flow_chain_remaining,
			_flow_overdrive_remaining,
			_flow_aggression_remaining,
			_flow_last_action_kind,
			twin_event_id,
			twin_spawn,
			twin_ratio
		)
	if OS.is_debug_build():
		print(
			"[M4][Ranged] peer=%s attack_event=%s spawn=%s" % [
				network_owner_peer_id,
				event_sequence,
				spawn,
			]
		)
	return true


func _try_execute_server_bomb_attack(requested_facing: Vector2) -> bool:
	if not _is_server_peer() or _is_dead:
		return false
	if _is_defending:
		return false
	if not _has_equipped_bomb():
		return false
	if _bomb_cooldown_remaining > 0.0:
		return false
	var resolved_facing := _normalized_attack_facing(requested_facing)
	_facing_planar = resolved_facing
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"bomb")
	var bomb_visual_style_id := _equipped_bomb_visual_style()
	var event_sequence := _server_bomb_event_sequence + 1
	if not _spawn_player_bomb(
		global_position,
		_facing_planar,
		true,
		true,
		bomb_visual_style_id,
		event_sequence
	):
		return false
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.BOMB)
	_server_bomb_event_sequence = event_sequence
	_last_applied_bomb_event_sequence = max(_last_applied_bomb_event_sequence, event_sequence)
	if _can_broadcast_world_replication():
		_rpc_receive_bomb_attack_event.rpc(
			event_sequence,
			global_position,
			_facing_planar,
			String(bomb_visual_style_id),
			_infusion_edge_expression_geometry_mult(),
			_flow_tempo,
			_flow_chain_remaining,
			_flow_overdrive_remaining,
			_flow_aggression_remaining,
			_flow_last_action_kind
		)
	if OS.is_debug_build():
		print(
			"[M4][Bomb] peer=%s attack_event=%s origin=%s" % [
				network_owner_peer_id,
				event_sequence,
				global_position,
			]
		)
	return true


func _submit_local_melee_attack_request(
	charge_ratio: float = 1.0,
	apply_charge_scaling: bool = true,
	surge_overcharge_norm: float = 0.0
) -> void:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	if apply_charge_scaling and cr < melee_charge_min_ratio:
		return
	if (
		weapon_mode != WeaponMode.SWORD
		or not _has_equipped_sword()
		or _melee_attack_cooldown_remaining > 0.0
		or _is_defending
	):
		return
	if _is_server_peer():
		_try_execute_server_melee_attack(_facing_planar, cr, apply_charge_scaling, surge_overcharge_norm)
		return
	if not _can_broadcast_world_replication():
		return
	_local_melee_request_sequence += 1
	_start_facing_lock(_facing_planar)
	_rpc_request_melee_attack.rpc_id(
		1,
		_local_melee_request_sequence,
		_facing_planar,
		cr,
		apply_charge_scaling,
		surge_overcharge_norm
	)
	# Client-side throttle while awaiting authoritative result.
	_melee_attack_cooldown_remaining = _flow_effective_melee_cooldown()


func _submit_local_ranged_attack_request(
	charge_ratio: float = 1.0, apply_charge_scaling: bool = true
) -> void:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	if apply_charge_scaling and cr < melee_charge_min_ratio:
		return
	if (
		weapon_mode != WeaponMode.GUN
		or not _has_equipped_handgun()
		or _ranged_cooldown_remaining > 0.0
		or _is_defending
	):
		return
	if _is_server_peer():
		_try_execute_server_ranged_attack(_facing_planar, cr, apply_charge_scaling)
		return
	if not _can_broadcast_world_replication():
		return
	_local_ranged_request_sequence += 1
	_start_facing_lock(_facing_planar)
	_rpc_request_ranged_attack.rpc_id(
		1, _local_ranged_request_sequence, _facing_planar, cr, apply_charge_scaling
	)
	_ranged_cooldown_remaining = _flow_effective_ranged_cooldown()


func _submit_local_bomb_attack_request() -> void:
	if not _has_equipped_bomb() or _bomb_cooldown_remaining > 0.0 or _is_defending:
		return
	if _is_server_peer():
		_try_execute_server_bomb_attack(_facing_planar)
		return
	if not _can_broadcast_world_replication():
		return
	_local_bomb_request_sequence += 1
	_start_facing_lock(_facing_planar)
	_rpc_request_bomb_attack.rpc_id(1, _local_bomb_request_sequence, _facing_planar)
	_bomb_cooldown_remaining = _flow_effective_bomb_cooldown()


func _submit_local_weapon_switch_request() -> void:
	if _is_dead:
		return
	if _available_main_weapon_modes().is_empty():
		_coerce_weapon_mode_to_available(true)
		return
	if _is_server_peer():
		_cycle_weapon()
		return
	if not _can_broadcast_world_replication():
		return
	_local_weapon_switch_request_sequence += 1
	_cycle_weapon()
	_rpc_request_cycle_weapon.rpc_id(1, _local_weapon_switch_request_sequence)


func _handle_local_multiplayer_combat_input(delta: float) -> void:
	if not _is_local_owner_peer() or _is_dead:
		return
	var use_wasd := _is_wasd_mouse_scheme_enabled()
	if _menu_input_blocked:
		_rmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		_lmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		_clear_pending_rmb_attack()
		return
	var defend_down := Input.is_action_pressed(&"defend") and _can_defend_in_current_mode()
	if Input.is_action_just_pressed(&"weapon_switch"):
		_clear_pending_rmb_attack()
		_submit_local_weapon_switch_request()
	if Input.is_action_just_pressed(&"bomb_throw"):
		_clear_pending_rmb_attack()
		_face_toward_mouse_planar()
		_submit_local_bomb_attack_request()
	var ui_blocks_attack := _ui_blocks_attack_this_physics_frame()
	_process_local_melee_charge_input(delta, use_wasd, ui_blocks_attack, defend_down, true)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_cycle_weapon(request_sequence: int) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_weapon_switch_request_sequence:
		return
	_server_last_weapon_switch_request_sequence = request_sequence
	_cycle_weapon()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_melee_attack(
	request_sequence: int,
	facing_planar: Vector2,
	charge_ratio: float = 1.0,
	apply_charge_scaling: bool = true,
	surge_overcharge_norm: float = 0.0
) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_melee_request_sequence:
		return
	var cr := clampf(charge_ratio, 0.0, 1.0)
	if apply_charge_scaling and cr < melee_charge_min_ratio:
		return
	_server_last_melee_request_sequence = request_sequence
	var ovn := _surge_validate_server_overcharge_norm(surge_overcharge_norm)
	_try_execute_server_melee_attack(facing_planar, cr, apply_charge_scaling, ovn)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_surge_charge_field_report(
	charge_r: float, overcharge_norm: float, active: bool
) -> void:
	if not _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != network_owner_peer_id:
		return
	_surge_server_field_active = active
	_surge_server_field_charge_r = clampf(charge_r, 0.0, 1.0)
	_surge_server_field_over_n = clampf(overcharge_norm, 0.0, 2.0)
	if active:
		_surge_server_field_until_msec = Time.get_ticks_msec() + 320
	else:
		_surge_server_field_until_msec = Time.get_ticks_msec() + 40


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_ranged_attack(
	request_sequence: int,
	facing_planar: Vector2,
	charge_ratio: float = 1.0,
	apply_charge_scaling: bool = true
) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_ranged_request_sequence:
		return
	var cr := clampf(charge_ratio, 0.0, 1.0)
	if apply_charge_scaling and cr < melee_charge_min_ratio:
		return
	_server_last_ranged_request_sequence = request_sequence
	_try_execute_server_ranged_attack(facing_planar, cr, apply_charge_scaling)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_bomb_attack(request_sequence: int, facing_planar: Vector2) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_bomb_request_sequence:
		return
	_server_last_bomb_request_sequence = request_sequence
	_try_execute_server_bomb_attack(facing_planar)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_loadout_equip(request_sequence: int, item_id: StringName) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_loadout_request_sequence:
		return
	_server_last_loadout_request_sequence = request_sequence
	_request_local_or_server_loadout_change(&"equip", item_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_loadout_unequip(request_sequence: int, slot_id: StringName) -> void:
	if not _is_server_peer():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	if sender_peer != network_owner_peer_id:
		return
	if request_sequence <= _server_last_loadout_request_sequence:
		return
	_server_last_loadout_request_sequence = request_sequence
	_request_local_or_server_loadout_change(&"unequip", slot_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_melee_attack_event(
	event_sequence: int,
	facing_planar: Vector2,
	hit_count: int,
	flow_tempo: float = 0.0,
	flow_chain_remaining: float = 0.0,
	flow_overdrive_remaining: float = 0.0,
	flow_aggression_remaining: float = 0.0,
	flow_last_action_kind: int = -1,
	phase_ghost_planar: Vector2 = Vector2.ZERO,
	phase_ghost_delay: float = 0.0
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_melee_event_sequence:
		return
	_last_applied_melee_event_sequence = event_sequence
	if facing_planar.length_squared() > 1e-6:
		_facing_planar = facing_planar.normalized()
	_flow_merge_state_from_network(
		flow_tempo,
		flow_chain_remaining,
		flow_overdrive_remaining,
		flow_aggression_remaining,
		flow_last_action_kind
	)
	_start_facing_lock(_facing_planar)
	_play_melee_attack_presentation()
	_melee_attack_cooldown_remaining = maxf(
		_melee_attack_cooldown_remaining, _flow_effective_melee_cooldown()
	)
	if phase_ghost_delay > 0.001 and _visual != null and _visual.has_method(&"show_phase_spatial_cue"):
		_visual.call(&"show_phase_spatial_cue", phase_ghost_planar, phase_ghost_delay)
	if OS.is_debug_build():
		print(
			"[M4][Melee][Remote] peer=%s attack_event=%s hits=%s" % [
				network_owner_peer_id,
				event_sequence,
				hit_count,
			]
		)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_echo_melee_smear_vfx(planar_dir: Vector2) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if _visual != null and _visual.has_method(&"spawn_echo_melee_smear"):
		_visual.call(&"spawn_echo_melee_smear", planar_dir)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_ranged_attack_event(
	event_sequence: int,
	spawn_position: Vector2,
	facing_planar: Vector2,
	projectile_style_id: String,
	charge_ratio: float = 1.0,
	apply_charge_scaling: bool = false,
	infusion_expr_mult: float = 1.0,
	flow_tempo: float = 0.0,
	flow_chain_remaining: float = 0.0,
	flow_overdrive_remaining: float = 0.0,
	flow_aggression_remaining: float = 0.0,
	flow_last_action_kind: int = -1,
	echo_twin_event_id: int = 0,
	echo_twin_spawn: Vector2 = Vector2.ZERO,
	echo_twin_damage_ratio: float = 1.0
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_ranged_event_sequence:
		return
	_last_applied_ranged_event_sequence = event_sequence
	_flow_merge_state_from_network(
		flow_tempo,
		flow_chain_remaining,
		flow_overdrive_remaining,
		flow_aggression_remaining,
		flow_last_action_kind
	)
	var dir := _normalized_attack_facing(facing_planar)
	_facing_planar = dir
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"ranged")
	var cr := clampf(charge_ratio, 0.0, 1.0)
	var sz_charge := _ranged_projectile_charge_size_mult(cr, apply_charge_scaling)
	var expr_m := maxf(1.0, infusion_expr_mult)
	_spawn_player_ranged_arrow(
		spawn_position,
		dir,
		false,
		false,
		event_sequence,
		StringName(projectile_style_id),
		sz_charge,
		expr_m,
		1.0
	)
	if echo_twin_event_id != 0:
		_spawn_player_ranged_arrow(
			echo_twin_spawn,
			dir,
			false,
			false,
			echo_twin_event_id,
			StringName(projectile_style_id),
			sz_charge,
			expr_m,
			maxf(0.05, echo_twin_damage_ratio),
			true
		)
	_ranged_cooldown_remaining = maxf(
		_ranged_cooldown_remaining, _flow_effective_ranged_cooldown()
	)
	if OS.is_debug_build():
		print(
			"[M4][Ranged][Remote] peer=%s attack_event=%s spawn=%s twin=%s" % [
				network_owner_peer_id,
				event_sequence,
				spawn_position,
				echo_twin_event_id,
			]
		)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_bomb_attack_event(
	event_sequence: int,
	spawn_position: Vector2,
	facing_planar: Vector2,
	bomb_visual_style: String = "red",
	infusion_expr_mult: float = 1.0,
	flow_tempo: float = 0.0,
	flow_chain_remaining: float = 0.0,
	flow_overdrive_remaining: float = 0.0,
	flow_aggression_remaining: float = 0.0,
	flow_last_action_kind: int = -1
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_bomb_event_sequence:
		return
	_last_applied_bomb_event_sequence = event_sequence
	_flow_merge_state_from_network(
		flow_tempo,
		flow_chain_remaining,
		flow_overdrive_remaining,
		flow_aggression_remaining,
		flow_last_action_kind
	)
	var dir := _normalized_attack_facing(facing_planar)
	var bomb_visual_style_id := StringName(bomb_visual_style)
	_facing_planar = dir
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"bomb")
	_spawn_player_bomb(
		spawn_position,
		dir,
		false,
		false,
		bomb_visual_style_id,
		event_sequence,
		maxf(1.0, infusion_expr_mult)
	)
	_bomb_cooldown_remaining = maxf(_bomb_cooldown_remaining, _flow_effective_bomb_cooldown())
	if OS.is_debug_build():
		print(
			"[M4][Bomb][Remote] peer=%s attack_event=%s origin=%s" % [
				network_owner_peer_id,
				event_sequence,
				spawn_position,
			]
		)


func _on_server_authoritative_ranged_projectile_finished(
	final_position: Vector2, projectile_event_id: int
) -> void:
	if not _is_server_peer():
		return
	if not _multiplayer_active():
		return
	if not _can_broadcast_world_replication():
		return
	_rpc_receive_ranged_projectile_finished.rpc(projectile_event_id, final_position)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_ranged_projectile_finished(
	projectile_event_id: int, final_position: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var projectile_v: Variant = _remote_ranged_projectiles_by_event_id.get(projectile_event_id, null)
	if projectile_v == null or not is_instance_valid(projectile_v):
		_remote_ranged_projectiles_by_event_id.erase(projectile_event_id)
		return
	var projectile := projectile_v as ArrowProjectile
	if projectile == null:
		_remote_ranged_projectiles_by_event_id.erase(projectile_event_id)
		return
	projectile.global_position = final_position
	if projectile.has_method(&"_finish_projectile"):
		projectile.call(&"_finish_projectile")
	else:
		projectile.queue_free()
	_remote_ranged_projectiles_by_event_id.erase(projectile_event_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_loadout_snapshot(snapshot: Dictionary) -> void:
	if _multiplayer_active() and not _is_server_peer() and multiplayer.get_remote_sender_id() != 1:
		return
	apply_authoritative_loadout_snapshot(snapshot)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_loadout_request_failed(message: String) -> void:
	if _multiplayer_active() and not _is_server_peer() and multiplayer.get_remote_sender_id() != 1:
		return
	loadout_request_failed.emit(message)


func _physics_process_multiplayer(delta: float) -> void:
	_run_shared_cooldown_and_debug_tick(delta)
	_handle_local_multiplayer_combat_input(delta)
	if _is_dead:
		if _is_server_peer():
			_broadcast_server_state(delta)
		elif _is_local_owner_peer():
			_apply_local_reconciliation(delta)
		return
	if _is_server_peer():
		_server_authoritative_step(delta)
		return
	if _is_local_owner_peer():
		_client_predicted_step(delta)
		return
	_client_remote_step(delta)


# --- Debug UI snapshot (gameplay state; mesh drawing is on player.gd) ---
func get_combat_debug_snapshot() -> Dictionary:
	var authoritative_weapon_display := _weapon_mode_display_from_id(_authoritative_weapon_mode_id)
	if _loadout_snapshot.is_empty():
		authoritative_weapon_display = _weapon_mode_display_from_id(_authoritative_weapon_mode_id)
	elif not _has_equipped_sword() and not _has_equipped_handgun():
		authoritative_weapon_display = "None"
	return {
		"weapon_mode": get_weapon_mode_display(),
		"weapon_mode_id": int(weapon_mode),
		"authoritative_weapon_mode": authoritative_weapon_display,
		"authoritative_weapon_mode_id": _authoritative_weapon_mode_id,
		"is_downed": _is_dead,
		"stamina": stamina,
		"authoritative_stamina": _authoritative_stamina,
		"stamina_broken": _stamina_broken,
		"authoritative_stamina_broken": _authoritative_stamina_broken,
		"stamina_regen_cooldown": maxf(0.0, _stamina_regen_cooldown_remaining),
		"melee_cooldown": maxf(0.0, _melee_attack_cooldown_remaining),
		"ranged_cooldown": maxf(0.0, _ranged_cooldown_remaining),
		"bomb_cooldown": maxf(0.0, _bomb_cooldown_remaining),
		"authoritative_melee_cooldown": maxf(0.0, _authoritative_melee_cooldown_remaining),
		"authoritative_ranged_cooldown": maxf(0.0, _authoritative_ranged_cooldown_remaining),
		"authoritative_bomb_cooldown": maxf(0.0, _authoritative_bomb_cooldown_remaining),
		"is_defending": _is_defending,
		"authoritative_is_defending": _authoritative_is_defending,
		"facing_lock_time": maxf(0.0, _facing_lock_time_remaining),
		"is_server_peer": _is_server_peer(),
		"is_local_owner_peer": _is_local_owner_peer(),
		"network_owner_peer_id": network_owner_peer_id,
		"multiplayer_authority": get_multiplayer_authority(),
		"local_peer_id": _local_peer_id(),
		"has_peer": _multiplayer_active(),
		"flow_tempo": _flow_tempo,
		"flow_chain_remaining": _flow_chain_remaining,
		"flow_overdrive_remaining": _flow_overdrive_remaining,
		"flow_aggression_remaining": _flow_aggression_remaining,
		"flow_last_action_kind": _flow_last_action_kind,
		"anchor_pressure": _anchor_pressure,
		"anchor_micro_shield": _anchor_micro_shield,
		"anchor_bastion_charge": _anchor_bastion_charge,
		"anchor_rooted": _anchor_rooted,
		"anchor_critical_bastion": _anchor_critical_bastion,
		"enemy_dash_blocked": _external_dash_blocked,
		"enemy_movement_rooted": _external_movement_rooted,
		"enemy_root_origin": _external_root_origin_position,
		"enemy_root_pull_used": _external_root_pull_used,
		"leecher_escape_progress": _external_leecher_escape_progress,
		"latched_enemy_id": _external_latched_enemy_id,
	}


func _any_runtime_debug_visual_enabled() -> bool:
	return (
		(show_melee_hit_debug and _attack_hitbox_visual_time_remaining > 0.0)
		or show_player_hitbox_debug
		or show_mob_hitbox_debug
		or show_shield_block_debug
	)


func _refresh_debug_visuals(delta: float, force: bool = false) -> void:
	if not _any_runtime_debug_visual_enabled():
		_debug_visual_refresh_time_remaining = 0.0
		if _melee_debug_mi != null:
			_melee_debug_mi.visible = false
		if _player_hitbox_mi != null:
			_player_hitbox_mi.visible = false
		if _shield_block_debug_mi != null:
			_shield_block_debug_mi.visible = false
		if _mob_hitboxes_mi != null:
			_mob_hitboxes_mi.visible = false
		return
	_debug_visual_refresh_time_remaining = maxf(0.0, _debug_visual_refresh_time_remaining - delta)
	if not force and _debug_visual_refresh_time_remaining > 0.0:
		return
	_debug_visual_refresh_time_remaining = maxf(0.02, debug_visual_update_interval)
	if show_melee_hit_debug and _attack_hitbox_visual_time_remaining > 0.0:
		if has_method(&"_rebuild_melee_debug_mesh"):
			call(&"_rebuild_melee_debug_mesh")
	elif _melee_debug_mi:
		_melee_debug_mi.visible = false
	if show_player_hitbox_debug:
		if has_method(&"_rebuild_player_hitbox_debug"):
			call(&"_rebuild_player_hitbox_debug")
	elif _player_hitbox_mi:
		_player_hitbox_mi.visible = false
	if show_shield_block_debug:
		if has_method(&"_rebuild_shield_block_debug_mesh"):
			call(&"_rebuild_shield_block_debug_mesh")
	elif _shield_block_debug_mi:
		_shield_block_debug_mi.visible = false
	if show_mob_hitbox_debug:
		if has_method(&"_rebuild_mob_hitboxes_debug"):
			call(&"_rebuild_mob_hitboxes_debug")
	elif _mob_hitboxes_mi:
		_mob_hitboxes_mi.visible = false


func _rebuild_visual_mesh_instance_cache() -> void:
	_cached_visual_mesh_instances.clear()
	_last_invulnerability_flash_state = -1
	if _visual == null or not is_instance_valid(_visual):
		return
	_collect_visual_mesh_instances_recursive(_visual)


func _collect_visual_mesh_instances_recursive(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			_cached_visual_mesh_instances.append(child as MeshInstance3D)
		_collect_visual_mesh_instances_recursive(child)


func _weapon_mode_display_from_id(mode_id: int) -> String:
	match mode_id:
		int(WeaponMode.GUN):
			return "Gun"
		_:
			return "Sword"


func get_weapon_mode_display() -> String:
	var available_modes: Array = _available_main_weapon_modes()
	if available_modes.is_empty():
		return "None"
	if available_modes.find(weapon_mode) < 0:
		return _weapon_mode_display_from_id(int(available_modes[0]))
	return _weapon_mode_display_from_id(int(weapon_mode))


func is_downed() -> bool:
	return _is_dead


func _cycle_weapon() -> void:
	if _is_dead:
		return
	var available_modes: Array = _available_main_weapon_modes()
	if available_modes.is_empty():
		_coerce_weapon_mode_to_available(true)
		return
	if available_modes.size() == 1:
		weapon_mode = available_modes[0]
		_coerce_weapon_mode_to_available(true)
		return
	var mode_index := available_modes.find(weapon_mode)
	if mode_index < 0:
		weapon_mode = available_modes[0]
	else:
		weapon_mode = available_modes[(mode_index + 1) % available_modes.size()]
	_coerce_weapon_mode_to_available(true)


func _face_toward_mouse_planar() -> void:
	if _is_facing_locked():
		return
	var t := _mouse_planar_world() - global_position
	if t.length_squared() > 0.0001:
		_facing_planar = t.normalized()


func _clear_pending_rmb_attack() -> void:
	_pending_rmb_kind = &""
	_cancel_melee_charge()
	_cancel_ranged_charge()


func _clear_melee_attack_hold_state() -> void:
	_melee_charging = false
	_melee_charge_pre_hold_time = 0.0
	_melee_charge_past_commit_delay = false
	_melee_charge_time = 0.0
	_melee_charge_input_source = _MELEE_CHARGE_SRC_NONE
	_surge_melee_overcharge_time = 0.0
	_update_melee_charge_bar_visual(-1.0)


func _clear_ranged_attack_hold_state() -> void:
	_ranged_charging = false
	_ranged_charge_pre_hold_time = 0.0
	_ranged_charge_past_commit_delay = false
	_ranged_charge_time = 0.0
	_ranged_charge_input_source = _MELEE_CHARGE_SRC_NONE
	_update_melee_charge_bar_visual(-1.0)


func _cancel_melee_charge() -> void:
	if not _melee_charging:
		return
	_clear_melee_attack_hold_state()


func _cancel_ranged_charge() -> void:
	if not _ranged_charging:
		return
	_clear_ranged_attack_hold_state()


func _update_melee_charge_bar_visual(charge_ratio: float) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	if not _visual.has_method(&"set_melee_charge_progress"):
		return
	_visual.call(&"set_melee_charge_progress", charge_ratio)


func _melee_damage_for_charge_ratio(charge_ratio: float) -> int:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	var m := lerpf(melee_charge_damage_min_mult, melee_charge_damage_max_mult, cr)
	return maxi(1, int(roundf(float(melee_attack_damage) * m)))


func _melee_knockback_for_charge_ratio(charge_ratio: float) -> float:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	return melee_knockback_strength * lerpf(
		melee_charge_knockback_min_mult, melee_charge_knockback_max_mult, cr
	)


func _charge_hold_release_detected(
	input_source: int,
	use_wasd: bool,
	lmb_was: bool,
	rmb_was: bool,
	lmb_cur: bool,
	rmb_cur: bool
) -> bool:
	match input_source:
		_MELEE_CHARGE_SRC_MELEE_ACTION:
			return Input.is_action_just_released(&"melee_attack")
		_:
			if use_wasd:
				return lmb_was and not lmb_cur
			return rmb_was and not rmb_cur


func _process_local_melee_charge_input(
	delta: float,
	use_wasd: bool,
	ui_blocks_attack: bool,
	defend_down: bool,
	input_allowed: bool
) -> void:
	var lmb_was := _lmb_down
	var rmb_was := _rmb_down
	var lmb_cur := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) if input_allowed else false
	var rmb_cur := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) if input_allowed else false

	if not input_allowed:
		_cancel_melee_charge()
		_cancel_ranged_charge()
		_lmb_down = lmb_cur
		_rmb_down = rmb_cur
		return

	if defend_down or ui_blocks_attack:
		_cancel_melee_charge()
		_cancel_ranged_charge()

	if (
		weapon_mode == WeaponMode.SWORD
		and _has_equipped_sword()
		and _melee_attack_cooldown_remaining <= 0.0
		and not defend_down
		and not ui_blocks_attack
		and not _is_defending
	):
		if _melee_charging:
			_face_toward_mouse_planar()
			if not _melee_charge_past_commit_delay:
				_melee_charge_pre_hold_time += delta
				if _melee_charge_pre_hold_time >= melee_charge_commit_delay:
					_melee_charge_past_commit_delay = true
					_melee_charge_time = 0.0
					_update_melee_charge_bar_visual(0.0)
				elif _charge_hold_release_detected(
					_melee_charge_input_source, use_wasd, lmb_was, rmb_was, lmb_cur, rmb_cur
				):
					_commit_melee_strike(0.0, false, false)

			if _melee_charge_past_commit_delay:
				_melee_charge_time += delta
				var denom := maxf(0.05, _flow_effective_melee_charge_max_time())
				var raw_t := _melee_charge_time / denom
				var st_surge := _infusion_surge_threshold()
				var allow_surge_over := InfusionSurgeRef.allows_melee_overcharge_hold(st_surge)
				var r_bar := minf(1.0, raw_t)
				if allow_surge_over and raw_t >= 1.0:
					var max_over := InfusionSurgeRef.overcharge_max_hold_sec(st_surge)
					if max_over > 0.0:
						_surge_melee_overcharge_time = minf(_surge_melee_overcharge_time + delta, max_over)
					else:
						_surge_melee_overcharge_time = 0.0
					_update_melee_charge_bar_visual(1.0)
					if _charge_hold_release_detected(
						_melee_charge_input_source, use_wasd, lmb_was, rmb_was, lmb_cur, rmb_cur
					):
						_commit_melee_strike(
							1.0, true, true, _surge_current_melee_overcharge_norm()
						)
				else:
					_surge_melee_overcharge_time = 0.0
					_update_melee_charge_bar_visual(r_bar)
					if r_bar >= 1.0:
						_commit_melee_strike(1.0, true, false, 0.0)
					elif _charge_hold_release_detected(
						_melee_charge_input_source, use_wasd, lmb_was, rmb_was, lmb_cur, rmb_cur
					):
						if r_bar >= melee_charge_min_ratio:
							_commit_melee_strike(r_bar, true, true, 0.0)
						else:
							_cancel_melee_charge()
		else:
			var want_start := Input.is_action_just_pressed(&"melee_attack")
			if use_wasd:
				want_start = want_start or (lmb_cur and not lmb_was)
			else:
				want_start = want_start or (rmb_cur and not rmb_was)
			if want_start:
				_cancel_ranged_charge()
				_melee_charging = true
				_melee_charge_time = 0.0
				if Input.is_action_just_pressed(&"melee_attack"):
					_melee_charge_input_source = _MELEE_CHARGE_SRC_MELEE_ACTION
					_melee_charge_pre_hold_time = melee_charge_commit_delay
					_melee_charge_past_commit_delay = true
					_update_melee_charge_bar_visual(0.0)
				else:
					_melee_charge_input_source = _MELEE_CHARGE_SRC_MOUSE_PRIMARY
					_melee_charge_pre_hold_time = 0.0
					_melee_charge_past_commit_delay = false
				_face_toward_mouse_planar()

	elif (
		weapon_mode == WeaponMode.GUN
		and _has_equipped_handgun()
		and _ranged_cooldown_remaining <= 0.0
		and not defend_down
		and not ui_blocks_attack
		and not _is_defending
	):
		if _ranged_charging:
			_face_toward_mouse_planar()
			if not _ranged_charge_past_commit_delay:
				_ranged_charge_pre_hold_time += delta
				if _ranged_charge_pre_hold_time >= melee_charge_commit_delay:
					_ranged_charge_past_commit_delay = true
					_ranged_charge_time = 0.0
					_update_melee_charge_bar_visual(0.0)
				elif _charge_hold_release_detected(
					_ranged_charge_input_source, use_wasd, lmb_was, rmb_was, lmb_cur, rmb_cur
				):
					_commit_ranged_strike(0.0, false, false)

			if _ranged_charge_past_commit_delay:
				_ranged_charge_time += delta
				var r_r := minf(1.0, _ranged_charge_time / maxf(0.05, melee_charge_max_time))
				_update_melee_charge_bar_visual(r_r)
				if r_r >= 1.0:
					_commit_ranged_strike(1.0, true, false)
				elif _charge_hold_release_detected(
					_ranged_charge_input_source, use_wasd, lmb_was, rmb_was, lmb_cur, rmb_cur
				):
					if r_r >= melee_charge_min_ratio:
						_commit_ranged_strike(r_r, true, true)
					else:
						_cancel_ranged_charge()
		else:
			var want_ranged := Input.is_action_just_pressed(&"melee_attack")
			if use_wasd:
				want_ranged = want_ranged or (lmb_cur and not lmb_was)
			else:
				want_ranged = want_ranged or (rmb_cur and not rmb_was)
			if want_ranged:
				_cancel_melee_charge()
				_ranged_charging = true
				_ranged_charge_time = 0.0
				if Input.is_action_just_pressed(&"melee_attack"):
					_ranged_charge_input_source = _MELEE_CHARGE_SRC_MELEE_ACTION
					_ranged_charge_pre_hold_time = melee_charge_commit_delay
					_ranged_charge_past_commit_delay = true
					_update_melee_charge_bar_visual(0.0)
				else:
					_ranged_charge_input_source = _MELEE_CHARGE_SRC_MOUSE_PRIMARY
					_ranged_charge_pre_hold_time = 0.0
					_ranged_charge_past_commit_delay = false
				_face_toward_mouse_planar()

	_lmb_down = lmb_cur
	_rmb_down = rmb_cur
	_surge_maybe_report_charge_field_to_server(delta)


func _commit_melee_strike(
	charge_ratio: float,
	apply_charge_scaling: bool,
	enforce_min_ratio: bool,
	surge_overcharge_norm: float = 0.0
) -> void:
	if not _melee_charging:
		return
	var cr := clampf(charge_ratio, 0.0, 1.0)
	_clear_melee_attack_hold_state()
	if apply_charge_scaling and enforce_min_ratio and cr < melee_charge_min_ratio:
		return
	if _multiplayer_active():
		if _is_server_peer():
			_try_execute_server_melee_attack(
				_facing_planar, cr, apply_charge_scaling, surge_overcharge_norm
			)
		else:
			_submit_local_melee_attack_request(cr, apply_charge_scaling, surge_overcharge_norm)
	else:
		_execute_local_melee_strike(cr, apply_charge_scaling, surge_overcharge_norm)


func _execute_local_melee_strike(
	charge_ratio: float, apply_charge_scaling: bool = true, surge_overcharge_norm: float = 0.0
) -> void:
	_phase_maybe_skew_melee_facing_warp()
	_start_facing_lock(_facing_planar)
	_play_melee_attack_presentation()
	var ph_t_loc := _infusion_phase_threshold()
	if InfusionPhaseRef.is_skew_or_higher(ph_t_loc) and _visual != null and _visual.has_method(&"show_phase_spatial_cue"):
		var gdl := (
			InfusionPhaseRef.ghost_strike_delay_min_sec(ph_t_loc)
			+ InfusionPhaseRef.ghost_strike_delay_max_sec(ph_t_loc)
		) * 0.5
		_visual.call(&"show_phase_spatial_cue", global_position, gdl)
	var hit_count := _squash_mobs_in_melee_hit(
		-1, charge_ratio, apply_charge_scaling, surge_overcharge_norm
	)
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.MELEE)
	_flow_pulse_ability_cooldowns_after_melee()
	_melee_attack_cooldown_remaining = _flow_effective_melee_cooldown()
	if hit_count > 0:
		_anchor_maybe_timing_purge(false)


func _commit_ranged_strike(
	charge_ratio: float, apply_charge_scaling: bool, enforce_min_ratio: bool
) -> void:
	if not _ranged_charging:
		return
	var cr := clampf(charge_ratio, 0.0, 1.0)
	_clear_ranged_attack_hold_state()
	if apply_charge_scaling and enforce_min_ratio and cr < melee_charge_min_ratio:
		return
	if _multiplayer_active():
		if _is_server_peer():
			_try_execute_server_ranged_attack(_facing_planar, cr, apply_charge_scaling)
		else:
			_submit_local_ranged_attack_request(cr, apply_charge_scaling)
	else:
		_execute_local_ranged_strike(cr, apply_charge_scaling)


func _execute_local_ranged_strike(charge_ratio: float, apply_charge_scaling: bool = true) -> void:
	_start_facing_lock(_facing_planar)
	_play_attack_animation_presentation(&"ranged")
	var spawn := _compute_ranged_spawn(_facing_planar)
	var sz := _ranged_projectile_charge_size_mult(charge_ratio, apply_charge_scaling)
	var style := _equipped_handgun_projectile_style()
	var twin_plan := _echo_handgun_build_twin_plan(spawn, _facing_planar, -1)
	if not _spawn_player_ranged_arrow(
		spawn,
		_facing_planar,
		true,
		true,
		-1,
		style,
		sz
	):
		return
	_echo_handgun_spawn_twin_from_plan(twin_plan, _facing_planar, style, sz, 0.0, true)
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.RANGED)
	_ranged_cooldown_remaining = _flow_effective_ranged_cooldown()


func _queue_rmb_attack_after_facing_mouse() -> void:
	_face_toward_mouse_planar()
	_pending_rmb_facing = _facing_planar
	if weapon_mode == WeaponMode.GUN and _has_equipped_handgun() and _ranged_cooldown_remaining <= 0.0:
		_pending_rmb_kind = &"gun"


func _execute_pending_rmb_attack_if_any() -> void:
	if _is_defending:
		_pending_rmb_kind = &""
		return
	if _pending_rmb_kind == &"":
		return
	var kind := _pending_rmb_kind
	_pending_rmb_kind = &""
	_facing_planar = _pending_rmb_facing
	if kind == &"gun":
		if weapon_mode != WeaponMode.GUN or not _has_equipped_handgun() or _ranged_cooldown_remaining > 0.0:
			return
		_play_attack_animation_presentation(&"ranged")
		_try_fire_ranged_arrow()


func _try_throw_bomb() -> bool:
	if not _has_equipped_bomb() or _bomb_cooldown_remaining > 0.0 or _is_defending:
		return false
	var dir := _normalized_attack_facing(_facing_planar)
	_facing_planar = dir
	_start_facing_lock(_facing_planar)
	if not _spawn_player_bomb(global_position, dir, true, true, _equipped_bomb_visual_style()):
		return false
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.BOMB)
	return true


func _try_fire_ranged_arrow() -> void:
	if not _has_equipped_handgun():
		return
	var dir := _normalized_attack_facing(_facing_planar)
	_facing_planar = dir
	var spawn := _compute_ranged_spawn(dir)
	var style := _equipped_handgun_projectile_style()
	var twin_plan := _echo_handgun_build_twin_plan(spawn, dir, -1)
	if not _spawn_player_ranged_arrow(spawn, dir, true, true, -1, style):
		return
	_echo_handgun_spawn_twin_from_plan(twin_plan, dir, style, 1.0, 0.0, true)
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.RANGED)


func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0 or _is_dead or _damage_receiver == null:
		return
	var packet := _build_incoming_damage_packet(
		amount,
		&"direct",
		global_position,
		Vector2.ZERO,
		false
	)
	_damage_receiver.receive_damage(packet, _player_hurtbox)


func take_attack_damage(
	amount: int, source_position: Vector2, incoming_direction: Vector2 = Vector2.ZERO
) -> void:
	if amount <= 0 or health <= 0 or _is_dead or _damage_receiver == null:
		return
	var packet := _build_incoming_damage_packet(
		amount,
		&"attack",
		source_position,
		incoming_direction,
		true
	)
	_damage_receiver.receive_damage(packet, _player_hurtbox)


func _set_mesh_instances_transparency(_root: Node, transparency_amount: float) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	if _cached_visual_mesh_instances.is_empty():
		_rebuild_visual_mesh_instance_cache()
	for mesh in _cached_visual_mesh_instances:
		if mesh != null and is_instance_valid(mesh):
			mesh.transparency = transparency_amount


func _update_invulnerability_flash_visual() -> void:
	if _visual == null:
		return
	var ms := maxi(1, int(roundf(hit_flash_blink_interval * 1000.0)))
	var opaque := int(floor(float(Time.get_ticks_msec()) / float(ms))) % 2 == 0
	var flash_state := 1 if opaque else 0
	if _last_invulnerability_flash_state == flash_state:
		return
	_last_invulnerability_flash_state = flash_state
	_set_mesh_instances_transparency(_visual, 0.0 if opaque else hit_flash_transparency)


func _reset_player_visual_transparency() -> void:
	if _visual:
		_last_invulnerability_flash_state = 1
		_set_mesh_instances_transparency(_visual, 0.0)


func _mouse_steering_active() -> bool:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return false
	# Don't steal movement when a Control is under the cursor (e.g. game-over overlay).
	return not _ui_blocks_attack_this_physics_frame()


## Screen mouse → GameWorld2D plane (same coords as global_position: x, y ↔ 3D x, z).
func _mouse_planar_world() -> Vector2:
	var physics_frame := Engine.get_physics_frames()
	if _cached_mouse_world_physics_frame == physics_frame:
		return _cached_mouse_world
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_cached_mouse_world = global_position
		_cached_mouse_world_physics_frame = physics_frame
		return _cached_mouse_world
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if absf(dir.y) < 1e-5:
		_cached_mouse_world = global_position
		_cached_mouse_world_physics_frame = physics_frame
		return _cached_mouse_world
	var t := -from.y / dir.y
	if t < 0.0:
		_cached_mouse_world = global_position
		_cached_mouse_world_physics_frame = physics_frame
		return _cached_mouse_world
	var hit_pos := from + dir * t
	_cached_mouse_world = Vector2(hit_pos.x, hit_pos.z)
	_cached_mouse_world_physics_frame = physics_frame
	return _cached_mouse_world


const _MOVE_STEER_HINT_DISTANCE := 512.0


func _wasd_move_facing_aim(aim_planar: Vector2, _move_direction: Vector2) -> Vector2:
	return aim_planar


func _is_wasd_mouse_scheme_enabled() -> bool:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_method("is_wasd_mouse_scheme"):
		return bool(settings.call("is_wasd_mouse_scheme"))
	return false


func _mouse_aim_direction_planar() -> Vector2:
	var t := _mouse_planar_world() - global_position
	if t.length_squared() > 0.0001:
		return t.normalized()
	return Vector2.ZERO


func _resolve_dodge_direction(move_direction: Vector2) -> Vector2:
	if move_direction.length_squared() > 1e-6:
		return move_direction.normalized()
	var facing := _facing_planar.normalized()
	if facing.length_squared() > 1e-6:
		return facing
	return Vector2(0.0, -1.0)


func _wants_mouse_facing_while_blocking_or_attacking(defend_down: bool) -> bool:
	var blocking := (
		defend_down and _can_defend_in_current_mode() and _dodge_time_remaining <= 0.0
	)
	var attacking := (
		_melee_charging
		or _ranged_charging
		or _attack_hitbox_visual_time_remaining > 0.0
	)
	return blocking or attacking


func _resolve_facing_aim_for_move_step(
	aim_planar: Vector2, move_direction: Vector2, defend_down: bool
) -> Vector2:
	if _wants_mouse_facing_while_blocking_or_attacking(defend_down):
		if (not _multiplayer_active()) or _is_local_owner_peer():
			var m := _mouse_aim_direction_planar()
			if m.length_squared() > 1e-6:
				return m
		if aim_planar.length_squared() > 1e-6:
			return aim_planar
		return Vector2.ZERO
	return _wasd_move_facing_aim(aim_planar, move_direction)


func _local_move_steering_intent() -> Dictionary:
	if _is_wasd_mouse_scheme_enabled():
		var v_raw := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down", 0.2)
		# Planar = world XZ; map get_vector (screen-style axes) into walk space (both axes flipped here).
		var v := Vector2(-v_raw.x, -v_raw.y)
		var move_active := v.length_squared() > 0.0001
		var target_world := (
			global_position + v.normalized() * _MOVE_STEER_HINT_DISTANCE
			if move_active
			else global_position
		)
		var aim := _mouse_planar_world() - global_position
		var aim_planar := aim.normalized() if aim.length_squared() > 0.0001 else Vector2.ZERO
		return {"move_active": move_active, "target_world": target_world, "aim_planar": aim_planar}
	return {
		"move_active": _mouse_steering_active(),
		"target_world": _mouse_planar_world(),
		"aim_planar": Vector2.ZERO,
	}


func _update_facing_planar(
	direction: Vector2, allow_mouse_fallback: bool = true, aim_planar: Vector2 = Vector2.ZERO
) -> void:
	if _is_facing_locked():
		_facing_planar = _facing_lock_planar
		_sync_melee_hitbox_geometry()
		return
	if aim_planar.length_squared() > 1e-4:
		_facing_planar = aim_planar.normalized()
		_sync_melee_hitbox_geometry()
		return
	var f := direction
	if allow_mouse_fallback and f.length_squared() <= 1e-6 and _mouse_steering_active():
		var t := _mouse_planar_world() - global_position
		if t.length_squared() > 0.01:
			f = t.normalized()
	if f.length_squared() > 1e-6:
		_facing_planar = f.normalized()
	_sync_melee_hitbox_geometry()


func _get_player_body_radius() -> float:
	if _body_shape and _body_shape.shape is CircleShape2D:
		return (_body_shape.shape as CircleShape2D).radius
	return 0.7605869


func _melee_range_start() -> float:
	return _get_player_body_radius() + melee_start_beyond_body


const _DEBUG_ADD_INFUSION_KEYCODES: Array[int] = [
	KEY_F5,
	KEY_F6,
	KEY_F7,
	KEY_F8,
	KEY_F9,
	KEY_F10,
	KEY_F11,
]


## Debug only (`OS.is_debug_build()`): F5–F11 add one stack of each pillar in `PILLAR_ORDER`
## (Edge, Flow, Mass, Echo, Anchor, Phase, Surge). F12 clears run infusions.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if infusion_manager == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_F12:
			infusion_manager.call(&"clear_run_infusions")
			get_viewport().set_input_as_handled()
			return
		var key_index := _DEBUG_ADD_INFUSION_KEYCODES.find(k.keycode)
		if key_index >= 0 and key_index < InfusionConstantsRef.PILLAR_ORDER.size():
			var pillar_id: StringName = InfusionConstantsRef.PILLAR_ORDER[key_index]
			infusion_manager.call(
				&"add_infusion",
				pillar_id,
				InfusionConstantsRef.STACK_NORMAL,
				InfusionConstantsRef.SourceKind.NORMAL
			)
			get_viewport().set_input_as_handled()


# --- Infusion systems (Edge / Flow / Phase / Mass / Echo / Anchor / Surge) ---
func _infusion_edge_melee_damage_bonus() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return 0
	var t: int = int(
		infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_EDGE)
	)
	return InfusionEdgeRef.melee_damage_bonus(t)


func _infusion_edge_threshold() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return int(InfusionConstantsRef.InfusionThreshold.INACTIVE)
	return int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_EDGE))


func _infusion_mass_threshold() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return int(InfusionConstantsRef.InfusionThreshold.INACTIVE)
	return int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_MASS))


func _infusion_echo_threshold() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return int(InfusionConstantsRef.InfusionThreshold.INACTIVE)
	return int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_ECHO))


func _infusion_mass_melee_damage_bonus() -> int:
	return InfusionMassRef.melee_damage_bonus(_infusion_mass_threshold())


func _infusion_anchor_threshold() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return int(InfusionConstantsRef.InfusionThreshold.INACTIVE)
	return int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_ANCHOR))


func _infusion_anchor_melee_damage_bonus() -> int:
	return InfusionAnchorRef.outgoing_melee_bonus(
		_infusion_anchor_threshold(), _anchor_pressure, _anchor_rooted, _anchor_critical_bastion
	)


func _anchor_reset_pressure_state() -> void:
	_anchor_pressure = 0.0
	_anchor_micro_shield = 0.0
	_anchor_bastion_charge = 0.0
	_anchor_rooted = false
	_anchor_critical_bastion = false


func anchor_preprocess_incoming_damage(packet: DamagePacket) -> DamagePacket:
	var p := packet.duplicate_packet()
	if p.amount <= 0:
		return p
	var at := _infusion_anchor_threshold()
	if not InfusionAnchorRef.is_anchor_attuned(at):
		_anchor_reset_pressure_state()
		return p
	if not is_damage_authority():
		return p
	var working := float(p.amount)
	var press := _anchor_pressure
	if at >= int(InfusionConstantsRef.InfusionThreshold.ESCALATED) and press > 0.001:
		var spill_r := InfusionAnchorRef.brace_hit_spill_ratio(at)
		var spill := press * spill_r
		working += spill
		press = maxf(0.0, press - spill)
	var rooted_now := _anchor_rooted and at >= int(InfusionConstantsRef.InfusionThreshold.EXPRESSION)
	if rooted_now:
		var shift_r := InfusionAnchorRef.bastion_incoming_to_reserve_ratio(at)
		var shift_amt := floorf(working * shift_r)
		press += shift_amt
		working -= shift_amt
	elif at >= int(InfusionConstantsRef.InfusionThreshold.ESCALATED):
		var rr := InfusionAnchorRef.brace_reserve_ratio(at)
		var store := floorf(working * rr)
		press += store
		working -= store
	press = minf(120.0, press)
	var imm := int(floorf(working))
	imm = maxi(0, imm - InfusionAnchorRef.fortify_flat_damage_reduction(at))
	if rooted_now:
		imm = maxi(0, imm - InfusionAnchorRef.bastion_extra_flat_reduction_while_rooted(at))
	var cap := InfusionAnchorRef.fortify_micro_shield_cap(at)
	if cap > 0.0 and _anchor_micro_shield > 0.0:
		var use_sh := minf(_anchor_micro_shield, float(imm))
		imm = maxi(0, imm - int(floorf(use_sh)))
		_anchor_micro_shield = maxf(0.0, _anchor_micro_shield - use_sh)
	if imm > 0 and cap > 0.0:
		var gain := float(InfusionAnchorRef.fortify_micro_shield_gain_per_hit(at))
		_anchor_micro_shield = minf(cap, _anchor_micro_shield + gain)
	if InfusionAnchorRef.fortify_attack_commit_knockback_immunity(at) or rooted_now:
		if (
			rooted_now
			or _attack_hitbox_visual_time_remaining > 0.0
			or _melee_charging
			or _ranged_charging
		):
			p.knockback = 0.0
	if rooted_now and at >= int(InfusionConstantsRef.InfusionThreshold.EXPRESSION):
		if press >= InfusionAnchorRef.bastion_critical_pressure_threshold(at):
			_anchor_critical_bastion = true
	p.amount = maxi(0, imm)
	_anchor_pressure = press
	return p


func anchor_on_guard_block_success(_packet: DamagePacket) -> void:
	if not is_damage_authority():
		return
	_anchor_maybe_timing_purge(true)


func _anchor_decay_step(delta: float) -> void:
	if not is_damage_authority():
		return
	var at := _infusion_anchor_threshold()
	if not InfusionAnchorRef.is_anchor_attuned(at):
		_anchor_reset_pressure_state()
		return
	var dps := InfusionAnchorRef.brace_pressure_decay_per_sec(at)
	if dps > 0.0:
		_anchor_pressure = maxf(0.0, _anchor_pressure - dps * maxf(0.0, delta))


func _anchor_maybe_timing_purge(from_guard: bool) -> void:
	if not is_damage_authority():
		return
	var at := _infusion_anchor_threshold()
	if at < int(InfusionConstantsRef.InfusionThreshold.ESCALATED):
		return
	if _anchor_pressure <= 0.25:
		return
	var frac := InfusionAnchorRef.brace_purge_fraction(at)
	var purged := _anchor_pressure * frac
	_anchor_pressure = maxf(0.0, _anchor_pressure - purged)
	if purged <= 0.25:
		return
	var ratio := InfusionAnchorRef.brace_purge_shockwave_damage_ratio(at)
	var r := InfusionAnchorRef.brace_purge_shockwave_radius(at)
	var pool := maxi(1, int(floorf(float(purged) * ratio)))
	_anchor_emit_radial_shockwave(r, pool, &"anchor_purge_shockwave", from_guard)


func _anchor_emit_radial_shockwave(
	radius: float, total_damage: int, debug_label: StringName, _from_guard: bool
) -> void:
	if total_damage <= 0 or radius <= 0.0001 or not is_damage_authority():
		return
	var origin := global_position
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, radius, -1)
	if candidates.is_empty():
		return
	var each := maxi(
		1, int(floorf(float(total_damage) / float(maxi(1, candidates.size()))))
	)
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.kind = &"melee"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = origin
	pkt.apply_iframes = false
	pkt.suppress_edge_procs = true
	pkt.suppress_mass_procs = true
	pkt.suppress_echo_procs = true
	pkt.debug_label = debug_label
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		var dir := eb.global_position - origin
		if dir.length_squared() < 1e-8:
			dir = Vector2(0.0, -1.0)
		else:
			dir = dir.normalized()
		var cp := pkt.duplicate_packet()
		cp.amount = each
		cp.direction = dir
		cp.knockback = 4.5
		eb.take_direct_damage_packet(cp)


func _anchor_release_bastion() -> void:
	if not _anchor_rooted:
		return
	_anchor_rooted = false
	var at := _infusion_anchor_threshold()
	if at < int(InfusionConstantsRef.InfusionThreshold.EXPRESSION):
		_anchor_pressure = 0.0
		_anchor_critical_bastion = false
		return
	var mult := 1.0
	if _anchor_critical_bastion:
		mult = InfusionAnchorRef.bastion_critical_release_multiplier(at)
	_anchor_critical_bastion = false
	var pool := int(
		floorf(float(_anchor_pressure) * InfusionAnchorRef.bastion_release_damage_ratio(at) * mult)
	)
	_anchor_pressure = 0.0
	_anchor_emit_radial_shockwave(
		InfusionAnchorRef.bastion_release_radius(at),
		maxi(1, pool),
		&"anchor_bastion_release",
		false
	)


func _anchor_bastion_charge_tick(
	delta: float, move_active: bool, dodge_pressed: bool, defend_down: bool
) -> void:
	var at := _infusion_anchor_threshold()
	if at < int(InfusionConstantsRef.InfusionThreshold.EXPRESSION):
		return
	if _anchor_rooted:
		return
	var still := not move_active and not dodge_pressed and _dodge_time_remaining <= 0.0
	var stance := (
		defend_down
		or _attack_hitbox_visual_time_remaining > 0.0
		or _melee_charging
		or _ranged_charging
	)
	var rate := InfusionAnchorRef.bastion_charge_rate_per_sec(at)
	var dec := InfusionAnchorRef.bastion_charge_decay_per_sec(at)
	if still and stance:
		_anchor_bastion_charge = minf(1.0, _anchor_bastion_charge + rate * maxf(0.0, delta))
	else:
		_anchor_bastion_charge = maxf(0.0, _anchor_bastion_charge - dec * maxf(0.0, delta))
	if _anchor_bastion_charge >= 1.0:
		_anchor_bastion_charge = 0.0
		_anchor_rooted = true


func _infusion_surge_threshold() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return int(InfusionConstantsRef.InfusionThreshold.INACTIVE)
	return int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_SURGE))


func _infusion_surge_melee_flat_bonus() -> int:
	return InfusionSurgeRef.melee_flat_damage_bonus(_infusion_surge_threshold())


func _surge_reset_combat_state() -> void:
	_surge_energy = 0.0
	_surge_melee_overcharge_time = 0.0
	_surge_overdrive_active = false
	_surge_overdrive_energy_sink = 0.0
	_surge_field_pulse_accum = 0.0
	_surge_field_report_accum = 0.0
	_surge_server_field_active = false
	_surge_server_field_charge_r = 0.0
	_surge_server_field_over_n = 0.0
	_surge_server_field_until_msec = 0


func _surge_current_melee_overcharge_norm() -> float:
	var st := _infusion_surge_threshold()
	if not InfusionSurgeRef.allows_melee_overcharge_hold(st):
		return 0.0
	var max_o := InfusionSurgeRef.overcharge_max_hold_sec(st)
	if max_o <= 0.0:
		return 0.0
	return clampf(_surge_melee_overcharge_time / maxf(0.05, max_o), 0.0, 1.0)


func _surge_authoritative_tick(delta: float) -> void:
	if not is_damage_authority():
		return
	var st := _infusion_surge_threshold()
	if _is_server_peer() and not _is_local_owner_peer():
		if Time.get_ticks_msec() > _surge_server_field_until_msec:
			_surge_server_field_active = false
	if InfusionSurgeRef.is_surge_attuned(st):
		_surge_apply_charge_field_tick(delta, st)
	if not InfusionSurgeRef.is_surge_attuned(st):
		return
	if _surge_overdrive_active:
		var drain := InfusionSurgeRef.overdrive_energy_drain_per_sec() * maxf(0.0, delta)
		_surge_overdrive_energy_sink += drain
		_surge_energy = maxf(0.0, _surge_energy - drain)
		if _surge_energy <= 0.001:
			_surge_overdrive_active = false
			_surge_trigger_overdrive_finale(st)


func _surge_trigger_overdrive_finale(surge_threshold: int) -> void:
	if surge_threshold < int(InfusionConstantsRef.InfusionThreshold.EXPRESSION):
		_surge_overdrive_energy_sink = 0.0
		return
	var used := _surge_overdrive_energy_sink
	_surge_overdrive_energy_sink = 0.0
	if used <= 0.25:
		return
	var ratio := InfusionSurgeRef.finale_damage_ratio_for_energy_used(used)
	var pool := maxi(1, int(roundf(float(_mass_effective_melee_damage_estimate()) * ratio)))
	var fwd := _normalized_attack_facing(_facing_planar)
	_surge_deal_secondary_burst(global_position, pool, -1, fwd, InfusionSurgeRef.finale_knockback(), 11.5, &"surge_finale")


func _surge_apply_charge_field_tick(delta: float, surge_threshold: int) -> void:
	if not _is_server_peer() and _multiplayer_active():
		return
	var in_od := _surge_overdrive_active
	var ch_r := 0.0
	var ov_n := 0.0
	var active := false
	if in_od:
		active = true
		ch_r = 1.0
		ov_n = 1.0
	elif _is_local_owner_peer():
		if _melee_charging and _melee_charge_past_commit_delay:
			var denom := maxf(0.05, _flow_effective_melee_charge_max_time())
			ch_r = clampf(_melee_charge_time / denom, 0.0, 1.0)
			if InfusionSurgeRef.allows_melee_overcharge_hold(surge_threshold):
				var raw_t := _melee_charge_time / denom
				if raw_t >= 1.0 - 1e-5:
					ch_r = 1.0
					ov_n = _surge_current_melee_overcharge_norm()
			active = ch_r > 0.02
		elif _ranged_charging and _ranged_charge_past_commit_delay:
			ch_r = clampf(_ranged_charge_time / maxf(0.05, melee_charge_max_time), 0.0, 1.0)
			active = ch_r > 0.02
	else:
		if _surge_server_field_active and Time.get_ticks_msec() <= _surge_server_field_until_msec:
			ch_r = _surge_server_field_charge_r
			ov_n = _surge_server_field_over_n
			active = true
	if not active:
		_surge_field_pulse_accum = 0.0
		return
	var origin := global_position
	var radius := InfusionSurgeRef.charge_field_radius(surge_threshold, ch_r, ov_n, in_od)
	if radius <= 0.05:
		return
	var spd := InfusionSurgeRef.charge_field_enemy_speed_mult(surge_threshold, ch_r, ov_n, in_od)
	var cd_m := InfusionSurgeRef.charge_field_enemy_cooldown_tick_mult(surge_threshold, ov_n, in_od)
	var ttl := InfusionSurgeRef.field_refresh_ttl_msec()
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, radius, -1)
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		eb.surge_infusion_refresh_charge_field(spd, cd_m, ttl)
	var pulse_iv := InfusionSurgeRef.field_pulse_interval_sec(surge_threshold, in_od)
	var micro := InfusionSurgeRef.field_pulse_micro_interrupt_sec(surge_threshold, in_od)
	if micro > 0.0001 and pulse_iv < 900.0:
		_surge_field_pulse_accum -= delta
		if _surge_field_pulse_accum <= 0.0:
			_surge_field_pulse_accum = pulse_iv
			for eb2 in candidates:
				if eb2 == null or not is_instance_valid(eb2):
					continue
				eb2.surge_infusion_bump_action_delay(micro)


func _surge_maybe_report_charge_field_to_server(delta: float) -> void:
	if not _multiplayer_active() or _is_server_peer():
		return
	if not _is_local_owner_peer():
		return
	if not _can_broadcast_world_replication():
		return
	var st := _infusion_surge_threshold()
	if not InfusionSurgeRef.is_surge_attuned(st):
		return
	var active := false
	var ch_r := 0.0
	var ov_n := 0.0
	if _melee_charging and _melee_charge_past_commit_delay:
		var denom := maxf(0.05, _flow_effective_melee_charge_max_time())
		ch_r = clampf(_melee_charge_time / denom, 0.0, 1.0)
		if InfusionSurgeRef.allows_melee_overcharge_hold(st):
			var raw_t2 := _melee_charge_time / denom
			if raw_t2 >= 1.0 - 1e-5:
				ov_n = _surge_current_melee_overcharge_norm()
		active = ch_r > 0.02
	elif _ranged_charging and _ranged_charge_past_commit_delay:
		ch_r = clampf(_ranged_charge_time / maxf(0.05, melee_charge_max_time), 0.0, 1.0)
		active = ch_r > 0.02
	_surge_field_report_accum += delta
	if _surge_field_report_accum < 0.09 and active:
		return
	_surge_field_report_accum = 0.0
	var max_o := InfusionSurgeRef.max_client_reported_overcharge_sec_fudge()
	var over_cap := 1.0
	if InfusionSurgeRef.allows_melee_overcharge_hold(st) and max_o > 0.0:
		over_cap = clampf(max_o / maxf(0.05, InfusionSurgeRef.overcharge_max_hold_sec(st)), 1.0, 2.5)
	_rpc_surge_charge_field_report.rpc_id(1, ch_r, clampf(ov_n, 0.0, over_cap), active)


func _surge_validate_server_overcharge_norm(requested: float) -> float:
	var st := _infusion_surge_threshold()
	if not InfusionSurgeRef.allows_melee_overcharge_hold(st):
		return 0.0
	return clampf(requested, 0.0, 1.0)


func _surge_deal_secondary_burst(
	origin: Vector2,
	pool: int,
	primary_uid: int,
	forward: Vector2,
	pulse_kb: float,
	radius: float,
	debug_label: StringName
) -> void:
	if pool <= 0 or radius <= 0.05:
		return
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, radius, primary_uid)
	if candidates.is_empty():
		return
	var each := maxi(1, int(floorf(float(pool) / float(candidates.size()))))
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.kind = &"melee"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = origin
	pkt.direction = forward
	pkt.knockback = maxf(0.0, pulse_kb)
	pkt.apply_iframes = false
	pkt.suppress_edge_procs = true
	pkt.suppress_mass_procs = true
	pkt.debug_label = debug_label
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		var p := pkt.duplicate_packet()
		p.amount = each
		eb.take_direct_damage_packet(p)


func _mass_loadout_knockback_mult() -> float:
	var v := _loadout_stat_from_totals(_stat_totals_merged(), LoadoutConstantsRef.STAT_KNOCKBACK_MULTIPLIER)
	if v <= 0.0001:
		return 1.0
	return maxf(0.25, v)


func _mass_effective_melee_damage_estimate() -> int:
	return maxi(
		1,
		melee_attack_damage
			+ _infusion_edge_melee_damage_bonus()
			+ _infusion_mass_melee_damage_bonus()
			+ _infusion_anchor_melee_damage_bonus()
			+ _infusion_surge_melee_flat_bonus()
	)


func _infusion_edge_expression_geometry_mult() -> float:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return 1.0
	var t: int = int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_EDGE))
	return InfusionEdgeRef.expression_geometry_mult(t)


func _infusion_flow_threshold() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return int(InfusionConstantsRef.InfusionThreshold.INACTIVE)
	return int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_FLOW))


func _flow_pack_state() -> Dictionary:
	return {
		"tempo": _flow_tempo,
		"chain_rem": _flow_chain_remaining,
		"od_rem": _flow_overdrive_remaining,
		"agg_rem": _flow_aggression_remaining,
		"last_kind": _flow_last_action_kind,
	}


func _flow_apply_state(d: Dictionary) -> void:
	_flow_tempo = clampf(float(d.get("tempo", 0.0)), 0.0, 1.0)
	_flow_chain_remaining = maxf(0.0, float(d.get("chain_rem", 0.0)))
	_flow_overdrive_remaining = maxf(0.0, float(d.get("od_rem", 0.0)))
	_flow_aggression_remaining = maxf(0.0, float(d.get("agg_rem", 0.0)))
	_flow_last_action_kind = int(d.get("last_kind", -1))


func _flow_merge_state_from_network(
	tempo: float, chain_rem: float, od_rem: float, agg_rem: float, last_kind: int
) -> void:
	_flow_tempo = clampf(tempo, 0.0, 1.0)
	_flow_chain_remaining = maxf(0.0, chain_rem)
	_flow_overdrive_remaining = maxf(0.0, od_rem)
	_flow_aggression_remaining = maxf(0.0, agg_rem)
	_flow_last_action_kind = last_kind


func _flow_decay_step(delta: float) -> void:
	var t := _infusion_flow_threshold()
	var next := InfusionFlowRef.state_decay(delta, t, _flow_pack_state())
	_flow_apply_state(next)


func _flow_after_successful_weapon_action(kind: int) -> void:
	if _multiplayer_active() and not _is_server_peer():
		return
	var t := _infusion_flow_threshold()
	var next := InfusionFlowRef.weapon_action_advance(t, _flow_pack_state(), kind)
	_flow_apply_state(next)


func _flow_pulse_ability_cooldowns_after_melee() -> void:
	var t := _infusion_flow_threshold()
	if t < int(InfusionConstantsRef.InfusionThreshold.ESCALATED):
		return
	if _flow_chain_remaining <= 0.0:
		return
	var p := InfusionFlowRef.CHAIN_MELEE_ABILITY_CD_PULSE_SEC
	_ranged_cooldown_remaining = maxf(0.0, _ranged_cooldown_remaining - p)
	_bomb_cooldown_remaining = maxf(0.0, _bomb_cooldown_remaining - p)


func _infusion_phase_threshold() -> int:
	if infusion_manager == null or not infusion_manager.has_method(&"get_pillar_threshold"):
		return int(InfusionConstantsRef.InfusionThreshold.INACTIVE)
	return int(infusion_manager.call(&"get_pillar_threshold", InfusionConstantsRef.PILLAR_PHASE))


func _flow_effective_melee_cooldown() -> float:
	var t := _infusion_flow_threshold()
	var cd_m := InfusionFlowRef.cooldown_multiplier(t)
	var as_m := InfusionFlowRef.combined_attack_speed_multiplier(
		_flow_tempo, _flow_chain_remaining, _flow_overdrive_remaining, t
	)
	return melee_attack_cooldown * cd_m / maxf(1e-3, as_m)


func _flow_effective_ranged_cooldown() -> float:
	var t := _infusion_flow_threshold()
	var cd_m := InfusionFlowRef.cooldown_multiplier(t)
	var as_m := InfusionFlowRef.combined_attack_speed_multiplier(
		_flow_tempo, _flow_chain_remaining, _flow_overdrive_remaining, t
	)
	return ranged_cooldown * cd_m / maxf(1e-3, as_m)


func _flow_effective_bomb_cooldown() -> float:
	var t := _infusion_flow_threshold()
	var cd_m := InfusionFlowRef.cooldown_multiplier(t)
	var as_m := InfusionFlowRef.combined_attack_speed_multiplier(
		_flow_tempo, _flow_chain_remaining, _flow_overdrive_remaining, t
	)
	return bomb_cooldown * cd_m / maxf(1e-3, as_m)


func _flow_effective_melee_charge_max_time() -> float:
	var cap := melee_charge_max_time
	if InfusionFlowRef.should_extend_combo_window(_infusion_flow_threshold()):
		cap += flow_expression_combo_charge_bonus
	return cap


func _phase_outgoing_damage_multiplier() -> float:
	var r := InfusionPhaseRef.armor_ignore_ratio(_infusion_phase_threshold())
	return 1.0 + clampf(r, 0.0, 1.0)


func _infusion_phase_depth_mult() -> float:
	return InfusionPhaseRef.combined_melee_depth_multiplier(_infusion_phase_threshold())


func _phase_tag_melee_packet(packet: DamagePacket) -> void:
	if packet == null:
		return
	var t := _infusion_phase_threshold()
	if not InfusionPhaseRef.is_phase_attuned(t):
		return
	packet.mitigation_ignore_ratio = InfusionPhaseRef.armor_ignore_ratio(t)
	if InfusionPhaseRef.is_fracture(t):
		packet.ignore_directional_guard = true


func _phase_tag_aux_melee_packet(packet: DamagePacket) -> void:
	if packet == null:
		return
	_phase_tag_melee_packet(packet)
	packet.suppress_phase_procs = true
	packet.suppress_echo_procs = true


func _phase_begin_slip_body_window() -> void:
	var t := _infusion_phase_threshold()
	if not InfusionPhaseRef.is_phase_attuned(t):
		return
	if not is_damage_authority():
		return
	var dur := attack_hitbox_visual_duration + InfusionPhaseRef.slip_collision_window_extra_sec(t)
	_phase_slip_body_time_remaining = maxf(_phase_slip_body_time_remaining, dur)
	if _phase_saved_body_collision_mask < 0:
		_phase_saved_body_collision_mask = collision_mask
	collision_mask = collision_mask & ~InfusionPhase.MOB_BODY_PHYSICS_LAYER_BIT


func _phase_end_slip_body_collision() -> void:
	if _phase_saved_body_collision_mask >= 0:
		collision_mask = _phase_saved_body_collision_mask
		_phase_saved_body_collision_mask = -1


func _phase_slip_body_physics_tick(delta: float) -> void:
	if not is_damage_authority():
		return
	if _phase_slip_body_time_remaining <= 0.0:
		return
	_phase_slip_body_time_remaining = maxf(0.0, _phase_slip_body_time_remaining - delta)
	_phase_maybe_contact_chip_tick()
	if _phase_slip_body_time_remaining <= 0.0:
		_phase_end_slip_body_collision()


func _phase_maybe_skew_melee_facing_warp() -> void:
	var t := _infusion_phase_threshold()
	if not InfusionPhaseRef.is_skew_or_higher(t):
		return
	if not is_damage_authority():
		return
	var cone := deg_to_rad(InfusionPhaseRef.facing_warp_cone_degrees(t) * 0.5)
	var max_turn := deg_to_rad(InfusionPhaseRef.facing_warp_max_degrees(t))
	var fwd := _normalized_attack_facing(_facing_planar)
	var best: EnemyBase = null
	var best_ang := INF
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is EnemyBase:
			continue
		var eb := node as EnemyBase
		var to := eb.global_position - global_position
		if to.length_squared() < 0.01:
			continue
		to = to.normalized()
		if fwd.dot(to) < cos(cone):
			continue
		var cross := fwd.x * to.y - fwd.y * to.x
		var ang := atan2(cross, fwd.dot(to))
		var absa := absf(ang)
		if absa < best_ang:
			best_ang = absa
			best = eb
	if best == null:
		return
	var to_t := best.global_position - global_position
	if to_t.length_squared() < 1e-6:
		return
	to_t = to_t.normalized()
	var target_ang := atan2(fwd.x * to_t.y - fwd.y * to_t.x, fwd.dot(to_t))
	var clamped := clampf(target_ang, -max_turn, max_turn)
	var cs := cos(clamped)
	var sn := sin(clamped)
	_facing_planar = Vector2(fwd.x * cs - fwd.y * sn, fwd.x * sn + fwd.y * cs).normalized()


func _phase_try_dash_trail_burst(start_planar: Vector2, dodge_dir: Vector2) -> void:
	var t := _infusion_phase_threshold()
	if not InfusionPhaseRef.is_skew_or_higher(t):
		return
	if not is_damage_authority():
		return
	if _phase_dash_trail_cooldown_remaining > 0.0:
		return
	var rad := InfusionPhaseRef.dash_trail_radius(t)
	var ratio := InfusionPhaseRef.dash_trail_damage_ratio(t)
	if rad <= 0.05 or ratio <= 0.0:
		return
	var est := _mass_effective_melee_damage_estimate()
	var pool := maxi(1, int(roundf(float(est) * ratio * _phase_outgoing_damage_multiplier())))
	var mid := start_planar + dodge_dir.normalized() * (dodge_speed * dodge_duration * 0.32)
	_phase_dash_trail_cooldown_remaining = InfusionPhaseRef.dash_trail_cooldown_sec(t)
	_phase_deal_tagged_radial_burst(
		mid, pool, -1, dodge_dir.normalized(), melee_knockback_strength * 0.22, rad, &"phase_dash_trail"
	)
	if _visual != null and _visual.has_method(&"show_phase_dash_trail_cue"):
		_visual.call(&"show_phase_dash_trail_cue", start_planar, dodge_dir)


func _phase_deal_tagged_radial_burst(
	origin: Vector2,
	pool: int,
	primary_uid: int,
	forward: Vector2,
	pulse_kb: float,
	radius: float,
	debug_label: StringName
) -> void:
	if pool <= 0 or radius <= 0.05 or not is_damage_authority():
		return
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, radius, primary_uid)
	if candidates.is_empty():
		return
	var each := maxi(1, int(floorf(float(pool) / float(candidates.size()))))
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.kind = &"melee"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = origin
	pkt.direction = forward
	pkt.knockback = maxf(0.0, pulse_kb)
	pkt.apply_iframes = false
	pkt.suppress_edge_procs = true
	pkt.suppress_mass_procs = true
	pkt.suppress_echo_procs = true
	pkt.suppress_edge_procs = true
	pkt.suppress_phase_procs = true
	pkt.debug_label = debug_label
	_phase_tag_aux_melee_packet(pkt)
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		var p := pkt.duplicate_packet()
		p.amount = each
		eb.take_direct_damage_packet(p)


func _phase_maybe_contact_chip_tick() -> void:
	var t := _infusion_phase_threshold()
	var chip := InfusionPhaseRef.contact_chip_damage(t)
	if chip <= 0 or not InfusionPhaseRef.is_skew_or_higher(t):
		return
	if _phase_contact_chip_cooldown_remaining > 0.0:
		return
	var reach := _get_player_body_radius() + 0.95
	var r2 := reach * reach
	var best: EnemyBase = null
	var best_d2 := INF
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is EnemyBase:
			continue
		var eb := node as EnemyBase
		var d2 := eb.global_position.distance_squared_to(global_position)
		if d2 > r2 or d2 >= best_d2:
			continue
		best_d2 = d2
		best = eb
	if best == null:
		return
	var p := DamagePacketScript.new() as DamagePacket
	p.amount = maxi(1, chip)
	p.kind = &"melee"
	p.source_node = self
	p.source_uid = get_instance_id()
	p.attack_instance_id = _server_melee_hit_event_sequence * 10000 + _phase_aux_attack_serial + 9000
	_phase_aux_attack_serial = (_phase_aux_attack_serial + 1) % 800
	p.origin = global_position
	p.direction = (best.global_position - global_position).normalized()
	p.knockback = melee_knockback_strength * 0.08
	p.apply_iframes = false
	p.debug_label = &"phase_contact_chip"
	p.suppress_edge_procs = true
	_phase_tag_aux_melee_packet(p)
	best.take_direct_damage_packet(p)
	_phase_contact_chip_cooldown_remaining = InfusionPhaseRef.contact_chip_cooldown_sec(t)


func _phase_schedule_skew_ghost_strike(
	snap_pos: Vector2,
	snap_facing: Vector2,
	base_damage: int,
	base_knockback: float,
	_server_hit_event_id: int
) -> void:
	var t := _infusion_phase_threshold()
	if not InfusionPhaseRef.is_skew_or_higher(t):
		return
	if not is_damage_authority():
		return
	if base_damage <= 0:
		return
	var dmin := InfusionPhaseRef.ghost_strike_delay_min_sec(t)
	var dmax := InfusionPhaseRef.ghost_strike_delay_max_sec(t)
	if dmax <= 0.0:
		return
	var delay := randf_range(dmin, dmax)
	var ratio := InfusionPhaseRef.ghost_strike_damage_ratio(t)
	var gdam := maxi(1, int(roundf(float(base_damage) * ratio)))
	var gkb := base_knockback * 0.82
	_phase_aux_attack_serial += 1
	var atk_id := 600_000 + _phase_aux_attack_serial + maxi(0, _server_hit_event_id) * 13
	var tree := get_tree()
	if tree == null:
		return
	var self_ref := self
	var cb := func () -> void:
		if is_instance_valid(self_ref):
			self_ref._phase_deliver_ghost_melee(snap_pos, snap_facing, gdam, gkb, atk_id)
	tree.create_timer(delay).timeout.connect(cb, CONNECT_ONE_SHOT)


func _phase_deliver_ghost_melee(
	pos: Vector2,
	facing: Vector2,
	damage: int,
	knockback: float,
	attack_instance_id: int
) -> void:
	if not is_damage_authority():
		return
	_deliver_melee_polygon_hits_at_pose(
		pos, facing, damage, knockback, attack_instance_id, &"phase_ghost_melee"
	)


func _phase_deliver_fracture_flanks_if_eligible(center: Vector2, facing: Vector2, base_damage: int, base_kb: float, hit_event_id: int) -> void:
	var t := _infusion_phase_threshold()
	if not InfusionPhaseRef.is_fracture(t):
		return
	if not is_damage_authority():
		return
	var off := InfusionPhaseRef.multi_origin_flank_offset(t)
	var ratio := InfusionPhaseRef.multi_origin_damage_ratio(t)
	if off <= 0.0 or ratio <= 0.0:
		return
	var f := facing.normalized()
	if f.length_squared() < 1e-6:
		f = Vector2(0.0, -1.0)
	var r := Vector2(-f.y, f.x)
	var dmg := maxi(1, int(roundf(float(base_damage) * ratio)))
	var kbb := base_kb * 0.78
	_phase_aux_attack_serial += 1
	var id0 := 700_000 + _phase_aux_attack_serial + maxi(0, hit_event_id) * 3
	_phase_aux_attack_serial += 1
	var id1 := 700_000 + _phase_aux_attack_serial + maxi(0, hit_event_id) * 3
	_deliver_melee_polygon_hits_at_pose(
		center + r * off, f, dmg, kbb, id0, &"phase_flank_melee"
	)
	_deliver_melee_polygon_hits_at_pose(
		center - r * off, f, dmg, kbb, id1, &"phase_flank_melee"
	)


func _deliver_melee_polygon_hits_at_pose(
	center: Vector2,
	facing: Vector2,
	damage: int,
	knockback: float,
	attack_instance_id: int,
	debug_lbl: StringName
) -> void:
	var f := facing.normalized()
	if f.length_squared() < 1e-6:
		f = Vector2(0.0, -1.0)
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is CharacterBody2D:
			continue
		var mob := node as CharacterBody2D
		if not _melee_hit_overlaps_mob_at(center, f, mob):
			continue
		var dmg_hit := damage
		var from_bs := false
		var is_crit := false
		if mob is EnemyBase:
			var res := _melee_resolve_precision(damage, mob as EnemyBase, self)
			dmg_hit = int(res["amount"])
			from_bs = bool(res.get("from_backstab", false))
			is_crit = bool(res.get("is_critical", false))
		var kb_hit := knockback
		var dir_hit := f
		if mob is EnemyBase:
			var kb_res := _mass_kb_dir_for_enemy(knockback, f, mob as EnemyBase)
			kb_hit = float(kb_res.get("kb", knockback))
			var dv: Variant = kb_res.get("dir", f)
			if dv is Vector2:
				dir_hit = dv as Vector2
		if mob is EnemyBase:
			var eb := mob as EnemyBase
			var pkt := DamagePacketScript.new() as DamagePacket
			pkt.amount = dmg_hit
			pkt.kind = &"melee"
			pkt.source_node = self
			pkt.source_uid = get_instance_id()
			pkt.attack_instance_id = attack_instance_id
			pkt.origin = center
			pkt.direction = dir_hit
			pkt.knockback = kb_hit
			pkt.apply_iframes = false
			pkt.blockable = false
			pkt.debug_label = debug_lbl
			pkt.from_backstab = from_bs
			pkt.is_critical = is_crit
			pkt.suppress_edge_procs = true
			_phase_tag_aux_melee_packet(pkt)
			var hb := eb.get_combat_hurtbox()
			if hb != null:
				apply_mass_melee_packet_adjustments(pkt, hb)
			eb.take_direct_damage_packet(pkt)
			_mass_try_impact_pulse_and_shockwave_from_hit(dmg_hit, eb, dir_hit)
		elif mob.has_method(&"take_hit"):
			mob.call(&"take_hit", dmg_hit, dir_hit, kb_hit, from_bs, is_crit)


func _melee_hit_effective_width_depth() -> Vector2:
	var g_edge := _infusion_edge_expression_geometry_mult()
	var phase_d := _infusion_phase_depth_mult()
	return Vector2(melee_width * g_edge, melee_depth * g_edge * phase_d)


func _planar_point_in_melee_hit(mob_pos: Vector2) -> bool:
	var inner := _melee_range_start()
	var f := _resolve_melee_hit_facing()
	var r := Vector2(-f.y, f.x)
	var v := mob_pos - global_position
	var along := v.dot(f)
	var lateral := v.dot(r)
	var sz := _melee_hit_effective_width_depth()
	var half_w := sz.x * 0.5
	return along >= inner and along <= inner + sz.y and absf(lateral) <= half_w


func _melee_hit_polygon_world() -> PackedVector2Array:
	var f := _resolve_melee_hit_facing()
	var r := Vector2(-f.y, f.x)
	var sz := _melee_hit_effective_width_depth()
	var half_w := sz.x * 0.5
	var inner := _melee_range_start()
	var p := global_position
	var poly := PackedVector2Array()
	poly.append(p + f * inner + r * (-half_w))
	poly.append(p + f * inner + r * half_w)
	poly.append(p + f * (inner + sz.y) + r * half_w)
	poly.append(p + f * (inner + sz.y) + r * (-half_w))
	return poly


func _melee_hit_overlaps_mob(mob: CharacterBody2D) -> bool:
	var melee_poly := _melee_hit_polygon_world()
	var mob_poly := HitboxOverlap2D.mob_collision_polygon_world(mob)
	if mob_poly.size() >= 3:
		return HitboxOverlap2D.convex_polygons_overlap(melee_poly, mob_poly)
	return _planar_point_in_melee_hit(mob.global_position)


func _melee_hit_polygon_world_at(center: Vector2, facing: Vector2) -> PackedVector2Array:
	var f := facing.normalized()
	if f.length_squared() < 1e-6:
		f = Vector2(0.0, -1.0)
	var r := Vector2(-f.y, f.x)
	var sz := _melee_hit_effective_width_depth()
	var half_w := sz.x * 0.5
	var inner := _melee_range_start()
	var p := center
	var poly := PackedVector2Array()
	poly.append(p + f * inner + r * (-half_w))
	poly.append(p + f * inner + r * half_w)
	poly.append(p + f * (inner + sz.y) + r * half_w)
	poly.append(p + f * (inner + sz.y) + r * (-half_w))
	return poly


func _planar_point_in_melee_hit_at(center: Vector2, facing: Vector2, mob_pos: Vector2) -> bool:
	var inner := _melee_range_start()
	var f := facing.normalized()
	if f.length_squared() < 1e-6:
		f = Vector2(0.0, -1.0)
	var r := Vector2(-f.y, f.x)
	var v := mob_pos - center
	var along := v.dot(f)
	var lateral := v.dot(r)
	var sz := _melee_hit_effective_width_depth()
	var half_w := sz.x * 0.5
	return along >= inner and along <= inner + sz.y and absf(lateral) <= half_w


func _melee_hit_overlaps_mob_at(center: Vector2, facing: Vector2, mob: CharacterBody2D) -> bool:
	var melee_poly := _melee_hit_polygon_world_at(center, facing)
	var mob_poly := HitboxOverlap2D.mob_collision_polygon_world(mob)
	if mob_poly.size() >= 3:
		return HitboxOverlap2D.convex_polygons_overlap(melee_poly, mob_poly)
	return _planar_point_in_melee_hit_at(center, facing, mob.global_position)


func apply_backstab_bonus_to_melee_packet(packet: DamagePacket, hurtbox: Hurtbox2D) -> void:
	if packet == null or hurtbox == null:
		return
	if packet.is_echo:
		return
	if packet.kind != &"melee" or packet.debug_label != &"player_melee":
		return
	if packet.suppress_edge_procs:
		return
	if melee_backstab_damage_multiplier <= 1.000001:
		return
	var target := hurtbox.get_target_node()
	if target == null or not target is EnemyBase:
		return
	var attacker := packet.source_node as Node2D
	if attacker == null:
		attacker = self
	var res := _melee_resolve_precision(packet.amount, target as EnemyBase, attacker)
	packet.amount = int(res.get("amount", packet.amount))
	packet.from_backstab = bool(res.get("from_backstab", false))
	packet.is_critical = bool(res.get("is_critical", false))


func _mass_kb_dir_for_enemy(base_kb: float, base_dir: Vector2, enemy: EnemyBase) -> Dictionary:
	var kb := base_kb
	var dir := base_dir
	var mt := _infusion_mass_threshold()
	if enemy == null:
		return {"kb": kb, "dir": dir}
	if not enemy.mass_infusion_receives_knockback():
		return {"kb": 0.0, "dir": base_dir}
	if not InfusionMassRef.is_mass_attuned(mt):
		if enemy is DasherMob:
			return {"kb": kb, "dir": dir}
		return {"kb": 0.0, "dir": dir}
	kb *= maxf(0.22, enemy.mass_infusion_knockback_size_factor())
	var blend := InfusionMassRef.expression_inward_knockback_blend(mt)
	if blend > 0.0001 and base_dir.length_squared() > 1e-8:
		var to_tgt := enemy.global_position - global_position
		if to_tgt.length_squared() > 1e-8:
			to_tgt = to_tgt.normalized()
			var out := base_dir.normalized()
			dir = (out * (1.0 - blend) + to_tgt * blend).normalized()
	return {"kb": kb, "dir": dir}


func apply_mass_melee_packet_adjustments(packet: DamagePacket, hurtbox: Hurtbox2D) -> void:
	if packet == null or hurtbox == null:
		return
	if packet.kind != &"melee" or packet.debug_label != &"player_melee":
		return
	if packet.suppress_mass_procs:
		return
	var target := hurtbox.get_target_node()
	if target == null or not target is EnemyBase:
		return
	var res := _mass_kb_dir_for_enemy(packet.knockback, packet.direction, target as EnemyBase)
	packet.knockback = float(res.get("kb", packet.knockback))
	var d: Variant = res.get("dir", packet.direction)
	if d is Vector2:
		packet.direction = d as Vector2


func _mass_try_impact_pulse_and_shockwave_from_hit(
	dmg_amount: int, primary: EnemyBase, forward: Vector2
) -> void:
	if not is_damage_authority() or primary == null:
		return
	var mt := _infusion_mass_threshold()
	if not InfusionMassRef.is_mass_attuned(mt):
		return
	var pulse_r := InfusionMassRef.impact_pulse_radius(mt)
	var ratio := InfusionMassRef.impact_pulse_damage_ratio(mt)
	if pulse_r <= 0.0 or ratio <= 0.0:
		return
	var origin := primary.global_position
	var pool := maxi(1, int(roundf(float(dmg_amount) * ratio)))
	var pk := InfusionMassRef.impact_pulse_knockback(mt) * _mass_loadout_knockback_mult()
	var fwd := forward
	if fwd.length_squared() < 1e-8:
		fwd = _active_melee_attack_facing
	fwd = fwd.normalized()
	_mass_deal_impact_pulse(origin, pool, primary.get_instance_id(), fwd, pk)
	_mass_maybe_advance_shockwave_build(dmg_amount)


func _on_melee_hitbox_target_resolved(
	packet: DamagePacket,
	target_uid: int,
	accepted: bool,
	consume_hit: bool,
	_reason: StringName
) -> void:
	if not is_damage_authority():
		return
	if not accepted or not consume_hit:
		return
	if packet == null or packet.suppress_mass_procs:
		return
	if packet.kind != &"melee" or packet.debug_label != &"player_melee":
		return
	var tree := get_tree()
	if tree == null:
		return
	var primary: EnemyBase = null
	for node in tree.get_nodes_in_group(&"mob"):
		if not node is EnemyBase:
			continue
		var eb := node as EnemyBase
		if eb.get_instance_id() == target_uid:
			primary = eb
			break
	if primary == null:
		return
	var fwd := packet.direction
	if fwd.length_squared() < 1e-8:
		fwd = _active_melee_attack_facing
	_mass_try_impact_pulse_and_shockwave_from_hit(packet.amount, primary, fwd)
	_echo_maybe_schedule_melee_reverberate(packet, primary, target_uid, fwd)


func _echo_find_enemy_by_uid(target_uid: int) -> EnemyBase:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(&"mob"):
		if not node is EnemyBase:
			continue
		var eb := node as EnemyBase
		if eb.get_instance_id() == target_uid:
			return eb
	return null


func _echo_deliver_linked_chain(
	exclude_uid: int,
	origin: Vector2,
	amount: int,
	forward: Vector2,
	echo_gen: int,
	echo_threshold: int
) -> void:
	if not is_damage_authority() or amount <= 0:
		return
	var r := InfusionEchoRef.linked_chain_radius(echo_threshold)
	if r <= 0.0001:
		return
	var candidates := _edge_collect_enemies_in_radius(origin, r, exclude_uid)
	if candidates.is_empty():
		return
	var best: EnemyBase = null
	var best_d2 := INF
	for eb in candidates:
		var d2 := origin.distance_squared_to(eb.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = eb
	if best == null:
		return
	var p := DamagePacketScript.new() as DamagePacket
	p.amount = maxi(1, amount)
	p.kind = &"melee"
	p.debug_label = &"player_melee"
	p.source_node = self
	p.source_uid = get_instance_id()
	p.origin = global_position
	p.direction = forward
	if p.direction.length_squared() < 1e-8:
		p.direction = Vector2(0.0, -1.0)
	else:
		p.direction = p.direction.normalized()
	p.knockback = maxf(
		0.0,
		melee_knockback_strength * 0.32 * InfusionEchoRef.afterimage_damage_ratio(echo_threshold)
	)
	p.apply_iframes = false
	p.is_echo = true
	p.echo_generation = echo_gen
	p.suppress_echo_procs = true
	var hb := best.get_combat_hurtbox()
	if hb != null:
		apply_mass_melee_packet_adjustments(p, hb)
	best.take_direct_damage_packet(p)
	_mass_try_impact_pulse_and_shockwave_from_hit(p.amount, best, p.direction)


func _echo_broadcast_melee_smear_vfx(planar_dir: Vector2) -> void:
	var d := planar_dir
	if d.length_squared() < 1e-8:
		d = _active_melee_attack_facing
	if d.length_squared() < 1e-8:
		d = _facing_planar
	d = d.normalized()
	if _visual != null and _visual.has_method(&"spawn_echo_melee_smear"):
		_visual.call(&"spawn_echo_melee_smear", d)
	if _can_broadcast_world_replication():
		_rpc_echo_melee_smear_vfx.rpc(d)


func _echo_deliver_melee_micro(
	victim_uid: int,
	dmg: int,
	is_critical: bool,
	from_backstab: bool,
	dir: Vector2,
	knockback: float,
	echo_gen: int,
	echo_threshold: int,
	is_last_micro: bool,
	linked_dmg: int,
	linked_exclude_uid: int
) -> void:
	if not is_damage_authority() or not is_instance_valid(self):
		return
	var eb := _echo_find_enemy_by_uid(victim_uid)
	if eb == null or eb.is_queued_for_deletion():
		return
	var d := dir
	if d.length_squared() < 1e-8:
		d = _active_melee_attack_facing
	d = d.normalized()
	_echo_broadcast_melee_smear_vfx(d)
	var p := DamagePacketScript.new() as DamagePacket
	p.amount = maxi(1, dmg)
	p.kind = &"melee"
	p.debug_label = &"player_melee"
	p.source_node = self
	p.source_uid = get_instance_id()
	p.origin = global_position
	p.direction = d
	p.knockback = knockback
	p.apply_iframes = false
	p.is_critical = is_critical
	p.from_backstab = from_backstab
	p.is_echo = true
	p.echo_generation = echo_gen
	p.suppress_echo_procs = true
	var hb := eb.get_combat_hurtbox()
	if hb != null:
		apply_mass_melee_packet_adjustments(p, hb)
	eb.take_direct_damage_packet(p)
	_mass_try_impact_pulse_and_shockwave_from_hit(p.amount, eb, d)
	if is_last_micro and linked_dmg > 0:
		_echo_deliver_linked_chain(linked_exclude_uid, eb.global_position, linked_dmg, d, echo_gen, echo_threshold)
	var max_g := InfusionEchoRef.max_echo_generation(echo_threshold)
	if (
		is_last_micro
		and echo_threshold >= int(InfusionConstantsRef.InfusionThreshold.EXPRESSION)
		and echo_gen < max_g
		and randf() < InfusionEchoRef.child_echo_proc_chance(echo_threshold)
	):
		var cd := InfusionEchoRef.child_echo_damage_ratio(echo_threshold)
		var next_amt := maxi(1, int(roundf(float(dmg) * cd)))
		var delay := randf_range(
			InfusionEchoRef.afterimage_delay_min_sec(echo_threshold),
			InfusionEchoRef.afterimage_delay_max_sec(echo_threshold)
		)
		var tree := get_tree()
		if tree != null:
			tree.create_timer(delay).timeout.connect(
				_echo_deliver_melee_micro.bind(
					victim_uid,
					next_amt,
					is_critical,
					from_backstab,
					d,
					knockback * 0.62,
					echo_gen + 1,
					echo_threshold,
					true,
					0,
					linked_exclude_uid
				),
				CONNECT_ONE_SHOT
			)


func _echo_maybe_schedule_melee_reverberate(
	packet: DamagePacket, primary: EnemyBase, target_uid: int, fwd: Vector2
) -> void:
	if packet == null or primary == null:
		return
	if packet.suppress_echo_procs or packet.is_echo:
		return
	var echo_th := _infusion_echo_threshold()
	if not InfusionEchoRef.is_echo_attuned(echo_th):
		return
	var had_imprint := primary.echo_infusion_imprint_active()
	if echo_th >= int(InfusionConstantsRef.InfusionThreshold.ESCALATED):
		primary.echo_infusion_refresh_imprint(InfusionEchoRef.imprint_duration_sec(echo_th))
	var chorus := had_imprint and echo_th >= int(InfusionConstantsRef.InfusionThreshold.ESCALATED)
	var proc := chorus or randf() < InfusionEchoRef.reverberate_proc_chance(echo_th)
	if not proc:
		return
	var micro := InfusionEchoRef.chorus_micro_hit_count(echo_th) if chorus else 1
	var ratio := InfusionEchoRef.afterimage_damage_ratio(echo_th)
	var total_echo_dmg := maxi(1, int(roundf(float(packet.amount) * ratio)))
	var each := maxi(1, int(ceil(float(total_echo_dmg) / float(maxi(1, micro)))))
	var base_d := randf_range(
		InfusionEchoRef.afterimage_delay_min_sec(echo_th),
		InfusionEchoRef.afterimage_delay_max_sec(echo_th)
	)
	var spacing := (
		InfusionEchoRef.chorus_micro_hit_spacing_sec(echo_th)
		if chorus
		else 0.0
	)
	var link_ratio := InfusionEchoRef.linked_chain_damage_ratio(echo_th)
	var linked_dmg := (
		maxi(1, int(roundf(float(total_echo_dmg) * link_ratio)))
		if InfusionEchoRef.linked_chain_radius(echo_th) > 0.0001
		else 0
	)
	var echo_kb := packet.knockback * ratio
	var tree := get_tree()
	if tree == null:
		return
	for mi in range(micro):
		var t_wait := base_d + float(mi) * spacing
		var is_last := mi == micro - 1
		tree.create_timer(t_wait).timeout.connect(
			_echo_deliver_melee_micro.bind(
				target_uid,
				each,
				packet.is_critical,
				packet.from_backstab,
				fwd,
				echo_kb,
				1,
				echo_th,
				is_last,
				linked_dmg if is_last else 0,
				target_uid
			),
			CONNECT_ONE_SHOT
		)


func _mass_deal_impact_pulse(
	origin: Vector2, pool: int, primary_uid: int, forward: Vector2, pulse_kb: float
) -> void:
	var mt := _infusion_mass_threshold()
	var r := InfusionMassRef.impact_pulse_radius(mt)
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, r, primary_uid)
	if candidates.is_empty():
		return
	var each := maxi(1, int(floorf(float(pool) / float(candidates.size()))))
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.kind = &"melee"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = origin
	pkt.direction = forward
	pkt.knockback = maxf(0.0, pulse_kb)
	pkt.apply_iframes = false
	pkt.suppress_edge_procs = true
	pkt.suppress_mass_procs = true
	pkt.debug_label = &"mass_impact_pulse"
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		var p := pkt.duplicate_packet()
		p.amount = each
		eb.take_direct_damage_packet(p)


func _mass_maybe_advance_shockwave_build(last_swing_damage: int) -> void:
	var mt := _infusion_mass_threshold()
	if mt < int(InfusionConstantsRef.InfusionThreshold.EXPRESSION):
		return
	_mass_shockwave_hit_stacks += 1
	var need := InfusionMassRef.shockwave_buildup_hits(mt)
	if _mass_shockwave_hit_stacks < need:
		return
	_mass_shockwave_hit_stacks = 0
	_mass_trigger_shockwave(last_swing_damage)


func _mass_trigger_shockwave(hit_damage: int) -> void:
	var mt := _infusion_mass_threshold()
	var origin := global_position
	var base_r := InfusionMassRef.shockwave_radius(mt)
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, base_r, -1)
	var bonus := InfusionMassRef.shockwave_chain_radius_bonus_per_enemy(mt) * float(maxi(0, candidates.size() - 1))
	var r_eff := base_r + bonus
	if r_eff > base_r + 0.01:
		candidates = _edge_collect_enemies_in_radius(origin, r_eff, -1)
	if candidates.is_empty():
		return
	var total := maxi(
		1, int(roundf(float(maxi(1, hit_damage)) * InfusionMassRef.shockwave_damage_ratio(mt)))
	)
	var each := maxi(1, int(floorf(float(total) / float(candidates.size()))))
	var kb := (
		InfusionMassRef.shockwave_knockback(mt)
		* _mass_loadout_knockback_mult()
		* InfusionMassRef.melee_knockback_multiplier(mt)
	)
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.kind = &"melee"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = origin
	pkt.apply_iframes = false
	pkt.suppress_edge_procs = true
	pkt.suppress_mass_procs = true
	pkt.debug_label = &"mass_shockwave"
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		var dir := eb.global_position - origin
		if dir.length_squared() < 1e-8:
			dir = Vector2(0.0, -1.0)
		else:
			dir = dir.normalized()
		var p := pkt.duplicate_packet()
		p.amount = each
		p.direction = dir
		p.knockback = kb
		eb.take_direct_damage_packet(p)
	_mass_play_shockwave_visual(origin, r_eff)


func mass_infusion_dispatch_wall_carrier_impact(
	victim: EnemyBase,
	other: EnemyBase,
	is_wall: bool,
	impact_pos: Vector2 = Vector2.ZERO,
	wall_normal: Vector2 = Vector2.ZERO
) -> void:
	if not is_damage_authority() or victim == null:
		return
	var mt := _infusion_mass_threshold()
	if mt < int(InfusionConstantsRef.InfusionThreshold.ESCALATED):
		return
	if victim.mass_infusion_consume_unstable_burst_if_active():
		_mass_deal_unstable_burst(victim, mt)
		return
	if is_wall:
		_mass_deal_wall_slam(victim, mt, impact_pos, wall_normal)
	elif other != null:
		_mass_deal_carrier_hit(victim, other, mt, impact_pos)


func _mass_deal_wall_slam(
	victim: EnemyBase, mt: int, impact_pos: Vector2, wall_normal: Vector2
) -> void:
	var ratio := InfusionMassRef.wall_slam_damage_ratio(mt)
	if ratio <= 0.0:
		return
	var dmg := maxi(1, int(roundf(float(_mass_effective_melee_damage_estimate()) * ratio)))
	var p := DamagePacketScript.new() as DamagePacket
	p.amount = dmg
	p.kind = &"melee"
	p.source_node = self
	p.source_uid = get_instance_id()
	p.origin = victim.global_position
	p.direction = _active_melee_attack_facing
	if p.direction.length_squared() < 1e-8:
		p.direction = Vector2(0.0, -1.0)
	else:
		p.direction = p.direction.normalized()
	p.knockback = 0.0
	p.apply_iframes = false
	p.suppress_edge_procs = true
	p.suppress_mass_procs = true
	p.debug_label = &"mass_wall_slam"
	victim.take_direct_damage_packet(p)
	var extra := InfusionMassRef.wall_slam_extra_stun_sec(mt)
	if extra > 0.0:
		victim.mass_infusion_add_bonus_stun(extra)
	var fx_pos := impact_pos
	if impact_pos == Vector2.ZERO:
		fx_pos = victim.global_position
	var wn := wall_normal
	if wn.length_squared() < 1e-8:
		wn = -p.direction
	if victim.has_method(&"mass_broadcast_combat_vfx"):
		victim.call(
			&"mass_broadcast_combat_vfx",
			MassCombatVfxRef.Kind.WALL_SLAM,
			fx_pos,
			wn,
			0.0
		)


func _mass_deal_carrier_hit(
	projectile_victim: EnemyBase, struck: EnemyBase, mt: int, impact_pos: Vector2 = Vector2.ZERO
) -> void:
	var dmg := InfusionMassRef.carrier_hit_damage(mt)
	var kb := InfusionMassRef.carrier_hit_knockback(mt) * _mass_loadout_knockback_mult()
	if dmg <= 0 and kb <= 0.0:
		return
	var dir := struck.global_position - projectile_victim.global_position
	if dir.length_squared() < 1e-8:
		dir = Vector2(0.0, -1.0)
	else:
		dir = dir.normalized()
	var p := DamagePacketScript.new() as DamagePacket
	p.amount = maxi(1, dmg)
	p.kind = &"melee"
	p.source_node = self
	p.source_uid = get_instance_id()
	p.origin = struck.global_position
	p.direction = dir
	p.knockback = kb
	p.apply_iframes = false
	p.suppress_edge_procs = true
	p.suppress_mass_procs = true
	p.debug_label = &"mass_carrier_hit"
	struck.take_direct_damage_packet(p)
	var mid := impact_pos
	if mid.length_squared() < 1e-6:
		mid = projectile_victim.global_position.lerp(struck.global_position, 0.5)
	var sep := projectile_victim.global_position.distance_to(struck.global_position)
	if struck.has_method(&"mass_broadcast_combat_vfx"):
		struck.call(
			&"mass_broadcast_combat_vfx",
			MassCombatVfxRef.Kind.CARRIER_CLASH,
			mid,
			dir,
			sep
		)


func _mass_play_shockwave_visual(origin: Vector2, shock_radius: float) -> void:
	if _multiplayer_active() and _is_server_peer():
		if not OS.has_feature("dedicated_server"):
			var vw := get_node_or_null("../../VisualWorld3D") as Node3D
			MassCombatVfxRef.play_on_visual_world(
				vw, MassCombatVfxRef.Kind.SHOCKWAVE, origin, Vector2.ZERO, shock_radius
			)
		_rpc_mass_shockwave_vfx.rpc(origin, shock_radius)
		return
	if not OS.has_feature("dedicated_server"):
		var vw2 := get_node_or_null("../../VisualWorld3D") as Node3D
		MassCombatVfxRef.play_on_visual_world(
			vw2, MassCombatVfxRef.Kind.SHOCKWAVE, origin, Vector2.ZERO, shock_radius
		)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_mass_shockwave_vfx(origin: Vector2, shock_radius: float) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	MassCombatVfxRef.play_on_visual_world(
		vw, MassCombatVfxRef.Kind.SHOCKWAVE, origin, Vector2.ZERO, shock_radius
	)


func _mass_deal_unstable_burst(victim: EnemyBase, mt: int) -> void:
	var origin := victim.global_position
	var r := InfusionMassRef.unstable_burst_radius(mt)
	var ratio := InfusionMassRef.unstable_burst_damage_ratio(mt)
	if r <= 0.0 or ratio <= 0.0:
		return
	var total := maxi(1, int(roundf(float(_mass_effective_melee_damage_estimate()) * ratio)))
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, r, -1)
	if candidates.is_empty():
		return
	var each := maxi(1, int(floorf(float(total) / float(candidates.size()))))
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.kind = &"melee"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = origin
	pkt.knockback = 5.0 * _mass_loadout_knockback_mult()
	pkt.apply_iframes = false
	pkt.suppress_edge_procs = true
	pkt.suppress_mass_procs = true
	pkt.debug_label = &"mass_unstable_burst"
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		var dir := eb.global_position - origin
		if dir.length_squared() < 1e-8:
			dir = Vector2(0.0, -1.0)
		else:
			dir = dir.normalized()
		var p := pkt.duplicate_packet()
		p.amount = each
		p.direction = dir
		eb.take_direct_damage_packet(p)


func _melee_is_backstab(enemy: EnemyBase, attacker: Node2D) -> bool:
	if melee_backstab_damage_multiplier <= 1.000001:
		return false
	var to_attacker := attacker.global_position - enemy.global_position
	if to_attacker.length_squared() < 1e-8:
		return false
	to_attacker = to_attacker.normalized()
	var ef := enemy.get_combat_planar_facing()
	if ef.length_squared() < 1e-8:
		return false
	ef = ef.normalized()
	return to_attacker.dot(ef) <= melee_backstab_facing_dot_threshold


func _melee_crit_chance_for_next_hit() -> float:
	var totals := _stat_totals_merged()
	var bonus := _loadout_stat_from_totals(totals, LoadoutConstantsRef.STAT_CRIT_CHANCE_BONUS)
	var win := _edge_sever_kill_window_crit_bonus()
	return clampf(melee_base_crit_chance + bonus + win, 0.0, 0.92)


func _edge_sever_kill_window_crit_bonus() -> float:
	if _edge_sever_kill_window_until_sec < 0.0:
		return 0.0
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now >= _edge_sever_kill_window_until_sec:
		return 0.0
	return _edge_sever_kill_window_stored_bonus


## Server: called from `EnemyBase` when Edge kills convert into splash / overkill / tempo buffs.
func edge_infusion_dispatch_kill_procs(
	victim: Node2D,
	killing_packet: DamagePacket,
	hp_before_absorb: int,
	victim_was_primed: bool = false
) -> void:
	if not is_damage_authority() or victim == null or killing_packet == null:
		return
	var et := _infusion_edge_threshold()
	if not InfusionEdgeRef.is_edge_attuned(et):
		return
	var origin := victim.global_position
	var forward := killing_packet.direction
	if forward.length_squared() < 1e-6:
		forward = _active_melee_attack_facing
	forward = forward.normalized()
	var absorbed := mini(maxi(1, killing_packet.amount), maxi(1, hp_before_absorb))
	var splash_r := InfusionEdgeRef.sharpen_kill_splash_radius(et)
	var splash_ratio := InfusionEdgeRef.sharpen_kill_splash_damage_ratio(et)
	if splash_r > 0.0 and splash_ratio > 0.0:
		var splash_total := maxi(1, int(roundf(float(absorbed) * splash_ratio)))
		_edge_deal_kill_splash_damage(origin, splash_total, victim.get_instance_id(), forward)
	var kcrit := InfusionEdgeRef.sever_kill_window_crit_bonus(et)
	if kcrit > 0.0:
		var dur := InfusionEdgeRef.sever_kill_window_duration_sec(et)
		var now := float(Time.get_ticks_msec()) / 1000.0
		_edge_sever_kill_window_stored_bonus = kcrit
		_edge_sever_kill_window_until_sec = now + dur
	var spill_ratio := InfusionEdgeRef.sever_overkill_spill_ratio(et)
	var overkill := maxi(0, killing_packet.amount - hp_before_absorb)
	var expr := int(InfusionConstantsRef.InfusionThreshold.EXPRESSION)
	var primed_burst := (
		victim_was_primed
		and et >= expr
		and overkill > 0
	)
	if primed_burst:
		var pool := maxi(1, overkill)
		var max_hops := 1 + InfusionEdgeRef.execution_overkill_max_extra_hops(et)
		_edge_overkill_spill_chain(
			origin,
			forward,
			pool,
			max_hops,
			victim.get_instance_id(),
			et,
			false,
			true,
			&"edge_primed_overkill"
		)
	elif overkill > 0 and spill_ratio > 0.0:
		var pool := maxi(1, int(roundf(float(overkill) * spill_ratio)))
		var max_hops := 1 + InfusionEdgeRef.execution_overkill_max_extra_hops(et)
		_edge_overkill_spill_chain(
			origin,
			forward,
			pool,
			max_hops,
			victim.get_instance_id(),
			et,
			true,
			false,
			&"edge_overkill_spill"
		)


func _edge_deal_kill_splash_damage(
	origin: Vector2, total_damage: int, exclude_uid: int, forward: Vector2
) -> void:
	var splash_r := InfusionEdgeRef.sharpen_kill_splash_radius(_infusion_edge_threshold())
	if splash_r <= 0.0:
		return
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, splash_r, exclude_uid)
	if candidates.is_empty():
		return
	var each := maxi(1, int(floorf(float(total_damage) / float(candidates.size()))))
	var pkt := DamagePacketScript.new() as DamagePacket
	pkt.kind = &"melee"
	pkt.source_node = self
	pkt.source_uid = get_instance_id()
	pkt.origin = origin
	pkt.direction = forward
	pkt.knockback = 0.0
	pkt.apply_iframes = false
	pkt.suppress_edge_procs = true
	pkt.is_critical = false
	pkt.from_backstab = false
	pkt.debug_label = &"edge_kill_splash"
	for eb in candidates:
		if eb == null or not is_instance_valid(eb):
			continue
		var p := pkt.duplicate_packet()
		p.amount = each
		eb.take_direct_damage_packet(p)


func _edge_collect_enemies_in_radius(
	origin: Vector2, radius: float, exclude_uid: int
) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	var r2 := radius * radius
	var tree := get_tree()
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(&"mob"):
		if not node is EnemyBase:
			continue
		var eb := node as EnemyBase
		if eb.get_instance_id() == exclude_uid or eb.is_queued_for_deletion():
			continue
		if origin.distance_squared_to(eb.global_position) > r2:
			continue
		out.append(eb)
	return out


func _edge_overkill_spill_chain(
	origin: Vector2,
	forward: Vector2,
	pool: int,
	hops_remaining: int,
	exclude_uid: int,
	et: int,
	decay_pool_each_hop: bool = true,
	prioritize_lowest_hp: bool = false,
	packet_label: StringName = &"edge_overkill_spill"
) -> void:
	if pool <= 0 or hops_remaining <= 0:
		return
	var range_m := InfusionEdgeRef.sever_overkill_range(et)
	var half_rad := deg_to_rad(InfusionEdgeRef.sever_overkill_cone_degrees(et) * 0.5)
	var excluded: Dictionary = {exclude_uid: true}
	var dmg := pool
	var hop_origin := origin
	var hop_forward := forward
	while hops_remaining > 0 and dmg > 0:
		var next_eb: EnemyBase = null
		if prioritize_lowest_hp:
			next_eb = _edge_pick_cone_enemy_lowest_hp(
				hop_origin, hop_forward, range_m, half_rad, excluded
			)
		else:
			next_eb = _edge_pick_cone_enemy(hop_origin, hop_forward, range_m, half_rad, excluded)
		if next_eb == null:
			break
		var pkt := DamagePacketScript.new() as DamagePacket
		pkt.amount = dmg
		pkt.kind = &"melee"
		pkt.source_node = self
		pkt.source_uid = get_instance_id()
		pkt.origin = hop_origin
		pkt.direction = hop_forward
		pkt.knockback = 0.0
		pkt.apply_iframes = false
		pkt.suppress_edge_procs = true
		pkt.debug_label = packet_label
		next_eb.take_direct_damage_packet(pkt)
		excluded[next_eb.get_instance_id()] = true
		if decay_pool_each_hop:
			dmg = maxi(1, int(roundf(float(dmg) * 0.52)))
		hop_origin = next_eb.global_position
		hops_remaining -= 1


func _edge_pick_cone_enemy_lowest_hp(
	origin: Vector2,
	forward: Vector2,
	range_m: float,
	half_angle: float,
	excluded: Dictionary
) -> EnemyBase:
	if forward.length_squared() < 1e-8:
		return null
	forward = forward.normalized()
	var best: EnemyBase = null
	var best_hp := 999999999
	var best_d2 := INF
	var tree := get_tree()
	if tree == null:
		return null
	var range_m2 := range_m * range_m
	for node in tree.get_nodes_in_group(&"mob"):
		if not node is EnemyBase:
			continue
		var eb := node as EnemyBase
		var uid := eb.get_instance_id()
		if excluded.has(uid) or eb.is_queued_for_deletion():
			continue
		var off := eb.global_position - origin
		var d2 := off.length_squared()
		if d2 > range_m2 or d2 < 1e-8:
			continue
		var dir := off.normalized()
		var ang := absf(forward.angle_to(dir))
		if ang > half_angle:
			continue
		var hp := eb.edge_infusion_current_hp_for_chain()
		if hp < best_hp or (hp == best_hp and d2 < best_d2):
			best_hp = hp
			best_d2 = d2
			best = eb
	return best


func _edge_pick_cone_enemy(
	origin: Vector2,
	forward: Vector2,
	range_m: float,
	half_angle: float,
	excluded: Dictionary
) -> EnemyBase:
	if forward.length_squared() < 1e-8:
		return null
	forward = forward.normalized()
	var best: EnemyBase = null
	var best_d2 := INF
	var tree := get_tree()
	if tree == null:
		return null
	var range_m2 := range_m * range_m
	for node in tree.get_nodes_in_group(&"mob"):
		if not node is EnemyBase:
			continue
		var eb := node as EnemyBase
		var uid := eb.get_instance_id()
		if excluded.has(uid) or eb.is_queued_for_deletion():
			continue
		var off := eb.global_position - origin
		var d2 := off.length_squared()
		if d2 > range_m2 or d2 < 1e-8:
			continue
		var dir := off.normalized()
		var ang := absf(forward.angle_to(dir))
		if ang > half_angle:
			continue
		if d2 < best_d2:
			best_d2 = d2
			best = eb
	return best


func _melee_resolve_backstab(base: int, enemy: EnemyBase, attacker: Node2D) -> Dictionary:
	var out := {"amount": base, "from_backstab": false}
	if base <= 0:
		return out
	out["from_backstab"] = _melee_is_backstab(enemy, attacker)
	return out


func _melee_resolve_precision(base: int, enemy: EnemyBase, attacker: Node2D) -> Dictionary:
	var out := {
		"amount": maxi(1, base),
		"from_backstab": false,
		"is_critical": false,
	}
	if base <= 0 or melee_backstab_damage_multiplier <= 1.000001:
		return out
	out["from_backstab"] = _melee_is_backstab(enemy, attacker)
	var crit := bool(out["from_backstab"])
	if not crit:
		crit = randf() < _melee_crit_chance_for_next_hit()
	out["is_critical"] = crit
	var mult := 1.0
	if crit:
		var edge_t := _infusion_edge_threshold()
		mult = melee_backstab_damage_multiplier * InfusionEdgeRef.sharpen_crit_damage_multiplier(edge_t)
	out["amount"] = maxi(1, int(roundf(float(base) * mult)))
	return out


func _surge_try_melee_secondary_burst(
	surge_threshold: int,
	overcharge_norm: float,
	damage_pool_base: int,
	hit_count: int,
	attack_facing: Vector2
) -> void:
	if hit_count <= 0:
		return
	if not InfusionSurgeRef.is_surge_attuned(surge_threshold):
		return
	var rad := InfusionSurgeRef.secondary_burst_radius(surge_threshold, overcharge_norm)
	if rad <= 0.05:
		return
	var ratio := InfusionSurgeRef.secondary_burst_damage_ratio(surge_threshold, overcharge_norm)
	var pool := maxi(1, int(roundf(float(damage_pool_base) * ratio)))
	var fwd := _normalized_attack_facing(attack_facing)
	_surge_deal_secondary_burst(global_position, pool, -1, fwd, 6.2, rad, &"surge_secondary")


func _squash_mobs_in_melee_hit(
	hit_event_id: int = -1,
	charge_ratio: float = 1.0,
	apply_charge_scaling: bool = true,
	surge_overcharge_norm: float = 0.0,
	surge_overdrive_full_melee: bool = false
) -> int:
	var cr := clampf(charge_ratio, 0.0, 1.0)
	if surge_overdrive_full_melee and apply_charge_scaling:
		cr = 1.0
	var ovn := clampf(surge_overcharge_norm, 0.0, 1.0)
	var st_s := _infusion_surge_threshold()
	var dmg: int = melee_attack_damage
	var kb: float = melee_knockback_strength
	if apply_charge_scaling:
		dmg = _melee_damage_for_charge_ratio(cr)
		kb = _melee_knockback_for_charge_ratio(cr)
		dmg = maxi(
			1,
			dmg
				+ _infusion_edge_melee_damage_bonus()
				+ _infusion_mass_melee_damage_bonus()
				+ _infusion_anchor_melee_damage_bonus()
				+ _infusion_surge_melee_flat_bonus()
		)
	dmg = maxi(1, int(roundf(float(dmg) * _phase_outgoing_damage_multiplier())))
	if InfusionSurgeRef.is_surge_attuned(st_s):
		dmg = maxi(
			1,
			int(
				roundf(
					float(dmg) * InfusionSurgeRef.overcharge_melee_damage_multiplier(st_s, ovn)
				)
			)
		)
		if apply_charge_scaling and cr >= 0.999 - 1e-5 and ovn < 0.02:
			dmg += InfusionSurgeRef.primed_full_charge_flat_bonus(st_s)
	var mass_t := _infusion_mass_threshold()
	if InfusionMassRef.is_mass_attuned(mass_t):
		kb *= InfusionMassRef.melee_knockback_multiplier(mass_t) * _mass_loadout_knockback_mult()
	var attack_facing := _normalized_attack_facing(_facing_planar)
	_active_melee_attack_facing = attack_facing
	_phase_begin_slip_body_window()
	_last_phase_melee_snapshot_damage = dmg
	_last_phase_melee_snapshot_knockback = kb
	if _melee_hitbox != null:
		_sync_melee_hitbox_geometry()
		_melee_hitbox.repeat_mode = Hitbox2D.RepeatMode.NONE
		_melee_hitbox.debug_draw_enabled = show_melee_hit_debug
		var packet := DamagePacketScript.new() as DamagePacket
		packet.amount = dmg
		packet.kind = &"melee"
		packet.source_node = self
		packet.source_uid = get_instance_id()
		packet.attack_instance_id = hit_event_id
		packet.origin = global_position
		packet.direction = attack_facing
		packet.knockback = kb
		packet.apply_iframes = false
		packet.blockable = false
		packet.debug_label = &"player_melee"
		_phase_tag_melee_packet(packet)
		_melee_hitbox.activate(packet, attack_hitbox_visual_duration)
		var hc := _melee_hitbox.get_last_resolved_count()
		_surge_try_melee_secondary_burst(st_s, ovn, dmg, hc, attack_facing)
		_phase_post_melee_spatial_followup(hit_event_id, attack_facing, dmg, kb)
		return hc
	var hit_count := 0
	for node in get_tree().get_nodes_in_group(&"mob"):
		if not node is CharacterBody2D:
			continue
		var mob := node as CharacterBody2D
		if _melee_hit_overlaps_mob(mob):
			var dmg_hit := dmg
			var from_bs := false
			var is_crit := false
			if mob is EnemyBase:
				var res := _melee_resolve_precision(dmg, mob as EnemyBase, self)
				dmg_hit = int(res["amount"])
				from_bs = bool(res.get("from_backstab", false))
				is_crit = bool(res.get("is_critical", false))
			var kb_hit := kb
			var dir_hit := attack_facing
			if mob is EnemyBase:
				var kb_res := _mass_kb_dir_for_enemy(kb, attack_facing, mob as EnemyBase)
				kb_hit = float(kb_res.get("kb", kb))
				var dv: Variant = kb_res.get("dir", attack_facing)
				if dv is Vector2:
					dir_hit = dv as Vector2
			if hit_event_id >= 0 and mob.has_method(&"apply_authoritative_hit_event"):
				var applied := bool(
					mob.call(
						&"apply_authoritative_hit_event",
						hit_event_id,
						dmg_hit,
						dir_hit,
						kb_hit,
						from_bs,
						is_crit
					)
				)
				if applied:
					hit_count += 1
					if mob is EnemyBase:
						_mass_try_impact_pulse_and_shockwave_from_hit(
							dmg_hit, mob as EnemyBase, dir_hit
						)
			elif mob.has_method(&"take_hit"):
				mob.call(&"take_hit", dmg_hit, dir_hit, kb_hit, from_bs, is_crit)
				hit_count += 1
				if mob is EnemyBase:
					_mass_try_impact_pulse_and_shockwave_from_hit(dmg_hit, mob as EnemyBase, dir_hit)
	_surge_try_melee_secondary_burst(st_s, ovn, dmg, hit_count, attack_facing)
	_phase_post_melee_spatial_followup(hit_event_id, attack_facing, dmg, kb)
	return hit_count


func _phase_post_melee_spatial_followup(
	hit_event_id: int, attack_facing: Vector2, dmg: int, kb: float
) -> void:
	if not is_damage_authority():
		return
	_phase_deliver_fracture_flanks_if_eligible(global_position, attack_facing, dmg, kb, hit_event_id)
	_phase_schedule_skew_ghost_strike(global_position, attack_facing, dmg, kb, hit_event_id)


## Stubs for methods implemented on `player.gd` (leaf). Required so this script passes GDScript check-only.
func _free_world_debug_meshes() -> void:
	pass


func _ui_blocks_attack_this_physics_frame() -> bool:
	return false
