@tool
extends Resource
class_name RoomPieceCatalog

@export var pieces: Array[Resource] = []


func find_piece(piece_id: StringName):
	for piece in pieces:
		if piece != null and piece.piece_id == piece_id:
			return piece
	return null


func categories() -> PackedStringArray:
	var seen: Dictionary = {}
	var out := PackedStringArray()
	for piece in pieces:
		if piece == null:
			continue
		var category := String(piece.category)
		if category.is_empty() or seen.has(category):
			continue
		seen[category] = true
		out.append(category)
	return out


func pieces_in_category(category: StringName) -> Array:
	var out: Array = []
	for piece in pieces:
		if piece != null and piece.category == category:
			out.append(piece)
	return out
