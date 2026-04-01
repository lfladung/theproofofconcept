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
	if piece.is_connection_marker():
		var last_reason := ""
		for test_rotation in _connection_marker_rotation_candidates(rotation_steps):
			var ft := GridMath.rotated_footprint(piece.footprint, test_rotation)
			var candidates: Array[Vector2i] = [grid_position]
			if ft.x > 1 or ft.y > 1:
				candidates = GridMath.connection_marker_anchor_candidates(
					grid_position,
					piece.footprint,
					test_rotation
				)
			for ap in candidates:
				var r := _evaluate_anchor(
					room,
					layout,
					catalog,
					piece,
					ap,
					test_rotation,
					ignore_item_id,
					candidate_layer
				)
				if bool(r.get("valid", false)):
					return {
						"valid": true,
						"reason": "",
						"resolved_grid": ap,
						"resolved_rotation_steps": test_rotation,
					}
				last_reason = String(r.get("reason", ""))
		return {
			"valid": false,
			"reason": last_reason if last_reason != "" else "Connection markers must snap to the matching room boundary.",
		}
	var single := _evaluate_anchor(
		room,
		layout,
		catalog,
		piece,
		grid_position,
		rotation_steps,
		ignore_item_id,
		candidate_layer
	)
	if not bool(single.get("valid", false)):
		return single
	return {
		"valid": true,
		"reason": "",
		"resolved_grid": grid_position,
		"resolved_rotation_steps": posmod(rotation_steps, 4),
	}


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
	var resolved: Vector2i = result.get("resolved_grid", grid_position)
	var item = ItemDataScript.new()
	item.item_id = session.next_item_id(piece)
	item.piece_id = piece.piece_id
	item.category = piece.category
	item.grid_position = resolved
	item.rotation_steps = int(result.get("resolved_rotation_steps", session.placement_rotation_steps))
	item.tags = piece.default_tags.duplicate()
	item.encounter_group_id = &""
	item.enemy_id = piece.enemy_id
	item.placement_layer = _resolve_piece_layer(piece)
	item.blocks_movement = piece.blocks_movement
	item.blocks_projectiles = piece.blocks_projectiles
	session.layout.items.append(item)
	session.layout.emit_changed()
	return {"valid": true, "item": item}


func _connection_marker_rotation_candidates(preferred_rotation: int) -> PackedInt32Array:
	var preferred := posmod(preferred_rotation, 4)
	var ordered := PackedInt32Array([preferred])
	for offset in range(1, 4):
		var candidate := posmod(preferred + offset, 4)
		if not ordered.has(candidate):
			ordered.append(candidate)
	return ordered


func _evaluate_anchor(
	room: RoomBase,
	layout,
	catalog,
	piece,
	anchor: Vector2i,
	rotation_steps: int,
	ignore_item_id: String,
	candidate_layer: StringName
) -> Dictionary:
	var local_point := GridMath.grid_to_local(anchor, layout, room)
	if not GridMath.is_inside_room(local_point, room, layout):
		return {"valid": false, "reason": "Placement is outside the room bounds."}
	var candidate_rect := GridMath.anchor_rect(anchor, piece.footprint, rotation_steps, layout, room)
	if piece.is_connection_marker():
		var direction := GridMath.direction_from_rotation(rotation_steps)
		if not GridMath.connection_marker_spans_room_boundary(room, layout, candidate_rect, direction):
			return {"valid": false, "reason": "Connection markers must sit on the room boundary."}
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
