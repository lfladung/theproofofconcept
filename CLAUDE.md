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
- Gameplay world: `res://dungeon/game/dungeon_orchestrator.tscn`
- Autoloads: `GameSettings`, `LoadingOverlay`, `NetworkSession`, `NetEventBus`, `RunState` (see `project.godot`)

## Key File Groups

**Networking:** `scripts/network/network_session.gd`, `scripts/entities/player.gd`, `dungeon/game/dungeon_orchestrator.gd` / `dungeon_orchestrator_internals.gd`

**Dungeon/encounters:** `dungeon/game/dungeon_orchestrator_internals.gd`, `dungeon/game/components/*.gd`, `dungeon/modules/**/*.gd`

**Room editor/authoring:** `addons/dungeon_room_editor/`, `dungeon/rooms/base/room_base.gd`, `dungeon/metadata/zone_marker_2d.gd`

**Visuals/equipment:** `scripts/visuals/player_visual.gd` / `player_visual_internals.gd`, `scenes/visuals/player_visual.tscn`

**Meta-progression / inventory:** `scripts/meta_progression/meta_progression_constants.gd`, `scripts/meta_progression/meta_progression_store.gd` (autoload), `scripts/meta_progression/gear_item_data.gd`, `scripts/meta_progression/gem_item_data.gd`, `scripts/meta_progression/tempering_manager.gd`

**Inventory UI:** `scripts/ui/inventory/inventory_screen.gd`, `scripts/ui/lobby_menu.gd`

**Loadout:** `scripts/loadout/loadout_constants.gd`, `scripts/loadout/loadout_repository.gd`, `scripts/ui/loadout/loadout_overlay.gd`, `scenes/ui/loadout/loadout_category_section.tscn`

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
- `dungeon_orchestrator_internals.gd` (and thin `dungeon_orchestrator.gd`) have broad side effects — changes there ripple into networking, encounters, cameras, and doors
- `room_query_service.gd` is a shared hot-path — do not add per-frame scans to it

## Current Status (as of 2026-04-10)

- Multiplayer milestones 1–9 complete; dedicated join-by-session-code through DS milestones 1–3 (see `dungeon/MULTIPLAYER_MILESTONE_MAP.md`)
- Melee: owner-client request → server validation → replicated event
- Sword blocking: server-authoritative directional stamina guard
- Boss rooms: auto-stamped `floor_exit` marker placed by Room Editor, consumed at runtime by `room_query_service.gd`
- Stat pillar module added (`dungeon/modules/gameplay/stat_pillar_2d.gd`); new affix stats declared but not yet wired into combat calculations
- Authored outline starter rooms: `dungeon/rooms/authored/outlines/` with `tools/room_editor/generate_outline_rooms.gd` / `validate_outline_rooms.gd`
- **Meta-progression system implemented** (see `ideas/META_PROGRESSION.md`, `ideas/INVENTORY.md`):
  - `MetaProgressionStore` autoload — single mutation gateway for gear instances, gems, materials, resonant dust; persists to `user://meta_progression_{player_id}.json`; `apply_server_state()` is future server-authority entry point
  - `GearItemData` — owned gear instance with tier (1–3), pillar alignment, familiarity XP, promotion progress, inscriptions, gem sockets
  - `GemItemData` — gem instance with pillar, effect key, durability model
  - `TemperingManager` — run-scoped `RefCounted`; tracks tempering XP per gear piece, two thresholds (Tempered I/II), emits `tempering_state_changed`; wired into orchestrator lifecycle
  - `MetaProgressionConstants` — all thresholds, multipliers, cost tables; `class_name MetaProgressionConstants`
  - `LoadoutRepository` now initialises owners from `MetaProgressionStore` (only owned items visible in-run); equipping during a run syncs back to `MetaProgressionStore`
  - Item display names centralised in `LoadoutConstants.ITEM_DISPLAY_NAMES` / `item_display_name()`
  - Starter state: T1 equipped + T2 Aligned + T3 Specialized per slot, varied pillar per slot, seeded materials
- **Inventory UI implemented:**
  - Lobby "Inventory" button → full-screen overlay (`scripts/ui/inventory/inventory_screen.gd`)
  - 3 sub-screens: Loadout (categorised/collapsible per slot, equip via click), Gear Detail (tier/pillar/familiarity/promotion/inscriptions/sockets/evolve), Gem Management
  - Clicking an already-equipped item opens Gear Detail; clicking a stash item equips it
  - In-run loadout overlay tooltips now include tier, pillar, and familiarity info
