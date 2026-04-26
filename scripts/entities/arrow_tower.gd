extends EnemyBase
class_name ArrowTowerMob

const TOWER_VISUAL_SCENE := preload("res://art/combat/towers/stylized_arrow_tower_texture.glb")
const ArrowProjectilePoolScript = preload("res://scripts/entities/arrow_projectile_pool.gd")
const FlowTelegraphArrowMeshScript = preload("res://scripts/entities/flow_telegraph_arrow_mesh.gd")
const MassGroundZoneScene = preload("res://dungeon/modules/gameplay/mass_ground_zone_2d.tscn")
const TurretInfusionConstantsRef = preload("res://scripts/infusion/infusion_constants.gd")
const _TELEGRAPH_PROGRESS_STEPS := 12

const ARCHETYPE_SPITTER := &"spitter"
const ARCHETYPE_VOLLEY := &"volley"
const ARCHETYPE_BARRAGE := &"barrage"

const FAMILY_FLOW := &"flow"
const FAMILY_EDGE := &"edge"
const FAMILY_ECHO := &"echo"
const FAMILY_SURGE := &"surge"
const FAMILY_PHASE := &"phase"
const FAMILY_MASS := &"mass"
const FAMILY_ANCHOR := &"anchor"

@export_enum("spitter", "volley", "barrage") var ranged_archetype := "volley"
@export_enum("flow", "edge", "echo", "surge", "phase", "mass", "anchor") var family_id := "flow"
@export var range_tiles := 5.6
@export var world_units_per_tile := 3.0
@export var fire_cooldown := 2.0
@export var charge_duration := 1.0
@export var arrow_damage := 13
@export var arrow_max_tiles := 6.0
@export var arrow_speed := 20.0
@export var projectile_spawn_distance := 0.55
@export var mesh_ground_y := 0.95
@export var mesh_scale := Vector3(2.3, 2.3, 2.3)
@export var facing_yaw_offset_deg := 90.0
@export var tower_turn_deg_per_sec := 220.0
@export var telegraph_ground_y := 0.06
@export var telegraph_arrow_length := 8.4
@export var telegraph_arrow_head_length := 0.8
@export var telegraph_arrow_half_width := 0.34

var _target_player: Node2D
var _cooldown_remaining := 0.0
var _charge_remaining := 0.0
var _charge_dir := Vector2(0.0, -1.0)
var _visual: Node3D
var _vw: Node3D
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _telegraph_meshes: Array[Mesh] = []
var _aggro_enabled := true
var _in_range_presence_by_instance_id: Dictionary = {}
var _net_telegraph_in_range := false
var _net_telegraph_dir := Vector2(0.0, -1.0)
var _net_telegraph_progress := 0.0
var _server_projectile_event_sequence := 0
var _last_applied_projectile_event_sequence := -1
var _remote_projectiles_by_event_id: Dictionary = {}
var _telegraph_progress_step := -1
var _tower_visual_facing := Vector2(0.0, -1.0)


func configure_ranged_family(config: Dictionary) -> void:
	if config.is_empty():
		return
	var arch := StringName(String(config.get("archetype", ranged_archetype)).strip_edges().to_lower())
	var fam := StringName(String(config.get("family", family_id)).strip_edges().to_lower())
	if arch in [ARCHETYPE_SPITTER, ARCHETYPE_VOLLEY, ARCHETYPE_BARRAGE]:
		ranged_archetype = String(arch)
	if fam in TurretInfusionConstantsRef.PILLAR_ORDER:
		family_id = String(fam)
	_apply_family_baseline_exports()


func get_enemy_spawn_config() -> Dictionary:
	var config := super.get_enemy_spawn_config()
	config.merge({
		"archetype": ranged_archetype,
		"family": family_id,
	}, true)
	return config


func _ready() -> void:
	super._ready()
	_apply_family_baseline_exports()
	_cooldown_remaining = maxf(0.01, fire_cooldown)
	_charge_remaining = charge_duration
	var vw := get_node_or_null("../../VisualWorld3D") as Node3D
	_vw = vw
	if vw != null and TOWER_VISUAL_SCENE != null:
		var vis := TOWER_VISUAL_SCENE.instantiate() as Node3D
		if vis != null:
			_disable_cast_shadows_recursive(vis)
			vis.scale = mesh_scale
			vw.add_child(vis)
			_visual = vis
	if vw != null:
		_telegraph_mesh = MeshInstance3D.new()
		_telegraph_mesh.name = &"VolleyFamilyTurretTelegraph"
		_outline_mat = FlowTelegraphArrowMeshScript.create_outline_material()
		_fill_mat = FlowTelegraphArrowMeshScript.create_fill_material(_telegraph_color_for_family())
		_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_mesh.visible = false
		_telegraph_meshes.clear()
		for step in range(_TELEGRAPH_PROGRESS_STEPS + 1):
			_telegraph_meshes.append(_build_telegraph_mesh_for_step(step))
		vw.add_child(_telegraph_mesh)
	_sync_visual()
	_target_player = null


func _physics_process(delta: float) -> void:
	if _multiplayer_active() and not _is_server_peer():
		_enemy_network_client_interpolate(delta)
		if _aggro_enabled and _net_telegraph_in_range:
			_update_tower_visual_facing(_net_telegraph_dir, delta)
		_update_telegraph_visual(
			_aggro_enabled and _net_telegraph_in_range,
			_net_telegraph_dir,
			_net_telegraph_progress
		)
		_sync_visual()
		return
	if apply_universal_stagger_stop(delta, false):
		_reset_charge_state(false, Vector2.ZERO)
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	if not _aggro_enabled:
		_target_player = null
		_in_range_presence_by_instance_id.clear()
		_cooldown_remaining = maxf(0.01, fire_cooldown)
		_charge_remaining = charge_duration
		_net_telegraph_in_range = false
		_net_telegraph_progress = 0.0
		_update_telegraph_visual(false, Vector2.ZERO, 0.0)
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	var range_world := range_tiles * world_units_per_tile
	_refresh_target_lock(range_world)
	if _target_player == null or not is_instance_valid(_target_player):
		_reset_charge_state(false, Vector2.ZERO)
		_enemy_network_server_broadcast(delta)
		_sync_visual()
		return
	var to_player := _target_player.global_position - global_position
	var in_range := to_player.length_squared() <= range_world * range_world
	var aim_dir := to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	if in_range:
		_update_tower_visual_facing(aim_dir, delta)
		_charge_dir = aim_dir
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
		if _cooldown_remaining <= 0.0:
			_charge_remaining = maxf(0.0, _charge_remaining - delta)
			if _charge_remaining <= 0.0:
				_fire_attack_pattern(_charge_dir)
				_cooldown_remaining = fire_cooldown
				_charge_remaining = charge_duration
	else:
		_reset_charge_state(false, aim_dir)
	var charge_progress := 0.0
	if in_range and _cooldown_remaining <= 0.0:
		charge_progress = 1.0 - clampf(_charge_remaining / maxf(0.01, charge_duration), 0.0, 1.0)
	_net_telegraph_in_range = in_range and _cooldown_remaining <= 0.0
	_net_telegraph_dir = _charge_dir if _charge_dir.length_squared() > 0.0001 else aim_dir
	_net_telegraph_progress = charge_progress
	_update_telegraph_visual(_net_telegraph_in_range, _net_telegraph_dir, _net_telegraph_progress)
	_enemy_network_server_broadcast(delta)
	_sync_visual()


func _apply_family_baseline_exports() -> void:
	var arch := StringName(ranged_archetype)
	var fam := StringName(family_id)
	match arch:
		ARCHETYPE_SPITTER:
			arrow_damage = 14
			arrow_speed = 18.0
			arrow_max_tiles = 5.4
			fire_cooldown = 1.75
			charge_duration = 0.75
		ARCHETYPE_BARRAGE:
			arrow_damage = 9
			arrow_speed = 17.0
			arrow_max_tiles = 6.6
			fire_cooldown = 2.75
			charge_duration = 1.2
		_:
			arrow_damage = 12
			arrow_speed = 20.0
			arrow_max_tiles = 6.0
			fire_cooldown = 2.0
			charge_duration = 0.95
	match fam:
		FAMILY_FLOW:
			arrow_speed *= 1.18
			arrow_max_tiles *= 1.2
		FAMILY_EDGE:
			arrow_speed *= 1.22
			arrow_damage += 2
			charge_duration *= 0.82
		FAMILY_SURGE:
			arrow_speed *= 0.86
			charge_duration *= 1.12
		FAMILY_PHASE:
			arrow_speed *= 1.05
		FAMILY_MASS:
			arrow_speed *= 0.86
			fire_cooldown *= 1.08
		FAMILY_ANCHOR:
			arrow_speed *= 0.95
			charge_duration *= 1.08


func _reset_charge_state(in_range: bool, dir: Vector2) -> void:
	_cooldown_remaining = maxf(_cooldown_remaining, 0.01)
	_charge_remaining = charge_duration
	_net_telegraph_in_range = in_range
	_net_telegraph_dir = dir
	_net_telegraph_progress = 0.0
	_update_telegraph_visual(false, Vector2.ZERO, 0.0)


func _fire_attack_pattern(dir: Vector2) -> void:
	if not is_damage_authority():
		return
	var arch := StringName(ranged_archetype)
	match arch:
		ARCHETYPE_SPITTER:
			_fire_projectile_group(_build_projectile_shots(dir, 1, 0.0, &"primary"))
		ARCHETYPE_BARRAGE:
			var first_count := 5
			var first_spread := _family_barrage_spread()
			_fire_projectile_group(_build_projectile_shots(dir, first_count, first_spread, &"barrage_spread"))
			_schedule_barrage_followup(dir)
		_:
			var total_spread := _family_volley_spread()
			_fire_projectile_group(_build_projectile_shots(dir, 3, total_spread, &"primary"))
			if StringName(family_id) == FAMILY_ECHO:
				_schedule_echo_repeat(dir, 3, total_spread)


func _schedule_barrage_followup(dir: Vector2) -> void:
	var timer := get_tree().create_timer(0.55)
	timer.timeout.connect(
		func() -> void:
			if not is_inside_tree() or not is_damage_authority() or _dead:
				return
			var follow_dir := dir
			if StringName(family_id) == FAMILY_EDGE and _target_player != null and is_instance_valid(_target_player):
				var to_player := _target_player.global_position - global_position
				if to_player.length_squared() > 0.0001:
					follow_dir = to_player.normalized()
			_fire_projectile_group(_build_projectile_shots(follow_dir, 3, _family_barrage_followup_spread(), &"barrage_followup"))
	)


func _schedule_echo_repeat(dir: Vector2, count: int, spread: float) -> void:
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(
		func() -> void:
			if not is_inside_tree() or not is_damage_authority() or _dead:
				return
			_fire_projectile_group(_build_projectile_shots(dir, count, spread, &"echo_repeat"))
	)


func _build_projectile_shots(
	base_direction: Vector2, count: int, total_spread_degrees: float, phase_id: StringName
) -> Array:
	var shots: Array = []
	var fam := StringName(family_id)
	var forward_bias := 0.0
	if fam == FAMILY_FLOW and phase_id == &"primary" and count > 1:
		forward_bias = -total_spread_degrees * 0.18
	for projectile_index in range(count):
		var dir := _volley_direction_for(base_direction, projectile_index, count, total_spread_degrees, forward_bias)
		var shot := {
			"dir": dir,
			"speed": _shot_speed_for_phase(phase_id),
			"distance": arrow_max_tiles * world_units_per_tile,
			"damage": _shot_damage_for_phase(phase_id),
			"scale": _shot_scale_for_phase(phase_id),
			"style": _projectile_style_for_family(),
			"effect": _effect_config_for_shot(phase_id, projectile_index, count, dir),
		}
		shots.append(shot)
	return shots


func _fire_projectile_group(
	shots: Array, spawn_position_override: Vector2 = Vector2.ZERO, use_spawn_override: bool = false
) -> void:
	if shots.is_empty():
		return
	_server_projectile_event_sequence += 1
	var event_sequence := _server_projectile_event_sequence
	var spawn_position := (
		spawn_position_override
		if use_spawn_override
		else global_position + _charge_dir.normalized() * projectile_spawn_distance
	)
	for i in range(shots.size()):
		_spawn_tower_projectile(
			spawn_position,
			shots[i] as Dictionary,
			true,
			_projectile_event_id_for(event_sequence, i)
		)
	if _can_broadcast_world_replication():
		_rpc_receive_tower_projectile_group.rpc(event_sequence, spawn_position, shots)


func _spawn_tower_projectile(
	spawn_position: Vector2,
	shot: Dictionary,
	authoritative_damage: bool,
	projectile_event_id: int = -1
) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	if not authoritative_damage and projectile_event_id > 0:
		var existing_v: Variant = _remote_projectiles_by_event_id.get(projectile_event_id, null)
		if existing_v is ArrowProjectile and is_instance_valid(existing_v):
			return true
	var arrow := ArrowProjectilePoolScript.acquire_projectile(parent)
	if arrow == null:
		return false
	var dir_v: Variant = shot.get("dir", Vector2(0.0, -1.0))
	var dir: Vector2 = dir_v if dir_v is Vector2 else Vector2(0.0, -1.0)
	arrow.speed = float(shot.get("speed", arrow_speed))
	arrow.max_distance = float(shot.get("distance", arrow_max_tiles * world_units_per_tile))
	arrow.damage = int(shot.get("damage", arrow_damage))
	arrow.knockback_strength = 4.0 if StringName(family_id) == FAMILY_MASS else 8.0
	var scale := float(shot.get("scale", 1.0))
	arrow.mesh_scale = Vector3(1.6, 1.6, 1.6) * scale
	if arrow.has_method(&"set_authoritative_damage"):
		arrow.call(&"set_authoritative_damage", authoritative_damage)
	var effect_config := (shot.get("effect", {}) as Dictionary).duplicate(true)
	arrow.configure(
		spawn_position,
		dir,
		_vw,
		false,
		StringName(String(shot.get("style", "red"))),
		projectile_event_id,
		scale,
		0,
		null,
		false,
		self,
		effect_config
	)
	if authoritative_damage and _is_server_peer() and projectile_event_id > 0 and arrow.has_signal(&"projectile_finished"):
		arrow.projectile_finished.connect(
			_on_server_authoritative_tower_projectile_finished.bind(projectile_event_id),
			CONNECT_ONE_SHOT
		)
	elif not authoritative_damage and projectile_event_id > 0:
		_remote_projectiles_by_event_id[projectile_event_id] = arrow
	return true


func _effect_config_for_shot(
	phase_id: StringName, projectile_index: int, count: int, direction: Vector2
) -> Dictionary:
	var fam := StringName(family_id)
	var arch := StringName(ranged_archetype)
	var cfg := {
		"family": family_id,
		"archetype": ranged_archetype,
		"phase": String(phase_id),
		"direction": direction,
	}
	match fam:
		FAMILY_FLOW:
			if arch == ARCHETYPE_SPITTER:
				cfg["flow_slide"] = true
			elif arch == ARCHETYPE_BARRAGE and phase_id == &"barrage_followup":
				cfg["acceleration"] = 16.0
		FAMILY_EDGE:
			if arch == ARCHETYPE_BARRAGE and phase_id == &"barrage_followup":
				cfg["reaim_after"] = 0.12
				cfg["reaim_target_position"] = (
					_target_player.global_position if _target_player != null and is_instance_valid(_target_player) else global_position + direction * 6.0
				)
		FAMILY_ECHO:
			if arch == ARCHETYPE_SPITTER:
				cfg["echo_split"] = true
			elif arch == ARCHETYPE_BARRAGE and phase_id == &"barrage_spread":
				cfg["echo_impact_repeat"] = true
		FAMILY_SURGE:
			cfg["delayed_detonation"] = true
			cfg["detonation_radius"] = 2.2 if arch != ARCHETYPE_BARRAGE else 3.0
			cfg["detonation_delay"] = 0.45 if arch != ARCHETYPE_BARRAGE else 0.7
		FAMILY_PHASE:
			cfg["blink_after"] = 0.18 + float(projectile_index) * 0.025
			cfg["blink_distance"] = 2.2 if arch == ARCHETYPE_BARRAGE else 1.6
			if arch != ARCHETYPE_SPITTER:
				cfg["phase_phantom"] = true
		FAMILY_MASS:
			cfg["mass_zone"] = true
			cfg["mass_zone_radius"] = 2.4 if arch != ARCHETYPE_BARRAGE else 3.4
			cfg["mass_zone_lifetime"] = 2.6 if arch != ARCHETYPE_BARRAGE else 3.8
			cfg["mass_pull"] = arch == ARCHETYPE_BARRAGE and phase_id == &"barrage_followup"
		FAMILY_ANCHOR:
			cfg["anchor_hit_slow"] = true
			cfg["anchor_zone"] = arch != ARCHETYPE_SPITTER
			cfg["anchor_duration"] = 0.65 if arch == ARCHETYPE_SPITTER else 1.1
			cfg["anchor_zone_radius"] = 2.1 if arch != ARCHETYPE_BARRAGE else 2.8
	if phase_id == &"echo_repeat":
		cfg["damage_ratio"] = 0.75
	return cfg


func on_ranged_projectile_effect_finished(
	final_position: Vector2,
	direction: Vector2,
	target_uid: int,
	accepted_hit: bool,
	effect_config: Dictionary
) -> void:
	if effect_config.is_empty() or not is_damage_authority():
		return
	var damage_ratio := float(effect_config.get("damage_ratio", 1.0))
	var effect_damage := maxi(1, int(roundf(float(arrow_damage) * damage_ratio)))
	if bool(effect_config.get("flow_slide", false)):
		_spawn_secondary_projectile(final_position, direction, effect_damage, 8.0, 3.0, FAMILY_FLOW)
	if bool(effect_config.get("echo_split", false)):
		_spawn_secondary_projectile(final_position, direction.rotated(deg_to_rad(-18.0)), effect_damage, 15.0, 5.0, FAMILY_ECHO)
		_spawn_secondary_projectile(final_position, direction.rotated(deg_to_rad(18.0)), effect_damage, 15.0, 5.0, FAMILY_ECHO)
	if bool(effect_config.get("echo_impact_repeat", false)):
		var timer := get_tree().create_timer(0.5)
		timer.timeout.connect(func() -> void:
			if is_inside_tree() and is_damage_authority() and not _dead:
				_spawn_secondary_projectile(final_position, direction, effect_damage, arrow_speed, 7.0, FAMILY_ECHO)
		)
	if bool(effect_config.get("delayed_detonation", false)):
		_schedule_area_damage(
			final_position,
			float(effect_config.get("detonation_radius", 2.2)),
			float(effect_config.get("detonation_delay", 0.45)),
			effect_damage
		)
	if bool(effect_config.get("mass_zone", false)):
		_spawn_mass_zone(
			final_position,
			float(effect_config.get("mass_zone_radius", 2.5)),
			float(effect_config.get("mass_zone_lifetime", 2.6)),
			0.58 if bool(effect_config.get("mass_pull", false)) else 0.72
		)
	if bool(effect_config.get("mass_pull", false)):
		_apply_mass_pull(final_position, float(effect_config.get("mass_zone_radius", 2.5)) + 1.2, 1.2)
	if bool(effect_config.get("anchor_zone", false)):
		_spawn_anchor_zone(
			final_position,
			float(effect_config.get("anchor_zone_radius", 2.2)),
			float(effect_config.get("anchor_duration", 1.0))
		)
	if accepted_hit and bool(effect_config.get("anchor_hit_slow", false)):
		_apply_anchor_hit_control(target_uid, final_position, float(effect_config.get("anchor_duration", 0.75)))
	if accepted_hit and bool(effect_config.get("phase_phantom", false)):
		_schedule_area_damage(final_position, 1.4, 0.28, maxi(1, int(roundf(float(effect_damage) * 0.45))))


func _spawn_secondary_projectile(
	spawn_position: Vector2,
	direction: Vector2,
	damage_amount: int,
	speed_value: float,
	max_distance_value: float,
	family: StringName
) -> void:
	var shot := {
		"dir": direction,
		"speed": speed_value,
		"distance": max_distance_value,
		"damage": damage_amount,
		"scale": 0.72,
		"style": TurretInfusionConstantsRef.handgun_projectile_style_id(family),
		"effect": {},
	}
	_fire_projectile_group([shot], spawn_position, true)


func _spawn_mass_zone(position: Vector2, radius: float, lifetime_sec: float, move_speed_multiplier: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var zone := MassGroundZoneScene.instantiate()
	if zone == null:
		return
	zone.name = &"TurretMassZone"
	zone.radius = radius
	zone.move_speed_multiplier = move_speed_multiplier
	zone.lifetime_sec = lifetime_sec
	zone.global_position = position
	parent.add_child(zone)


func _spawn_anchor_zone(position: Vector2, radius: float, lifetime_sec: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var zone := MassGroundZoneScene.instantiate()
	if zone == null:
		return
	zone.name = &"TurretAnchorZone"
	zone.radius = radius
	zone.move_speed_multiplier = 0.45
	zone.lifetime_sec = lifetime_sec
	zone.zone_color = Color(0.1, 0.1, 0.12, 0.26)
	zone.ring_color = Color(0.74, 0.9, 1.0, 0.36)
	zone.global_position = position
	parent.add_child(zone)


func _schedule_area_damage(position: Vector2, radius: float, delay: float, damage_amount: int) -> void:
	var timer := get_tree().create_timer(maxf(0.01, delay))
	timer.timeout.connect(func() -> void:
		if not is_inside_tree() or not is_damage_authority() or _dead:
			return
		var radius_sq := radius * radius
		for player in _targetable_player_candidates():
			if player == null or not is_instance_valid(player):
				continue
			if player.global_position.distance_squared_to(position) > radius_sq:
				continue
			if player.has_method(&"take_attack_damage"):
				var dir := (player.global_position - position).normalized()
				player.call(&"take_attack_damage", damage_amount, position, dir)
	)


func _apply_mass_pull(position: Vector2, radius: float, pull_distance: float) -> void:
	var radius_sq := radius * radius
	for player in _targetable_player_candidates():
		if player == null or not is_instance_valid(player):
			continue
		var to_center := position - player.global_position
		var dist_sq := to_center.length_squared()
		if dist_sq <= 0.0001 or dist_sq > radius_sq:
			continue
		var dist := sqrt(dist_sq)
		var step := minf(pull_distance, dist * 0.45)
		player.global_position += to_center.normalized() * step


func _apply_anchor_hit_control(target_uid: int, origin: Vector2, duration: float) -> void:
	var player := _find_player_by_instance_id(target_uid)
	if player == null:
		return
	if StringName(ranged_archetype) == ARCHETYPE_SPITTER and player.has_method(&"enemy_control_apply_root"):
		player.call(&"enemy_control_apply_root", get_instance_id(), player.global_position)
		var timer := get_tree().create_timer(maxf(0.1, duration))
		timer.timeout.connect(func() -> void:
			if player != null and is_instance_valid(player) and player.has_method(&"enemy_control_clear_root"):
				player.call(&"enemy_control_clear_root", get_instance_id())
		)
	elif player.has_method(&"set_external_move_speed_multiplier"):
		var key := StringName("turret_anchor_hit_%s" % [str(get_instance_id())])
		player.call(&"set_external_move_speed_multiplier", key, 0.42)
		var timer2 := get_tree().create_timer(maxf(0.1, duration))
		timer2.timeout.connect(func() -> void:
			if player != null and is_instance_valid(player) and player.has_method(&"clear_external_move_speed_multiplier"):
				player.call(&"clear_external_move_speed_multiplier", key)
		)


func _find_player_by_instance_id(instance_id: int) -> Node2D:
	if instance_id <= 0:
		return null
	for candidate in _targetable_player_candidates():
		if candidate != null and is_instance_valid(candidate) and candidate.get_instance_id() == instance_id:
			return candidate
	return null


func _family_volley_spread() -> float:
	match StringName(family_id):
		FAMILY_EDGE:
			return 16.0
		FAMILY_FLOW:
			return 28.0
		FAMILY_SURGE:
			return 30.0
		FAMILY_PHASE:
			return 24.0
		_:
			return 22.0


func _family_barrage_spread() -> float:
	match StringName(family_id):
		FAMILY_EDGE:
			return 24.0
		FAMILY_MASS:
			return 44.0
		FAMILY_FLOW:
			return 48.0
		_:
			return 38.0


func _family_barrage_followup_spread() -> float:
	match StringName(family_id):
		FAMILY_EDGE:
			return 8.0
		FAMILY_FLOW:
			return 20.0
		_:
			return 14.0


func _shot_speed_for_phase(phase_id: StringName) -> float:
	var speed_value := arrow_speed
	if phase_id == &"barrage_followup":
		speed_value *= 1.08
	if phase_id == &"echo_repeat":
		speed_value *= 0.96
	return speed_value


func _shot_damage_for_phase(phase_id: StringName) -> int:
	if phase_id == &"barrage_followup":
		return maxi(1, int(roundf(float(arrow_damage) * 0.9)))
	if phase_id == &"echo_repeat":
		return maxi(1, int(roundf(float(arrow_damage) * 0.75)))
	return arrow_damage


func _shot_scale_for_phase(phase_id: StringName) -> float:
	if phase_id == &"barrage_followup" and StringName(family_id) == FAMILY_EDGE:
		return 0.58
	if StringName(family_id) == FAMILY_MASS:
		return 0.9
	return 0.78


func _volley_direction_for(
	base_direction: Vector2,
	projectile_index: int,
	count: int,
	total_spread_degrees: float,
	forward_bias_degrees: float = 0.0
) -> Vector2:
	var dir := base_direction.normalized() if base_direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	if count <= 1:
		return dir
	var start_deg := -total_spread_degrees * 0.5
	var step_deg := total_spread_degrees / float(maxi(1, count - 1))
	return dir.rotated(deg_to_rad(start_deg + step_deg * float(projectile_index) + forward_bias_degrees)).normalized()


func _projectile_event_id_for(group_event_id: int, projectile_index: int) -> int:
	return group_event_id * 100 + projectile_index + 1


func _projectile_style_for_family() -> StringName:
	return TurretInfusionConstantsRef.handgun_projectile_style_id(StringName(family_id))


func _telegraph_color_for_family() -> Color:
	var color := TurretInfusionConstantsRef.ui_pillar_dot_color(StringName(family_id))
	color.a = 0.72
	return color


func _refresh_target_lock(range_world: float) -> void:
	var current_presence: Dictionary = {}
	var best_entrant: Node2D = null
	var best_entrant_d2 := INF
	var best_entrant_peer_id := 0
	var best_entrant_name := ""
	var range_world_sq := range_world * range_world
	for candidate in _targetable_player_candidates():
		if not _is_targetable_player(candidate):
			continue
		var candidate_d2 := global_position.distance_squared_to(candidate.global_position)
		if candidate_d2 > range_world_sq:
			continue
		var instance_id := candidate.get_instance_id()
		current_presence[instance_id] = true
		if bool(_in_range_presence_by_instance_id.get(instance_id, false)):
			continue
		var candidate_peer_id := _peer_id_for_player_candidate(candidate)
		var candidate_name := String(candidate.name)
		if (
			best_entrant == null
			or _is_better_player_target_choice(
				candidate_d2,
				candidate_peer_id,
				candidate_name,
				best_entrant_d2,
				best_entrant_peer_id,
				best_entrant_name
			)
		):
			best_entrant = candidate
			best_entrant_d2 = candidate_d2
			best_entrant_peer_id = candidate_peer_id
			best_entrant_name = candidate_name
	var keep_target := false
	if _target_player != null and is_instance_valid(_target_player):
		keep_target = (
			current_presence.has(_target_player.get_instance_id())
			and not _is_player_downed_node(_target_player)
		)
	if not keep_target:
		_target_player = best_entrant
		if _target_player != null:
			_cooldown_remaining = maxf(0.01, fire_cooldown)
			_charge_remaining = charge_duration
	_in_range_presence_by_instance_id = current_presence


func _enemy_network_compact_state() -> Dictionary:
	return {
		"ag": _aggro_enabled,
		"ir": _net_telegraph_in_range,
		"dir": _net_telegraph_dir,
		"cp": _net_telegraph_progress,
		"arch": ranged_archetype,
		"fam": family_id,
	}


func _enemy_network_apply_remote_state(state: Dictionary) -> void:
	_aggro_enabled = bool(state.get("ag", _aggro_enabled))
	_net_telegraph_in_range = bool(state.get("ir", _net_telegraph_in_range))
	var dir_v: Variant = state.get("dir", _net_telegraph_dir)
	if dir_v is Vector2:
		var dir := dir_v as Vector2
		if dir.length_squared() > 0.0001:
			_net_telegraph_dir = dir.normalized()
	_net_telegraph_progress = clampf(float(state.get("cp", _net_telegraph_progress)), 0.0, 1.0)
	ranged_archetype = String(state.get("arch", ranged_archetype))
	family_id = String(state.get("fam", family_id))


func _update_tower_visual_facing(aim_dir: Vector2, delta: float) -> void:
	if _visual == null or aim_dir.length_squared() <= 0.0001:
		return
	var max_step := deg_to_rad(tower_turn_deg_per_sec) * delta
	_tower_visual_facing = EnemyBase.step_planar_facing_toward(
		_tower_visual_facing, aim_dir.normalized(), max_step
	)
	_visual.rotation.y = (
		atan2(_tower_visual_facing.x, _tower_visual_facing.y) + deg_to_rad(facing_yaw_offset_deg)
	)


func get_combat_planar_facing() -> Vector2:
	if _tower_visual_facing.length_squared() > 1e-6:
		return _tower_visual_facing.normalized()
	return super.get_combat_planar_facing()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_tower_projectile_group(
	event_sequence: int, spawn_position: Vector2, shots: Array
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if event_sequence <= _last_applied_projectile_event_sequence:
		return
	_last_applied_projectile_event_sequence = event_sequence
	for i in range(shots.size()):
		var shot := shots[i] as Dictionary
		_spawn_tower_projectile(spawn_position, shot, false, _projectile_event_id_for(event_sequence, i))


func _on_server_authoritative_tower_projectile_finished(
	final_position: Vector2, projectile_event_id: int
) -> void:
	if not _is_server_peer() or not _multiplayer_active() or not _can_broadcast_world_replication():
		return
	_rpc_receive_tower_projectile_finished.rpc(projectile_event_id, final_position)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_tower_projectile_finished(
	projectile_event_id: int, final_position: Vector2
) -> void:
	if _is_server_peer():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var projectile_v: Variant = _remote_projectiles_by_event_id.get(projectile_event_id, null)
	if projectile_v == null or not is_instance_valid(projectile_v):
		_remote_projectiles_by_event_id.erase(projectile_event_id)
		return
	var projectile := projectile_v as ArrowProjectile
	if projectile == null:
		_remote_projectiles_by_event_id.erase(projectile_event_id)
		return
	projectile.global_position = final_position
	if projectile.has_method(&"_finish_projectile"):
		projectile.call(&"_finish_projectile")
	else:
		projectile.queue_free()
	_remote_projectiles_by_event_id.erase(projectile_event_id)


func _update_telegraph_visual(in_range: bool, dir: Vector2, progress: float) -> void:
	if _telegraph_mesh == null:
		return
	if not in_range:
		_telegraph_mesh.visible = false
		_telegraph_progress_step = -1
		return
	_telegraph_mesh.visible = true
	var facing := dir.normalized() if dir.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	_telegraph_mesh.global_position = Vector3(global_position.x, telegraph_ground_y, global_position.y)
	_telegraph_mesh.rotation = Vector3(0.0, atan2(facing.x, facing.y), 0.0)
	var progress_step := int(round(clampf(progress, 0.0, 1.0) * float(_TELEGRAPH_PROGRESS_STEPS)))
	if progress_step == _telegraph_progress_step:
		return
	_telegraph_progress_step = progress_step
	if progress_step >= 0 and progress_step < _telegraph_meshes.size():
		_telegraph_mesh.mesh = _telegraph_meshes[progress_step]


func _build_telegraph_mesh_for_step(progress_step: int) -> Mesh:
	var width_mult := 1.0
	match StringName(ranged_archetype):
		ARCHETYPE_SPITTER:
			width_mult = 0.55
		ARCHETYPE_BARRAGE:
			width_mult = 1.55
		_:
			width_mult = 1.0
	if StringName(family_id) == FAMILY_EDGE:
		width_mult *= 0.65
	elif StringName(family_id) == FAMILY_MASS:
		width_mult *= 1.25
	return FlowTelegraphArrowMeshScript.build_mesh_for_step(
		progress_step,
		_TELEGRAPH_PROGRESS_STEPS,
		telegraph_arrow_length,
		telegraph_arrow_head_length,
		telegraph_arrow_half_width * width_mult,
		_outline_mat,
		_fill_mat
	)


func _sync_visual() -> void:
	if _visual != null:
		_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)


func mass_infusion_receives_knockback() -> bool:
	return false


func _on_nonlethal_hit(knockback_dir: Vector2, knockback_strength: float) -> void:
	super._on_nonlethal_hit(knockback_dir, knockback_strength)


func cancel_active_attack_for_stagger() -> void:
	_reset_charge_state(false, Vector2.ZERO)


func can_contact_damage() -> bool:
	return false


func apply_speed_multiplier(_multiplier: float) -> void:
	pass


func set_aggro_enabled(enabled: bool) -> void:
	_aggro_enabled = enabled
	if not _aggro_enabled:
		_target_player = null
		_in_range_presence_by_instance_id.clear()
		_cooldown_remaining = maxf(0.01, fire_cooldown)
		_charge_remaining = charge_duration
		_update_telegraph_visual(false, Vector2.ZERO, 0.0)


func _disable_cast_shadows_recursive(node: Node) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_cast_shadows_recursive(child)


func _exit_tree() -> void:
	super._exit_tree()
	_remote_projectiles_by_event_id.clear()
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()


func get_shadow_visual_root() -> Node3D:
	return _visual


func _pick_target_player() -> Node2D:
	return _pick_nearest_player_target()
