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

- Date: 2026-03-27
- Goal: Refactor gameplay damage into a reusable `Hitbox2D -> Hurtbox2D -> DamageReceiver -> HealthComponent` pipeline and remove duplicate / missed contact-damage edge cases.
- Why now: Milestone 4 authoritative combat was still mixing body collision, Area2D overlap, and direct damage calls, which caused phantom non-hits and same-instant duplicate hits.
- Relevant subsystem: Authoritative combat, player guard handling, enemy contact damage, projectile damage, trap damage.
- Files likely involved: `scripts/combat/*.gd`, `scripts/entities/player.gd`, `scripts/entities/enemy_base.gd`, `scripts/entities/mob.gd`, `scripts/entities/arrow_projectile.gd`, `scripts/entities/player_bomb.gd`, `dungeon/modules/gameplay/trap_tile_2d.gd`, related entity scenes, and `project.godot`.
- Constraints / must-not-break: Preserve server authority, keep `Player.take_damage(...)` and `Player.take_attack_damage(...)` facades, keep `EnemyBase.take_hit(...)` facade, preserve loadout/visual WIP, and do not reintroduce body-collision damage paths.

### What Changed

- Files touched: Added `scripts/combat/damage_packet.gd`, `health_component.gd`, `damage_receiver_component.gd`, `player_damage_receiver_component.gd`, `hurtbox_2d.gd`, `hitbox_2d.gd`; updated `project.godot`; updated `scenes/entities/player.tscn`, `dasher.tscn`, `arrow_tower.tscn`, `arrow_projectile.tscn`, `dungeon/modules/gameplay/trap_tile_2d.tscn`; updated `scripts/entities/player.gd`, `enemy_base.gd`, `mob.gd`, `arrow_projectile.gd`, `arrow_tower.gd`, `player_bomb.gd`, `dungeon/modules/gameplay/trap_tile_2d.gd`.
- Behavior added or changed: Player, enemies, projectiles, and traps now resolve gameplay damage only through hurtboxes/receivers; dash contact damage uses a controlled interval-repeat hitbox; melee uses an explicit player attack hitbox; player HP hits use short i-frames; blocked frontal hits consume stamina and also consume the source hit so one overlap cannot drain stamina and HP in the same instant.
- Architectural decisions: Movement collision stays on `CharacterBody2D`; gameplay damage moved to dedicated Area2D layers (`player_hurtbox`, `enemy_hurtbox`, `player_attack`, `hostile_attack`). Duplicate suppression keys off `source_uid + attack_instance_id`, and sustained overlap uses immediate first hit plus interval repeats instead of per-frame body-entered logic.
- Commands run: `git status --short`; targeted file reads with `Get-Content`/`Select-String`; `.\tools\run_headless.ps1 -CheckOnly -Script res://scripts/combat/damage_packet.gd`; `res://scripts/combat/health_component.gd`; `res://scripts/combat/damage_receiver_component.gd`; `res://scripts/combat/player_damage_receiver_component.gd`; `res://scripts/combat/hurtbox_2d.gd`; `res://scripts/combat/hitbox_2d.gd`; `res://scripts/entities/enemy_base.gd`; `res://scripts/entities/mob.gd`; `res://scripts/entities/player.gd`; `res://scripts/entities/arrow_projectile.gd`; `res://scripts/entities/arrow_tower.gd`; `res://scripts/entities/player_bomb.gd`; `res://dungeon/modules/gameplay/trap_tile_2d.gd`.
- Verification result: All targeted `--check-only` script validations passed after resolving a final `mob.gd` inherited-constant conflict. Full gameplay feel validation in host/client runtime is still recommended.

### Risks And Follow-Ups

- Known risks: Runtime scene boot and multiplayer feel were not fully exercised in this thread; `_show_mob_hitbox_debug` style legacy debug overlays in `player.gd` still coexist with the new combat debug logging; more enemy types will need migration if they still call direct damage paths.
- Follow-up tasks: Run dedicated-server plus client verification for dash contact, guard blocking, projectile hits, traps, and melee replication; consider small post-hit separation if body cling still feels sticky; migrate any remaining hostile damage producers onto `Hitbox2D`.
- Open questions: Whether sustained enemy contact should eventually require separation/re-contact instead of interval repeats; whether enemy hurtboxes should get per-faction filtering beyond collision masks; whether combat debug should be consolidated into a shared in-game overlay.

### Next Best Prompt

- Paste-ready prompt for the next thread: "Validate the new authoritative combat pipeline in live multiplayer. Focus on `scripts/entities/player.gd`, `scripts/entities/mob.gd`, `scripts/entities/arrow_projectile.gd`, and `dungeon/modules/gameplay/trap_tile_2d.gd`. Run host/client gameplay checks for dash contact, guard blocking, melee, arrows, bombs, and traps; fix any runtime issues without regressing the new `Hitbox2D -> Hurtbox2D -> DamageReceiver -> HealthComponent` architecture."

## Prompting Tips

- Name the subsystem and expected verification when possible.
- If a task spans player authority or combat replication, explicitly mention `player.gd`, `network_session.gd`, and `small_dungeon.gd`.
- If a task is local, name the target file directly and say what should not change around it.
