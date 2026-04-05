extends CharacterBody2D

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
@export var dodge_speed := 36.0
@export var dodge_duration := 0.16
@export var dodge_cooldown := 0.05
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
var _reconcile_target_facing_lock_time_remaining := 0.0
var _reconcile_target_facing_lock_planar := Vector2(0.0, -1.0)
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
var _cached_ui_hovered_physics_frame := -1
var _cached_ui_blocks_attack := false
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


func _multiplayer_active() -> bool:
	return multiplayer.multiplayer_peer != null


func _local_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


func _is_server_peer() -> bool:
	return _multiplayer_active() and multiplayer.is_server()


func _can_broadcast_world_replication() -> bool:
	if not _multiplayer_active() or not _is_server_peer():
		return true
	var session := get_node_or_null("/root/NetworkSession")
	if session != null and session.has_method("can_broadcast_world_replication"):
		return bool(session.call("can_broadcast_world_replication"))
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
	_apply_visual_defending_state()


func _set_downed_state(next_downed: bool, emit_hit_signal: bool = false) -> void:
	if _is_dead == next_downed:
		return
	_is_dead = next_downed
	if _is_dead:
		_set_defending_state(false)
	if _is_dead:
		velocity = Vector2.ZERO
		height = 0.0
		_dodge_time_remaining = 0.0
		_dodge_cooldown_remaining = 0.0
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
	if not _multiplayer_active() or _is_server_peer():
		_authoritative_stamina = stamina
		_authoritative_stamina_broken = _stamina_broken
	if changed:
		stamina_changed.emit(stamina, _max_stamina_value())


func _restore_stamina_to_full() -> void:
	_stamina_regen_cooldown_remaining = 0.0
	_set_stamina_value(_max_stamina_value())


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
		_flow_last_action_kind
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
	flow_last_action_kind: int = -1
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
		_reconcile_target_facing_lock_time_remaining = _facing_lock_time_remaining
		_reconcile_target_facing_lock_planar = _facing_lock_planar
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
	_facing_lock_time_remaining = _reconcile_target_facing_lock_time_remaining
	_facing_lock_planar = _reconcile_target_facing_lock_planar
	for command in _pending_input_commands:
		var move_active := bool(command.get("move_active", false))
		var target_world_variant: Variant = command.get("target_world", global_position)
		var target_world: Vector2 = (
			target_world_variant if target_world_variant is Vector2 else global_position
		)
		var aim_v: Variant = command.get("aim_planar", Vector2.ZERO)
		var aim_planar: Vector2 = aim_v as Vector2 if aim_v is Vector2 else Vector2.ZERO
		var dodge_pressed := bool(command.get("dodge_pressed", false))
		var defend_down := bool(command.get("defend_down", false))
		var command_delta := float(command.get("delta", 1.0 / maxf(1.0, float(Engine.physics_ticks_per_second))))
		_apply_movement_step(command_delta, move_active, target_world, dodge_pressed, defend_down, aim_planar)
	_reconcile_has_target = false


func _apply_movement_step(
	delta: float,
	move_active: bool,
	target_world: Vector2,
	dodge_pressed: bool,
	defend_down: bool,
	aim_planar: Vector2 = Vector2.ZERO,
) -> float:
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
	if _dodge_time_remaining > 0.0:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
	elif dodge_pressed and _dodge_cooldown_remaining <= 0.0 and not _is_defending:
		_dodge_direction = _facing_planar.normalized()
		if _dodge_direction.length_squared() <= 1e-6:
			_dodge_direction = Vector2(0.0, -1.0)
		_dodge_time_remaining = dodge_duration
		_dodge_cooldown_remaining = dodge_cooldown
	var planar_speed := 0.0
	if _dodge_time_remaining > 0.0:
		velocity = _dodge_direction * dodge_speed
		planar_speed = dodge_speed
	elif direction != Vector2.ZERO:
		var resolved_speed := speed
		resolved_speed *= InfusionFlowRef.overdrive_move_speed_multiplier(
			_flow_overdrive_remaining, _infusion_flow_threshold()
		)
		if _is_defending:
			resolved_speed *= clampf(defend_move_speed_multiplier, 0.0, 1.0)
		velocity = direction * resolved_speed
		planar_speed = resolved_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_update_visual_from_planar_speed(planar_speed)
	return planar_speed


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
	_apply_movement_step(delta, move_active, target_world, dodge_pressed, defend_down, aim_planar)
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
	_apply_movement_step(delta, move_active, target_world, dodge_pressed, defend_down, aim_planar)
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


func _spawn_player_ranged_arrow(
	spawn_position: Vector2,
	facing: Vector2,
	authoritative_damage: bool,
	apply_cooldown: bool,
	projectile_event_id: int = -1,
	projectile_style_id: StringName = LoadoutConstantsRef.PROJECTILE_STYLE_RED,
	charge_size_mult: float = 1.0,
	infusion_geometry_scale: float = 0.0
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
	arrow.damage = maxi(1, int(roundf(float(ranged_damage) * _phase_outgoing_damage_multiplier())))
	arrow.speed = ranged_speed
	arrow.max_distance = ranged_max_tiles * world_units_per_tile
	arrow.knockback_strength = ranged_knockback
	var expr_m := (
		infusion_geometry_scale
		if infusion_geometry_scale > 0.001
		else _infusion_edge_expression_geometry_mult()
	)
	arrow.mesh_scale = Vector3(1.6, 1.6, 1.6) * expr_m
	if arrow.has_method(&"set_authoritative_damage"):
		arrow.call(&"set_authoritative_damage", authoritative_damage)
	arrow.configure(
		spawn_position,
		facing,
		vw,
		true,
		projectile_style_id,
		projectile_event_id,
		charge_size_mult * expr_m
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
	requested_facing: Vector2, charge_ratio: float = 1.0, apply_charge_scaling: bool = true
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
	var resolved_facing := requested_facing
	if resolved_facing.length_squared() > 1e-6:
		_facing_planar = resolved_facing.normalized()
	_start_facing_lock(_facing_planar)
	_play_melee_attack_presentation()
	_server_melee_hit_event_sequence += 1
	var hit_event_id := _server_melee_hit_event_sequence
	var hit_count := _squash_mobs_in_melee_hit(hit_event_id, cr, apply_charge_scaling)
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.MELEE)
	_flow_pulse_ability_cooldowns_after_melee()
	_melee_attack_cooldown_remaining = _flow_effective_melee_cooldown()
	_server_melee_event_sequence += 1
	var event_sequence := _server_melee_event_sequence
	_last_applied_melee_event_sequence = max(_last_applied_melee_event_sequence, event_sequence)
	if _can_broadcast_world_replication():
		_rpc_receive_melee_attack_event.rpc(
			event_sequence,
			_facing_planar,
			hit_count,
			_flow_tempo,
			_flow_chain_remaining,
			_flow_overdrive_remaining,
			_flow_aggression_remaining,
			_flow_last_action_kind
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
	if not _spawn_player_ranged_arrow(
		spawn, _facing_planar, true, true, event_sequence, projectile_style_id, sz
	):
		return false
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
			_flow_last_action_kind
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
	charge_ratio: float = 1.0, apply_charge_scaling: bool = true
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
		_try_execute_server_melee_attack(_facing_planar, cr, apply_charge_scaling)
		return
	_local_melee_request_sequence += 1
	_start_facing_lock(_facing_planar)
	_rpc_request_melee_attack.rpc_id(
		1, _local_melee_request_sequence, _facing_planar, cr, apply_charge_scaling
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
	apply_charge_scaling: bool = true
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
	_try_execute_server_melee_attack(facing_planar, cr, apply_charge_scaling)


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
	flow_last_action_kind: int = -1
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
	if OS.is_debug_build():
		print(
			"[M4][Melee][Remote] peer=%s attack_event=%s hits=%s" % [
				network_owner_peer_id,
				event_sequence,
				hit_count,
			]
		)


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
	flow_last_action_kind: int = -1
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
		expr_m
	)
	_ranged_cooldown_remaining = maxf(
		_ranged_cooldown_remaining, _flow_effective_ranged_cooldown()
	)
	if OS.is_debug_build():
		print(
			"[M4][Ranged][Remote] peer=%s attack_event=%s spawn=%s" % [
				network_owner_peer_id,
				event_sequence,
				spawn_position,
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
		_rebuild_melee_debug_mesh()
	elif _melee_debug_mi:
		_melee_debug_mi.visible = false
	if show_player_hitbox_debug:
		_rebuild_player_hitbox_debug()
	elif _player_hitbox_mi:
		_player_hitbox_mi.visible = false
	if show_shield_block_debug:
		_rebuild_shield_block_debug_mesh()
	elif _shield_block_debug_mi:
		_shield_block_debug_mi.visible = false
	if show_mob_hitbox_debug:
		_rebuild_mob_hitboxes_debug()
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
				var r := minf(
					1.0,
					_melee_charge_time / maxf(0.05, _flow_effective_melee_charge_max_time())
				)
				_update_melee_charge_bar_visual(r)
				if r >= 1.0:
					_commit_melee_strike(1.0, true, false)
				elif _charge_hold_release_detected(
					_melee_charge_input_source, use_wasd, lmb_was, rmb_was, lmb_cur, rmb_cur
				):
					if r >= melee_charge_min_ratio:
						_commit_melee_strike(r, true, true)
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


func _commit_melee_strike(
	charge_ratio: float, apply_charge_scaling: bool, enforce_min_ratio: bool
) -> void:
	if not _melee_charging:
		return
	var cr := clampf(charge_ratio, 0.0, 1.0)
	_clear_melee_attack_hold_state()
	if apply_charge_scaling and enforce_min_ratio and cr < melee_charge_min_ratio:
		return
	if _multiplayer_active():
		if _is_server_peer():
			_try_execute_server_melee_attack(_facing_planar, cr, apply_charge_scaling)
		else:
			_submit_local_melee_attack_request(cr, apply_charge_scaling)
	else:
		_execute_local_melee_strike(cr, apply_charge_scaling)


func _execute_local_melee_strike(charge_ratio: float, apply_charge_scaling: bool = true) -> void:
	_start_facing_lock(_facing_planar)
	_play_melee_attack_presentation()
	_squash_mobs_in_melee_hit(-1, charge_ratio, apply_charge_scaling)
	_flow_after_successful_weapon_action(InfusionFlowRef.ActionKind.MELEE)
	_flow_pulse_ability_cooldowns_after_melee()
	_melee_attack_cooldown_remaining = _flow_effective_melee_cooldown()


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
	if not _spawn_player_ranged_arrow(
		spawn,
		_facing_planar,
		true,
		true,
		-1,
		_equipped_handgun_projectile_style(),
		sz
	):
		return
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
	if not _spawn_player_ranged_arrow(spawn, dir, true, true, -1, _equipped_handgun_projectile_style()):
		return
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


func _wasd_move_facing_aim(aim_planar: Vector2, move_direction: Vector2) -> Vector2:
	if _is_wasd_mouse_scheme_enabled() and move_direction.length_squared() > 1e-6:
		return Vector2.ZERO
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


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if infusion_manager == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_F9:
				infusion_manager.call(
					&"add_infusion",
					InfusionConstantsRef.PILLAR_EDGE,
					InfusionConstantsRef.STACK_NORMAL,
					InfusionConstantsRef.SourceKind.NORMAL
				)
				get_viewport().set_input_as_handled()
			KEY_F10:
				infusion_manager.call(
					&"add_infusion",
					InfusionConstantsRef.PILLAR_FLOW,
					InfusionConstantsRef.STACK_NORMAL,
					InfusionConstantsRef.SourceKind.NORMAL
				)
				get_viewport().set_input_as_handled()
			KEY_F11:
				infusion_manager.call(&"clear_run_infusions")
				get_viewport().set_input_as_handled()
			KEY_F12:
				infusion_manager.call(
					&"add_infusion",
					InfusionConstantsRef.PILLAR_PHASE,
					InfusionConstantsRef.STACK_NORMAL,
					InfusionConstantsRef.SourceKind.NORMAL
				)
				get_viewport().set_input_as_handled()


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


func _infusion_mass_melee_damage_bonus() -> int:
	return InfusionMassRef.melee_damage_bonus(_infusion_mass_threshold())


func _infusion_stub_melee_damage_bonus() -> int:
	if infusion_manager == null:
		return 0
	var mgr: Node = infusion_manager
	return (
		InfusionEchoRef.melee_bonus_from_manager(mgr)
		+ InfusionAnchorRef.melee_bonus_from_manager(mgr)
		+ InfusionSurgeRef.melee_bonus_from_manager(mgr)
	)


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
			+ _infusion_stub_melee_damage_bonus()
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
	return InfusionPhaseRef.expression_depth_multiplier(_infusion_phase_threshold())


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


func apply_backstab_bonus_to_melee_packet(packet: DamagePacket, hurtbox: Hurtbox2D) -> void:
	if packet == null or hurtbox == null:
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
	if not InfusionMassRef.is_mass_attuned(mt) or enemy == null:
		return {"kb": kb, "dir": dir}
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


func _mass_deal_impact_pulse(
	origin: Vector2, pool: int, primary_uid: int, forward: Vector2, pulse_kb: float
) -> void:
	var mt := _infusion_mass_threshold()
	var r := InfusionMassRef.impact_pulse_radius(mt)
	var candidates: Array[EnemyBase] = _edge_collect_enemies_in_radius(origin, r, primary_uid)
	if candidates.is_empty():
		return
	var each := maxi(1, pool / candidates.size())
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
	var each := maxi(1, total / candidates.size())
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


func mass_infusion_dispatch_wall_carrier_impact(
	victim: EnemyBase, other: EnemyBase, is_wall: bool
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
		_mass_deal_wall_slam(victim, mt)
	elif other != null:
		_mass_deal_carrier_hit(victim, other, mt)


func _mass_deal_wall_slam(victim: EnemyBase, mt: int) -> void:
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


func _mass_deal_carrier_hit(projectile_victim: EnemyBase, struck: EnemyBase, mt: int) -> void:
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
	var each := maxi(1, total / candidates.size())
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
	var each := maxi(1, total_damage / candidates.size())
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


func _squash_mobs_in_melee_hit(
	hit_event_id: int = -1, charge_ratio: float = 1.0, apply_charge_scaling: bool = true
) -> int:
	var cr := clampf(charge_ratio, 0.0, 1.0)
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
			+ _infusion_stub_melee_damage_bonus()
	)
	dmg = maxi(1, int(roundf(float(dmg) * _phase_outgoing_damage_multiplier())))
	var mass_t := _infusion_mass_threshold()
	if InfusionMassRef.is_mass_attuned(mass_t):
		kb *= InfusionMassRef.melee_knockback_multiplier(mass_t) * _mass_loadout_knockback_mult()
	var attack_facing := _normalized_attack_facing(_facing_planar)
	_active_melee_attack_facing = attack_facing
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
		_melee_hitbox.activate(packet, attack_hitbox_visual_duration)
		return _melee_hitbox.get_last_resolved_count()
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
	return hit_count


func _rebuild_melee_debug_mesh() -> void:
	if _melee_debug_mi == null:
		return
	_melee_debug_mi.visible = true
	var f2 := _resolve_melee_hit_facing()
	var p0 := global_position
	var f3 := Vector3(f2.x, 0.0, f2.y)
	var r3 := Vector3(-f3.z, 0.0, f3.x)
	var origin3 := Vector3(p0.x, melee_debug_ground_y, p0.y)
	var sz2 := _melee_hit_effective_width_depth()
	var half_w := sz2.x * 0.5
	var inner := _melee_range_start()
	var near_o := f3 * inner
	var far_o := f3 * (inner + sz2.y)
	var c0 := origin3 + near_o + r3 * (-half_w)
	var c1 := origin3 + near_o + r3 * half_w
	var c2 := origin3 + far_o + r3 * half_w
	var c3 := origin3 + far_o + r3 * (-half_w)
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _melee_debug_mat)
	var up := Vector3.UP
	for v in [c0, c1, c2, c0, c2, c3]:
		imm.surface_set_normal(up)
		imm.surface_add_vertex(v)
	imm.surface_end()
	_melee_debug_mi.mesh = imm


func _append_circle_fan_xz(
	imm: ImmediateMesh, mat: Material, center2: Vector2, radius: float, ground_y: float, segments: int
) -> void:
	if radius <= 0.0 or segments < 3:
		return
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var up := Vector3.UP
	var c := Vector3(center2.x, ground_y, center2.y)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var e0 := Vector3(center2.x + cos(a0) * radius, ground_y, center2.y + sin(a0) * radius)
		var e1 := Vector3(center2.x + cos(a1) * radius, ground_y, center2.y + sin(a1) * radius)
		for v in [c, e0, e1]:
			imm.surface_set_normal(up)
			imm.surface_add_vertex(v)
	imm.surface_end()


func _append_sector_fan_xz(
	imm: ImmediateMesh,
	mat: Material,
	center2: Vector2,
	facing2: Vector2,
	radius: float,
	ground_y: float,
	total_angle_radians: float,
	segments: int
) -> void:
	if radius <= 0.0 or segments < 1 or total_angle_radians <= 0.0:
		return
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var up := Vector3.UP
	var c := Vector3(center2.x, ground_y, center2.y)
	var center_angle := atan2(facing2.y, facing2.x)
	var half_angle := total_angle_radians * 0.5
	for i in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var a0 := center_angle - half_angle + total_angle_radians * t0
		var a1 := center_angle - half_angle + total_angle_radians * t1
		var e0 := Vector3(center2.x + cos(a0) * radius, ground_y, center2.y + sin(a0) * radius)
		var e1 := Vector3(center2.x + cos(a1) * radius, ground_y, center2.y + sin(a1) * radius)
		for v in [c, e0, e1]:
			imm.surface_set_normal(up)
			imm.surface_add_vertex(v)
	imm.surface_end()


func _rebuild_shield_block_debug_mesh() -> void:
	if _shield_block_debug_mi == null or _shield_block_debug_mat == null:
		return
	if not _is_defending or not _can_defend_in_current_mode() or stamina <= 0.0:
		_shield_block_debug_mi.visible = false
		return
	var total_angle_radians := deg_to_rad(clampf(block_arc_degrees, 0.0, 360.0))
	if total_angle_radians <= 0.0:
		_shield_block_debug_mi.visible = false
		return
	var facing2 := _facing_planar
	if facing2.length_squared() <= 1e-6:
		facing2 = Vector2(0.0, -1.0)
	else:
		facing2 = facing2.normalized()
	var radius := _get_player_body_radius() + 2.25
	var segments := maxi(6, int(ceil(clampf(block_arc_degrees, 0.0, 360.0) / 12.0)))
	var imm := ImmediateMesh.new()
	_append_sector_fan_xz(
		imm,
		_shield_block_debug_mat,
		global_position,
		facing2,
		radius,
		hitbox_debug_ground_y + 0.006,
		total_angle_radians,
		segments
	)
	_shield_block_debug_mi.visible = true
	_shield_block_debug_mi.material_override = _shield_block_debug_mat
	_shield_block_debug_mi.mesh = imm


func _rebuild_player_hitbox_debug() -> void:
	if _player_hitbox_mi == null:
		return
	if not show_player_hitbox_debug:
		_player_hitbox_mi.visible = false
		return
	_player_hitbox_mi.visible = true
	var radius := 0.7605869
	var center2 := global_position
	if _body_shape:
		center2 = _body_shape.global_position
		if _body_shape.shape is CircleShape2D:
			radius = (_body_shape.shape as CircleShape2D).radius
	var imm := ImmediateMesh.new()
	_append_circle_fan_xz(
		imm,
		_player_hitbox_mat,
		center2,
		radius,
		hitbox_debug_ground_y,
		maxi(3, hitbox_debug_circle_segments)
	)
	_player_hitbox_mi.mesh = imm


func _rebuild_mob_hitboxes_debug() -> void:
	if _mob_hitboxes_mi == null:
		return
	if not show_mob_hitbox_debug:
		_mob_hitboxes_mi.visible = false
		return
	var gy := hitbox_debug_ground_y
	var up := Vector3.UP
	var verts: PackedVector3Array = PackedVector3Array()
	for node in get_tree().get_nodes_in_group(&"mob"):
		var cs := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null:
			continue
		var sh := cs.shape
		if sh is RectangleShape2D:
			var rect := sh as RectangleShape2D
			var hw := rect.size.x * 0.5
			var hh := rect.size.y * 0.5
			var xf := cs.global_transform
			var g0: Vector2 = xf * Vector2(-hw, -hh)
			var g1: Vector2 = xf * Vector2(hw, -hh)
			var g2: Vector2 = xf * Vector2(hw, hh)
			var g3: Vector2 = xf * Vector2(-hw, hh)
			var p0 := Vector3(g0.x, gy, g0.y)
			var p1 := Vector3(g1.x, gy, g1.y)
			var p2 := Vector3(g2.x, gy, g2.y)
			var p3 := Vector3(g3.x, gy, g3.y)
			verts.append_array([p0, p1, p2, p0, p2, p3])
	if verts.is_empty():
		_mob_hitboxes_mi.mesh = null
		_mob_hitboxes_mi.visible = false
		return
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mob_hitbox_mat)
	for k in range(verts.size()):
		imm.surface_set_normal(up)
		imm.surface_add_vertex(verts[k])
	imm.surface_end()
	_mob_hitboxes_mi.visible = true
	_mob_hitboxes_mi.mesh = imm


func _physics_process(delta: float) -> void:
	if _multiplayer_active():
		_physics_process_multiplayer(delta)
		return
	if _is_dead:
		return
	_tick_facing_lock(delta)
	_flow_decay_step(delta)
	var cd_sp := InfusionFlowRef.cooldown_tick_multiplier(
		_flow_aggression_remaining, _flow_overdrive_remaining, _infusion_flow_threshold()
	)
	_melee_attack_cooldown_remaining = maxf(0.0, _melee_attack_cooldown_remaining - delta * cd_sp)
	_ranged_cooldown_remaining = maxf(0.0, _ranged_cooldown_remaining - delta * cd_sp)
	_bomb_cooldown_remaining = maxf(0.0, _bomb_cooldown_remaining - delta * cd_sp)

	var use_wasd_sp := _is_wasd_mouse_scheme_enabled()
	if _menu_input_blocked:
		_clear_pending_rmb_attack()
		_rmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		_lmb_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	elif Input.is_action_just_pressed(&"weapon_switch"):
		_clear_pending_rmb_attack()
		_cycle_weapon()
	if not _menu_input_blocked and Input.is_action_just_pressed(&"bomb_throw"):
		_clear_pending_rmb_attack()
		_face_toward_mouse_planar()
		if _try_throw_bomb():
			_play_attack_animation_presentation(&"bomb")

	var defend_down := (
		not _menu_input_blocked
		and Input.is_action_pressed(&"defend")
		and _can_defend_in_current_mode()
	)
	_set_defending_state(defend_down)
	_tick_stamina_regen(delta)

	var ui_blocks_attack := _ui_blocks_attack_this_physics_frame()
	_process_local_melee_charge_input(
		delta, use_wasd_sp, ui_blocks_attack, defend_down, not _menu_input_blocked
	)

	var direction := Vector2.ZERO
	var aim_planar_sp := Vector2.ZERO
	if not _menu_input_blocked:
		var intent := _local_move_steering_intent()
		if bool(intent.get("move_active", false)):
			var tw: Variant = intent.get("target_world", global_position)
			var target_world: Vector2 = tw as Vector2 if tw is Vector2 else global_position
			var to_target := target_world - global_position
			if to_target.length_squared() > 0.01:
				direction = to_target.normalized()
		var av: Variant = intent.get("aim_planar", Vector2.ZERO)
		aim_planar_sp = av as Vector2 if av is Vector2 else Vector2.ZERO

	_update_facing_planar(
		direction, true, _resolve_facing_aim_for_move_step(aim_planar_sp, direction, defend_down)
	)
	if not _menu_input_blocked:
		_execute_pending_rmb_attack_if_any()
	else:
		velocity = Vector2.ZERO

	_dodge_cooldown_remaining = maxf(0.0, _dodge_cooldown_remaining - delta)
	if _dodge_time_remaining > 0.0:
		_dodge_time_remaining = maxf(0.0, _dodge_time_remaining - delta)
	elif (
		not _menu_input_blocked
		and Input.is_action_just_pressed(&"dodge")
		and _dodge_cooldown_remaining <= 0.0
		and not _is_defending
	):
		_dodge_direction = _facing_planar.normalized()
		if _dodge_direction.length_squared() <= 1e-6:
			_dodge_direction = Vector2(0.0, -1.0)
		_dodge_time_remaining = dodge_duration
		_dodge_cooldown_remaining = dodge_cooldown

	var planar_speed := 0.0
	if _dodge_time_remaining > 0.0:
		velocity = _dodge_direction * dodge_speed
		planar_speed = dodge_speed
	elif direction != Vector2.ZERO:
		var resolved_speed := speed
		resolved_speed *= InfusionFlowRef.overdrive_move_speed_multiplier(
			_flow_overdrive_remaining, _infusion_flow_threshold()
		)
		if _is_defending:
			resolved_speed *= clampf(defend_move_speed_multiplier, 0.0, 1.0)
		velocity = direction * resolved_speed
		planar_speed = resolved_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	if _visual:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)
		var visual_facing := _resolve_visual_facing_planar()
		_visual.rotation.y = atan2(visual_facing.x, visual_facing.y)
		if _visual.has_method(&"set_locomotion_from_planar_speed"):
			_visual.set_locomotion_from_planar_speed(planar_speed, speed)

	_attack_hitbox_visual_time_remaining = maxf(0.0, _attack_hitbox_visual_time_remaining - delta)
	_refresh_debug_visuals(delta)

	if _health_component != null:
		_invuln_time_remaining = _health_component.get_invulnerability_remaining()
	if _invuln_time_remaining > 0.0:
		_update_invulnerability_flash_visual()


func _ui_blocks_attack_this_physics_frame() -> bool:
	var physics_frame := Engine.get_physics_frames()
	if _cached_ui_hovered_physics_frame == physics_frame:
		return _cached_ui_blocks_attack
	var viewport := get_viewport()
	_cached_ui_blocks_attack = viewport != null and viewport.gui_get_hovered_control() != null
	_cached_ui_hovered_physics_frame = physics_frame
	return _cached_ui_blocks_attack


func _exit_tree() -> void:
	_free_world_debug_meshes()
	_remote_ranged_projectiles_by_event_id.clear()
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.queue_free()


func die() -> void:
	_set_downed_state(true, true)


func reset_for_retry(world_pos: Vector2) -> void:
	_set_downed_state(false)
	_set_defending_state(false)
	_clear_pending_rmb_attack()
	weapon_mode = WeaponMode.SWORD
	_coerce_weapon_mode_to_available(true)
	heal_to_full()
	global_position = world_pos
	velocity = Vector2.ZERO
	height = 0.0
	_invuln_time_remaining = 0.0
	_stamina_regen_cooldown_remaining = 0.0
	_dodge_time_remaining = 0.0
	_dodge_cooldown_remaining = 0.0
	_facing_lock_time_remaining = 0.0
	_rmb_down = false
	_lmb_down = false
	_bomb_cooldown_remaining = 0.0
	if _body_shape != null:
		_body_shape.disabled = false
	if _player_hurtbox != null:
		_player_hurtbox.set_active(is_damage_authority())
	_reset_player_visual_transparency()
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, height, global_position.y)


func revive(health_after_revive: int = -1) -> void:
	if _multiplayer_active() and not _is_server_peer():
		return
	if not _is_dead:
		return
	var resolved_health := health_after_revive
	if resolved_health <= 0:
		resolved_health = REVIVE_HEALTH
	health = clampi(resolved_health, 1, max_health)
	_sync_health_component_state()
	_restore_stamina_to_full()
	_set_downed_state(false)
	_set_defending_state(false)


func revive_to_full() -> void:
	revive(max_health)


func heal_to_full() -> void:
	health = max_health
	_sync_health_component_state()
	_restore_stamina_to_full()


func _free_world_debug_meshes() -> void:
	for mi in [_melee_debug_mi, _player_hitbox_mi, _mob_hitboxes_mi, _shield_block_debug_mi]:
		if mi != null and is_instance_valid(mi):
			mi.queue_free()
	_melee_debug_mi = null
	_player_hitbox_mi = null
	_mob_hitboxes_mi = null
	_shield_block_debug_mi = null
	_cached_visual_mesh_instances.clear()
	_debug_visual_refresh_time_remaining = 0.0
	_last_invulnerability_flash_state = -1


func get_shadow_visual_root() -> Node3D:
	return _visual
