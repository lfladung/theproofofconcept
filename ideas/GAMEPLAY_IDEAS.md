1. Edge (Precision / Damage)

**Runtime status (implemented):** Server-authoritative melee on `EnemyBase` / `Player`. Tuning lives in `scripts/infusion/infusion_edge.gd`; combat hooks in `scripts/entities/player.gd`, `scripts/entities/enemy_base.gd`, and `scripts/combat/damage_packet.gd` (`is_critical`, `suppress_edge_procs` for secondary hits). Infusion thresholds map as **Baseline → tier 1**, **Escalated → tier 2**, **Expression → tier 3**.

**What it does (design):** Reward aim and target choice; turn overkill and chains into tempo; late tier adds execution fantasy.

### Tier 1 — Sharpen (Edge Baseline+)

- Extra flat melee damage (existing `melee_damage_bonus` hook).
- **Crits** deal significantly more damage (multiplier stacks with the player’s melee crit mult; loadout `crit_chance_bonus` + `melee_base_crit_chance` feed rolled crits).
- **Rear “backstab”** is treated as a **guaranteed crit** (same crit multiplier path as rolled crits; no separate backstab damage stack).
- **Kill splash:** on lethal hits, a fraction of absorbed damage is dealt in a small radius (split across nearby enemies).

### Tier 2 — Sever (Edge Escalated+)

- **Overkill spill:** excess damage vs. the victim’s HP before the hit spills into a **forward cone** (decaying damage over multiple hops).
- **Bleed:** melee **crits** apply a short DoT (server tick; uses `suppress_edge_procs` so it does not recurse Edge procs).
- **Mark:** after a damaging crit resolves, the target gains a window where **Edge-attuned** follow-up hits deal increased damage (mark applies **after** the crit hit so that hit is not self-amplified).
- **Kill tempo:** killing an enemy grants a short **bonus crit chance** window (stacks with loadout crit bonus).

### Tier 3 — Execution / Primed (Edge Expression) — reworked

- **Execute:** if current HP% is at or below **~20%**, the hit is forced lethal (no stack-based threshold).
- **Primed target:** melee **crits** from an Expression Edge attacker apply **prime** for **X seconds** (tuned in `execution_prime_duration_sec`). The Sever **mark** glow is **normal size** when the enemy is marked but **not** primed; **primed** uses the **same mesh at 2× scale** (mark can still be active alongside prime).
- **While primed:** victims take **extra Edge damage** on incoming Edge hits (`execution_prime_edge_damage_multiplier`, after Sever mark if both apply).
- **Primed death:** if they die with overkill while still primed and the **killer** has Expression Edge, spill uses the **full overkill amount** (no `sever_overkill_spill_ratio` shrink), **no per-hop pool decay**, chain **picks lowest current HP** in the cone (ties → nearer). Other kills still use tier-2 style spill (ratio + decay + nearest).
- **Expression geometry:** existing wider melee arc (`expression_geometry_mult`) unchanged.

**Not yet in doc / future hooks:** Dedicated weak-point colliders (today, “precision” is **crit + rear crit** only). UI color pass for crit numbers optional.

2. Flow (Speed / Tempo / Momentum)

**Runtime status (implemented):** Server-authoritative tempo state on `Player`; tuning and pure math in `scripts/infusion/infusion_flow.gd`. Tempo / chain / Overdrive replicate via combat event RPCs and periodic server snapshots (`_rpc_receive_server_state`). Infusion thresholds map **Baseline → tier 1 (Accelerate)**, **Escalated → tier 2 (Chain)**, **Expression → tier 3 (Overdrive)**.

**Design loop:** open fight → build tempo → chain actions → hit Overdrive → sharp drop → rebuild. Rewards continuous engagement; avoids passive global CDR and permanent speed.

### Tier 1 — Accelerate (Baseline tempo shift)

- Small always-on attack-speed floor (`passive_attack_speed_floor`).
- **Tempo stacks:** each weapon action (melee / gun / bomb) adds pressure on a **0..1 meter** that decays quickly; higher tempo increases effective attack speed (`tempo_attack_speed_multiplier`).
- **Aggression recovery:** after a weapon action, a short **aggression window** speeds up **cooldown tick rate** on melee, gun, and bomb timers (not a shorter passive cap — conditional, decays with the window).
- **Feel:** first swings normal; sustained combat ramps speed until you drop the pace and tempo falls off.

### Tier 2 — Chain (Action linking)

- **Flow chain window:** after any weapon action, a ~0.8–1.1s window (tiered) where the next action gets a **chain attack-speed bonus** and **extra tempo** when the window was active.
- **Alternating tools:** changing action family (melee vs ranged vs bomb) **extends** the chain window (`CHAIN_ALTERNATE_EXTENSION_SEC`).
- **Ability respect:** melee hits during an active chain **pulse** gun and bomb cooldowns by a small flat amount (`CHAIN_MELEE_ABILITY_CD_PULSE_SEC`) so primary fire meaningfully feeds abilities.
- **Feel:** rhythm and sequencing matter; mixed loadouts chain harder than one-button spam.

### Tier 3 — Overdrive (Expression tempo breakpoint)

- **Enter Overdrive:** at Expression, when tempo reaches **full** after an action, consume that spike and enter a short **Overdrive** window (`OVERDRIVE_DURATION_SEC`).
- **During Overdrive:** large attack-speed multiplier, much faster cooldown ticks, snappier move speed (`OVERDRIVE_MOVE_SPEED_MULT`), shorter visual facing-lock / animation window (`OVERDRIVE_ANIM_TIME_MULT`) for **soft animation compression** (presentation-only; hit timing stays authoritative).
- **Exit cliff:** when Overdrive ends, tempo is **crushed** (`OVERDRIVE_EXIT_TEMPO_MULT`) and the chain window can clear so you must rebuild — avoids permanent blender state.
- **Echo-lite (planned):** rare / small follow-up strike distinct from Echo — constants reserved in `infusion_flow.gd`; not yet attached to the damage pipeline.

### Guardrails (multiplayer + hitboxes)

- No pure passive CDR at Baseline (`cooldown_multiplier` stays 1.0 there); recovery spikes come from **aggression** and **Overdrive tick multipliers**.
- No animation-cancel exploits on damage authority: only **visual** lock compression under Overdrive.
- State advances **only on the server** in multiplayer; clients merge snapshots from RPCs so tempo stays consistent with decay run everywhere.

**Not yet in runtime:** true hitbox-phase cancels; Echo-lite proc on `EnemyBase` / `DamagePacket`; UI tempo / Overdrive readout.


3. Mass (Impact / Control)
What it does:
Knockback
Stagger
AoE impact

High Expression:
Ground slams
Shockwaves
Enemies get launched or pinned

4. Echo (Repetition / Multiplicity)
What it does:
Chance to repeat attacks
Multi-hit effects
Projectiles duplicate

High Expression:
Chain reactions
Cascading hits
Attacks “linger” in time

5. Anchor (Stability / Defense)
What it does:

Damage reduction
Poise / stagger resistance
Shields / sustain

High Expression:
Damage converts to delayed damage
Temporary invulnerability windows
“Rooted power” feeling

6. Phase (Weirdness / Rule-Breaking)
What it does:

Piercing attacks
Ignore armor
Pass through enemies/objects

High Expression:
Teleporting strikes
Hits from unexpected angles
Geometry-breaking interactions


7. Surge (Energy / Burst Power)
What it does:
Charge mechanics
Burst damage
Energy buildup

High Expression:

Explosive releases
Overcharge states
Big “moment” attacks

Secondaries
1. Bloom (Growth / Scaling Over Time)
Effects get stronger the longer you fight
Ramp mechanics


2. Leech (Sustain / Vampirism)
Heal on hit
Convert damage into sustain

3. Bind (Control / Slow / Freeze)
Slow enemies
Root / freeze mechanics


4. Rupture (Damage Over Time / Explosive Effects)
Bleed, burn, delayed explosions

**Note:** Edge **Sever** (Escalated+) currently implements a **melee crit bleed** on enemies; other pillars may add DoTs later.