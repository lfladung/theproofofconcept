# AGENTS.md

## Repo Purpose

- Godot 4.6 project converting a prototype into a 2-4 player authoritative co-op dungeon crawler.
- The active user flow starts in `res://scenes/ui/lobby_menu.tscn`, not the old singleplayer sample flow.
- The main gameplay runtime is `res://dungeon/game/small_dungeon.tscn`.
- `project.godot` still contains starter-template metadata (`Squash The Creeps`), so code and docs are the real source of truth for project identity.

## Read First

Read the smallest relevant set before editing:

- Multiplayer roadmap and status: `dungeon/MULTIPLAYER_MILESTONE_MAP.md`
- Dungeon architecture and room rulebook: `dungeon/README.md`
- Common launch and verification commands: `tools/COMMANDS.md`
- Asset and equipment pipeline snapshot: `tools/asset_pipeline/CODEX_THREAD_SUMMARY_2026-03-26.md`

## Runtime Entrypoints

- Main scene: `res://scenes/ui/lobby_menu.tscn`
- Lobby controller: `res://scripts/ui/lobby_menu.gd`
- Core world orchestration: `res://dungeon/game/small_dungeon.gd`
- Player gameplay and networking: `res://scripts/entities/player.gd`
- Player 3D presentation and modular equipment: `res://scripts/visuals/player_visual.gd`
- Network autoloads in `project.godot`:
  - `NetworkSession = res://scripts/network/network_session.gd`
  - `NetEventBus = res://scripts/network/net_event_bus.gd`
  - `RunState = res://scripts/network/run_state.gd`

## Current Project Snapshot

As of 2026-03-27:

- Multiplayer milestones 1-3 are complete.
- Milestone 4 authoritative combat is in progress.
- Melee already has owner-client request -> server validation -> replicated event flow.
- Sword blocking now uses a server-authoritative directional stamina guard: front-blocked hostile hits drain stamina instead of HP, and stamina regen is delayed after use/break.
- Lobby/session-code flow and peer-slot mapping are implemented.
- `small_dungeon.gd` is session-aware and manages roster, encounter state, doors, coins, camera, and replication helpers.

## Subsystem Notes

### Networking

- The project uses an authoritative server model for 2-4 players.
- `NetworkSession` owns session lifecycle, lobby state, registry/session-code lookups, peer slots, readiness, and host/client/dedicated-server roles.
- `Player` owns authority assignment, prediction/reconciliation, weapon mode state, and combat request sequencing.
- Guard-aware hostile damage should call `Player.take_attack_damage(...)`; direct environmental damage should stay on `take_damage(...)`.
- If a change affects replication or player authority, inspect both `network_session.gd` and `player.gd`, then confirm how `small_dungeon.gd` consumes that behavior.

### Dungeon And World

- Follow `dungeon/README.md` as the room authoring and generator rulebook.
- `res://dungeon/rooms/base/room_base.tscn` is the base room contract.
- `small_dungeon.gd` currently mixes generation, encounter flow, room transitions, camera, doors, coins, and multiplayer glue, so seemingly local changes can have broad side effects.

### Visuals And Equipment

- `player_visual.gd` is the main visual controller for runtime and editor preview behavior.
- The player visual already includes modular equipment attachment points for sword, chest, legs, helmet, and shield.
- Asset scale anchors, intake prompts, and audit commands live under `tools/asset_pipeline/`.

### Tools And Verification

- Common local multiplayer commands live in `tools/COMMANDS.md`.
- Preferred launch flow for multiplayer testing:
  - `.\tools\start_dedicated_server.ps1`
  - `.\tools\start_player_client.ps1`
  - `.\tools\tail_dedicated_log.ps1`
- Asset pipeline helpers:
  - `python tools/asset_pipeline/audit_glb.py --path ...`
  - `.\tools\capture_player_still.ps1 -Mode attack`
  - `.\tools\capture_player_clips.ps1 -Modes walk,attack`

## Working Agreements

- Check `git status --short` before editing and preserve unrelated local WIP.
- Treat `scripts/core/main.gd` as legacy sample scaffolding unless the task explicitly targets it.
- Do not casually delete or rewrite `tools/tmp_*` scripts; many are temporary debug helpers.
- When touching visuals/equipment, consider both runtime behavior and editor preview behavior.
- When touching multiplayer code, keep ownership checks explicit and avoid hidden singleplayer assumptions such as "first player node wins."

## Performance Checklist

Use this checklist whenever a task could affect runtime cost, load-time spikes, or network scale.

- Start with a budget. Name the expected player count, enemy count, projectile count, replicated actor count, and the smallest useful verification for the change.
- Treat `_process()` and `_physics_process()` code as hot paths. Before adding work there, ask whether it can be event-driven, throttled, cached, or limited to the authoritative peer only.
- Be suspicious of scene-tree scans in hot paths. Avoid spreading patterns like `get_tree().get_nodes_in_group(...)` across per-frame AI, combat, trap, UI, or world logic when a maintained roster/cache would work.
- Keep `small_dungeon.gd` lean during play. New roster checks, encounter checks, elevator checks, UI refreshes, or room queries should not quietly add more full scans every frame.
- Keep debug cost out of shipping behavior. Debug overlays, hitbox meshes, combat logs, and FPS labels should stay easy to disable and should not be used when judging gameplay performance.
- Budget replication deliberately. For new RPCs or replicated state, decide whether the data is reliable vs unreliable, event-driven vs periodic, authoritative-only vs all peers, and whether the payload can be reduced.
- Avoid high-frequency replication of derived state. Replicate compact authoritative facts, then let clients derive visuals locally when possible.
- Watch for allocation churn. Rebuilding meshes, allocating dictionaries/arrays, instantiating scenes, or formatting large debug strings inside hot loops should be treated as a performance smell.
- Prefer simple math in AI/combat loops. Favor squared-distance checks, direct nearest-candidate tracking, and early-outs over repeated sorting or broad candidate rebuilding.
- Separate steady-state cost from floor-build cost. `small_dungeon.gd` room generation and 3D visual assembly can tolerate some one-time work, but repeated `instantiate()` / `queue_free()` spikes should be watched as room detail grows.
- Be careful when adding projectiles, traps, coins, or temporary combat helpers. Large counts can multiply both server simulation cost and replication cost faster than expected.
- Profile dedicated server and client separately. A change can look smooth on one client while still making the authoritative server tick too expensive.
- Performance-sensitive validations should use release-like settings when possible: debug visuals off, expected player count, expected enemy density, and at least one worst-case combat room.
- If a task changes combat, AI, spawning, networking, dungeon generation, or visuals, the thread summary should briefly note the expected performance impact or explicitly say it was not measured yet.

## Local WIP Snapshot

Snapshot taken 2026-03-27; update this section when it becomes stale:

- Modified: `scenes/visuals/player_visual.tscn`
- Modified: `scripts/visuals/player_visual.gd`
- Untracked debug helpers:
  - `tools/tmp_convert_helmet_anchor.gd`
  - `tools/tmp_convert_helmet_anchor2.gd`
  - `tools/tmp_dump_attachment_runtime.gd`
  - `tools/tmp_dump_bone_axes.gd`
- Assume the above are user-owned unless the active task says otherwise.

## New-Thread Spin-Up Checklist

1. Read this `AGENTS.md`.
2. Read only the domain docs and files relevant to the task.
3. Check `git status --short` before making changes.
4. If the task touches runtime behavior, networking, combat, AI, spawning, or dungeon generation, skim the Performance Checklist and identify the likely hot path before editing.
5. Prefer the smallest verification command that matches the change.
6. If the task touches architecture, update the memory template section below before ending the thread.

Use these file groups as shortcuts:

- Networking tasks:
  - `dungeon/MULTIPLAYER_MILESTONE_MAP.md`
  - `scripts/network/network_session.gd`
  - `scripts/entities/player.gd`
  - `dungeon/game/small_dungeon.gd`
- Dungeon generation or encounter tasks:
  - `dungeon/README.md`
  - `dungeon/game/small_dungeon.gd`
  - `dungeon/game/components/*.gd`
  - `dungeon/modules/**/*.gd`
- Visual, animation, or equipment tasks:
  - `scripts/visuals/player_visual.gd`
  - `scenes/visuals/player_visual.tscn`
  - `tools/asset_pipeline/CODEX_THREAD_SUMMARY_2026-03-26.md`
  - `tools/animation_pipeline/README.md`

## Project Memory Template

Use or refresh this block after any substantial thread so the next thread has a warm start.

### Task Snapshot

- Date: 2026-03-28
- Goal: Add a first-version in-editor handcrafted room authoring plugin for `RoomBase` scenes, with sidecar layout resources, snapped placement, generated runtime markers, and a playtest harness.
- Why now: The project is pivoting from generic procedural room geometry toward handcrafted rooms plus later procedural floor assembly, and the team needed a practical Godot-native authoring workflow to build those rooms quickly.
- Relevant subsystem: Dungeon room authoring tools, `RoomBase` contract, generated sockets/zones/gameplay markers, editor UX, playtest workflow.
- Files likely involved: `addons/dungeon_room_editor/**/*`, `dungeon/rooms/base/room_base.gd`, `project.godot`, and asset references under `assets/structure/*` and `assets/props/*`.
- Constraints / must-not-break: Keep the existing `RoomBase` / `DoorSocket2D` / `ZoneMarker2D` contract intact, preserve user-owned WIP outside the addon, avoid replacing the runtime dungeon pipeline, and keep the tool data-driven so procedural assembly can consume it later.

### What Changed

- Files touched: Added `addons/dungeon_room_editor/` plugin scaffold, core controllers, docks, overlay, preview builder, playtest harness, resource scripts, and `default_room_piece_catalog.tres`; updated `dungeon/rooms/base/room_base.gd`; updated `project.godot` to enable the plugin by default.
- Behavior added or changed: Opening a `RoomBase` scene now enables a docked room editor with palette/properties/3D preview UI, a toolbar for place/select/erase/rotate, a sidecar `*.layout.tres` resource workflow, generated `Sockets/Zones/Gameplay/Visual3DProxy/GeneratedByRoomEditor` content, JSON import/export, and a “Play Test Current Room” launcher.
- Architectural decisions: The source of truth is `RoomLayoutData` plus `RoomPlacedItemData`, not hand-edited generated children; the palette is driven by an explicit `RoomPieceCatalog` resource, not runtime folder scans; authoring happens on a logical 2D grid while 3D preview stays a presentation layer; `RoomBase` now prefers generated sockets/zones when the editor has authored them.
- Commands run: `git status --short`; targeted `Get-Content` / `Select-String` reads across `dungeon/README.md`, `room_base.*`, marker scenes, addon scripts, and catalog resources; `.\tools\run_headless.ps1 -CheckOnly -Script res://dungeon/rooms/base/room_base.gd`; `res://addons/dungeon_room_editor/core/serializer.gd`; `res://addons/dungeon_room_editor/playtest/room_playtest_harness.gd`; `res://addons/dungeon_room_editor/plugin.gd`; `.\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe --headless --editor --path . --quit`; temporary headless smoke script that instantiated `room_base.tscn`, validated placement rules, synced generated nodes, and round-tripped JSON.
- Verification result: All targeted addon and `RoomBase` script checks passed, the project booted in headless editor mode with the plugin enabled and no plugin startup errors, and the smoke test printed `ROOM_EDITOR_SMOKE_OK` after validating door-boundary placement, generated container sync, and JSON import/export.

### Risks And Follow-Ups

- Known risks: The editor UX was smoke-tested headlessly but not manually exercised through full click/drag sessions inside the visual editor yet; the playtest harness assumes the existing player scene still works in a minimal non-lobby environment; the starter catalog is intentionally small and will need curation as more modular pieces are approved.
- Follow-up tasks: Open a real `RoomBase` scene in the editor and verify full click placement, drag-move, rotate, erase, and playtest flows; add more piece definitions to `default_room_piece_catalog.tres`; decide whether runtime-scene pieces also need mirrored 3D proxies in authored room scenes beyond the preview dock; consider a helper action for creating new room scenes with the expected contract and sidecar layout.
- Open questions: Whether `grid_size` should remain the layout’s gameplay tile step or be renamed later for clarity; whether room templates should eventually store explicit floor bounds separate from `RoomBase.room_size_tiles`; whether authored obstacle metadata should later feed nav/path validation directly.

### Next Best Prompt

- Paste-ready prompt for the next thread: "Open the new `dungeon_room_editor` plugin in Godot and do a full manual authoring pass on a `RoomBase` scene. Verify place/select/move/rotate/erase behavior, generated `Sockets/Zones/Gameplay/Visual3DProxy` sync, JSON export/import, and `Play Test Current Room`; fix any editor UX or runtime issues without replacing the `RoomLayoutData` sidecar workflow."

## Prompting Tips

- Name the subsystem and expected verification when possible.
- If a task spans player authority or combat replication, explicitly mention `player.gd`, `network_session.gd`, and `small_dungeon.gd`.
- If a task is local, name the target file directly and say what should not change around it.
