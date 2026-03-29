@tool
extends Resource
class_name RoomLayoutData

@export var room_id := ""
@export var room_tags: PackedStringArray = []
@export var recommended_enemy_groups: PackedStringArray = []
@export var grid_size := Vector2i(3, 3)
@export var items: Array[Resource] = []


func find_item(item_id: String):
	for item in items:
		if item != null and item.item_id == item_id:
			return item
	return null


func duplicate_layout():
	var duplicate = get_script().new()
	duplicate.room_id = room_id
	duplicate.room_tags = room_tags.duplicate()
	duplicate.recommended_enemy_groups = recommended_enemy_groups.duplicate()
	duplicate.grid_size = grid_size
	for item in items:
		if item != null:
			duplicate.items.append(item.duplicate_item())
	return duplicate
