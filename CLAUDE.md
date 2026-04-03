# CLAUDE.md

Godot 4.6 project: 2–4 player authoritative co-op dungeon crawler.

## Do Not Do This

- **Do not scan `dungeon/rooms/authored/` unless the task explicitly targets authored room files.** These are large Godot scene/resource files with no useful information for logic tasks. Reading them wastes context and slows down work. If you need to understand a room's structure, read one example file — not the whole folder.
- Do not casually delete or rewrite `tools/tmp_*` scripts — they are user-owned debug helpers.
- Do not treat `scripts/core/main.gd` as active code; it is legacy sample scaffolding.

## Read First (by task)

- Full project context: `AGENTS.md`
- Room authoring rules and contract: `dungeon/README.md`
- Multiplayer milestone status: `dungeon/MULTIPLAYER_MILESTONE_MAP.md`
- Verification commands: `tools/COMMANDS.md`
- Asset/equipment pipeline: `tools/asset_pipeline/CODEX_THREAD_SUMMARY_2026-03-26.md`

## Runtime Entrypoints

- Main scene: `res://scenes/ui/lobby_menu.tscn`
- Gameplay world: `res://dungeon/game/small_dungeon.tscn`
- Network autoloads: `NetworkSession`, `NetEventBus`, `RunState` (see `project.godot`)

## Key File Groups

**Networking:** `scripts/network/network_session.gd`, `scripts/entities/player.gd`, `dungeon/game/small_dungeon.gd`

**Dungeon/encounters:** `dungeon/game/small_dungeon.gd`, `dungeon/game/components/*.gd`, `dungeon/modules/**/*.gd`

**Room editor/authoring:** `addons/dungeon_room_editor/`, `dungeon/rooms/base/room_base.gd`, `dungeon/metadata/zone_marker_2d.gd`

**Visuals/equipment:** `scripts/visuals/player_visual.gd`, `scenes/visuals/player_visual.tscn`

## Authored Room System (summary — do not read the folder)

- Base contract: `dungeon/rooms/base/room_base.tscn` with script `room_base.gd`
- Each room has a sidecar `*.layout.tres` (`RoomLayoutData`) — this is the source of truth, not the generated scene children
- Generated children live under `Sockets/GeneratedByRoomEditor`, `Zones/GeneratedByRoomEditor`, `Gameplay/GeneratedByRoomEditor`
- Room naming: `room_<category>_<theme>_<size>_<variant>.tscn`
- Variants are versioned: `v2/` = old (some deleted), `v3/` = current authored set
- Required metadata per room: `room_id`, `size_class`, `tile_size`, `room_size_tiles`, `allowed_rotations`, `room_tags`, `allowed_connection_types`, `encounter_budget`, `max_tile_budget`
- Zone types: `melee`, `filler`, `encounter_trigger`, `loot_marker`, `nav_boundary`, `floor_exit`
- Socket types: `EntranceMarker`, `ExitMarker` with `direction` = `north/south/east/west`

## Architecture Rules

- Authoritative server model — all combat, spawning, and state changes run on the server peer
- 2D physics for all gameplay logic; 3D is presentation only
- Coordinate mapping: `Vector2(x, y)` → `Vector3(x, height, y)` — never mix raw 2D/3D positions across the boundary
- `small_dungeon.gd` has broad side effects — changes there ripple into networking, encounters, cameras, and doors
- `room_query_service.gd` is a shared hot-path — do not add per-frame scans to it

## Current Status (as of 2026-04-01)

- Multiplayer milestones 1–9 complete (see `dungeon/MULTIPLAYER_MILESTONE_MAP.md`)
- Melee: owner-client request → server validation → replicated event
- Sword blocking: server-authoritative directional stamina guard
- Boss rooms: auto-stamped `floor_exit` marker placed by Room Editor, consumed at runtime by `room_query_service.gd`
- Stat pillar module added (`dungeon/modules/gameplay/stat_pillar_2d.gd`); new affix stats declared but not yet wired into combat calculations
