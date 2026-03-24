extends Node

## Matches VisualWorld3D ground: 60×60 → ±30 on the XZ plane (2D x / 2D y).
const PLAY_HALF_EXTENT := 30.0
## Mobs must spawn at least this far from the player (same units as the path).
const MIN_MOB_SPAWN_DISTANCE := 12.0

@export var mob_scene: PackedScene


func _ready() -> void:
	$CanvasLayer/UserInterface/Retry.hide()
	_configure_spawn_curve()


func _configure_spawn_curve() -> void:
	var path2d: Path2D = $GameWorld2D/SpawnPath2D
	var e := PLAY_HALF_EXTENT
	var curve := Curve2D.new()
	curve.add_point(Vector2(e, -e))
	curve.add_point(Vector2(-e, -e))
	curve.add_point(Vector2(-e, e))
	curve.add_point(Vector2(e, e))
	curve.add_point(Vector2(e, -e))
	path2d.curve = curve
	var follow: PathFollow2D = path2d.get_node_or_null(^"SpawnLocation") as PathFollow2D
	if follow:
		follow.progress = 0.0


func _place_follow_far_from_player(spawn_pt: PathFollow2D, player_pos: Vector2, path_len: float) -> void:
	var best_d := 0.0
	var best_t := 0.0
	const SAMPLES := 48
	for i in range(SAMPLES):
		var t := (float(i) + 0.5) / float(SAMPLES) * path_len
		spawn_pt.progress = t
		var d := spawn_pt.global_position.distance_to(player_pos)
		if d > best_d:
			best_d = d
			best_t = t
	spawn_pt.progress = best_t


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and $CanvasLayer/UserInterface/Retry.visible:
		get_tree().reload_current_scene()


func _on_mob_timer_timeout() -> void:
	var path2d: Path2D = $GameWorld2D/SpawnPath2D
	var curve: Curve2D = path2d.curve
	if curve == null or curve.point_count < 2:
		push_error("Spawn Path2D curve is missing; call _configure_spawn_curve from _ready.")
		return
	var path_len: float = curve.get_baked_length()
	if path_len < 0.01:
		push_error("Spawn Path2D has zero baked length.")
		return
	var spawn_pt: PathFollow2D = path2d.get_node(^"SpawnLocation") as PathFollow2D
	var player: Node2D = $GameWorld2D/Player
	var ppos := player.global_position
	for _i in range(40):
		spawn_pt.progress = randf() * path_len
		if spawn_pt.global_position.distance_to(ppos) >= MIN_MOB_SPAWN_DISTANCE:
			break
	if spawn_pt.global_position.distance_to(ppos) < MIN_MOB_SPAWN_DISTANCE:
		_place_follow_far_from_player(spawn_pt, ppos, path_len)
	var mob: Node = mob_scene.instantiate()
	mob.configure_spawn(spawn_pt.global_position, ppos)
	$GameWorld2D.add_child(mob)


func _on_player_hit() -> void:
	$MobTimer.stop()
	$CanvasLayer/UserInterface/Retry.show()
