extends RefCounted
class_name EchoSpawnGrowth

var duration_sec := 0.6
var start_scale := 0.12
var end_scale := 0.5
var elapsed_sec := 0.0
var active := false


func begin(next_duration_sec: float, next_end_scale: float = 0.5, next_start_scale: float = 0.12) -> void:
	duration_sec = maxf(0.05, next_duration_sec)
	start_scale = clampf(next_start_scale, 0.01, 1.0)
	end_scale = clampf(next_end_scale, start_scale, 4.0)
	elapsed_sec = 0.0
	active = true


func tick(delta: float) -> float:
	if not active:
		return end_scale
	elapsed_sec += maxf(0.0, delta)
	var t := clampf(elapsed_sec / duration_sec, 0.0, 1.0)
	if t >= 1.0:
		active = false
	return lerpf(start_scale, end_scale, t)


func is_complete() -> bool:
	return not active
