# Multiplayer Refactor Milestone Map

Date created: 2026-03-24
Scope: Godot 4.6, co-op 2-4 players, authoritative server model, incremental refactor

## Progress Snapshot

- [x] Milestone 1 - Networking Foundation (session lifecycle + lobby flow)
- [x] Milestone 2 - Player Spawn And Authority
  - [x] Session slot-map driven player roster in `small_dungeon`
  - [x] Per-peer authority assignment + authority debug logging
  - [x] Local HUD binding updated to local authority player
  - [x] Host + client live-play verification pass (movement + late-join behavior)
- [x] Milestone 3 - Movement Prediction And Reconciliation
  - [x] Client input command stream to server (tick stamped)
  - [x] Server authoritative movement state replication
  - [x] Client reconciliation path + remote interpolation scaffolding
  - [x] Host + client feel/smoothing tuning pass
- [ ] Milestone 4 - Combat Vertical Slice (Authoritative) (in progress)
  - [x] Option A selected: melee
  - [x] Owner-client melee request -> server validation path
  - [x] Server melee resolution + replicated attack event
  - [x] Server-validated hit event IDs in combat log / telemetry

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
  - low-frequency state events (telegraph, dash start/end, death)``

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
3. `dungeon/game/small_dungeon.gd` (session-aware orchestration)
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
