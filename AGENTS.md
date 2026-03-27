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
- Lobby/session-code flow and peer-slot mapping are implemented.
- `small_dungeon.gd` is session-aware and manages roster, encounter state, doors, coins, camera, and replication helpers.

## Subsystem Notes

### Networking

- The project uses an authoritative server model for 2-4 players.
- `NetworkSession` owns session lifecycle, lobby state, registry/session-code lookups, peer slots, readiness, and host/client/dedicated-server roles.
- `Player` owns authority assignment, prediction/reconciliation, weapon mode state, and combat request sequencing.
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
4. Prefer the smallest verification command that matches the change.
5. If the task touches architecture, update the memory template section below before ending the thread.

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
- Commands run:
- Verification result:

### Risks And Follow-Ups

- Known risks:
- Follow-up tasks:
- Open questions:

### Next Best Prompt

- Paste-ready prompt for the next thread:

## Prompting Tips

- Name the subsystem and expected verification when possible.
- If a task spans player authority or combat replication, explicitly mention `player.gd`, `network_session.gd`, and `small_dungeon.gd`.
- If a task is local, name the target file directly and say what should not change around it.
