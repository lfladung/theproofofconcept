extends RefCounted
class_name DungeonConstants

const TILE_SIZE := Vector2i(32, 32)

const ROOM_SIZE_TILES := {
	"small": Vector2i(16, 16),
	"medium": Vector2i(24, 24),
	"large": Vector2i(32, 32),
	"arena": Vector2i(40, 40),
}

const SOCKET_DIRECTIONS := {
	"north": "south",
	"south": "north",
	"east": "west",
	"west": "east",
	"up": "down",
	"down": "up",
}

const LAYER_NAMES := PackedStringArray([
	"floor",
	"walls",
	"hazards",
	"decor",
])

const DEBUG_TILE_KEYS := PackedStringArray([
	"ground",
	"wall",
	"trap",
	"door",
	"stairs",
])

const DEBUG_TILE_COLORS := {
	"ground": Color(1.0, 1.0, 1.0, 1.0),
	"wall": Color(0.47, 0.31, 0.20, 1.0),
	"trap": Color(1.0, 0.89, 0.10, 1.0),
	"door": Color(0.62, 0.26, 0.86, 1.0),
	"stairs": Color(1.0, 0.55, 0.15, 1.0),
}
