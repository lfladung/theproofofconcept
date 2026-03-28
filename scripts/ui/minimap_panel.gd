extends Panel
class_name MinimapPanel

const MAP_PADDING := 14.0
const WORLD_BOUNDS_PADDING := 3.0
const ROOM_OUTLINE_WIDTH := 2.0
const PLAYER_MARKER_RADIUS := 4.5
const PLAYER_MARKER_OUTLINE := 2.0
const ROOM_OUTLINE_COLOR := Color(0.21, 0.16, 0.11, 0.95)
const CURRENT_ROOM_TINT := Color(1.0, 0.97, 0.88, 1.0)
const PLAYER_MARKER_FILL := Color(0.98, 0.95, 0.88, 1.0)
const PLAYER_MARKER_BORDER := Color(0.11, 0.09, 0.07, 1.0)
const DEFAULT_ROOM_COLOR := Color(0.48, 0.46, 0.43, 0.84)
const ROOM_COLORS := {
	"safe": Color(0.42, 0.62, 0.47, 0.86),
	"connector": Color(0.56, 0.53, 0.47, 0.84),
	"arena": Color(0.72, 0.43, 0.28, 0.88),
	"puzzle": Color(0.33, 0.54, 0.67, 0.88),
	"treasure": Color(0.83, 0.69, 0.27, 0.9),
	"boss": Color(0.77, 0.24, 0.2, 0.9),
	"trap": Color(0.8, 0.48, 0.18, 0.9),
}

var rooms_root: Node2D
var tracked_player: CharacterBody2D


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func bind_rooms_root(root: Node2D) -> void:
	rooms_root = root
	queue_redraw()


func bind_player(player: CharacterBody2D) -> void:
	tracked_player = player
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var content_rect := Rect2(
		Vector2(MAP_PADDING, MAP_PADDING),
		size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	)
	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		return
	var rooms := _collect_rooms()
	if rooms.is_empty():
		return
	var world_bounds := _combined_world_bounds(rooms)
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return
	var draw_scale := minf(
		content_rect.size.x / maxf(world_bounds.size.x, 1.0),
		content_rect.size.y / maxf(world_bounds.size.y, 1.0)
	)
	var used_size := world_bounds.size * draw_scale
	var draw_origin := content_rect.position + (content_rect.size - used_size) * 0.5

	var player_world_pos := Vector2.ZERO
	var has_player := tracked_player != null and is_instance_valid(tracked_player)
	if has_player:
		player_world_pos = tracked_player.global_position

	for room_entry in rooms:
		var world_rect := room_entry.get("rect", Rect2()) as Rect2
		var draw_rect_local := _map_world_rect_to_draw_rect(
			world_rect,
			world_bounds,
			draw_origin,
			draw_scale
		)
		var fill_color := room_entry.get("color", DEFAULT_ROOM_COLOR) as Color
		if has_player and world_rect.has_point(player_world_pos):
			fill_color = fill_color.lerp(CURRENT_ROOM_TINT, 0.35)
		draw_rect(draw_rect_local, fill_color, true)
		draw_rect(draw_rect_local, ROOM_OUTLINE_COLOR, false, ROOM_OUTLINE_WIDTH)

	if has_player:
		var marker_pos := _map_world_point_to_draw_point(
			player_world_pos,
			world_bounds,
			draw_origin,
			draw_scale
		)
		marker_pos.x = clampf(
			marker_pos.x,
			content_rect.position.x + PLAYER_MARKER_RADIUS,
			content_rect.end.x - PLAYER_MARKER_RADIUS
		)
		marker_pos.y = clampf(
			marker_pos.y,
			content_rect.position.y + PLAYER_MARKER_RADIUS,
			content_rect.end.y - PLAYER_MARKER_RADIUS
		)
		draw_circle(marker_pos, PLAYER_MARKER_RADIUS + PLAYER_MARKER_OUTLINE, PLAYER_MARKER_BORDER)
		draw_circle(marker_pos, PLAYER_MARKER_RADIUS, PLAYER_MARKER_FILL)


func _collect_rooms() -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	if rooms_root == null:
		return rooms
	for child in rooms_root.get_children():
		if child is not RoomBase:
			continue
		var room := child as RoomBase
		var local_rect := room.get_room_rect_world()
		var world_rect := Rect2(room.global_position - local_rect.size * 0.5, local_rect.size)
		rooms.append(
			{
				"name": String(room.name),
				"rect": world_rect,
				"color": _color_for_room_type(room.room_type),
			}
		)
	return rooms


func _combined_world_bounds(rooms: Array[Dictionary]) -> Rect2:
	if rooms.is_empty():
		return Rect2()
	var bounds := rooms[0].get("rect", Rect2()) as Rect2
	for i in range(1, rooms.size()):
		bounds = bounds.merge(rooms[i].get("rect", Rect2()) as Rect2)
	return bounds.grow(WORLD_BOUNDS_PADDING)


func _map_world_point_to_draw_point(
	world_point: Vector2,
	world_bounds: Rect2,
	draw_origin: Vector2,
	draw_scale: float
) -> Vector2:
	var mirrored := world_bounds.end - world_point
	return draw_origin + mirrored * draw_scale


func _map_world_rect_to_draw_rect(
	world_rect: Rect2,
	world_bounds: Rect2,
	draw_origin: Vector2,
	draw_scale: float
) -> Rect2:
	var p0 := _map_world_point_to_draw_point(world_rect.position, world_bounds, draw_origin, draw_scale)
	var p1 := _map_world_point_to_draw_point(world_rect.end, world_bounds, draw_origin, draw_scale)
	var top_left := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y))
	var size := Vector2(absf(p1.x - p0.x), absf(p1.y - p0.y))
	return Rect2(top_left, size)


func _color_for_room_type(room_type: String) -> Color:
	if ROOM_COLORS.has(room_type):
		return ROOM_COLORS[room_type] as Color
	return DEFAULT_ROOM_COLOR
