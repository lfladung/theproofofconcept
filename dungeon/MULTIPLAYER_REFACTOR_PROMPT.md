# Multiplayer Refactor Prompt (Saved)

Date saved: 2026-03-24

I have an existing Godot 4.6 project (not a greenfield project) and I want to convert it from singleplayer to scalable online co-op multiplayer incrementally.

Project context (already implemented):
- Main playable scene: `res://dungeon/game/small_dungeon.tscn` with orchestration in `small_dungeon.gd`.
- Architecture already split into:
  - `GameWorld2D` for gameplay simulation/collision
  - `VisualWorld3D` for 3D presentation
  - `CanvasLayer/UI` for HUD
- Existing procedural dungeon pipeline:
  - `DungeonMapLayoutV1` + `ProceduralAssemblyV1`
  - runtime room assembly, sockets, encounter modules, door locks, puzzle gate, boss exit portal, floor regeneration
- Existing gameplay systems:
  - Player (`player.gd`): movement, dodge, melee, ranged arrows, bombs, health/invuln, death/retry
  - Enemies: dasher (`mob.gd`) and arrow tower (`arrow_tower.gd`)
  - Combat objects: `arrow_projectile.gd`, `player_bomb.gd`
  - Dungeon gameplay objects: traps, treasure chest, dropped coins, puzzle floor button, encounter triggers/spawn points/spawn volumes
- Existing assumptions are singleplayer:
  - Direct references to one player (`$GameWorld2D/Player`)
  - Frequent `get_first_node_in_group("player")`
  - No current multiplayer API usage (`@rpc`, ENet peers, MultiplayerSpawner/Synchronizer not yet implemented)
  - No autoload networking managers yet

Goals:
- Keep Spiral Knights-like feel (top-down / 2.5D, dungeon run, action combat)
- Online co-op for 2–4 players (not PvP)
- Authoritative model wherever practical
- Responsive controls + cheating resistance + maintainable architecture
- Incremental refactor (no full rewrite unless absolutely unavoidable)

Please deliver:
1. Recommended networking model
2. Core architecture changes
3. System-by-system authority breakdown
4. Scene and code structure
5. Phased implementation roadmap
6. Example code patterns
7. Biggest risks and how to avoid them

I need you to be concrete about THIS codebase:
- Audit likely multiplayer conversion issues specifically from this current structure.
- Propose how to refactor existing scripts/modules rather than replacing everything.
- Call out which current scripts should change first (e.g., `small_dungeon.gd`, `player.gd`, enemy scripts, projectile/bomb scripts, trap/loot/encounter scripts).
- Define which systems should be:
  - server-authoritative
  - client-predicted (with reconciliation)
  - client-visual-only

Design scope to include:
- Lobby/party creation
- Match start and joining a dungeon run
- Networked player spawning
- Movement
- Melee attacks
- Projectile attacks
- Enemy AI + aggro/targeting
- Damage/health
- Room transitions
- Traps/hazards
- Loot drops/pickups
- Player death/revive/respawn
- Basic disconnect handling/session recovery

Please include:
- Recommended node/scene structure using my existing `GameWorld2D` + `VisualWorld3D` pattern
- Suggested autoload singletons/managers
- Godot authority ownership rules and RPC boundaries
- What data to replicate vs reconstruct locally
- How to sync enemy movement/combat and prevent duplicate hit/desync
- Clean projectile handling strategy
- A reusable network entity base class pattern (if useful)
- Folder structure proposal for multiplayer refactor
- Godot GDScript pseudocode/stubs

Important constraints:
- Indie scale, 2–4 players, co-op only
- Prioritize clarity and long-term maintainability
- Avoid MMO complexity
- Explain tradeoffs when multiple options are valid
- Prefer practical modern co-op architecture over full deterministic lockstep unless strongly justified

First milestone definition (must be explicit):
- A host + 1 client can join the same run
- Both players spawn and move with correct authority
- At least one enemy type is server-driven and synced
- At least one combat path (melee or projectile) is authoritative and works across peers
- Encounter lock/unlock state stays consistent on all peers
- One loot pickup flow is synchronized correctly
- Include acceptance criteria and debug instrumentation plan for this milestone
