# AGENTS.md

## Repo Purpose

- Godot 4.6 project converting a prototype into a 2-4 player authoritative co-op dungeon crawler.
- The active user flow starts in `res://scenes/ui/lobby_menu.tscn`, not the old singleplayer sample flow.
- The main gameplay runtime is `res://dungeon/game/dungeon_orchestrator.tscn`.
- `project.godot` now uses the current project identity (`The Proof of Concept`); code and docs remain the source of truth for gameplay direction.

## Read First

Read the smallest relevant set before editing:

- Current roadmap: `ideas/MILESTONES_v2.md`
- Completed/sunset multiplayer roadmap and status: `ideas/sunset/MULTIPLAYER_MILESTONE_MAP.md`
- Dungeon architecture and room rulebook: `dungeon/README.md`
- Common launch and verification commands: `tools/COMMANDS.md`
- Asset and equipment pipeline snapshot: `tools/asset_pipeline/CODEX_THREAD_SUMMARY_2026-03-26.md`
- Gameplay and upgrade design (when changing affixes, economy, pillars): `ideas/GAMEPLAY_IDEAS.md`, `ideas/EQUIPMENT_UPGRADES.md`

## Runtime Entrypoints

- Main scene: `res://scenes/ui/lobby_menu.tscn`
- Lobby controller: `res://scripts/ui/lobby_menu.gd`
- Core world orchestration: `res://dungeon/game/dungeon_orchestrator.gd` (extends `dungeon_orchestrator_internals.gd`)
- Player gameplay and networking: `res://scripts/entities/player.gd`
- Player 3D presentation and modular equipment: `res://scripts/visuals/player_visual.gd` (extends `player_visual_internals.gd`)
- Autoloads in `project.godot` (see file for order):
  - `GameSettings = res://scripts/settings/game_settings.gd`
  - `LoadingOverlay = res://scripts/ui/loading_overlay.gd`
  - `NetworkSession = res://scripts/network/network_session.gd`
  - `NetEventBus = res://scripts/network/net_event_bus.gd`
  - `RunState = res://scripts/network/run_state.gd`

## Current Project Snapshot

As of 2026-04-11 (bump this date when you materially change this section):

- `ideas/MILESTONES_v2.md` is the active roadmap for hub, mission select, upgrade UI, gems/socketing, mini-hubs, authored encounter composition, reward-drop replacement, naming, and display polish.
- Project identity metadata and the lobby title now use `The Proof of Concept`.
- Multiplayer milestones 1-9 are complete per `ideas/sunset/MULTIPLAYER_MILESTONE_MAP.md`.
- Dedicated server: session boot, registry/session-code scaffold, and client join-by-code are in place (DS milestones 1-3); external matchmaker/allocator and reconnect-token run handoff remain future work (DS 4-5).
- Melee already has owner-client request -> server validation -> replicated event flow.
- Sword blocking now uses a server-authoritative directional stamina guard: front-blocked hostile hits drain stamina instead of HP, and stamina regen is delayed after use/break.
- Lobby/session-code flow and peer-slot mapping are implemented.
- `dungeon_orchestrator.gd` is session-aware and manages roster, encounter state, doors, coins, camera, and replication helpers.
- A dedicated `Room Editor` main-screen plugin now exists for authoring handcrafted `RoomBase` scenes with sidecar layout resources, generated sockets/zones/gameplay markers, a live 3D preview, and a room playtest harness.
- Stat pillars (`dungeon/modules/gameplay/stat_pillar_2d.gd`) grant server-authoritative runtime bonuses merged in `player.gd`; several new stat keys exist in `scripts/loadout/loadout_constants.gd` but are not necessarily consumed by combat math yet (affix items / full wiring: see `ideas/EQUIPMENT_UPGRADES.md`).
- A reusable authored outline library lives under `dungeon/rooms/authored/outlines/` with generator/validator helpers in `tools/room_editor/generate_outline_rooms.gd` and `tools/room_editor/validate_outline_rooms.gd`.
- Enemy families now share more of their common target-refresh and single-model visual-state wiring through `scripts/entities/enemy_base.gd`; when adding a new Flow/Mass/Edge variant, prefer family or base helpers over copy-pasting per-enemy plumbing.

## Subsystem Notes

### Networking

- The project uses an authoritative server model for 2-4 players.
- `NetworkSession` owns session lifecycle, lobby state, registry/session-code lookups, peer slots, readiness, and host/client/dedicated-server roles.
- `Player` owns authority assignment, prediction/reconciliation, weapon mode state, and combat request sequencing.
- Guard-aware hostile damage should call `Player.take_attack_damage(...)`; direct environmental damage should stay on `take_damage(...)`.
- If a change affects replication or player authority, inspect both `network_session.gd` and `player.gd`, then confirm how `dungeon_orchestrator.gd` consumes that behavior.

### Dungeon And World

- Follow `dungeon/README.md` as the room authoring and generator rulebook.
- `res://dungeon/rooms/base/room_base.tscn` is the base room contract.
- `dungeon_orchestrator_internals.gd` currently mixes generation, encounter flow, room transitions, camera, doors, coins, and multiplayer glue, so seemingly local changes can have broad side effects.
- Do not bulk-read `dungeon/rooms/authored/` unless the task explicitly edits or validates specific room assets; those trees are large packed scenes/resources. Prefer contract scripts, `dungeon/README.md`, room-editor code, and orchestrator/query services (see **Context hygiene** under Working Agreements).

### Enemy Families And Combat AI

- Start enemy work with `scripts/entities/enemy_base.gd`, then read the narrowest family root (`mob.gd` / `arrow_tower.gd` / `edge_lunge_mob.gd` / `flow_model_dasher_mob.gd` / specific Mass family root) before opening leaf variants.
- Shared behaviors such as target refresh cadence, reusable visual-state config, replication helpers, knockback timers, and roster queries should live in `enemy_base.gd` or the nearest family base, not duplicated across leaf enemy scripts.
- Flow-family dashers should keep their common chase/dash/telegraph loop in `mob.gd`/`flow_model_dasher_mob.gd`; Edge variants should usually be data/model overrides on top of that rather than re-implementations.
- When reviewing a new enemy, look for duplicate `_refresh_target_player`, `_build_visual_state_config`, nav chase, telegraph mesh setup, and wall-hit reset code before adding new branches.
- Enemy gameplay remains 2D-authoritative. Only `enemy_state_visual.gd`, telegraph meshes, and other presentation helpers should convert into 3D world space.

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

- `player_visual_internals.gd` holds most presentation logic; `player_visual.gd` adds the per-frame `_process` tick (editor preview, bone follow, smear).
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

### Meta-Progression And Inventory

- `MetaProgressionStore` is an autoload Node — all gear/gem/material reads and writes go through it. Never mutate `GearItemData` fields directly outside of `MetaProgressionStore` methods.
- Gear tiers (1–3), pillar alignment, familiarity XP, and promotion progress live on `GearItemData` instances, not on item definitions. The base item definition (`LoadoutItemDefinition`) stays tier-agnostic; stats scale at runtime via `tier_stat_multiplier * (1 + familiarity_bonus) * tempering_multiplier`.
- `TemperingManager` is run-scoped (`RefCounted`, not an autoload). The orchestrator creates it at run start, passes it to `LoadoutRepository` via `set_tempering_manager`, and all calls on it use `.call(&"method")` because the variable is typed as `RefCounted`.
- `LoadoutRepository.ensure_owner_initialized` checks `MetaProgressionStore.is_initialized` first — if meta data exists, only owned gear appears in the in-run panel. Equipping during a run calls `_sync_equip_to_meta_store` so the choice persists.
- Item display names: single source of truth is `LoadoutConstants.ITEM_DISPLAY_NAMES` dict + `item_display_name(item_id)` helper. When adding new items, update both `ITEM_DISPLAY_NAMES` and `LoadoutRepository._build_default_definitions`.
- Persistence: `user://meta_progression_{player_id}.json`. Delete this file to regenerate starter state (T1 + T2 + T3 per slot). `apply_server_state()` is the future server-authority deserialization entry point.
- Inventory UI lives in `scripts/ui/inventory/inventory_screen.gd` (built entirely in code). The lobby shows it as a full-screen overlay toggled by `_showing_inventory` in `lobby_menu.gd`.

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

### Context hygiene (read order)

- **Default:** Do not open, glob-scan, or read whole trees under `dungeon/rooms/authored/` (including `outlines/`) unless the task explicitly edits a named room, validates a specific scene, or debugs layout sync for that asset.
- **Prefer for room behavior:** `dungeon/rooms/base/room_base.gd`, `dungeon/metadata/zone_marker_2d.gd`, `dungeon/README.md`, `addons/dungeon_room_editor/`, `dungeon/game/dungeon_orchestrator_internals.gd`, `dungeon/game/components/room_query_service.gd`, and `tools/room_editor/generate_outline_rooms.gd` / `validate_outline_rooms.gd` instead of raw `.tscn` text.
- **If one room artifact is needed:** read a single representative `.tscn` or sidecar `*.layout.tres` for shape, not a batch.
- **In general:** treat other generated or packed Godot assets (huge `.tscn`, large `.tres`, big catalogs) the same way — prefer scripts, small excerpts, and targeted search unless the task is asset-specific.

## Performance Checklist

Use this checklist whenever a task could affect runtime cost, load-time spikes, or network scale.

- Start with a budget. Name the expected player count, enemy count, projectile count, replicated actor count, and the smallest useful verification for the change.
- Treat `_process()` and `_physics_process()` code as hot paths. Before adding work there, ask whether it can be event-driven, throttled, cached, or limited to the authoritative peer only.
- Be suspicious of scene-tree scans in hot paths. Avoid spreading patterns like `get_tree().get_nodes_in_group(...)` across per-frame AI, combat, trap, UI, or world logic when a maintained roster/cache would work.
- Keep `dungeon_orchestrator_internals.gd` lean during play. New roster checks, encounter checks, elevator checks, UI refreshes, or room queries should not quietly add more full scans every frame.
- Keep debug cost out of shipping behavior. Debug overlays, hitbox meshes, combat logs, and FPS labels should stay easy to disable and should not be used when judging gameplay performance.
- Budget replication deliberately. For new RPCs or replicated state, decide whether the data is reliable vs unreliable, event-driven vs periodic, authoritative-only vs all peers, and whether the payload can be reduced.
- Avoid high-frequency replication of derived state. Replicate compact authoritative facts, then let clients derive visuals locally when possible.
- Watch for allocation churn. Rebuilding meshes, allocating dictionaries/arrays, instantiating scenes, or formatting large debug strings inside hot loops should be treated as a performance smell.
- Prefer simple math in AI/combat loops. Favor squared-distance checks, direct nearest-candidate tracking, and early-outs over repeated sorting or broad candidate rebuilding.
- Separate steady-state cost from floor-build cost. `dungeon_orchestrator_internals.gd` room generation and 3D visual assembly can tolerate some one-time work, but repeated `instantiate()` / `queue_free()` spikes should be watched as room detail grows.
- Be careful when adding projectiles, traps, coins, or temporary combat helpers. Large counts can multiply both server simulation cost and replication cost faster than expected.
- Profile dedicated server and client separately. A change can look smooth on one client while still making the authoritative server tick too expensive.
- Performance-sensitive validations should use release-like settings when possible: debug visuals off, expected player count, expected enemy density, and at least one worst-case combat room.
- If a task changes combat, AI, spawning, networking, dungeon generation, or visuals, the thread summary should briefly note the expected performance impact or explicitly say it was not measured yet.

### Current Performance Watchouts

- Treat `dungeon/game/components/room_query_service.gd` as a shared hot-path service. Do not reintroduce room-wide or cell-wide scans for every point query; prefer cache invalidation, last-hit reuse, or spatial indexing.
- Treat `scripts/ui/minimap_panel.gd` as cached UI, not live geometry generation. Room geometry should be rebuilt only when the room layout changes; player-marker updates should be throttled rather than forcing a full redraw every frame.
- Keep `dungeon/game/dungeon_orchestrator_internals.gd` maintenance work on intervals or events. Encounter cleanup, revive/wipe checks, elevator boarding checks, info-label refreshes, and authored-room visual streaming should not quietly drift back into unconditional every-frame scans.
- For authored-room visual streaming, prefer spatial bucketing or another nearby-room filter before iterating room visuals. As the authored room library grows, “scan every room and test bounds” stops scaling well.
- In `scripts/entities/player.gd`, treat mouse-to-world projection and UI hover queries as per-frame cache candidates. Reuse results inside the same physics frame instead of asking the viewport repeatedly through helper chains.
- Avoid rebuilding `ImmediateMesh` telegraphs during active combat in enemy scripts. Prefer prebuilt meshes, cached step variants, or simple decals/sprites that only update transform/visibility.
- Be conservative with `FakeShadow3D`. New users of `scripts/entities/fake_shadow_3d.gd` should justify their update frequency, and low-value actors should stay shadow-free by default.
- When adding combat visuals, ask whether the effect belongs in the live game at all distances. Enemy visuals, props, and telegraphs should support low-detail or streamed behavior before the project scales up to denser fights.
- Prefer caches that invalidate explicitly when dungeon rooms regenerate, room trees change, or encounter rosters change. Hidden stale-cache bugs are bad, but hidden per-frame scans are usually worse.
- If a future prompt asks for new UI, debug, AI, encounter, room, or visual behavior, include one sentence up front about where the likely hot path lives before editing.
- Enemy AI hot path: avoid adding fresh per-frame target scans, telegraph mesh rebuilds, or repeated state-dictionary churn across multiple enemy leaf scripts when a shared helper or cached family path would do.

## Local WIP Snapshot

Do not keep a frozen file list here (it goes stale). When editing `AGENTS.md`, run `git status --short` and treat unrelated modified/untracked files as user-owned WIP unless the active task says otherwise. Assume `tools/tmp_*` helpers are user-owned.

## New-Thread Spin-Up Checklist

1. Read this `AGENTS.md`.
2. Read only the domain docs and files relevant to the task.
3. Check `git status --short` before making changes.
4. If the task touches runtime behavior, networking, combat, AI, spawning, or dungeon generation, skim the Performance Checklist and identify the likely hot path before editing.
5. Prefer the smallest verification command that matches the change.
6. If the task touches architecture, update the memory template section below before ending the thread.

Use these file groups as shortcuts:

- Networking tasks:
  - `ideas/sunset/MULTIPLAYER_MILESTONE_MAP.md`
  - `scripts/network/network_session.gd`
  - `scripts/entities/player.gd`
  - `dungeon/game/dungeon_orchestrator_internals.gd`
- Dungeon generation or encounter tasks:
  - `dungeon/README.md`
  - `dungeon/game/dungeon_orchestrator_internals.gd`
  - `dungeon/game/components/*.gd`
  - `dungeon/modules/**/*.gd`
- Enemy / combat AI tasks:
  - `scripts/entities/enemy_base.gd`
  - `scripts/entities/mob.gd`
  - `scripts/entities/arrow_tower.gd`
  - `scripts/entities/flow_model_dasher_mob.gd`
  - `scripts/entities/edge_lunge_mob.gd`
  - specific leaf enemy script(s) being changed
  - `scripts/visuals/enemy_state_visual.gd`
- Visual, animation, or equipment tasks:
  - `scripts/visuals/player_visual.gd`
  - `scenes/visuals/player_visual.tscn`
  - `tools/asset_pipeline/CODEX_THREAD_SUMMARY_2026-03-26.md`
  - `tools/animation_pipeline/README.md`
- Loadout, stat bonuses, pillars:
  - `scripts/loadout/loadout_constants.gd`
  - `scripts/loadout/loadout_item_definition.gd`
  - `scripts/loadout/loadout_repository.gd`
  - `scripts/entities/player.gd`
  - `dungeon/modules/gameplay/stat_pillar_2d.gd`
  - `ideas/GAMEPLAY_IDEAS.md`, `ideas/EQUIPMENT_UPGRADES.md`
- Meta-progression / inventory tasks:
  - `scripts/meta_progression/meta_progression_constants.gd` — thresholds, multipliers, cost tables
  - `scripts/meta_progression/meta_progression_store.gd` — autoload; all gear/gem/material mutations
  - `scripts/meta_progression/gear_item_data.gd` — owned gear instance (tier, pillar, familiarity, promotion)
  - `scripts/meta_progression/gem_item_data.gd` — gem instance (pillar, effect, durability)
  - `scripts/meta_progression/tempering_manager.gd` — run-scoped RefCounted; tempering XP tracking
  - `scripts/ui/inventory/inventory_screen.gd` — full-screen lobby inventory overlay
  - `scripts/ui/lobby_menu.gd` — hosts inventory screen, visibility toggling
  - `scripts/loadout/loadout_repository.gd` — also owns meta-store sync on equip
  - `ideas/META_PROGRESSION.md`, `ideas/INVENTORY.md`

## Project Memory Template

Use or refresh this block after any substantial thread so the next thread has a warm start.

### Recently landed (rolling)

Update this list when something materially ships; prefer pointers to docs and scripts over long narratives.

- Boss rooms: authored `floor_exit` zone marker + Room Editor auto-stamp; runtime prefers marker via `RoomQueryService`, with legacy placement fallback (`dungeon/metadata/zone_marker_2d.gd`, `dungeon/rooms/base/room_base.gd`, `dungeon/game/components/room_query_service.gd`, `addons/dungeon_room_editor/`).
- Stat pillars: `dungeon/modules/gameplay/stat_pillar_2d.gd` applies server-authoritative runtime bonuses merged in `player.gd` (`_runtime_stat_bonuses`); extra stat keys live in `scripts/loadout/loadout_constants.gd` — affix item types (`affix_type` / `AFFIX_*`) and full combat wiring are still future work per `ideas/EQUIPMENT_UPGRADES.md`.
- Room editor: main-screen **Room Editor** tab, sidecar `*.layout.tres`, generated roots under `Sockets/Zones/Gameplay/Visual3DProxy/GeneratedByRoomEditor`; enemy spawn markers carry `enemy_id` on `ZoneMarker2D`.
- Authored outline starter kit: `dungeon/rooms/authored/outlines/` (nine rooms) with `tools/room_editor/generate_outline_rooms.gd` and `validate_outline_rooms.gd`.
- Roadmap: `ideas/MILESTONES_v2.md` is active; sunset milestone docs live under `ideas/sunset/`.
- Multiplayer: co-op milestones 1–9 complete; dedicated join-by-session-code through DS milestones 1–3; external matchmaker / reconnect-token handoff still open (`ideas/sunset/MULTIPLAYER_MILESTONE_MAP.md`).
- Enemy-family cleanup: `enemy_base.gd` now owns shared target-refresh cadence and single-scene visual-state helpers used by Flow/Edge/Mass enemy variants; keep future family work layered there first.
- Edge family: `edge_family_base.gd` now owns committed line-attack facing, thin floor telegraphs, and precision line damage; `skewer_mob.gd`, `glaiver_mob.gd`, and `razorform_mob.gd` layer Skewer/Glaiver/Razorform behavior on top, with Razorform cut telegraphs managed by `edge_cut_line_hazard.gd`.
- Meta-progression system: `MetaProgressionStore` autoload (gear instances, gems, materials, local JSON persistence); `GearItemData` / `GemItemData` resources; `TemperingManager` run-scoped RefCounted; `MetaProgressionConstants` (`class_name`). All stat multipliers flow through `LoadoutRepository._aggregate_stats_for_slots`. Item display names centralised in `LoadoutConstants.ITEM_DISPLAY_NAMES`. Design reference: `ideas/META_PROGRESSION.md`, `ideas/INVENTORY.md`.
- Inventory UI: full-screen lobby overlay at `scripts/ui/inventory/inventory_screen.gd`; 3 sub-screens (Loadout with collapsible slot categories + equip/detail, Gear Detail, Gem Management). In-run loadout overlay (`loadout_overlay.gd`) tooltips also show tier/pillar/familiarity. `LoadoutRepository` initialises from `MetaProgressionStore` and syncs equip changes back to it.
- Starter gear: T1 equipped + T2 Aligned + T3 Specialized per slot (varied pillars), seeded materials. Delete `user://meta_progression_local.json` to regenerate.

---

### Task Snapshot

- Date:
- Goal:
- Why now:
- Relevant subsystem:
- Files likely involved:
- Constraints / must-not-break:

### What Changed

- Files touched:
- Behavior added or changed:
- Architectural decisions:

### Risks And Follow-Ups

- Known risks:
- Follow-up tasks:
- Open questions:

### Next Best Prompt

- Paste-ready prompt for the next thread:

## Prompting Tips

- Name the subsystem and expected verification when possible.
- If a task spans player authority or combat replication, explicitly mention `player.gd`, `network_session.gd`, and `dungeon_orchestrator.gd`.
- If a task is local, name the target file directly and say what should not change around it.
- **Context hygiene:** By default, do not glob or bulk-read `dungeon/rooms/authored/` (including `outlines/`). Prefer `dungeon/rooms/base/room_base.gd`, `dungeon/metadata/zone_marker_2d.gd`, `dungeon/README.md`, `addons/dungeon_room_editor/`, `dungeon/game/dungeon_orchestrator_internals.gd`, `dungeon/game/components/room_query_service.gd`, and `tools/room_editor/*.gd` unless the task names a specific `.tscn` or `*.layout.tres` to edit or validate. Apply the same discipline to other huge packed `.tscn` / `.tres` / catalogs — use targeted search, scripts, or one representative file.
- **Paste-ready guardrails** (copy into prompts when needed):
  - "Do not read `dungeon/rooms/authored/`; fix X using `room_base.gd` and room-editor sync only."
  - "If a room file must be inspected, name the single scene or layout path — no folder-wide reads."
