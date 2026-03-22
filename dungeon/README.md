# Dungeon Module (Milestone 1)

This module introduces the first procedural-room architecture scaffolding for a hybrid 2D logic + 3D presentation dungeon pipeline.

## Canonical Room Rulebook

All new dungeon rooms must follow these rules. This is the source of truth for room authoring and generator integration.

### Core Structural Rules

1. Grid compliance
   - Room dimensions align to a global tile grid.
   - Width/height use standardized sizes (default set: `10`, `16`, `24`, `32` tiles).
   - Player footprint is treated as `1x1` tile baseline.
   - Door sockets align to grid centers.
2. Closed boundary
   - Rooms are enclosed by walls or void boundaries.
   - Open edges are allowed only at explicit door sockets.
   - Player exits only through defined connectors.
3. Door socket standardization
   - Cardinal sockets (`north`, `south`, `east`, `west`) are required for horizontal connectivity.
   - Socket width follows corridor standards.
   - Socket positions snap to the wall grid and boundary.
   - Every socket is represented by a connection node (`DoorSocket2D`).
   - Optional vertical sockets (`up`, `down`) are supported for stairs/pits/elevators.
4. Traversable space guarantee
   - Walkable flow must connect all entry/exit points.
   - No unreachable gameplay sections.
   - Elevation changes include accessible traversal (stairs/ramps).

### Gameplay Space Rules

5. Gameplay zoning
   - Every room reserves zones for combat, traversal, props, and entry safety.
6. Door safety buffer
   - No immediate hazard at doorway entry.
   - No spawn-on-entry enemy overlap.
   - Safe step-in tiles exist near each entrance.
7. Encounter self-containment
   - Combat rooms are completable without leaving.
   - Triggers/spawns are reset on completion.
   - Locked room completion condition is explicit.

### Technical Metadata Rules

8. Room origin standard
   - Each room defines an origin mode (`center` or `top_left`).
   - Origin aligns to world grid for placement and rotation math.
9. Room classification tag
   - Each room declares one type: `arena`, `corridor`, `puzzle`, `treasure`, `safe`, `boss`, `connector`.
10. Connection compatibility tag
   - Rooms define:
	 - door count and directions
	 - allowed connection types
	 - difficulty tier range

### Player Experience Rules

11. Readability rule
   - Walkable vs blocked areas are obvious.
   - Major hazards are visually clear.
   - Exits are readable at a glance.
12. Combat rhythm rule
   - Small: quick skirmish
   - Medium: tactical combat
   - Large/arena: waves/major encounter
   - Corridor: traversal transition
13. Landmark rule
   - Each room includes at least one recognizable feature to aid orientation.

### Generator Safety Rules

14. Tile budget limit
   - Room tile count must stay under a per-room budget.
15. Prop density limit
   - Keep traversal lanes clear by capping prop occupancy.
16. Rotation compatibility
   - If rotation is enabled, sockets and traversal remain valid at all allowed rotations.

### Minimal MVP Rules

The lean baseline for procedural viability:
- grid-aligned size
- enclosed boundaries
- standardized sockets
- walkable door-to-door path
- safe entry buffer
- room type tag
- defined origin point

Mental model: every room is a self-contained gameplay cartridge.

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

### Required RoomBase Metadata

Set these fields for each authored room:
- `room_id`
- `room_type`
- `origin_mode`
- `tile_size`
- `room_size_tiles`
- `allowed_rotations`
- `room_tags` (must include `room_type`)
- `allowed_connection_types`
- `min_difficulty_tier` / `max_difficulty_tier`
- `max_tile_budget`
- `max_prop_density`

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

## Enforcement in Code

`RoomBase` now performs automatic validation warnings in `_ready()` for:
- grid compliance and standard room size checks
- wall enclosure contract checks
- socket direction, snap, and boundary alignment checks
- minimum zone marker coverage checks
- origin/classification/connection metadata checks
- tile budget and prop-density limits
- rotation validity checks

Authoring workflow: duplicate `room_base.tscn`, set metadata first, then paint/layout content until all rule warnings are resolved.

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

- `res://dungeon/poc/small_dungeon_poc.tscn`
  - Multi-room dungeon POC that includes baseline room types:
	- entrance room
	- transition corridors between main rooms
	- combat room (lock/unlock proof without enemy spawning)
	- treasure dead-end room (chest marker)
	- boss room (completion portal after simulated clear)
  - Uses `RoomBase` instances and runtime boundary generation from socket openings.
