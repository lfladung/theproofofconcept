# Dungeon Module (Milestone 1)

This module introduces the first procedural-room architecture scaffolding for a hybrid 2D logic + 3D presentation dungeon pipeline.

## Folder Layout

- `res://dungeon/core/`
  - Shared constants and rule primitives.
- `res://dungeon/rooms/base/`
  - Base reusable room scene contract and door socket scene.
- `res://dungeon/metadata/`
  - Reusable metadata markers for generation and encounter logic.
- `res://dungeon/tilesets/`
  - Dummy color-coded assets for graybox authoring.

## Base Room Contract

Use `res://dungeon/rooms/base/room_base.tscn` as the parent for room templates.

Required children:
- `Layout/TileFloor`
- `Layout/TileWalls`
- `Layout/TileHazards`
- `Layout/TileDeco`
- `Sockets/*` (`DoorSocket2D` instances)
- `Zones/*` (`ZoneMarker2D` instances)
- `Gameplay`
- `Visual3DProxy` (optional in hybrid mode)

## Debug Color Legend

- Ground: white
- Walls: brown
- Traps/Hazards: yellow
- Doors/Exits: purple
- Stairs/Vertical transitions: orange

Legend texture:
- `res://dungeon/tilesets/debug_tile_legend.svg`

## Naming Rules

- Rooms: `room_<category>_<theme>_<size>_<variant>.tscn`
- Sockets: `DoorSocket_<Direction>_<Width>`
- Zones: `<ZoneType>_<Role>_<Index>`

## Current Scope

Milestone 1 provides the modular skeleton only:
- room composition contract
- reusable socket and zone marker scenes
- shared constants and color legend

Generation logic, room catalog loading, and runtime assembly are implemented in later milestones.

## POC Scene

- `res://dungeon/poc/dungeon_room_poc.tscn`
  - Instantiates `RoomBase`.
  - Adds a small-room world boundary and a playable `Player`.
  - Uses the milestone debug color language in 3D placeholders:
	- white ground
	- brown walls
	- yellow trap tile
	- purple doorway
	- orange stairs marker
