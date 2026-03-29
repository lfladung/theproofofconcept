@tool
extends RefCounted
class_name DungeonRoomPlacementController

const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const ItemDataScript = preload("res://addons/dungeon_room_editor/resources/room_placed_item_data.gd")


func can_place(
	room: RoomBase,
	layout,
	catalog,
	piece,
	grid_position: Vector2i,
	rotation_steps: int,
	ignore_item_id: String = "",
	candidate_layer: StringName = &""
) -> Dictionary:
	if room == null or layout == null or catalog == null or piece == null:
		return {"valid": false, "reason": "Editor session is incomplete."}
	var local_point := GridMath.grid_to_local(grid_position, layout, room)
	if not GridMath.is_inside_room(local_point, room, layout):
		return {"valid": false, "reason": "Placement is outside the room bounds."}
	if piece.is_door_socket():
		var direction := GridMath.direction_from_rotation(rotation_steps)
		if not GridMath.direction_matches_boundary(room, layout, local_point, direction):
			return {"valid": false, "reason": "Door sockets must snap to the matching room boundary."}

	var candidate_rect := GridMath.anchor_rect(
		grid_position,
		piece.footprint,
		rotation_steps,
		layout,
		room
	)
	var resolved_candidate_layer := _resolve_piece_layer(piece, candidate_layer)
	for item in layout.items:
		if item == null or item.item_id == ignore_item_id:
			continue
		var other_piece = catalog.find_piece(item.piece_id)
		if other_piece == null:
			continue
		if not candidate_rect.intersects(GridMath.item_rect(item, other_piece, layout, room), false):
			continue
		if resolved_candidate_layer != item.resolved_placement_layer(other_piece):
			continue
		if piece.allow_cell_overlap or other_piece.allow_cell_overlap:
			continue
		return {
			"valid": false,
			"reason": "This piece overlaps '%s'." % [
				other_piece.display_name if other_piece.display_name != "" else String(other_piece.piece_id)
			],
		}
	return {"valid": true, "reason": ""}


func place_item(session, piece, grid_position: Vector2i) -> Dictionary:
	var result := can_place(
		session.room,
		session.layout,
		session.catalog,
		piece,
		grid_position,
		session.placement_rotation_steps
	)
	if not bool(result.get("valid", false)):
		return result
	var item = ItemDataScript.new()
	item.item_id = session.next_item_id(piece)
	item.piece_id = piece.piece_id
	item.category = piece.category
	item.grid_position = grid_position
	item.rotation_steps = session.placement_rotation_steps
	item.tags = piece.default_tags.duplicate()
	item.encounter_group_id = &""
	item.enemy_id = piece.enemy_id
	item.placement_layer = _resolve_piece_layer(piece)
	item.blocks_movement = piece.blocks_movement
	item.blocks_projectiles = piece.blocks_projectiles
	session.layout.items.append(item)
	session.layout.emit_changed()
	return {"valid": true, "item": item}


func remove_item(session, item_id: String) -> bool:
	if session.layout == null:
		return false
	for index in range(session.layout.items.size()):
		var item = session.layout.items[index]
		if item != null and item.item_id == item_id:
			session.layout.items.remove_at(index)
			session.layout.emit_changed()
			return true
	return false


func _resolve_piece_layer(piece, explicit_layer: StringName = &"") -> StringName:
	if explicit_layer != &"":
		return explicit_layer
	if piece != null and piece.has_method(&"default_placement_layer"):
		return piece.default_placement_layer()
	return &"overlay"
