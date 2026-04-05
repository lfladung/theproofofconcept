# Multiplayer Refactor Milestone Map

Date created: 2026-03-24
Scope: Godot 4.6, co-op 2-4 players, authoritative server model, incremental refactor

## Executive summary

The core multiplayer refactor milestones **1–9** are complete: session and lobby, spawn and authority, movement with prediction and reconciliation, authoritative melee combat with de-duplication, server-driven enemies and aggro, encounter and door progression, non-duplicated loot and per-player score, death/revive/rejoin recovery, and hardening toward stable **2–4 player** runs.

| Milestone | What it represents |
|-----------|---------------------|
| **1 – Networking foundation** | `NetworkSession`, `NetEventBus`, `RunState`; lobby host/join/disconnect; `peer_id` → player slot; lobby ↔ in-run flow. |
| **2 – Spawn & authority** | Multiplayer roster in `dungeon_orchestrator`; networked spawn; explicit per-peer authority; HUD tied to the local authority player; no “first player node wins” assumptions. |
| **3 – Movement** | Tick-stamped input to server; authoritative movement; prediction + reconciliation for the owner; interpolation for remotes. |
| **4 – Authoritative combat (melee slice)** | Melee vertical slice: client request → server validation → replicated resolution; hit/attack IDs so duplicates do not double-apply damage; effects driven from authoritative events. |
| **5 – Enemy AI & aggro sync** | Enemy logic server-side; targets from the player registry; transforms plus discrete state events (telegraph, dash, death, etc.) consistent for all peers. |
| **6 – Encounters, doors, room flow** | Server-owned encounter lifecycle (enter → lock → wave → clear → unlock); doors, gates, and portals kept in sync; progression does not fork per client. |
| **7 – Loot & score** | Server-owned spawn IDs; authoritative pickup and despawn; per-player coins/score replicated; chest bursts and dropped coins wired through the same ownership model. |
| **8 – Death, revive, recovery** | Server-driven death, respawn, and revive; rejoin path (snapshot-style recovery, respawn, rebuild); mid-run disconnect without corrupting the run. |
| **9 – Polish & scale** | Bandwidth and replication tuning; invalid RPC rejection and ownership checks on boundaries; validation toward stable four-player runs. |

**Gameplay and content layers** documented elsewhere in the repo (not 1:1 with a single milestone):

- **Sword blocking** — server-authoritative directional guard: frontal hostile hits can drain stamina instead of HP, with regen delay after use or break.
- **Boss floor exits** — authored `floor_exit` zone markers and runtime lookup (for example via room query), with fallback when a room has no marker yet.
- **Stat pillars** — world objects that apply runtime stat bonuses through the loadout stat merge; server processes hits in multiplayer.
- **Loadout and visuals** — equipment data driving modular 3D attachments (sword, chest, legs, helmet, shield).
- **Room Editor and authored rooms** — handcrafted `RoomBase` plus sidecar layouts; generated sockets, zones, and gameplay markers; enemy spawn markers with `enemy_id`; outline tooling for a reusable room library.

**Dedicated server track:** DS milestones **1–3** are complete (dedicated boot, registry/session-code scaffold, client join by session code). **DS 4–5** (matchmaker/allocator, reconnect tokens and run snapshot handoff) remain open.

**One-line status:** Co-op milestones 1–9 are treated as shipped end-to-end; dedicated join-by-code is in place while full external orchestration and reconnect-token handoff are still future work.

## Progress Snapshot

- [x] Milestone 1 - Networking Foundation (session lifecycle + lobby flow)
- [x] Milestone 2 - Player Spawn And Authority
  - [x] Session slot-map driven player roster in `dungeon_orchestrator`
  - [x] Per-peer authority assignment + authority debug logging
  - [x] Local HUD binding updated to local authority player
  - [x] Host + client live-play verification pass (movement + late-join behavior)
- [x] Milestone 3 - Movement Prediction And Reconciliation
  - [x] Client input command stream to server (tick stamped)
  - [x] Server authoritative movement state replication
  - [x] Client reconciliation path + remote interpolation scaffolding
  - [x] Host + client feel/smoothing tuning pass
- [x] Milestone 4 - Combat Vertical Slice (Authoritative)
  - [x] Option A selected: melee
  - [x] Owner-client melee request -> server validation path
  - [x] Server melee resolution + replicated attack event
  - [x] Server-validated hit event IDs in combat log / telemetry
- [x] Milestone 5 - Enemy AI And Aggro Sync
- [x] Milestone 6 - Encounter State, Doors, And Room Flow
- [x] Milestone 7 - Loot, Pickups, And Score Ownership
- [x] Milestone 8 - Death, Revive/Respawn, And Session Recovery
- [x] Milestone 9 - Polish, Hardening, And Scale To 4 Players

## Milestone 0 - Baseline And Guardrails

Goal:
- Freeze current singleplayer behavior and create regression checks before networking changes.

Deliverables:
- Add a short "networking assumptions" section to key scripts.
- Add debug flags for authority logging and network event tracing.
- Create a checklist of current gameplay flows that must keep working.

Done criteria:
- Singleplayer run still works end-to-end.
- We can toggle debug logs for player/enemy/damage/spawn events.

## Milestone 1 - Networking Foundation

Goal:
- Introduce session lifecycle and transport primitives without changing combat logic yet.

Deliverables:
- Add autoloads:
  - `NetworkSession.gd` (host/client lifecycle, peer management)
  - `NetEventBus.gd` (centralized network event dispatch)
  - `RunState.gd` (match-level replicated state snapshot container)
- Create lobby scene flow (host, join, disconnect handling basics).
- Define peer identity model (`peer_id -> player slot`).

Done criteria:
- Host starts a session.
- Client joins/leaves cleanly.
- Session transitions from lobby -> in-run and back.

## Milestone 2 - Player Spawn And Authority

Goal:
- Support multiple players in the same dungeon run with explicit ownership.

Deliverables:
- Replace single-player assumptions:
  - remove hard dependency on `$GameWorld2D/Player`
  - replace `get_first_node_in_group("player")` usage with player registry queries
- Add networked player spawner and per-peer ownership mapping.
- Introduce `PlayerController` split:
  - input collection (local)
  - simulation driver (authoritative)
  - presentation sync (all peers)

Done criteria:
- Host + 1 client spawn in same run.
- Both can move.
- Ownership is explicit and logged (`authority_peer_id` per player).

## Milestone 3 - Movement Prediction And Reconciliation

Goal:
- Improve movement responsiveness while keeping server authority.

Deliverables:
- Input command stream from client to server (tick stamped).
- Server authoritative movement state replication.
- Client-side prediction + reconciliation for owning player.
- Interpolation for remote players.

Done criteria:
- Local movement feels responsive on client.
- No sustained divergence after reconciliation.
- Remote players appear smooth under normal latency.

## Milestone 4 - Combat Vertical Slice (Authoritative)

Goal:
- Ship one full authoritative combat path.

Deliverables:
- Choose first vertical slice:
  - Option A: melee
  - Option B: projectile
- Server validates hits and applies damage.
- Clients render effects from authoritative events.
- Add anti-duplication guard (hit event IDs / attack IDs).

Done criteria:
- Combat path works between host and client.
- Damage and health match on all peers.
- Duplicate hit detection is prevented.

## Milestone 5 - Enemy AI And Aggro Sync

Goal:
- Move enemy decision logic fully server-side and replicate cleanly.

Deliverables:
- Server authoritative update for dasher and arrow tower.
- Deterministic target-selection rules against player registry.
- Enemy state channels:
  - high-frequency transform stream
  - low-frequency state events (telegraph, dash start/end, death)

Done criteria:
- Both enemy types behave consistently for all players.
- Aggro and attack state are synchronized and visually consistent.

## Milestone 6 - Encounter State, Doors, And Room Flow

Goal:
- Keep dungeon progression state identical across peers.

Deliverables:
- Server-authoritative encounter lifecycle:
  - trigger enter
  - lock doors
  - spawn wave
  - clear unlock
- Replicate puzzle gate and boss portal states.
- Centralize encounter state in run-level replicated structure.

Done criteria:
- Encounter lock/unlock is consistent on host/client.
- Room transitions and encounter completion cannot desync.

## Milestone 7 - Loot, Pickups, And Score Ownership

Goal:
- Prevent loot duplication and score mismatches.

Deliverables:
- Server-owned loot spawn IDs.
- Server-authoritative pickup validation and despawn.
- Replicated coin/score updates per player.
- Rework chest coin burst and dropped coin collection through net IDs.

Done criteria:
- Loot can only be picked once.
- Score/coin values are identical on all peers.

## Milestone 8 - Death, Revive/Respawn, And Session Recovery

Goal:
- Stabilize match continuity for co-op failure cases.

Deliverables:
- Server-controlled death/respawn or revive flow.
- Rejoin recovery:
  - snapshot current run state
  - respawn reconnecting player
  - rebuild active entities from authoritative snapshot
- Graceful handling for mid-run disconnects.

Done criteria:
- A disconnecting player can rejoin without corrupting run state.
- Death flow is synchronized and deterministic across peers.

## Milestone 9 - Polish, Hardening, And Scale To 4 Players

Goal:
- Productionize the 2-4 player architecture.

Deliverables:
- Bandwidth pass:
  - tune replication frequency
  - cull non-essential RPCs
- Security pass:
  - reject invalid client actions
  - enforce ownership checks at all RPC boundaries
- Test matrix:
  - host + 1..3 clients
  - latency/packet loss simulation

Done criteria:
- Stable 4-player co-op run in target scenarios.
- No critical authority bypasses in core systems.

## Recommended File-Touch Order

1. `project.godot` (autoload registration)
2. Add `scripts/network/` foundation classes
3. `dungeon/game/dungeon_orchestrator_internals.gd` (session-aware orchestration)
4. `scripts/entities/player.gd` (controller split + authority)
5. `scripts/entities/mob.gd`, `scripts/entities/arrow_tower.gd` (server AI ownership)
6. `scripts/entities/arrow_projectile.gd`, `scripts/entities/player_bomb.gd` (authoritative damage events)
7. `dungeon/modules/encounter/*.gd` and `dungeon/game/components/door_lock_controller.gd`
8. `dungeon/modules/gameplay/*.gd` for loot/trap/pickups
9. UI wiring (`scripts/ui/*.gd`) for per-player data

## MVP Checkpoint (First Playable Multiplayer Proof)

Must be true before expanding scope:
- Host + 1 client join same run.
- Both players spawn and move with authority + reconciliation.
- One enemy type is server-driven and synchronized.
- One combat path is authoritative end-to-end.
- Encounter lock/unlock replicates correctly.
- One loot pickup flow is synchronized.

If any of these fail, do not advance to later milestones.

## Dedicated Server Track (New)

Goal:
- Move from listen-server hosting to dedicated instance hosting suitable for external orchestration.

Progress:
- [x] DS Milestone 1: Dedicated server boot mode in `NetworkSession`
  - CLI boot flags (`--dedicated_server`, `--port`, `--max_players`, `--start_in_run`)
  - host peer excluded from gameplay slot map for dedicated sessions
  - dedicated placeholder player hardened in `dungeon_orchestrator`
- [x] DS Milestone 2: Session directory integration + registry service scaffold
  - optional instance registration/heartbeat/unregister from dedicated `NetworkSession`
  - new lightweight registry service in `tools/instance_registry/instance_registry_server.py`
  - session code support (`--session_code`) and advertised endpoint (`--public_host`, `--port`)
- [x] DS Milestone 3: Client resolve-and-join by session code (UI + API wiring)
- [ ] DS Milestone 4: Matchmaker + allocator (party queue -> free instance)
- [ ] DS Milestone 5: Reconnect tokens and run snapshot handoff

