# Milestones v2

Date created: 2026-04-11
Scope: Godot 4.6, 2-4 player authoritative co-op dungeon crawler

## Why This Exists

The original dungeon and multiplayer milestone docs have been moved to `ideas/sunset/`
because those tracks are largely complete. This v2 roadmap starts from the current
project state: co-op foundations, authored-room tooling, broad enemy families, loadout
scaffolding, infusions, and safe-room loadout swapping are already in place.

The next phase should turn those foundations into a more complete game loop:

- Hub flow before and between runs.
- Mission selection instead of a single direct dungeon entry.
- Upgrade, gem, and gear progression UI.
- Authored encounter composition and better reward drops.
- Layer/biome progression, boss mastery tests, and enemy-family readability.
- Resonance spending, gear evolution, gems, and slot identity.
- Presentation and naming cleanup so the project reads as "The Proof of Concept".
- Story/lore framing for the Pit, concept-creatures, and material degradation.
- Screen mode and resolution polish for reliable playtesting.

## Current Baseline

- Core multiplayer milestones 1-9 are complete in the sunset docs.
- Dedicated server DS 1-3 are complete; allocator/matchmaker and reconnect-token handoff remain optional future infrastructure work.
- The active user flow starts at `res://scenes/ui/lobby_menu.tscn`.
- Main gameplay runtime is `res://dungeon/game/dungeon_orchestrator.tscn`.
- Player loadout swapping exists and is gated to safe rooms.
- Infusion mechanics and guide UI exist; several pillars still need clearer live HUD/VFX feedback.
- Authored-room and Room Editor workflows exist; encounter composition needs a stronger design pass.
- Enemy drops still behave like coin/score rewards in places and should move toward progression materials or resonance.

## Roadmap Priorities

1. Hub And Mission Flow
2. Upgrade And Gear Progression
3. Gems And Socketing
4. Floor Structure And Mini-Hubs
5. Authored Encounter Composition
6. Reward Drop Replacement And Resonance Spending
7. Gear Evolution And Gems
8. Layer/Biome Progression
9. Bosses, Elites, And Mastery Tests
10. Enemy Family Completion And Visual Readability
11. Infusion HUD And Combat Feedback
12. Story, Naming, And Display Polish

## Milestone 1 - Hub Flow

Goal:
- Create a hub where players can select missions, upgrade gear, and interact with NPCs.

Deliverables:
- New hub scene reachable from the lobby/start flow.
- Hub spawn points for 1-4 players.
- Interactable NPC placeholders for mission selection, upgrades, and future story/vendor functions.
- Runtime path from hub -> mission -> return to hub.
- Multiplayer-safe interaction ownership so one player opening UI does not break other players.

Done criteria:
- Singleplayer and hosted multiplayer can enter the hub from the menu.
- Players can launch a mission from the hub.
- Players return to the hub after mission completion or abort.
- Interactions are explicit and do not depend on "first player node wins" assumptions.

Likely files:
- `scenes/ui/lobby_menu.tscn`
- `scripts/ui/lobby_menu.gd`
- `scripts/network/network_session.gd`
- `dungeon/game/dungeon_orchestrator.gd`
- New hub scene/scripts under `scenes/` or `dungeon/`

## Milestone 2 - Mission Select UI

Goal:
- Create mission selection UI that replaces the implicit "start the one current dungeon" flow.

Deliverables:
- Mission select screen opened from the hub.
- Mission card data model: mission id, display name, difficulty, floor count, enemy theme, rewards, and entry scene.
- Host-authoritative mission selection in multiplayer.
- Ready/start affordance for party flow.
- Minimal mission registry for current dungeon plus at least one test mission variant.

Done criteria:
- Host selects a mission and clients see the selected mission.
- Starting a run loads the selected mission for all peers.
- Mission data is easy to extend without editing UI logic for every mission.

Likely files:
- `scripts/ui/`
- `scripts/network/network_session.gd`
- `dungeon/game/dungeon_orchestrator_internals.gd`
- New mission data/resources under `dungeon/` or `scripts/`

## Milestone 3 - Upgrade UI

Goal:
- Create the upgrade UI needed for persistent gear evolution and material spending.

Deliverables:
- Upgrade screen opened from the hub.
- Gear detail panel for equipped items.
- Material counters by pillar/resource type.
- Upgrade actions for the first vertical slice, such as tier upgrade or gem crafting/refreshing.
- Server-authoritative validation for multiplayer upgrade requests.
- Clear unavailable-state messaging for missing materials or locked upgrade tiers.

Done criteria:
- A player can open the upgrade UI in the hub.
- A test upgrade can be purchased and reflected in that player's loadout snapshot.
- Invalid upgrade requests fail cleanly on server and client.
- The UI is structured so future upgrade branches do not require a full rewrite.

Likely files:
- `scripts/loadout/`
- `scripts/ui/inventory/`
- `scripts/ui/loadout/`
- `ideas/PROGRESSION.md`
- `ideas/META_PROGRESSION.md`

## Milestone 4 - Gems And Armor Socketing

Goal:
- Create gems that socket into armor as the first flexible build-expression layer.

Deliverables:
- Gem data model: gem id, pillar, display name, socket rules, effect description, optional fatigue/durability.
- Armor socket data on loadout items.
- Gem management UI for socket, unsocket, and replace.
- One implemented gem effect that is visible in combat.
- Multiplayer-safe loadout snapshot replication for socket state.

Done criteria:
- Armor can report available sockets.
- A gem can be socketed into armor from UI and persists in the player's loadout state.
- The socketed gem changes runtime behavior or stats in a testable way.
- The system can later expand to weapons/shields without redesigning the model.

Likely files:
- `scripts/loadout/loadout_item_definition.gd`
- `scripts/loadout/loadout_repository.gd`
- `scripts/entities/player.gd`
- `scripts/entities/player/player_internals.gd`
- `scripts/ui/inventory/`
- `ideas/INVENTORY.md`

## Milestone 5 - Floor Structure And Mini-Hub Gear Changes

Goal:
- Separate floors with mini-hubs where players can change gear before continuing.

Deliverables:
- Floor transition flow: combat floor -> mini-hub -> next floor.
- Mini-hub room type or scene role that permits loadout changes.
- Party-ready gate before entering the next floor.
- Run state tracking for floor index, selected mission, and floor reward state.
- Optional floor-end infusion/reward presentation.

Done criteria:
- Completing a floor moves the party into a mini-hub instead of immediately continuing.
- Loadout UI can be opened in the mini-hub.
- The next floor starts only after the party is ready.
- Floor state survives normal multiplayer replication.

Likely files:
- `dungeon/game/dungeon_orchestrator_internals.gd`
- `dungeon/game/components/room_query_service.gd`
- `scripts/network/run_state.gd`
- `scripts/ui/loadout/loadout_overlay.gd`

## Milestone 6 - Authored Encounter Composition

Goal:
- Create authored rooms with specific enemy compositions and pacing rules.

Deliverables:
- Encounter composition data that can be attached to authored room metadata or room-editor markers.
- Support for enemy groups, spawn timing, elite flags, and composition role tags.
- Runtime resolver that maps composition data to `EnemySpawnById`.
- Validation tooling for missing enemy ids and invalid composition references.
- First pass of curated encounter archetypes, such as "sniper + pusher", "echo swarm", and "tank + control".

Done criteria:
- At least one authored room can spawn a named enemy composition from metadata.
- Invalid enemy ids are caught by validation before playtest.
- Composition data is readable without opening large authored scene files by hand.
- Runtime spawning remains server-authoritative and event/interval driven.

Likely files:
- `dungeon/game/enemy_spawn_by_id.gd`
- `dungeon/game/dungeon_orchestrator_internals.gd`
- `dungeon/metadata/zone_marker_2d.gd`
- `addons/dungeon_room_editor/`
- `tools/room_editor/`
- `ideas/ENEMY_LEVEL_DESIGN.md`

## Milestone 7 - Enemy Drops And Reward Economy

Goal:
- Update enemy drops away from gold coins and toward progression-relevant rewards.

Deliverables:
- Define replacement drops: resonance, pillar materials, gem shards, or mission reward tokens.
- Server-authoritative reward spawn/pickup flow.
- Enemy reward values by family or encounter tier.
- UI update for reward counters.
- Treasure chest update so chest rewards match the new economy.

Done criteria:
- Normal enemy deaths no longer rely on gold coins as the primary reward.
- Rewards are still non-duplicated in multiplayer.
- Players can see the new reward totals.
- The old score/coin code path is either sunset, renamed, or clearly isolated as debug/legacy.

Likely files:
- `scripts/entities/enemy_base.gd`
- `dungeon/modules/gameplay/dropped_coin.gd`
- `dungeon/modules/gameplay/treasure_chest_2d.gd`
- `scripts/ui/score_label.gd`
- `scripts/network/run_state.gd`
- `ideas/PROGRESSION.md`

## Milestone 8 - Resonance And Infusion Reward Loop

Goal:
- Make resonance and infusion rewards the active in-run build-shaping economy.

Deliverables:
- Enemy-death resonance pickup or auto-collect flow.
- Floor-end infusion manifestation flow.
- Resonance spend actions: reroll, pin, stabilize, and force propagation.
- Cost model with escalating reroll cost and high-cost pinning.
- Multiplayer-safe per-player reward state so party members can diverge.
- Boss infusion handling with stronger or hybrid rewards.
- End-of-run infusion conversion into pillar materials.

Done criteria:
- Clearing rooms grants resonance in a visible, non-duplicated way.
- After a floor, each player receives an infusion manifestation.
- A player can spend resonance to reroll or influence the next infusion.
- Held infusions convert to material rewards when the run ends.
- The system answers the open questions in `ideas/PROGRESSION.md` enough for implementation: soft bias, reroll cap/cost, and pin timing.

Likely files:
- `scripts/network/run_state.gd`
- `dungeon/game/dungeon_orchestrator_internals.gd`
- `scripts/entities/enemy_base.gd`
- `scripts/infusion/`
- `scripts/ui/`
- `scripts/meta_progression/`
- `ideas/PROGRESSION.md`

## Milestone 9 - Gear Evolution And Gems

Goal:
- Turn the upgrade UI into the full permanent progression loop: gear tiers, promotion, gems, and bounded stat growth.

Deliverables:
- Gear tier upgrade path: Tier 1 base -> Tier 2 aligned -> Tier 3 specialized.
- Promotion progress bridge from deep runs, boss clears, strong infusion states, and mission accomplishments into permanent tier unlocks.
- Gem crafting, refreshing, fatigue, and socket management as the flexible customization layer.
- Material costs by pillar and tier.
- Bounded stat scaling and familiarity display.
- Server-authoritative validation plan for multiplayer meta progression.

Done criteria:
- A gear item can evolve at least one tier through the upgrade UI.
- A gem can be crafted/refreshed and socketed as the only flexible gear modifier layer.
- Materials are spent as abstract counters, not inventory objects.
- The system follows `ideas/META_PROGRESSION.md`: qualitative upgrades first, small/capped stat growth second.

Likely files:
- `scripts/meta_progression/`
- `scripts/loadout/loadout_repository.gd`
- `scripts/loadout/loadout_item_definition.gd`
- `scripts/ui/inventory/inventory_screen.gd`
- `scripts/ui/loadout/`
- `ideas/META_PROGRESSION.md`
- `ideas/INVENTORY.md`

## Milestone 10 - Full Slot Identity Pass

Goal:
- Expand pillar expression across sword, handgun, bomb, shield, helmet, and armor so loadout choices are about behavior, not only numbers.

Deliverables:
- Define one implemented pillar-expression vertical slice for each gear slot.
- Sword, handgun, bomb, shield, helmet, and armor behavior panels in gear detail UI.
- Data model support for slot-specific pillar behavior descriptions.
- Runtime hooks for non-sword slot expression where missing.
- At least one cross-slot synergy example, such as Flow weapon + Flow armor or Edge sword + Surge shield.

Done criteria:
- Each gear slot has at least one behavior-changing upgrade path described in UI.
- At least two non-sword slot behaviors are implemented and testable.
- Tooltips explain how the gear plays in plain language.
- The design stays aligned with `ideas/EQUIPMENT_UPGRADES.md`.

Likely files:
- `scripts/loadout/`
- `scripts/entities/player.gd`
- `scripts/entities/player/player_internals.gd`
- `scripts/entities/player_bomb.gd`
- `scripts/entities/arrow_projectile.gd`
- `scripts/ui/inventory/inventory_screen.gd`
- `ideas/EQUIPMENT_UPGRADES.md`

## Milestone 11 - Layer And Biome Progression

Goal:
- Build the game around layer progression: 4-5 floors per layer, with distinct biome identity, enemy pacing, materials, and reality rules.

Deliverables:
- Layer data model: layer id, display name, floor range/count, biome theme, enemy tiers, boss, material set, and environmental rule notes.
- Layer 1 vertical slice using "The Edge of the Pit" structure.
- Floor pacing roles: introduce, reinforce, twist, pressure, master.
- Layer-specific material rewards.
- Mission/floor selection awareness of current layer.
- Environment hooks for layer-specific visuals and hazards, even if initially placeholder.

Done criteria:
- A mission can identify which layer it belongs to.
- Floor progression can move through a 4-5 floor layer and end in a boss/mastery floor.
- Layer 1 can gate enemy selection toward surface-tier encounters.
- The roadmap for Layer 2 and Layer 3 is represented in data/docs without requiring full implementation.

Likely files:
- `dungeon/game/dungeon_orchestrator_internals.gd`
- `dungeon/game/components/`
- `scripts/network/run_state.gd`
- New layer/mission data resources
- `ideas/LAYERS.md`
- `ideas/ENEMY_LEVEL_DESIGN.md`

## Milestone 12 - Bosses, Elites, And Mastery Tests

Goal:
- Make bosses and elites validate the systems players learned during each layer.

Deliverables:
- Boss progression model: focused elite, dual-concept boss, rule-breaker boss.
- Elite modifier model for foreshadowing boss mechanics on earlier floors.
- Boss room flow that supports phases, adds, weakpoints, and boss-specific rewards.
- First boss vertical slice for Layer 1.
- Hybrid elite prototype using one dominant trait and one secondary trait.
- Boss infusion reward or layer-clear reward integration.

Done criteria:
- A boss can run as the final floor of a layer.
- At least one elite encounter teaches or foreshadows a boss mechanic.
- Boss rewards integrate with resonance/material/infusion flow.
- The system follows the principle from `ideas/BOSS_CONCEPTS.md`: bosses are expressions of systems, not just larger enemies.

Likely files:
- `dungeon/game/dungeon_orchestrator_internals.gd`
- `scripts/entities/enemy_base.gd`
- `scripts/entities/`
- `dungeon/modules/encounter/`
- `dungeon/game/enemy_spawn_by_id.gd`
- `ideas/BOSS_CONCEPTS.md`
- `ideas/LAYERS.md`

## Milestone 13 - Enemy Family Completion And Visual Readability

Goal:
- Complete and communicate the surface/mid/deep enemy-family ladder with readable silhouettes and behaviors.

Deliverables:
- Family matrix for Flow, Volley, Mass, Echo, Phase, Edge, and Surge across surface/mid/deep tiers.
- Visual identity pass for each family and tier.
- Missing or placeholder family members prioritized and scoped.
- Spawn guidance and counterplay notes converted into encounter data where useful.
- Asset prompt / model pipeline checklist for enemy visuals.
- Multiplayer-specific coordination notes for enemies that require team play.

Done criteria:
- The enemy roster has a clear surface -> mid -> deep progression plan.
- Players can identify enemy family and tier from silhouette/color/readability cues.
- Encounter authors can pick enemies by role and tier instead of only scene name.
- At least one family receives a complete surface/mid/deep readability pass.

Likely files:
- `scripts/entities/`
- `scripts/visuals/enemy_state_visual.gd`
- `dungeon/game/enemy_spawn_by_id.gd`
- `addons/dungeon_room_editor/`
- `tools/asset_pipeline/`
- `ideas/MONSTER_IDEAS.md`
- `ideas/image_prompts.md`

## Milestone 14 - Infusion HUD And Combat Feedback

Goal:
- Make the existing infusion/combat depth readable during live play.

Deliverables:
- HUD readouts for key states such as Flow tempo/Overdrive, Anchor pressure/rooted, Surge energy/Overdrive, and active infusions.
- Crit/execute/readability pass for Edge.
- Echo afterimage or ghost-swing VFX/SFX pass.
- Anchor pressure/rooted audio or visual heartbeat.
- Surge energy/finale feedback.
- Cross-pillar proc feedback that avoids visual noise.
- Debug toggles remain separate from shipping feedback.

Done criteria:
- Players can tell when major infusion states are active without opening the guide.
- At least Flow, Anchor, and Surge have live state feedback.
- VFX/SFX communicates payoff without adding expensive per-frame debug meshes.
- Feedback is replicated or locally derived in a multiplayer-safe way.

Likely files:
- `scripts/ui/`
- `scripts/ui/infusion_guide_overlay.gd`
- `scripts/entities/player.gd`
- `scripts/entities/player/player_internals.gd`
- `scripts/visuals/player_visual.gd`
- `scripts/vfx/`
- `ideas/GAMEPLAY_IDEAS.md`

## Milestone 15 - Story And Lore Integration

Goal:
- Bring "The Proof of Concept" premise into the hub, layer flow, rewards, and moment-to-moment framing.

Deliverables:
- Hub NPC dialogue placeholders explaining the Pit, missions, upgrades, and material degradation.
- Layer intro/outro text or lightweight scenes.
- Lore fragment reward path from bosses and special rooms.
- Messaging for "use it before you lose it" and materials/creatures degrading outside the Pit.
- Naming pass support for "The Proof of Concept" across user-facing UI and docs.
- Optional story hooks for strange machines, abstract power sources, and incomplete concept-creatures.

Done criteria:
- A player can understand why they are entering the Pit and what they bring back.
- Boss/layer clears can award or reveal lore fragments.
- The reward economy language matches the story: resonance, pillar materials, infusions, and degradation.
- Hub NPCs provide clear next-step guidance without blocking gameplay.

Likely files:
- `scripts/ui/`
- `scenes/ui/`
- Hub scene/scripts
- Mission/layer data
- `ideas/STORY_IDEAS.md`
- `ideas/INFUSION_LOCATIONS.MD`

## Milestone 16 - Detonator Spawn Fix

Goal:
- Fix detonator spawns so authored and generated encounters can place detonators reliably.
- Ensure they are killable, don't spawn infinite copies

Deliverables:
- Confirm detonator enemy id mapping.
- Confirm Room Editor catalog entry and spawn marker metadata.
- Confirm runtime spawn resolver handles detonator scenes.
- Add a focused validation or check-only path for detonator spawn metadata.

Done criteria:
- A test room/mission can spawn a detonator from `enemy_id`.
- Unknown or misspelled detonator ids produce a clear validation error.
- Fix does not require bulk-editing authored room files.

Likely files:
- `dungeon/game/enemy_spawn_by_id.gd`
- `scripts/entities/detonator_mob.gd`
- `scenes/entities/detonator.tscn`
- `addons/dungeon_room_editor/`
- `tools/room_editor/`

## Milestone 17 - Project Naming Pass

Goal:
- Update naming across the project to "The Proof of Concept".

Deliverables:
- Update project display name and visible menu title strings.
- Replace stale starter-template references where safe.
- Keep internal paths stable unless there is a strong reason to rename files.
- Add a short note in docs that older sunset docs may still contain historical names.

Done criteria:
- `project.godot` displays "The Proof of Concept".
- Main menu/lobby UI uses "The Proof of Concept" where a project title is shown.
- Search finds no active user-facing stale starter-template names outside sunset/history docs.

Likely files:
- `project.godot`
- `scripts/ui/lobby_menu.gd`
- UI scenes under `scenes/ui/`
- Active docs outside `ideas/sunset/`

## Milestone 18 - Display Mode And Resolution Polish

Goal:
- Fix color tearing when resizing the screen and add fixed resolution options.

Deliverables:
- Reproduce and document the resize color-tearing issue.
- Add fixed resolution settings.
- Add display mode options: bordered fullscreen, windowed, and fullscreen.
- Persist display settings through `GameSettings`.
- Ensure UI scaling and 3D presentation behave consistently across supported modes.

Done criteria:
- Resizing no longer produces obvious color tearing in normal playtest scenarios.
- Players can choose windowed, bordered fullscreen, and fullscreen.
- Players can choose from fixed resolution options.
- Settings persist across restart.

Likely files:
- `scripts/settings/game_settings.gd`
- `scripts/ui/lobby_menu.gd`
- `project.godot`
- Display/window setup code if added

## Stretch Track - Dedicated Server Hardening

Goal:
- Continue the remaining dedicated server track only when external playtesting needs it.

Deliverables:
- DS Milestone 4: matchmaker + allocator, party queue -> free instance.
- DS Milestone 5: reconnect tokens and run snapshot handoff.

Done criteria:
- External or local allocator can route a party to a free dedicated instance.
- Reconnect can restore player identity and the current run snapshot without corrupting run state.

## Verification Philosophy

- For UI-only changes, prefer fast Godot check-only runs on touched scripts.
- For hub/mission/floor changes, verify singleplayer first, then host + one client.
- For reward/drop changes, verify server authority and non-duplication before tuning values.
- For encounter composition changes, validate metadata before opening large authored room assets.
- For display settings, test windowed, bordered fullscreen, fullscreen, and at least one resize path.
- For performance-sensitive runtime changes, watch authoritative server cost separately from client presentation.

## Notes From Planning Image

Included v2 planning items:

- Create hub where you can select missions, upgrade gear, and interact with NPCs.
- Create upgrade UI.
- Create mission select UI.
- Create gems that can socket into armor.
- Separate floors with mini-hub to change gear.
- Create authored rooms with specific enemy compositions.
- Fix detonator spawns.
- Update enemy drops from gold coins.
- Update naming across project to "The Proof of Concept".
- Fix color tearing when resizing screen.
- Add fixed resolution options, including bordered fullscreen, windowed, and fullscreen.
