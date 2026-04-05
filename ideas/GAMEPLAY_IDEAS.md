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

**Runtime status (design-first):** `scripts/infusion/infusion_mass.gd` is still a **stub** (+flat melee per Mass pickup). Tiered Mass mechanics below are **not** implemented. Loadout already declares `knockback_multiplier` (`STAT_KNOCKBACK_MULTIPLIER`) for future wiring into melee / impact math. Infusion thresholds map **Baseline → tier 1**, **Escalated → tier 2**, **Expression → tier 3**.

**What it does (design):** Every hit has **weight**—you shape enemy spacing and battlefield geometry instead of only deleting HP. Late tiers add terrain and collision payoffs, optional **downed** state, and expression-level **force direction** so rooms read as “compress → detonate” or “scatter → isolate.”

### Tier 1 — Heft (Mass Baseline+)

- **Knockback on all melee hits**; scales with enemy size (**small** enemies move a lot, **large** enemies budge).
- **Stagger meter** builds faster; you **interrupt** more often, especially on elites.
- **Impact AoE:** small **radial burst** around the primary target (secondary consequence, not full hitbox duplication—a true impact pulse).

**Feel:** “Hit → enemies slide → line them up.” Light crowd control without hard commitment; combat is about **spacing into walls and clusters**.

### Tier 2 — Crush (Mass Escalated+)

- **Wall slam:** enemies knocked **into walls** take bonus impact damage + **heavy stagger**.
- **Enemy collision:** knocked bodies **damage and stagger** other enemies they collide with.
- **Downed state:** heavy hits or repeated stagger can knock enemies **prone**; downed targets take **bonus melee damage**.

**Optional strong hook — Unstable:** tag enemies with a short **Unstable** window after being launched; the **next** impact (wall, enemy, ground) triggers an extra **burst**.

**Feel:** “Launch → slam → bounce into pack → chain stagger.” Pinball / chain reactions without hand-authored combo scripts.

### Tier 3 — Cataclysm (Mass Expression)

- **Ground slam trigger:** after X hits, on a heavy attack, or on an ability—**slam** creates a large **shockwave ring**; launches enemies **outward** *or* **inward** (pick a clear directional identity per build or stance).
- **Shockwave propagation:** shockwaves **chain through enemies**, extending effective range per hit.
- **Pin / crush zones:** enemies forced into **terrain** or **dense clusters** can become **pinned** (brief immobilize) or **crushed** (burst damage when multiple forces overlap).

**Signature — force direction control:** attacks **bias knockback direction**—e.g. **forward cone** (default) *or* slight **pull** then **outward burst** (vacuum + slam identity).

**Feel:** “Vacuum → slam → shockwave chain → everything pins against walls.” Reads like a **gravity / force weapon**, not plain melee.

### System fit (why it matches this project)

- Respects the **existing hitbox model**: primary swing still hits its arc; Mass adds **force, stagger, terrain, and collision** as follow-through.
- **Tiered complexity:** tier 1 is mostly passive feel; tier 2 is **positioning mastery**; tier 3 is **formation control**.
- **Cross-pillar hooks:** Edge (wall-slam crit windows / overkill), Flow (more hits → more launches), Phase (reposition through formations), Anchor (you resist knockback while acting as a ram), Surge (shockwaves as burst moments), Echo (delayed / repeated impacts).

### Guardrails

- Knockback must not feel **annoying**: slight **inward bias** or **friction** so packs do not scatter into empty space; **“they slide, not fly.”**
- **Large enemies** resist meaningfully but do not **ignore** Mass.
- If **wall slam** is a multiplier, **walls** must stay **readable** and intentional in room design.

**Not yet in runtime:** stagger meter tuning, wall/enemy collision damage, downed / pinned / unstable states, shockwave propagation, force-direction bias, and InfusionMass tier hooks beyond the current damage stub.

4. Echo (Repetition / Multiplicity)

**Runtime status (implemented):** Server-authoritative melee reverberation and handgun twin bolts in `scripts/infusion/infusion_echo.gd`; hooks in `scripts/entities/player.gd` (melee `Hitbox2D.target_resolved`, ranged RPC + spawn), `scripts/entities/enemy_base.gd` (Chorus **imprint** window, Edge proc guards for echo hits), and `scripts/combat/damage_packet.gd` (`is_echo`, `echo_generation`, `suppress_echo_procs`). Infusion thresholds map **Baseline → tier 1 (Reverberate)**, **Escalated → tier 2 (Chorus)**, **Expression → tier 3 (Resonance Cascade)**.

**Design loop:** tier 1 is a **flat** proc chance band (not linear 20→40→60%); tier 2 adds **state** (imprint → guaranteed follow-up behavior); tier 3 adds **controlled recursion** (child echoes with generation cap).

### Tier 1 — Reverberate (Echo Baseline+)

- **Afterimage melee:** chance (~22%) to schedule a delayed follow-up hit (~0.10–0.20s) for reduced damage (~44–52% of the damage that just resolved on the target). Copies crit/backstab flags from the primary hit so Edge mark / prime **preprocess** still reads the hit as a crit; echo hits do **not** apply Sever bleed, new Sever marks, or Edge kill splash/overkill (`is_echo` guards).
- **Projectile twin:** handgun shots can spawn a **parallel** bolt (lateral offset, ~52% damage, replicated to clients via extended ranged attack RPC).

### Tier 2 — Chorus (Echo Escalated+)

- **Echo imprint:** each successful primary melee hit refreshes a short imprint on the victim (~1.15–1.35s). If the **next** melee hit on that enemy arrives while the imprint is still active, the proc is **guaranteed** and expands into **2–3** spaced micro-hits (Chorus spacing) instead of one afterimage.
- **Linked target:** after the last micro-hit of a reverberate wave, spill damage to the **nearest** other enemy in radius (soft chain-lightning tied to repetition).

### Tier 3 — Resonance Cascade (Echo Expression)

- **Recursive echo (controlled):** the **last** micro-hit of a wave may roll a **child** echo (decayed damage again, new delay). Hard cap via `max_echo_generation` (child echoes do not chain-link to spare explosion).
- **Not yet in runtime:** echo fields (spatial memory zones), action replay, on-kill echo burst — reserved for later; tuning lives in `infusion_echo.gd` when added.

### Guardrails

- Echo packets are tagged `is_echo`; Edge **bleed / mark-from-crit / kill procs** ignore them to prevent recursive proc soup. Echo melee still flows through Mass stagger / impact pulse hooks where applicable.
- `suppress_echo_procs` on a packet prevents scheduling further echo logic from that strike (future use).

**Not yet in runtime:** ghost-swing / afterimage VFX, dedicated echo SFX layering, echo fields, action replay, kill burst.

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