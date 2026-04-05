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
- **Cross-pillar hooks:** Edge (wall-slam crit windows / overkill), Flow (more hits → more launches), Phase (reposition through formations), Anchor (Brace/Bastion pressure and commit/rooted knockback immunity—see **section 5**), Surge (shockwaves as burst moments), Echo (delayed / repeated impacts).

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

**Runtime status (implemented):** Server / offline **damage authority** only for pressure, micro-shield, bastion charge, and incoming damage shaping. Tuning in `scripts/infusion/infusion_anchor.gd`. Incoming pipeline: `PlayerDamageReceiverComponent` calls `Player.anchor_preprocess_incoming_damage` before `HealthComponent.apply_damage`; successful **guard blocks** call `Player.anchor_on_guard_block_success` for Brace purges. State (`_anchor_pressure`, `_anchor_micro_shield`, `_anchor_bastion_charge`, rooted / critical-bastion flags) replicates on periodic `_rpc_receive_server_state` snapshots. Infusion thresholds map **Baseline → tier 1 (Fortify)**, **Escalated → tier 2 (Brace)**, **Expression → tier 3 (Bastion)**.

**Design loop:** chip hits are softened (DR + micro-shield + optional knockback immunity during commits); Escalated+ turns part of each hit into a **pressure meter** that decays if you stabilize, spills into the next hit if you don’t, and can be **purged** with a timed guard or a melee that actually connects; Expression adds **stand-your-ground** charge → **rooted bastion** → **move/dodge to detonate** stored pressure as an AoE, with a **critical bastion** spike if pressure crosses a threshold while rooted.

### Tier 1 — Fortify (Anchor Baseline+)

- **Flat damage reduction** on all pre-health incoming damage (`fortify_flat_damage_reduction`).
- **Micro-shield:** absorbs from the next hit up to a **cap**; **taking HP damage** after mitigation adds a small stack back into the shield (`fortify_micro_shield_gain_per_hit` / `fortify_micro_shield_cap`).
- **Commit knockback immunity:** while in an attack commit (melee or ranged **charging**, or active melee **hitbox visual window**), **incoming knockback on the damage packet is zeroed** (`fortify_attack_commit_knockback_immunity`). There is still no global “cancel swing on hit” rule in the codebase—**poise / interrupt** hooks remain a future follow-up when a real interrupt pipeline exists.

**Feel:** lighter chip damage, slightly tankier trades, swings less likely to be thrown by knockback (when enemies apply it).

### Tier 2 — Brace (Anchor Escalated+)

- **Reserve:** a **fraction** of each hit’s damage is moved into **`_anchor_pressure`** instead of immediate HP (`brace_reserve_ratio`); pressure **decays per second** while you avoid new hits (`brace_pressure_decay_per_sec`).
- **Hit spill:** if pressure was already > 0, a **fraction** of that reserve is **added to the current hit’s immediate damage** before DR/shield (`brace_hit_spill_ratio`)—second hit hurts more if you didn’t stabilize.
- **Offense while pressured:** extra **flat melee damage** scales with pressure (capped) plus a tiered flat bonus while reserve is meaningful (`outgoing_melee_bonus` + `brace_while_reserve_melee_bonus`).
- **Purge windows:**
  - **Guard:** any successful **directional block** that converts damage to stamina can **purge** a chunk of pressure and emit a small **radial shockwave** (`brace_purge_fraction`, `brace_purge_shockwave_radius`, `brace_purge_shockwave_damage_ratio`).
  - **Melee:** after a **server-authoritative** melee (or local single-player melee) that hits **at least one** enemy, the same purge + shockwave can fire—**whiffs do not** stabilize reserve.

**Feel:** intentional tanking and timing; defense feeds short offensive spikes; shockwave is tagged `anchor_purge_shockwave` and suppresses Edge/Mass/Echo recursion on those packets.

### Tier 3 — Bastion (Anchor Expression)

- **Charge:** while **not moving** (no move intent, no dodge press, not in dodge time) and in a **stance** (defending, melee/ranged charging, or active melee swing window), **`_anchor_bastion_charge`** fills; it **decays** when you drift (`bastion_charge_rate_per_sec` / `bastion_charge_decay_per_sec`). At **full**, you enter **`_anchor_rooted`** and charge resets.
- **While rooted:** most **new** incoming damage is shifted into **pressure** instead of immediate HP (`bastion_incoming_to_reserve_ratio`), with **extra flat DR** (`bastion_extra_flat_reduction_while_rooted`); **knockback** on packets is cleared. If pressure crosses **`bastion_critical_pressure_threshold`**, **`_anchor_critical_bastion`** arms for a stronger release (`bastion_critical_release_multiplier`).
- **Release:** **move** or **dodge** (first frame of intent) calls **`_anchor_release_bastion`**: clears rooted + pressure, deals **AoE damage** around the player scaled by stored pressure (`bastion_release_radius`, `bastion_release_damage_ratio`), packet label `anchor_bastion_release`. Critical flag is consumed on release.

**Feel:** “I stand, I absorb, I step and everything breaks.” Positioning and timing matter; no infinite AFK tank—power is tied to **release** and **purge** windows.

### Guardrails (multiplayer + tuning)

- **Pressure cap:** `_anchor_pressure` is clamped (currently **120**) so pathological stacking cannot run away.
- **Authority:** preprocessing and bastion tick / release run only where `Player.is_damage_authority()` is true; snapshots mirror visuals/HUD-friendly state to non-server peers.
- **Stub removed:** Anchor no longer uses linear **+melee per pickup**; melee bonuses are **conditional** (pressure / rooted / critical bastion) via `outgoing_melee_bonus`.

**Not yet in runtime:** dedicated **pressure / rooted** HUD bar or audio heartbeat; **poise vs swing-cancel** when a global interrupt rule exists; cross-pillar synergies called out in design (Edge crit on release, Mass-scaled shockwaves, Flow-tightened purge windows, Echo duplicate shockwaves, Phase ghost interaction, Surge energy conversion)—constants and hooks can be added in `infusion_anchor.gd` / `player.gd` when those pillars expose stable APIs.

**Debug:** debug builds can add Anchor stacks with **F8** on the player (see `player.gd` unhandled input alongside **F9 Edge** and **F10 Flow**).

6. Phase (Weirdness / Rule-Breaking)

**Runtime status (implemented):** Server / offline **damage authority** only for spatial damage and body collision changes. Tuning in `scripts/infusion/infusion_phase.gd`; combat and scheduling in `scripts/entities/player.gd`. `DamagePacket` carries `mitigation_ignore_ratio`, `suppress_phase_procs`, and `ignore_directional_guard` (`scripts/combat/damage_packet.gd`). Enemy mitigation uses `HealthComponent.flat_damage_mitigation` + bypass split (`scripts/combat/health_component.gd`). Directional shields respect `ignore_directional_guard` in `scripts/combat/directional_guard_damage_receiver_component.gd`. Handgun **wall pierce** (Expression) in `scripts/entities/arrow_projectile.gd` (`configure(..., wall_pierce_hits_remaining)`). Readability VFX in `scripts/visuals/player_visual.gd` (`show_phase_spatial_cue`, `show_phase_dash_trail_cue`). Infusion thresholds map **Baseline → Slip**, **Escalated → Skew**, **Expression → Fracture**.

**Design identity:** Phase is **spatial multiplication**—collision, origin of hits, and targeting assumptions break—not a pure damage pillar. Distinct from **Echo** (delayed hits tied to the **victim**): Phase **ghost** strikes replay the arc from a **past player position** after a delay.

### Tier 1 — Slip (Phase Baseline+)

- **Body-block bypass:** During each melee resolve, the player’s `CharacterBody2D` **collision_mask** temporarily drops the **mob body** bit (`collision_layer = 2` on enemies) for the melee visual/hit window plus a short extra (`slip_collision_window_extra_sec`). Hurtbox and attack layers unchanged; **not** invulnerability—incoming damage is unaffected.
- **Mitigation bypass (data + fallback amp):** Outgoing melee / ranged / bomb damage still uses a **1 + armor_ignore_ratio** multiplier (15% Baseline, 30% Escalated+) for targets with no flat mitigation. `DamagePacket.mitigation_ignore_ratio` matches that ratio so that when `HealthComponent.flat_damage_mitigation` is set on an enemy, only the non-bypass fraction is reduced.
- **Phantom reach:** Melee **forward depth** scales by tier—**~1.04×** at Baseline+, **~1.09×** at Expression (`combined_melee_depth_multiplier`). Primary swing still uses the normal `Hitbox2D` path (already hits **multiple** enemies per swing; no single-target melee cap).

### Tier 2 — Skew (Phase Escalated+)

- **Afterimage / ghost strike:** After a primary melee resolve, a **delayed** second sweep uses the **same** melee polygon from the **position and facing recorded at commit** (~40–48% primary damage, tiered delay ~0.11–0.21s). Follow-up packets use `suppress_phase_procs` + `suppress_echo_procs` so Phase/Echo do not recurse off each other.
- **Angle warp:** Before the swing locks in, **server / local authority** can **rotate facing** up to a capped angle toward the nearest enemy in a forward **cone** (tuned in `infusion_phase.gd`).
- **Phase dash trail:** On **dodge start**, a **cooldown-gated** radial burst (`phase_dash_trail`) deals partial estimated melee damage around a point along the dash; VFX cue on the player visual.
- **Contact chip:** While the **Slip** body window is active, **Skew+** can apply small **cooldown-gated** chip damage to the **nearest** overlapping enemy (prevents per-frame melt).

### Tier 3 — Fracture (Phase Expression)

- **Multi-origin / flanks:** Two extra **polygon** melee resolutions at **± perpendicular** offsets from the player (fractional damage vs primary). Same suppression tags as ghost/aux hits.
- **Inside-out vs directional guard:** Expression Phase tags primary melee (and aux packets) so **`ignore_directional_guard`** bypasses `DirectionalGuardDamageReceiverComponent` when present—not a global “ignore all defenses” flag.
- **Geometry violation (handgun):** Player arrows can **ignore** a capped number of **wall** `body_entered` terminations (`ranged_wall_pierce_hits`, currently **2** at Expression). Does not unlimited tunnel through level geometry.

### Multiplayer and readability

- Ghost damage runs only on **authority**; remote peers get **approximate** ghost timing + position via extended melee RPC args and **blue** world-space cues (delayed sphere) so packs are not silent.
- **Not yet in runtime (deferred by design):** **Blink strike** (validated short-range position snap + replication), **phase loop** (persistent locked coordinate / linger zone), **bomb** Phase parity (`ideas/EQUIPMENT_UPGRADES.md` still lists bomb ideas; implementation focused melee + movement + handgun pierce first).

### Guardrails

- No full intangibility: only **mob body** collision is cleared, and only for a **short** post-melee window tied to the attack.
- Wall pierce is **count-limited**; flank/ghost use explicit packets so stacking with Echo remains rule-driven via flags.


7. Surge (Energy / Burst Power)

**Runtime status (implemented):** Protection-oriented charge fantasy: **charging is not punished**—holding commit builds a **charge field** that slows and disrupts nearby enemies; full and overcharged releases add **burst damage** and a **secondary radial hit**; Expression adds **Surge energy**, **Overdrive**, and a **finale** when the battery empties. Tuning and pure math in `scripts/infusion/infusion_surge.gd`. Player combat, overcharge input, energy, overdrive drain, and field application in `scripts/entities/player.gd` (including extended `_rpc_request_melee_attack` for **normalized overcharge** and unreliable `_rpc_surge_charge_field_report` so **dedicated servers** still get hold-state for the aura). Enemy debuffs via `EnemyBase.surge_infusion_refresh_charge_field` + tick decay; movement and attack cadence wired in `scripts/entities/mob.gd`, `robot_mob.gd`, and `iron_sentinel.gd`. Infusion thresholds map **Baseline → tier 1 (Primed charge + light field)**, **Escalated → tier 2 (Overcharge hold + stronger field + pulses)**, **Expression → tier 3 (Surge energy + Overdrive + finale)**.

**Design identity:** **Zone control** and **momentum protection**—you earn space by committing to charge; payoff is **bigger releases** and, at high tier, a short **dominion** window where the field stays maxed and melees count as fully charged.

### Tier 1 — Primed charge (Surge Baseline+)

- **Flat melee** bonus (tiered) stacks with other infusion flats in the normal melee damage pipeline.
- **Charge field (light):** While melee or ranged charging **after** the usual commit delay, enemies inside a radius (scales with **charge ratio** and tier) are **slowed**; debuff is **TTL-refreshed** each server tick so physics order stays stable.
- **Primed full release:** At **full** melee charge **without** meaningful overcharge, extra **flat** damage; melee **secondary burst** (`surge_secondary` on `DamagePacket`) around the player if the swing **hit** at least one target—radius and damage ratio scale with tier and overcharge norm (overcharge 0 here).

### Tier 2 — Overcharge (Surge Escalated+)

- **Hold past full (melee only):** Game no longer **auto-releases** at 100% charge; you can hold up to a **max overcharge time**, then release. Normalized overcharge (0..1) scales **melee damage multiplier** and **secondary burst** size/damage.
- **Charge field (active):** Larger radius, **stronger slow**, and **enemy attack cooldown** ticks slower (`robot_mob` / `iron_sentinel`; dasher-style mobs use stun micro-pulses instead of a cooldown scalar).
- **Energy pressure pulses:** On an interval, enemies in the field take a **micro action delay** (tiny stun on `Mob`, extra cooldown / charge cancel on `RobotMob`)—**not** hard knockback.

### Tier 3 — Overdrive (Surge Expression)

- **Surge energy:** Built on **server-resolved** charged melee hits (more for **full charge**, **multi-target**, and **overcharge**); clamped to a max pool (`surge_energy_max`).
- **Enter Overdrive:** On a **melee hit** (not whiff), if **overcharge** is high enough, **Expression** tier, and energy ≥ **entry cost**, pay the cost and enter **Overdrive**.
- **During Overdrive:** Field uses **overdrive** tuning (wider, stronger slow, faster pulses, stronger cadence slow); your **melee damage** uses **full charge** scaling; **self move speed** is slightly reduced (`overdrive_player_move_speed_mult`).
- **Exit — finale:** While Overdrive is up, energy **drains per second**; when it hits ~0, Overdrive ends and a **`surge_finale`** ring fires—damage scales with **energy consumed during the window** (`finale_damage_ratio_for_energy_used`), plus knockback from tuning.

### Multiplayer and guardrails

- **Authority:** Field slows and pulse interrupts run on **server** (or offline). Non-host clients **report** charge/overcharge **unreliably** to the server so hold-state exists without simulating local input on the dedicated host.
- **Validation:** Server **clamps** reported overcharge to the design range; melee RPC carries **surge_overcharge_norm** (extra arg, default 0 for compatibility).
- **Ranged:** Charge field applies while **gun** is charging; **overcharge hold** is **melee-only** (gun still auto-releases at full charge).

**Not yet in runtime:** Projectile slow inside the field; replication of **Surge energy / Overdrive** to the owning client for HUD; explicit **run-boundary reset** of `_surge_energy` (currently cleared on **downed** with `_surge_reset_combat_state`; cross-run persistence is a follow-up if desired).

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