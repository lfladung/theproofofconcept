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
- A dedicated `Room Editor` main-screen plugin now exists for authoring handcrafted `RoomBase` scenes with sidecar layout resources, generated sockets/zones/gameplay markers, a live 3D preview, and a room playtest harness.

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

### Room Editor / Map Authoring

- The handcrafted room workflow lives under `res://addons/dungeon_room_editor/`.
- The editor is a main-screen `Room Editor` plugin, but it only meaningfully handles scenes whose root is `RoomBase`; non-`RoomBase` scenes should redirect back to `2D`.
- The source of truth is a sidecar `*.layout.tres` (`RoomLayoutData` + `RoomPlacedItemData`), not the generated scene children.
- Generated authoring output is synced into:
  - `Sockets/GeneratedByRoomEditor`
  - `Zones/GeneratedByRoomEditor`
  - `Gameplay/GeneratedByRoomEditor`
  - `Visual3DProxy/GeneratedByRoomEditor`
- The room editor now supports:
  - ground vs overlay placement layers
  - layer visibility filtering (`All`, `Ground`, `Overlay`)
  - brush paint and box paint
  - palette category filtering and 3D piece preview
  - detachable live 3D preview window
  - room playtest with the player spawned at room center and the gameplay camera rig
- `preview_builder.gd` is shared across room preview, generated scene visuals, and playtest visuals, so preview-material or transform changes there affect all three.
- Floor preview visuals currently remap common floor-piece families onto the runtime dungeon floor materials so the editor `3D` view, preview dock, and playtest read closer to the main game.
- `default_room_piece_catalog.tres` is generated from curated assets under `assets/structure/*` and `assets/props/*`; use `tools/room_editor/generate_default_room_piece_catalog.gd` when refreshing that catalog.

### Visuals And Equipment

- `player_visual.gd` is the main visual controller for runtime and editor preview behavior.
- The player visual already includes modular equipment attachment points for sword, chest, legs, helmet, and shield.
- Asset scale anchors, intake prompts, and audit commands live under `tools/asset_pipeline/`.

### Coordinate System (Read Before Adding Anything Positional)

The game uses **2D physics (CharacterBody2D)** for all gameplay logic and converts to 3D visuals at display time. Every position and direction lives in 2D game space until it hits a visual node.

**The canonical mapping:**

```
2D game space        →  3D world space
Vector2(x, y)        →  Vector3(x, height, y)
2D "up" (−Y)         →  3D −Z
2D "down" (+Y)       →  3D +Z
```

**Facing angle uses swapped `atan2` arguments everywhere — this is intentional:**

```gdscript
rotation.y = atan2(facing.x, facing.y)  # NOT the standard atan2(y, x)
```

The argument swap compensates for the Y↔Z axis remap so the character faces the right direction.

**The conversion helpers used throughout the codebase:**

```gdscript
# 2D game position → 3D world position
Vector3(pos2d.x, height, pos2d.y)

# 3D world position → 2D game position
Vector2(pos3d.x, pos3d.z)
```

**Rules for new code:**

- All gameplay logic (movement, combat, AI, grid math, hitboxes) works in 2D game space with `Vector2` / `Vector2i`.
- Only visual nodes (`player_visual.gd`, `enemy_state_visual.gd`, mesh helpers) work in 3D world space.
- Never feed a raw 3D world position into gameplay logic, and never feed a raw 2D game position into a 3D visual without going through the mapping above.
- If something spawns, fires, or moves in the wrong direction, the first thing to check is whether it bypassed the Y↔Z remap.

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
- Room editor helpers:
  - `.\tools\run_headless.ps1 -CheckOnly -Script res://addons/dungeon_room_editor/plugin.gd`
  - `.\tools\run_headless.ps1 -CheckOnly -Script res://addons/dungeon_room_editor/preview/preview_builder.gd`
  - `.\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/room_editor/generate_default_room_piece_catalog.gd`

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

---

### Task Snapshot

- Date: 2026-03-28
- Goal: Lay the groundwork for an affix-based equipment upgrade system and introduce the first in-world stat pickup object (stat pillar).
- Why now: The ideas docs (`ideas/GAMEPLAY_IDEAS.md`, `ideas/EQUIPMENT_UPGRADES.md`) define 7 affix types (Edge, Flow, Mass, Echo, Anchor, Phase, Surge) + secondaries. Before items with those affixes can exist, the stat vocabulary and a runtime bonus delivery mechanism had to be added.
- Relevant subsystem: Loadout/equipment data layer, player stat application, dungeon gameplay modules.
- Files likely involved: `scripts/loadout/loadout_constants.gd`, `scripts/entities/player.gd`, `dungeon/modules/gameplay/stat_pillar_2d.gd/.tscn`.
- Constraints / must-not-break: All existing item definitions and the `_apply_loadout_stats` flow must keep working; `_runtime_stat_bonuses` must survive a loadout re-apply without being wiped; server authority for the pillar hit must be respected in multiplayer.

### What Changed

- Files touched:
  - `scripts/loadout/loadout_constants.gd` — 7 new stat constants added (`crit_chance_bonus`, `attack_speed_multiplier`, `cooldown_reduction`, `knockback_multiplier`, `aoe_radius_bonus`, `lifesteal_percent`, `on_hit_slow_chance`), added to `STAT_ORDER`, two display-type arrays (`PERCENT_STATS`, `MULTIPLIER_STATS`) and updated `format_stat_modifier_lines` to format each correctly.
  - `scripts/entities/player.gd` — added `_runtime_stat_bonuses: Dictionary`; runtime bonuses are merged into the `totals` dict inside `_apply_loadout_stats` before any stat is calculated; added `receive_pillar_bonus(stat_key, amount)`, `_rpc_receive_pillar_bonus(...)` (RPC), and `_apply_runtime_stat_bonus(...)`.
  - `dungeon/modules/gameplay/stat_pillar_2d.gd` — new dungeon module; one-hit destroyable object; exports `bonus_stat_key` and `bonus_amount`; `is_damage_authority()` gates processing to server; on depletion, calls `receive_pillar_bonus` on `packet.source_node`; supports optional `pillar_3d_scene` export following the TrapTile2D mesh pattern.
  - `dungeon/modules/gameplay/stat_pillar_2d.tscn` — new scene; gold octagon Polygon2D placeholder visual; `Hurtbox` on collision layer 16 (same as enemy hurtboxes) so the player melee hitbox (mask 16) hits it with no collision mask changes; `StaticBody2D` layer 2 so players physically bump into it; `HealthComponent` (1 HP, 0 iframes); `DamageReceiver`.
- Behavior added or changed:
  - New stat vocabulary in the loadout system; existing items are unaffected (they use none of the new keys).
  - Runtime bonuses accumulate across pillar interactions in `_runtime_stat_bonuses` and persist until the player node is freed; they stack on top of loadout modifiers every time stats are recalculated.
  - Multiplayer flow: server processes the pillar hit → calls `receive_pillar_bonus` on the player node on the server → applies locally and RPCs to the owning peer client if they are different.
- Architectural decisions:
  - Runtime bonuses live in a separate dict from the loadout snapshot so reloading/changing equipment does not wipe them.
  - The pillar reuses the existing `Hitbox2D → Hurtbox2D → DamageReceiverComponent → HealthComponent` pipeline rather than inventing a new contact path.
  - Collision layer 16 was chosen for the pillar hurtbox because the player melee hitbox already scans that mask; no scene edits to player.tscn were required.
  - Stat display in the UI is controlled by `PERCENT_STATS` / `MULTIPLIER_STATS` arrays so each stat renders with the right suffix/format without special-casing every formatter call site.

### Risks And Follow-Ups

- Known risks: New stats (`crit_chance_bonus`, `attack_speed_multiplier`, etc.) are declared and accumulate but are not yet read anywhere in `player.gd` combat logic — they have no gameplay effect until Task 4 (hook new stats into player) is done.
- Follow-up tasks:
  - Task 2: Add `affix_type: StringName` field to `LoadoutItemDefinition` + `AFFIX_*` constants in `LoadoutConstants`.
  - Task 3: Create new item definitions per affix type in `loadout_repository.gd`.
  - Task 4: Wire `attack_speed_multiplier`, `cooldown_reduction`, `knockback_multiplier`, `aoe_radius_bonus`, `crit_chance_bonus`, `lifesteal_percent` into actual `player.gd` combat calculations.
  - Place a `stat_pillar_2d.tscn` instance in `small_dungeon.tscn` or a room scene for in-game testing.
  - Consider resetting `_runtime_stat_bonuses` between runs (likely in `small_dungeon.gd` when a new run starts or the player is re-initialized).
- Open questions: Should runtime bonuses reset between floors or persist for the whole run? Should the pillar emit a signal/particle effect on trigger for visual polish? Should multiple pillars of the same stat type stack or cap?

### Next Best Prompt

- Paste-ready prompt for the next thread: "Continue the affix/upgrade system from `ideas/GAMEPLAY_IDEAS.md` and `ideas/EQUIPMENT_UPGRADES.md`. Task 2: add an `affix_type` field and `AFFIX_*` constants to `scripts/loadout/loadout_constants.gd` and `scripts/loadout/loadout_item_definition.gd`. Task 3: create new item definitions in `scripts/loadout/loadout_repository.gd` for Edge/Flow/Mass variants of each equipment slot. Read `AGENTS.md` for full context on what was done in the 2026-03-28 session before making changes."

---

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

---

### Task Snapshot

- Date: 2026-03-29
- Goal: Extend the room editor so enemy spawn markers carry a first-class `enemy_id`, and expose one spawn marker palette entry per supported enemy type.
- Why now: The editor could place generic spawn markers and grouping metadata, but handcrafted encounters still could not author exact enemy types. The team wanted authored rooms to specify "spawn an Iron Sentinel here" directly instead of relying on vague spawn roles.
- Relevant subsystem: Room editor data model, palette/catalog resources, scene sync, zone marker metadata, playtest harness.
- Files likely involved: `addons/dungeon_room_editor/resources/*.gd`, `addons/dungeon_room_editor/resources/default_room_piece_catalog.tres`, `addons/dungeon_room_editor/core/{placement_controller,serializer,scene_sync}.gd`, `addons/dungeon_room_editor/docks/properties_dock.*`, `addons/dungeon_room_editor/plugin.gd`, `addons/dungeon_room_editor/playtest/room_playtest_harness.gd`, `dungeon/metadata/zone_marker_2d.gd`.
- Constraints / must-not-break: Preserve the existing `RoomLayoutData` sidecar workflow, keep generic room piece placement/editing unchanged, do not break generated `ZoneMarker2D` runtime contracts, and avoid adding steady-state runtime cost to the main dungeon flow.

### What Changed

- Files touched:
  - `addons/dungeon_room_editor/resources/room_piece_definition.gd` and `room_placed_item_data.gd` now support `enemy_id`, with helper methods for enemy-spawn markers and fallback/default resolution.
  - `addons/dungeon_room_editor/core/placement_controller.gd`, `serializer.gd`, and `scene_sync.gd` now seed, persist, export/import, and sync `enemy_id` onto generated runtime markers and item metadata.
  - `addons/dungeon_room_editor/docks/properties_dock.gd/.tscn` and `plugin.gd` now expose an `Enemy ID` field for selected enemy spawn markers and save edits back into the layout item.
  - `addons/dungeon_room_editor/resources/default_room_piece_catalog.tres` now includes dedicated palette entries for Dasher, Arrow Tower, Iron Sentinel, and Robot Mob spawn markers.
  - `dungeon/metadata/zone_marker_2d.gd` now exports `enemy_id` and includes it in zone metadata.
  - `addons/dungeon_room_editor/playtest/room_playtest_harness.gd` now spawns authored enemies from `enemy_spawn` markers using `enemy_id` so room playtests reflect the authored marker type.
- Behavior added or changed:
  - Enemy spawn markers can now carry a specific enemy identifier instead of only generic role/tag metadata.
  - Newly placed enemy-specific spawn markers inherit a default `enemy_id` from their catalog piece, while still allowing per-marker override in the properties dock.
  - JSON export/import round-trips `enemy_id`, and generated `ZoneMarker2D` nodes now expose it to downstream consumers.
  - The room editor palette shows dedicated spawn entries for the currently supported enemy roster (`dasher`, `arrow_tower`, `iron_sentinel`, `robot_mob`).
- Architectural decisions:
  - `enemy_id` lives both on the piece definition (default) and the placed item (override), with the placed item treated as source of truth when set.
  - The generated runtime node contract was extended by enriching `ZoneMarker2D` metadata rather than introducing a separate authored-only spawn node type.
  - The change stays event-driven/editor-time only for normal authoring flow; no new per-frame room-editor or runtime dungeon scans were added outside the existing playtest harness setup step.

### Risks And Follow-Ups

- Known risks: The palette roster is manually curated, so newly added enemy scenes will not appear automatically until the catalog is updated; the playtest harness mapping currently covers the four known authored enemy ids only; the editor flow was validated headlessly but not yet through a full manual click-through in the visual editor.
- Follow-up tasks:
  - Do a manual Godot editor pass to verify selecting each new spawn marker, editing `Enemy ID`, saving/reopening the room, and playtesting the authored enemy placement.
  - Decide whether room/runtime generation outside the playtest harness should consume `zone.enemy_id` directly for authored encounters.
  - Consider replacing the freeform `Enemy ID` text field with an enum/dropdown sourced from a shared enemy registry to reduce typo risk.
- Open questions: Should the generic melee spawn marker remain in the default catalog once enemy-specific markers are standard? Should enemy ids be centralized in a shared constants file so the room editor and dungeon runtime cannot drift?

### Next Best Prompt

- Paste-ready prompt for the next thread: "Open a `RoomBase` scene in the room editor and manually validate the new enemy spawn marker workflow. Place each enemy-specific spawn marker, confirm the `Enemy ID` property behaves correctly, export/import JSON, run `Play Test Current Room`, and fix any editor/runtime issues without replacing the `RoomLayoutData` sidecar model."

---

### Task Snapshot

- Date: 2026-03-29
- Goal: Iterate on the new map editor so it is practical for daily handcrafted-room authoring: dedicated main-screen tab, layer-aware editing, better preview fidelity, larger palette/catalog coverage, and a more reliable playtest flow.
- Why now: The first-pass room editor existed, but real manual use immediately exposed friction around viewport conflicts, preview accuracy, collision, scale, and authoring ergonomics. The team needed the tool to feel trustworthy enough for actual room production rather than only proof-of-concept demos.
- Relevant subsystem: `addons/dungeon_room_editor/**/*`, `dungeon/rooms/base/room_base.gd`, authored room scenes/layouts, player scale/presentation, room playtest workflow.
- Files likely involved: `addons/dungeon_room_editor/plugin.gd`, `main_screen/*`, `docks/*`, `core/{scene_sync,serializer,playtest_launcher}.gd`, `preview/preview_builder.gd`, `playtest/room_playtest_harness.gd`, `resources/default_room_piece_catalog.tres`, `tools/room_editor/generate_default_room_piece_catalog.gd`, `scenes/entities/player.tscn`, `scenes/visuals/player_visual.tscn`.
- Constraints / must-not-break: Keep the sidecar `RoomLayoutData` workflow, preserve `RoomBase`/`DoorSocket2D`/`ZoneMarker2D` compatibility, keep generated editor nodes one-way/regenerable, and avoid replacing the main dungeon runtime with editor-only logic.

### What Changed

- Files touched:
  - `addons/dungeon_room_editor/main_screen/*` now owns the authoring workspace as a dedicated `Room Editor` main-screen tab rather than piggybacking on the stock `2D` canvas.
  - `addons/dungeon_room_editor/plugin.gd`, `core/editor_session.gd`, `core/scene_sync.gd`, `docks/*`, and `preview/preview_builder.gd` were iterated heavily for editor UX, preview sync, and popout-window behavior.
  - `addons/dungeon_room_editor/resources/default_room_piece_catalog.tres` was expanded to include the approved placeable assets under `assets/structure/floors`, `assets/structure/walls`, and `assets/props`, and `tools/room_editor/generate_default_room_piece_catalog.gd` was added to regenerate that catalog.
  - `addons/dungeon_room_editor/playtest/room_playtest_harness.gd/.tscn` was updated so authored room playtests use the gameplay camera style and spawn the player at the room center.
  - `dungeon/rooms/base/room_base.gd` was adjusted to behave better in editor tool mode and to reduce noisy template-validation warnings during authoring.
  - `scenes/entities/player.tscn` and `scenes/visuals/player_visual.tscn` were adjusted so the knight reads closer to a one-tile actor in authored rooms.
- Behavior added or changed:
  - The room editor now has layer-aware placement with `ground` vs `overlay`, layer visibility filtering, brush paint, box paint, category-filtered palette browsing, a 3D piece preview, and a detachable live 3D preview window.
  - Place/erase/selection flows were hardened: drag painting fills lines, box paint fills rectangles, out-of-bounds placement is ignored quietly, and typed property fields no longer reset the caret on each keystroke.
  - Generated room visuals and preview framing were stabilized: preview-root drift was fixed, generated 3D containers are rebuilt more cleanly, and popout preview window handling uses current Godot APIs.
  - The playtest harness now uses the room-center spawn plus gameplay-style camera rig, and room collision fallback/wall shell behavior was improved for authored-room iteration.
  - Palette preview and room preview lighting were aligned to the main dungeon scene, and common floor-piece families now remap onto runtime dungeon floor materials so the editor 3D view and playtest look closer to gameplay.
  - The nested `_godot_sanity/project.godot` was renamed out of the way (`project_godot_snapshot.txt`) so the main editor no longer warns about a nested Godot project on startup.
- Architectural decisions:
  - The dedicated main-screen editor was chosen over more `2D`-viewport hooks because it avoids fighting the stock scene tabs/toolbar and gives room for palette, canvas, properties, and live 3D preview together.
  - Preview fidelity fixes were concentrated in `preview_builder.gd` and the preview docks so room visuals, preview docks, and playtest reuse the same transform/material logic wherever possible.
  - Layering was kept intentionally simple for V1: `ground` for floors, `overlay` for walls/doors/props/markers, with selection preferring visible-layer content.

### Risks And Follow-Ups

- Known risks: Floor-material remapping currently targets the common dirt/metal/grate families only; `wood` and `foundation` floors still use their original asset materials. The room editor has been exercised through many targeted fixes, but it still needs longer manual production use to flush out remaining edge cases in stacked selection, room-size scaling, and preview fidelity.
- Follow-up tasks:
  - Add better stacked-item selection, likely click-to-cycle, for cells containing both ground and overlay content.
  - Consider a shared registry for floor visual themes so runtime dungeon generation and room-editor previews cannot drift.
  - Decide whether authored floor pieces should eventually carry explicit visual-theme metadata instead of relying on filename-based material remapping.
  - Continue manual authoring passes in Godot to catch any remaining 3D preview drift, playtest edge cases, or catalog curation gaps.
- Open questions: Whether the room editor should eventually create new room scenes from a guided wizard; whether floor-theme choice belongs at room level or piece level; whether the plugin should expose a stricter edit-layer lock in addition to the current view filter.

### Next Best Prompt

- Paste-ready prompt for the next thread: "Open a real authored `RoomBase` scene in the `Room Editor` tab and do a full manual room-building pass using the expanded asset palette. Verify layer filtering, box paint, popout 3D preview, generated `Visual3DProxy` sync, floor-material remapping, and `Play Test Current Room`; fix any remaining UX or preview mismatches without replacing the `RoomLayoutData` sidecar model."

---

### Task Snapshot

- Date: 2026-03-29
- Goal: Create the first reusable handcrafted room-outline library for later procedural floor assembly, using the `Room Editor` / `RoomBase` authored-layout workflow.
- Why now: The project has the editor and room contract in place, but it still needed an actual starter room kit to feed later procedural floor assembly and to validate that the tool can produce reusable gameplay spaces rather than one-off experiments.
- Relevant subsystem: Room authoring pipeline, `RoomBase` metadata contract, `RoomLayoutData` sidecars, room-editor catalog resources, generated sockets/zones/gameplay/visual roots.
- Files likely involved: `dungeon/rooms/authored/outlines/*`, `tools/room_editor/generate_outline_rooms.gd`, `tools/room_editor/validate_outline_rooms.gd`, `addons/dungeon_room_editor/resources/default_room_piece_catalog.tres`.
- Constraints / must-not-break: Keep the authored-layout sidecar workflow intact, preserve the existing `RoomBase` / generated-root contract, avoid hand-editing `GeneratedByRoomEditor` nodes, and keep room shapes readable from the fixed gameplay camera.

### What Changed

- Files touched:
  - Added `tools/room_editor/generate_outline_rooms.gd` to generate the first room-outline batch from declarative archetype specs.
  - Added `tools/room_editor/validate_outline_rooms.gd` to load/instantiate/verify the generated room scenes and their authored-layout metadata.
  - Extended `addons/dungeon_room_editor/resources/default_room_piece_catalog.tres` with structural marker entries (`encounter_entry_marker`, `prop_placement_marker`, `nav_boundary_marker`, `loot_marker`) plus a `hall_socket_double` logical socket piece for 2-tile-wide hallway exits.
  - Created `res://dungeon/rooms/authored/outlines/` with nine authored rooms and matching sidecar layouts:
    - `room_combat_skirmish_small_a`
    - `room_combat_tactical_medium_a`
    - `room_arena_wave_large_a`
    - `room_connector_narrow_medium_a`
    - `room_connector_turn_medium_a`
    - `room_connector_junction_medium_a`
    - `room_treasure_reward_small_a`
    - `room_chokepoint_gate_medium_a`
    - `room_boss_approach_large_a`
- Behavior added or changed:
  - The room-editor catalog now has enough structural marker vocabulary to author room outlines entirely through authored layout items instead of relying on the base template’s default zone setup.
  - Outline rooms now use consistent 2-tile-wide hallway exits and generated double-width logical sockets at those exits, while keeping art dressing intentionally sparse.
  - The generator stamps in floor/wall outlines, minimal blockers, structural markers, and encounter markers according to room archetype.
- Architectural decisions:
  - The first outline batch is generated from a declarative helper script so the rooms stay metrically consistent and can be regenerated/tuned later instead of becoming nine disconnected one-off edits.
  - Structural zone markers are first-class room-editor pieces because `RoomBase` validation expects them and future procedural assembly should be able to consume them from the same authored-layout source of truth.
  - “No explicit doors yet” was interpreted as “use clean hallway openings plus logical sockets,” not as “fall back to the base template’s default 4-socket setup.”
- Commands run:
  - `git status --short`
  - targeted `Get-Content` / `Select-String` reads across `room_base.*`, room-editor serializer/scene-sync/catalog files, and existing authored-room assets
  - `.\tools\run_headless.ps1 -CheckOnly -Script res://tools/room_editor/generate_outline_rooms.gd`
  - `Godot ... --headless --path . --script res://tools/room_editor/generate_outline_rooms.gd`
  - `.\tools\run_headless.ps1 -CheckOnly -Script res://tools/room_editor/validate_outline_rooms.gd`
  - `Godot ... --headless --path . --script res://tools/room_editor/validate_outline_rooms.gd`
  - `Godot ... --headless --editor --path . --quit`
- Verification result:
  - The generator and validator scripts parse successfully.
  - All nine room scenes were generated with sidecar layouts.
  - Headless validation successfully instantiated every generated scene as `RoomBase` and confirmed non-empty authored layouts plus generated sockets/zones. Reported counts:
    - `room_combat_skirmish_small_a`: 133 items, 2 sockets, 5 zones
    - `room_combat_tactical_medium_a`: 295 items, 3 sockets, 6 zones
    - `room_arena_wave_large_a`: 656 items, 2 sockets, 8 zones
    - `room_connector_narrow_medium_a`: 180 items, 2 sockets, 4 zones
    - `room_connector_turn_medium_a`: 102 items, 2 sockets, 4 zones
    - `room_connector_junction_medium_a`: 155 items, 3 sockets, 4 zones
    - `room_treasure_reward_small_a`: 132 items, 1 socket, 5 zones
    - `room_chokepoint_gate_medium_a`: 189 items, 2 sockets, 6 zones
    - `room_boss_approach_large_a`: 423 items, 2 sockets, 5 zones

### Risks And Follow-Ups

- Known risks:
  - The generated `.tscn` files are explicit packed `RoomBase` scenes rather than clean inherited-scene serializations of `room_base.tscn`; functionally they still instantiate as `RoomBase`, but if preserving inherited serialization matters later they should be re-saved through the editor or a dedicated inherited-scene writer.
  - The headless validation scripts emit small engine leak warnings on exit after instantiating many resources; the room scenes still validated, but those scripts are best treated as generation/validation utilities rather than frequent runtime tooling.
  - The room shapes are intentionally simple outline grammar; they are good procedural seeds, not final dressed content.
- Follow-up tasks:
  - Open the new rooms in the `Room Editor` and do a visual/manual pass on readability, wall silhouette, spawn spacing, and hallway feel.
  - Run `Play Test Current Room` on the representative rooms called out in the outline plan and tune any one-tile-movement or camera-readability issues.
  - Decide whether to keep the generator as the canonical source for this first outline batch or transition these rooms into manual per-room edits now that the library exists.
  - If desired, add more logical socket variants later (corners, vertical stacks, wider halls) rather than overloading the single `hall_socket_double` piece.
- Open questions:
  - Should the project eventually prefer true inherited-scene serialization for authored rooms, or is the current explicit `RoomBase` scene format acceptable for tool-generated content?
  - Should connector/treasure rooms continue carrying a minimal `enemy_spawn` marker purely for contract coverage, or should `RoomBase` validation become role-aware so non-combat rooms can omit combat markers cleanly?

### Next Best Prompt

- Paste-ready prompt for the next thread: "Open the new room-outline library under `res://dungeon/rooms/authored/outlines/` in the Room Editor and do a manual design pass. Playtest `room_combat_skirmish_small_a`, `room_arena_wave_large_a`, `room_connector_turn_medium_a`, and `room_treasure_reward_small_a`; tune any wall/floor silhouette, hallway opening, marker placement, or blocker issues without replacing the authored-layout sidecar workflow or the outline generator helpers."

## Prompting Tips

- Name the subsystem and expected verification when possible.
- If a task spans player authority or combat replication, explicitly mention `player.gd`, `network_session.gd`, and `small_dungeon.gd`.
- If a task is local, name the target file directly and say what should not change around it.
