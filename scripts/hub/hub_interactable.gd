extends Area2D
class_name HubInteractable

signal local_focus_changed(interactable: HubInteractable, focused: bool)
signal local_interacted(interactable: HubInteractable)

@export var prompt_text := "Press E"
@export var visual_scene: PackedScene
@export var visual_height := 0.0
@export var visual_rotation_y := 0.0

var _local_player: CharacterBody2D
var _visual_instance: Node3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_spawn_visual.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		return
	if not event.is_action_pressed(&"interact"):
		return
	local_interacted.emit(self)
	get_viewport().set_input_as_handled()


func clear_local_focus() -> void:
	if _local_player == null:
		return
	_local_player = null
	local_focus_changed.emit(self, false)


func _on_body_entered(body: Node2D) -> void:
	var player := body as CharacterBody2D
	if not _is_local_player(player):
		return
	_local_player = player
	local_focus_changed.emit(self, true)


func _on_body_exited(body: Node2D) -> void:
	if body != _local_player:
		return
	clear_local_focus()


func _is_local_player(player: CharacterBody2D) -> bool:
	if player == null or not player.is_in_group(&"player"):
		return false
	var peer := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	return player.get_multiplayer_authority() == peer


func _spawn_visual() -> void:
	if visual_scene == null or _visual_instance != null:
		return
	var world := get_tree().current_scene
	if world == null:
		return
	var visual_root := world.get_node_or_null("VisualWorld3D/HubProps") as Node3D
	if visual_root == null:
		return
	var instance := visual_scene.instantiate() as Node3D
	if instance == null:
		return
	instance.name = "%sVisual" % [name]
	instance.position = Vector3(global_position.x, visual_height, global_position.y)
	instance.rotation = Vector3(0.0, visual_rotation_y, 0.0)
	visual_root.add_child(instance)
	_visual_instance = instance
