@tool
extends RefCounted
class_name DungeonRoomSceneSync

const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const DoorSocketScene = preload("res://dungeon/rooms/base/door_socket_2d.tscn")
const ZoneMarkerScene = preload("res://dungeon/metadata/zone_marker_2d.tscn")
const PREVIEW_BUILDER_SCRIPT = preload("res://addons/dungeon_room_editor/preview/preview_builder.gd")

var _preview_builder = PREVIEW_BUILDER_SCRIPT.new()


func sync_room(room: RoomBase, layout, catalog) -> void:
	if room == null or layout == null or catalog == null:
		return
	room.room_id = layout.room_id
	room.room_tags = layout.room_tags.duplicate()
	room.authored_layout = layout
	room.tile_size = layout.grid_size

	var sockets_root := _ensure_node2d_container(room, room.get_node(^"Sockets") as Node2D)
	var zones_root := _ensure_node2d_container(room, room.get_node(^"Zones") as Node2D)
	var gameplay_root := _ensure_node2d_container(room, room.get_node(^"Gameplay") as Node2D)
	var visual_root := _ensure_node3d_container(room, room.get_node(^"Visual3DProxy") as Node3D)

	_clear_children(sockets_root)
	_clear_children(zones_root)
	_clear_children(gameplay_root)
	_clear_children(visual_root)

	for item in layout.items:
		if item == null:
			continue
		var piece = catalog.find_piece(item.piece_id)
		if piece == null:
			continue
		match String(piece.mapping_kind):
			"visual_only":
				_sync_visual_only_item(room, layout, item, piece, visual_root)
			"runtime_scene":
				_sync_runtime_scene_item(room, layout, item, piece, gameplay_root)
			"zone_marker":
				_sync_zone_marker_item(room, layout, item, piece, zones_root)
			"door_socket":
				_sync_socket_item(room, layout, item, piece, sockets_root)


func _sync_visual_only_item(
	room: RoomBase,
	layout,
	item,
	piece,
	parent: Node3D
) -> void:
	if piece.preview_scene == null:
		return
	var instance := piece.preview_scene.instantiate() as Node3D
	if instance == null:
		return
	instance.name = "%s_%s" % [String(piece.piece_id), item.item_id]
	_preview_builder.configure_piece_instance(instance, item, piece, layout, room)
	parent.add_child(instance)


func _sync_runtime_scene_item(
	room: RoomBase,
	layout,
	item,
	piece,
	parent: Node2D
) -> void:
	if piece.runtime_scene == null:
		return
	var instance := piece.runtime_scene.instantiate() as Node2D
	if instance == null:
		return
	instance.name = "%s_%s" % [String(piece.piece_id), item.item_id]
	instance.position = GridMath.grid_to_local(item.grid_position, layout, room)
	instance.rotation = float(item.normalized_rotation_steps()) * PI * 0.5
	parent.add_child(instance)
	_apply_common_item_metadata(instance, item)
	if _object_has_property(instance, &"direction"):
		instance.set(&"direction", GridMath.direction_from_rotation(item.normalized_rotation_steps()))


func _sync_zone_marker_item(
	room: RoomBase,
	layout,
	item,
	piece,
	parent: Node2D
) -> void:
	var zone := ZoneMarkerScene.instantiate() as ZoneMarker2D
	if zone == null:
		return
	zone.name = "%s_%s" % [String(piece.piece_id), item.item_id]
	zone.position = GridMath.grid_to_local(item.grid_position, layout, room)
	zone.zone_type = piece.zone_type if piece.zone_type != "" else "prop_placement"
	zone.zone_role = piece.zone_role
	zone.tags = item.tags.duplicate()
	parent.add_child(zone)


func _sync_socket_item(
	room: RoomBase,
	layout,
	item,
	piece,
	parent: Node2D
) -> void:
	var socket := DoorSocketScene.instantiate() as DoorSocket2D
	if socket == null:
		return
	socket.name = "%s_%s" % [String(piece.piece_id), item.item_id]
	socket.position = GridMath.grid_to_local(item.grid_position, layout, room)
	socket.direction = GridMath.direction_from_rotation(item.normalized_rotation_steps())
	socket.connector_type = piece.connector_type
	var rotated_footprint := GridMath.rotated_footprint(piece.footprint, item.normalized_rotation_steps())
	socket.width_tiles = maxi(rotated_footprint.x, rotated_footprint.y)
	parent.add_child(socket)


func _ensure_node2d_container(room: RoomBase, parent: Node2D) -> Node2D:
	var existing := parent.get_node_or_null(^"GeneratedByRoomEditor") as Node2D
	if existing != null:
		return existing
	var container := Node2D.new()
	container.name = "GeneratedByRoomEditor"
	parent.add_child(container)
	return container


func _ensure_node3d_container(room: RoomBase, parent: Node3D) -> Node3D:
	var existing := parent.get_node_or_null(^"GeneratedByRoomEditor") as Node3D
	if existing != null:
		return existing
	var container := Node3D.new()
	container.name = "GeneratedByRoomEditor"
	parent.add_child(container)
	return container


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()


func _local_2d_to_3d(local_position: Vector2) -> Vector3:
	return Vector3(local_position.x, 0.0, local_position.y)


func _apply_common_item_metadata(node: Node, item) -> void:
	node.set_meta(&"room_editor_item_id", item.item_id)
	node.set_meta(&"room_editor_piece_id", item.piece_id)
	node.set_meta(&"room_editor_category", item.category)
	node.set_meta(&"room_editor_encounter_group_id", item.encounter_group_id)
	node.set_meta(&"room_editor_placement_layer", item.resolved_placement_layer())
	node.set_meta(&"room_editor_tags", item.tags)
	node.set_meta(&"room_editor_blocks_movement", item.blocks_movement)
	node.set_meta(&"room_editor_blocks_projectiles", item.blocks_projectiles)


func _object_has_property(object: Object, property_name: StringName) -> bool:
	for info in object.get_property_list():
		if StringName(info.get("name", "")) == property_name:
			return true
	return false
