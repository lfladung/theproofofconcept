extends Area2D
class_name BinderTetherProjectile

signal tether_connected(target_uid: int, final_position: Vector2)
signal tether_finished(final_position: Vector2)

const DamagePacketScript = preload("res://scripts/combat/damage_packet.gd")

@export var speed := 8.0
@export var max_distance := 20.0
@export var damage := 10
@export var mesh_ground_y := 1.0
@export var mesh_scale := Vector3(1.2, 1.2, 1.2)

@onready var _world_shape: CollisionShape2D = $CollisionShape2D
@onready var _hitbox: Hitbox2D = $DamageHitbox
@onready var _hitbox_shape: CollisionShape2D = $DamageHitbox/CollisionShape2D

var _direction := Vector2.RIGHT
var _start_pos := Vector2.ZERO
var _travelled := 0.0
var _authoritative_damage := true
var _attack_instance_id := -1
var _owner_enemy: Node
var _visual_world: Node3D
var _visual: MeshInstance3D
var _finished := false


func configure(
	spawn_position: Vector2,
	direction: Vector2,
	owner_enemy: Node,
	visual_world: Node3D,
	authoritative_damage: bool = true,
	attack_instance_id: int = -1
) -> void:
	global_position = spawn_position
	_start_pos = spawn_position
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_owner_enemy = owner_enemy
	_visual_world = visual_world
	_authoritative_damage = authoritative_damage
	_attack_instance_id = attack_instance_id
	_travelled = 0.0
	_finished = false
	if is_inside_tree():
		_activate_runtime()


func set_authoritative_damage(enabled: bool) -> void:
	_authoritative_damage = enabled
	if is_inside_tree():
		_apply_hitbox_runtime()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not _hitbox.target_resolved.is_connected(_on_hitbox_target_resolved):
		_hitbox.target_resolved.connect(_on_hitbox_target_resolved)
	_activate_runtime()


func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()


func _activate_runtime() -> void:
	monitoring = true
	_apply_hitbox_runtime()
	_ensure_visual()
	_sync_visual()
	set_physics_process(true)


func _apply_hitbox_runtime() -> void:
	_hitbox.deactivate()
	_hitbox.collision_layer = 64
	_hitbox.collision_mask = 8
	_hitbox.repeat_mode = Hitbox2D.RepeatMode.NONE
	_hitbox.stop_after_first_consume_hit = true
	if not _authoritative_damage:
		return
	var packet := DamagePacketScript.new() as DamagePacket
	packet.amount = damage
	packet.kind = &"binder_tether"
	packet.source_node = _owner_enemy if _owner_enemy != null else self
	packet.source_uid = (
		_owner_enemy.get_instance_id() if _owner_enemy != null and is_instance_valid(_owner_enemy) else get_instance_id()
	)
	packet.attack_instance_id = _attack_instance_id
	packet.origin = global_position
	packet.direction = _direction
	packet.knockback = 0.0
	packet.apply_iframes = true
	packet.blockable = true
	packet.debug_label = &"binder_tether"
	_hitbox.activate(packet)


func _ensure_visual() -> void:
	if _visual_world == null:
		return
	if _visual == null or not is_instance_valid(_visual):
		_visual = MeshInstance3D.new()
		_visual.name = &"BinderTetherProjectileVisual"
		var sphere := SphereMesh.new()
		sphere.radius = 0.28
		sphere.height = 0.56
		_visual.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(0.56, 0.88, 1.0, 0.92)
		mat.emission_enabled = true
		mat.emission = Color(0.62, 0.92, 1.0, 1.0)
		mat.emission_energy_multiplier = 1.8
		_visual.material_override = mat
		_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual_world.add_child(_visual)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	var step := _direction * speed * delta
	global_position += step
	_travelled += step.length()
	_sync_visual()
	if _travelled >= max_distance:
		_finish()


func _sync_visual() -> void:
	if _visual == null:
		return
	_visual.global_position = Vector3(global_position.x, mesh_ground_y, global_position.y)
	_visual.scale = mesh_scale


func _on_body_entered(body: Node) -> void:
	if _finished:
		return
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group(&"player"):
		return
	_finish()


func _on_hitbox_target_resolved(
	_packet: DamagePacket, target_uid: int, accepted: bool, consume_hit: bool, _reason: StringName
) -> void:
	if _finished or not consume_hit:
		return
	if accepted:
		tether_connected.emit(target_uid, global_position)
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	monitoring = false
	set_physics_process(false)
	if _hitbox != null:
		_hitbox.deactivate()
	tether_finished.emit(global_position)
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	queue_free()
