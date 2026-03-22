extends Node

@export var mob_scene: PackedScene


func _ready() -> void:
	$CanvasLayer/UserInterface/Retry.hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and $CanvasLayer/UserInterface/Retry.visible:
		get_tree().reload_current_scene()


func _on_mob_timer_timeout() -> void:
	var mob := mob_scene.instantiate()
	var spawn_pt: PathFollow3D = $SpawnPath/SpawnLocation
	spawn_pt.progress_ratio = randf()
	var player: Node3D = $Player
	mob.initialize(spawn_pt.position, player.position)
	add_child(mob)
	mob.squashed.connect($CanvasLayer/UserInterface/ScoreLabel._on_mob_squashed)


func _on_player_hit() -> void:
	$MobTimer.stop()
	$CanvasLayer/UserInterface/Retry.show()
