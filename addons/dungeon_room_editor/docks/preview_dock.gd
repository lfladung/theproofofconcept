@tool
extends PanelContainer

const PreviewBuilderScript = preload("res://addons/dungeon_room_editor/preview/preview_builder.gd")
const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")

@onready var _preview_viewport: SubViewport = %PreviewViewport
@onready var _preview_root: Node3D = %PreviewRoot
@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %PreviewCamera

var _preview_builder = PreviewBuilderScript.new()


func _ready() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera_pivot.rotation_degrees = Vector3(-38.0, 180.0, 0.0)


func refresh_preview(room: RoomBase, layout, catalog, visible_layer_filter: StringName = &"all") -> void:
	_preview_builder.rebuild_preview(_preview_root, room, layout, catalog, visible_layer_filter)
	_refit_camera(room)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _refit_camera(room: RoomBase) -> void:
	if room == null:
		return
	var size := GridMath.room_world_size(room)
	_camera.size = maxf(maxf(size.x, size.y) * 0.62, 18.0)
	_camera_pivot.position = Vector3.ZERO
