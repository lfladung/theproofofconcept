@tool
extends VBoxContainer

signal piece_selected(piece_id: StringName)

const _CATEGORY_ORDER := [
	"floor",
	"wall",
	"door",
	"spawn",
	"exit",
	"prop",
	"trap",
	"treasure",
]

@onready var _search_line: LineEdit = %SearchLine
@onready var _piece_tree: Tree = %PieceTree

var _catalog
var _is_programmatic_selection := false
var _selected_piece_id: StringName = &""


func _ready() -> void:
	_piece_tree.hide_root = true
	_piece_tree.item_selected.connect(_on_piece_tree_item_selected)
	_search_line.text_changed.connect(func(_text: String) -> void: _rebuild_tree())


func set_catalog(catalog) -> void:
	_catalog = catalog
	_rebuild_tree()


func set_active_piece(piece_id: StringName) -> void:
	if _piece_tree.get_root() == null:
		return
	var selected := _piece_tree.get_selected()
	if selected != null and selected.get_metadata(0) == piece_id:
		_selected_piece_id = piece_id
		return
	_is_programmatic_selection = true
	_select_piece_in_tree(_piece_tree.get_root(), piece_id)
	_is_programmatic_selection = false
	_selected_piece_id = piece_id


func _rebuild_tree() -> void:
	_piece_tree.clear()
	var root := _piece_tree.create_item()
	if _catalog == null:
		return
	var filter_text := _search_line.text.strip_edges().to_lower()
	for category in _ordered_categories():
		var entries = _catalog.pieces_in_category(StringName(category))
		var category_item: TreeItem
		for piece in entries:
			if piece == null:
				continue
			var label = piece.display_name if piece.display_name != "" else String(piece.piece_id)
			if filter_text != "" and label.to_lower().find(filter_text) == -1:
				continue
			if category_item == null:
				category_item = _piece_tree.create_item(root)
				category_item.set_text(0, category.capitalize())
				category_item.set_selectable(0, false)
			var piece_item := _piece_tree.create_item(category_item)
			piece_item.set_text(0, label)
			piece_item.set_metadata(0, piece.piece_id)


func _ordered_categories() -> PackedStringArray:
	var categories := PackedStringArray()
	if _catalog == null:
		return categories
	var seen: Dictionary = {}
	for category in _CATEGORY_ORDER:
		if _catalog.categories().has(category):
			seen[category] = true
			categories.append(category)
	for category in _catalog.categories():
		if seen.has(category):
			continue
		categories.append(category)
	return categories


func _select_piece_in_tree(item: TreeItem, piece_id: StringName) -> bool:
	var current := item
	while current != null:
		if current.get_metadata(0) == piece_id:
			current.select(0)
			_piece_tree.scroll_to_item(current)
			return true
		if current.get_first_child() != null and _select_piece_in_tree(current.get_first_child(), piece_id):
			return true
		current = current.get_next()
	return false


func _on_piece_tree_item_selected() -> void:
	if _is_programmatic_selection:
		return
	var selected := _piece_tree.get_selected()
	if selected == null:
		return
	var piece_id := selected.get_metadata(0)
	if piece_id == null:
		return
	var next_piece_id := piece_id as StringName
	if _selected_piece_id == next_piece_id:
		return
	_selected_piece_id = next_piece_id
	piece_selected.emit(next_piece_id)
