# Dungeon Milestone Goals

This file tracks milestone goals for the dungeon architecture and procedural content framework.

## Completed Milestones

- [x] Milestone 1: Core room architecture scaffold
  - `RoomBase` contract
  - layered TileMap structure (`TileFloor`, `TileWalls`, `TileHazards`, `TileDeco`)
  - door socket + metadata zone marker base scenes
  - debug color standard (white ground, brown walls, yellow traps, purple doors/exits, orange stairs)

- [x] Milestone 1 POC: Playable single-room prototype
  - player can move inside a small room
  - room boundaries, door marker, trap marker, stairs marker

- [x] Rules Integration Milestone
  - canonical dungeon room rulebook added to `dungeon/README.md`
  - `RoomBase` validation checks for grid/socket/metadata/rotation/budget constraints
  - validated baseline documented from POC learnings

- [x] Multi-room Dungeon POC Milestone
  - entrance -> transition -> combat -> transition -> boss chain
  - optional treasure branch
  - simulated combat lock/clear + boss completion portal flow
  - player-follow camera
  - explicit brown visual walls for boundaries

- [x] Original Map Milestone #2: MVP structure + connectivity piece pack
  - structure pieces: floor, wall, corner, pit, ramp
  - connectivity pieces: standard door, locked door, entrance marker, exit marker
  - reusable base piece contract and locked-door API
  - wired into `small_dungeon_poc` runtime assembly

- [x] Milestone 3: Encounter infrastructure MVP
  - encounter modules: enemy spawn point, spawn volume, room trigger, arena boundary
  - `small_dungeon_poc` upgraded from simulated clear timers to real spawn-clear flow
  - encounter boundaries lock/unlock from live enemy state
  - boss exit portal now unlocks after actual boss encounter clear

- [x] Milestone 4: Gameplay object MVP
  - `TreasureChest2D` + `KeyPickup2D` modules; treasure room chest drops a key pickup
  - `LockedDoorPiece2D` optional `key_id` + unlock volume; branch↔treasure door keyed in `small_dungeon_poc`
  - `TrapTile2D` damage-over-time while standing on tile (cooldown), placed in treasure room

## Next Milestone Goals

- [ ] Milestone 5: Procedural assembly v1
  - room catalog loading from metadata
  - socket-based room graph generation
  - overlap validation + connectivity checks

- [ ] Milestone 6: Biome/theme pipeline
  - swappable tile/material sets
  - hazard/prop pool variation by biome
  - lighting/fog/atmosphere presets

## Working Rules

- One major milestone per commit.
- Keep milestones independently testable.
- Extend the validated POC baseline rather than replacing it.
