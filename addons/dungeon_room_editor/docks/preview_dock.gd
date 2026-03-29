@tool
extends PanelContainer

const PreviewBuilderScript = preload("res://addons/dungeon_room_editor/preview/preview_builder.gd")
const GridMath = preload("res://addons/dungeon_room_editor/core/grid_math.gd")
const CAMERA_LOCAL_OFFSET := Vector3(0.0, 0.0, 150.0)
const CAMERA_FAR := 500.0
const DUNGEON_BG_COLOR := Color(0.035, 0.04, 0.055, 1.0)
const DUNGEON_AMBIENT_COLOR := Color(0.62, 0.58, 0.52, 1.0)
const DUNGEON_AMBIENT_ENERGY := 0.5
const DUNGEON_SUN_ROTATION_DEG := Vector3(-63.8, 60.0, 0.0)
const DUNGEON_SUN_ENERGY := 1.0
const DUNGEON_SUN_SHADOW_BIAS := 0.04
const DUNGEON_SUN_SHADOW_BLUR := 1.5
const DUNGEON_SUN_MAX_DISTANCE := 260.0

@onready var _preview_viewport: SubViewport = %PreviewViewport
@onready var _preview_root: Node3D = %PreviewRoot
@onready var _preview_environment: WorldEnvironment = %PreviewEnvironment
@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %PreviewCamera
@onready var _sun: DirectionalLight3D = %Sun

var _preview_builder = PreviewBuilderScript.new()


func _ready() -> void:
	_configure_preview_environment()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera_pivot.rotation_degrees = Vector3(-38.0, 180.0, 0.0)
	_camera.position = CAMERA_LOCAL_OFFSET
	_camera.far = CAMERA_FAR
	_sun.rotation_degrees = DUNGEON_SUN_ROTATION_DEG
	_sun.light_energy = DUNGEON_SUN_ENERGY
	_sun.shadow_bias = DUNGEON_SUN_SHADOW_BIAS
	_sun.shadow_blur = DUNGEON_SUN_SHADOW_BLUR
	_sun.directional_shadow_max_distance = DUNGEON_SUN_MAX_DISTANCE


func _configure_preview_environment() -> void:
	if _preview_environment == null:
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = DUNGEON_BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = DUNGEON_AMBIENT_COLOR
	environment.ambient_light_energy = DUNGEON_AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.sdfgi_enabled = false
	_preview_environment.environment = environment


func refresh_preview(room: RoomBase, layout, catalog, visible_layer_filter: StringName = &"all") -> void:
	_preview_root.position = Vector3.ZERO
	_preview_root.rotation = Vector3.ZERO
	_preview_root.scale = Vector3.ONE
	_preview_builder.rebuild_preview(_preview_root, room, layout, catalog, visible_layer_filter)
	_align_preview_root_to_room(room)
	_refit_camera(room)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _refit_camera(room: RoomBase) -> void:
	if room == null:
		return
	var size := GridMath.room_world_size(room)
	_camera.size = maxf(maxf(size.x, size.y) * 0.62, 18.0)
	var room_center := room.get_room_rect_world().get_center()
	_camera_pivot.position = Vector3(room_center.x, 0.0, room_center.y)


func _align_preview_root_to_room(room: RoomBase) -> void:
	if room == null or _preview_root == null:
		return
	var bounds := _compute_preview_bounds()
	if bounds.size == Vector3.ZERO:
		return
	var room_center := room.get_room_rect_world().get_center()
	var visual_center := bounds.get_center()
	_preview_root.position = Vector3(
		room_center.x - visual_center.x,
		0.0,
		room_center.y - visual_center.z
	)


func _compute_preview_bounds() -> AABB:
	# Use local transform chains (same as piece grid-fit). global_transform is often stale inside
	# SubViewports immediately after add_child, which skews alignment and parks the newest prop at the pivot.
	return _preview_builder.merged_mesh_bounds_under_root(_preview_root)
