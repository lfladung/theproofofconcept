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

2. Flow (Speed / Tempo)
What it does:
Attack speed
Cooldown reduction
Movement speed (lightly)

High Expression:
Burst windows of extreme speed
Animations blend together
“Momentum” feeling


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