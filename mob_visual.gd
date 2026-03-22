extends Node3D

## 3D presentation for a 2D mob; VisibleOnScreenNotifier3D matches what the camera sees.

signal screen_exited_visual


func _ready() -> void:
	# Defer hookup so parent CreepMob can set global_position first (default was world origin).
	call_deferred(&"_hook_screen_notifier")


func _hook_screen_notifier() -> void:
	var n := $VisibleOnScreenNotifier3D
	if n:
		n.screen_exited.connect(_on_screen_exited)


func _on_screen_exited() -> void:
	screen_exited_visual.emit()
