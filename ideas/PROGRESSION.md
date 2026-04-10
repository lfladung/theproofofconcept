# Progression Design

Three tiers of reward. Each exists at a different timescale.
Each feels different in play. Together they create the full loop.

---

## Design Philosophy

Three principles guide every decision in this system:

**Amplification over accumulation** — you don't collect power, you focus it.
**Commitment over randomness** — strong builds require intentional direction, not lucky drops.
**Agency over correction** — currency doesn't fix builds, it shapes them.

---

## The Three Tiers

| Tier | Frequency | Impact | Timescale |
|------|-----------|--------|-----------|
| **Macro** — Infusions | After every floor / boss | Build-defining | Entire run |
| **Mid** — Discoveries | Side rooms, elites, events | Build-nudging | Multiple floors |
| **Micro** — Resonance | Every combat encounter | Build-shaping, spendable | On-demand |

---

## Tier 1: Macro — Infusions

*The thing that makes your run feel like yours.*

### What they are
Infusions are run-permanent amplifiers tied to the seven concept pillars:
 **Edge, Flow, Mass, Echo, Anchor, Phase, Surge**.

They do not grant flat stats. They activate and escalate pillar-coded behaviors across your equipped gear.

> Gear defines what you can do. Infusions define how far it goes.

An Edge infusion doesn't add +damage — it feeds the Edge-coded behaviors already present in your sword (cleave, crit),
armor (bonus damage at full HP), and any other slot with Edge expression. The infusion is fuel, not content.

### Acquisition
After completing each floor, one infusion manifests — random, and yours.
No menu. No selection. The Pit gives you something and you carry it forward.

Boss floors give a **Boss Infusion**: stronger, sometimes rule-bending or hybrid.
Same rule — random, mandatory, no choice.
In multiplayer, each player receives a different random infusion. The party diverges.

The run adapts to what you receive. That is the design.

### Stacking and thresholds
Infusions of the same pillar stack. Thresholds unlock intentional power spikes:

- **1 infusion** — baseline behavior active
- **2 infusions** — escalated effect
- **3 infusions** — high-expression unlock (build-defining moment)

These are not passive scaling. Hitting the 3-stack threshold is a milestone — the run snaps into focus.

Stacking is the peak power path. It is strong, but:
- Not guaranteed (manifestations are not chosen, they appear)
- Not the only viable path (see Cross-Pillar Synergies below)
- Requires commitment — going for a 3-stack means passing on diversification

Players choose between **specializing** (chasing thresholds) and **diversifying** (cross-pillar interactions).
Both are viable. Neither is dominant by design.

### End of run: conversion to materials
When a run ends — win or death — all held infusions dissolve. They become **pillar materials**.

Conversion is straightforward: each infusion yields material of its pillar type.
Boss infusions yield more than standard infusions.

There is no usage tracking. No optimization pressure. No hidden math.
The run was yours — the materials are what it left behind.

---

## Tier 2: Mid — Discoveries

*Not every reward changes your build. Some of them just nudge it.*

Discoveries are **found**, not offered. Side rooms, elite enemies, events. You have to look for them.

### Mini-Infusions
Half-strength infusions. They contribute to pillar stacking (1 mini = 0.5 toward thresholds).
Worth finding when one step from a threshold, or supplementing a pillar you're not heavily investing in.

### Gear Augments
Floor-scoped power boosts. They last until the next floor transition, then fall away.

Examples:
- *Unstable Edge* — 40% more damage this floor, but crit hits cause brief self-stagger
- *Rushing Current* — movement speed +30% this floor
- *Echo Chamber* — all effects have a 25% repeat chance this floor

Augments are powerful but temporary. They reward exploration without changing your build trajectory.

### Events
Encounters that aren't combat rooms. Choices with tradeoffs — no always-correct answer.

Examples:
- A cracked infusion on the ground. Pick it up: gain a mini-infusion, take 15 HP damage.
- A sealed hollow. Break it open: enemies spawn, guaranteed elite material drops.
- A sleeping Grazer. Leave it, or disturb it for a material drop at some risk.

Events make the world feel inhabited rather than procedurally assembled.

---

## Tier 3: Micro — Resonance

*The thing that makes combat feel like it's always giving you something.*

Resonance drops from every enemy as swirling particles — pulled toward the player automatically.
The visual is the lore: enemies shedding what they were still in the process of becoming.

### Enemy drops
Every enemy yields Resonance on death. Amounts are defined in the enemy specs
(1 for Scramblers, 15 for The Warden). Clearing a room always feels productive.

### What Resonance does

**Currency is not for buying items. It is for manipulating your build mid-run.**

Four uses. Each is about shaping direction, not correcting mistakes.

---

**1. Reroll**
After a floor manifestation appears, discard it and draw a new random one.
Cost escalates per reroll — cheap the first time, painful the third.

> Converts bad RNG into agency. You didn't get what you needed — try again.

---

**2. Pin**
Before entering a floor, declare a pillar. The manifestation that comes out of that floor
is guaranteed to be from that pillar.

Cost is high — this is the most powerful Resonance spend.

> You know what you need. You're paying to make the Pit agree.

Pin is also available through meta-progression: reaching Inscription Tier III on a pillar
means it always appears in your floor draw — earned, not purchased.

---

**3. Stabilize an Infusion**
Choose one held infusion. Temporarily strengthen it:
- Its effects become stronger
- More consistent in interactions
- More dominant when cross-pillar interactions resolve

Duration: lasts until the next floor transition.

> For players who want to commit harder. "I have this — make it count."

---

**4. Force Propagation**
A chosen infusion temporarily bleeds into additional gear slots beyond its normal reach.

Example: a Flow infusion that normally affects only your sword now also influences your armor's
Flow expression for the remainder of the floor.

> Increases synergy without needing more drops. A way to punch above your infusion count.

---

### Cost philosophy
Resonance costs are not final numbers — they should be tuned in playtesting.
The intended feel: Reroll is accessible. Stabilize and Propagate are meaningful spends.
Pin is a real sacrifice — using it means you're not using anything else for a while.

---

## Cross-Pillar Synergies

*Support system, not replacement for stacking.*

Small hybrid interactions exist when a player holds infusions from multiple pillars.
These reward flexible builds without competing with 3-stack thresholds.

| Combination | Interaction |
|-------------|-------------|
| Flow + Phase | Evasive chaining — dodges chain into brief phase windows |
| Edge + Surge | Burst spikes — critical hits trigger a short Surge pulse |
| Anchor + Mass | Immovable pressure — blocking generates knockback mass |

Design rule: **cross-pillar interactions are never as strong as a completed 3-stack**.
They are the consolation that isn't a consolation — a genuinely different way to play,
not a fallback for players who couldn't stack.

---

## Meta-Progression: Inscriptions

*What persists when everything else dissolves.*

### The concept
Between runs, pillar materials are spent at a **pre-run workbench** to permanently inscribe
bonuses onto your gear. An inscription is dormant by default.

It activates only when you're holding a matching infusion during a run.

> You've encountered the concept enough times that it recognizes your gear.
> When you carry it again, it responds differently.

This is not passive stat inflation. Inscriptions make your runs **deeper** when you return
to the same concept — they do not make you stronger without infusions.

### How inscriptions work
Each gear slot can hold one inscription per pillar. Inscriptions are tiered (I → II → III),
each requiring more material than the last.

**Example: Sword, Flow pillar**
- *Flow I* — Flow infusions also slightly increase attack speed
- *Flow II* — the 2-infusion threshold immediately activates the escalated effect (no wait for 3rd)
- *Flow III* — the high-expression behavior unlocks at 2 stacked infusions instead of 3

Inscription III effectively gives you one threshold level "for free" on that pillar.
You still need infusions. The inscription just makes each one count more.

### Inscription identity
Over many runs, a piece of gear becomes something specific.
A sword with Edge III, Flow II, Surge I inscriptions is *your* sword.
It has been to The Pit with you. The concepts left their mark.

### Multiplayer note
Each player brings their own gear with their own inscriptions. A well-inscribed Edge sword
and a well-inscribed Phase sword in the same party create natural role differentiation
without class locks. Inscriptions are personal — shared runs accelerate everyone's material gather.

---

## How the tiers interact

**Micro → Macro:** Resonance rerolls let you chase a pillar when the manifestations don't cooperate.

**Micro → Macro (mid-run):** Stabilize, Propagate, and Overclock let you extend and amplify infusions
you already hold without waiting for the next floor offer.

**Mid → Macro:** Mini-infusions contribute to thresholds. Two side-room finds can push a build
across a threshold the floor offers couldn't reach alone.

**Macro → Meta:** Infusions dissolve into materials at run's end, feeding inscriptions.

**Meta → Macro:** Inscriptions lower threshold requirements on specific pillars,
making future runs with those infusions deeper from the start.

---

## The loop

> Fight → earn Resonance → spend it to shape your build in the moment →
> clear floors → choose infusions → commit to a direction →
> hit thresholds → unlock defining behaviors →
> run ends → infusions become materials →
> inscribe materials onto gear →
> return to The Pit and find that the concept recognizes you.

---

## Open Design Questions

- **Soft bias:** With a single floor draw, should the pillar pool be softly weighted toward pillars you already hold, or fully random? Weighting nudges toward thresholds; pure random creates more pivots and makes Pin a stronger spend.
- **Reroll limit:** Should there be a hard cap on rerolls per floor (e.g. max 3), or is the escalating cost sufficient as the natural ceiling?
- **Pin timing:** Can Pin be used mid-floor (buy it now, applies to the next floor) or only at the floor transition screen?
