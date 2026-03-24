extends Node
class_name InfoLabelController

var info_label: Label
var player: CharacterBody2D
var room_queries: RoomQueryService
var _base_text := ""


func set_base_text(text: String) -> void:
	_base_text = text
	refresh()


func refresh() -> void:
	if info_label == null:
		return
	var base := _base_text if not _base_text.is_empty() else info_label.text
	if player == null or not is_instance_valid(player) or room_queries == null:
		info_label.text = base
		return
	var room_type := room_queries.room_type_at(player.global_position, 1.25)
	if room_type.is_empty():
		info_label.text = base
	else:
		info_label.text = "%s | Room: %s" % [base, room_type]
