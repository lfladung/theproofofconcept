@tool
extends RefCounted
class_name DungeonRoomSelectionController

const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")


func item_at_grid(layout, catalog, room: RoomBase, grid_position: Vector2i, layer_filter: StringName = &"all"):
	if layout == null or catalog == null or room == null:
		return null
	var local_point := GridMath.grid_to_local(grid_position, layout, room)
	var best_item = null
	var best_priority := -1
	var best_index := -1
	for index in range(layout.items.size() - 1, -1, -1):
		var item = layout.items[index]
		if item == null:
			continue
		var piece = catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		if not _layer_visible(item, piece, layer_filter):
			continue
		if not GridMath.item_rect(item, piece, layout, room).has_point(local_point):
			continue
		var priority := _layer_priority(item, piece)
		if priority > best_priority or (priority == best_priority and index > best_index):
			best_item = item
			best_priority = priority
			best_index = index
	return best_item


func _layer_priority(item, piece) -> int:
	match String(item.resolved_placement_layer(piece)):
		"overlay":
			return 1
		_:
			return 0


func _layer_visible(item, piece, layer_filter: StringName) -> bool:
	return layer_filter == &"all" or item.resolved_placement_layer(piece) == layer_filter
