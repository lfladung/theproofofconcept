# Layer Design

The Pit is not a dungeon. It is not a cave. It is a place where reality is still forming.

Each layer is a distinct biome — a different stage of that forming. Near the surface, things almost make sense.
Deeper, the Pit has had more time to iterate. The further you descend, the more fully expressed everything becomes:
the creatures, the environment, the rules themselves.

4–5 floors per layer. The final floor is always the layer boss.

---

## Layer 1: The Edge of the Pit

> "Everything here was almost normal once."

**Floors:** 1–5 (tutorial layer — first contact with The Pit)

### Aesthetic

Warm, sun-soaked. The rim of the pit is still close enough to light everything. Rocky cliff faces pocked with hollows and
natural alcoves. Petrified trees with roots that reach out horizontally — turned to stone mid-growth, frozen in the
act of seeking the sun. Grass grows in cracks. The sky is visible above. It feels almost safe.

Color palette: golds, sandy whites, sun-bleached greens. Shadows are warm, not cold.

The creatures here are animals. Fantastical, wrong in subtle ways, but animal. They do not hunt you by design.
They react. Some will ignore you entirely. Some will charge if cornered. The threat is real — but it still feels
like wildlife, not like war.

---

### Enemy Roster

**Native fauna (Layer 1 unique):**

**Grazer**
*The concept of territory — self-preservation without self-awareness*
- A large, slow herbivore with a thick hide. Wanders its hollow. Ignores the player if they keep distance (~6 units).
- If the player crosses into its territory or deals damage: it charges (RUSH behavior, high knockback on contact). Runs past the player and resets.
- High HP. No coordinated attacks. The threat is its size and the knockback — getting hit into a wall or off a ledge.
- **Stats:** 80 HP · Ignore radius: 6 · Charge speed: 16 · Contact damage: 22 · Drops: 2 Resonance + hide material
- **Spawn guidance:** 1–2 per room, grazing. The "peaceful option" is always available — teach players early that not everything needs to be fought.

**Swooper**
*The concept of trajectory — movement with a target it doesn't understand*
- A large gliding creature that circles above the room at high elevation. Cannot be hit while circling.
- Every 5–7s: selects a player and dives. Deals damage in a small area at impact, then immediately returns to altitude.
- **Dive telegraph:** 1.5s of circling tightening into a spiral before the dive. The impact point is where the player was at telegraph start — it cannot course-correct mid-dive.
- Low HP — one or two solid hits while it's grounded after a dive kill it. The challenge is the timing and the vertical angle.
- **Stats:** 20 HP · Dive damage: 18 · Dive interval: 5–7s · Drops: 1 coin + feather material
- **Spawn guidance:** 2–3 circling simultaneously. Staggered dive timers create layered aerial pressure. Teaches players to watch for overhead threats early.

**From existing families (surface-tier only):**
- **Scrambler** (RUSH) — first enemy the player meets
- **Spitter** (VOLLEY) — introduced mid-layer, teaches projectile evasion
- **Stumbler** (WEIGHT) — introduced late layer, teaches ground telegraphs
- **Spawner Sac** (ECHO) — introduced as a room gimmick: "kill the source"
- **Fizzler** (SURGE) — chain tutorial in a corridor room

*Mid and deep tier monsters do not appear in Layer 1.*

---

### Layer Boss: The Sentinel

*The concept of guardianship — protection without judgment*

A massive stone-and-flesh beast that has lived in its hollow for so long it has partially petrified. Limbs are stone.
The chest cavity is still organic, still breathing, still glowing faintly. It does not leave its hollow. It waits.

Entering the hollow is the provocation.

**Phase 1:**
- Slow movement. Stomps (WEIGHT family: expanding shadow AoE, 1.5s telegraph, high knockback).
- Every 10s: a boulder throw — lobs a heavy object that leaves a persistent debris field (reduces movement speed while standing on it for 3s).
- Highly telegraphed. The lesson is: read the telegraph, move early, don't panic.

**Phase 2 (below 50% HP):**
- Exposes the glowing chest cavity — this is the only weakpoint (3x damage).
- Begins charging RUSH-style after the player for 3s, then resets. High speed for something this large. The chest is vulnerable during the charge.
- Boulder throw rate increases: every 6s.

**On death:** collapses inward. The cavity opens completely. Inside: a half-formed object — a piece of equipment or a rare material. The first lore fragment. *Something was growing inside it. We don't know what it was meant to become.*

- **Stats:** 400 HP · Stomp damage: 30 · Boulder damage: 20 + debris field · Charge damage: 35 · Drops: Boss chest + layer clear reward

---

### Layer 1 Design Intent

This layer teaches:
- Basic movement and hitbox reading (Scrambler)
- Projectile evasion (Spitter, Swooper)
- Ground telegraph timing (Stumbler, Sentinel Phase 1)
- Prioritization (Spawner Sac)
- That some encounters can be avoided (Grazer)

The reality of The Pit is present but quiet. Petrified trees. Creatures that are "almost" right. The sky is still overhead.
Players should leave Layer 1 feeling capable — and slightly unsettled by what they didn't expect.

---

---

## Layer 2: The Canopy Descent

> "The sun doesn't reach here. You'll feel it before you see it."

**Floors:** 6–10 (first truly dangerous section)

### Aesthetic

The transition is abrupt. One floor you're in the warm rock hollows. The next, the ceiling closes in — enormous
fern-like vegetation, prehistoric root systems, canopy so dense it chokes the light down to ambient green.
Everything is oversized: leaves the size of walls, roots thick as corridors, stalks that block line of sight.

Color palette: deep greens, shadowed blacks, occasional bioluminescent yellow-green where spores drift. Visibility is
actively reduced. The environment conceals.

The creatures here are predators. Not reactive — hunting. The wildlife of Layer 1 was territory and instinct.
This is intention. Things here know you're food.

---

### Enemy Roster

**Native fauna (Layer 2 unique):**

**The Briar**
*The concept of ambush — the predator that makes the environment part of itself*
- A large quadruped with a hide that matches the vegetation. While stationary, it is nearly invisible (low opacity, geometry blends into foliage). When it moves, it becomes fully visible.
- Behavior: stalks toward the player slowly while stationary (moves only when the player looks away or is occupied). At close range (~4 units): lunges for a high-damage bite.
- **Stalk telegraph:** a subtle shimmer in the foliage — similar to Lurker's phase shimmer, but wider. If the player faces it, it freezes (stops movement entirely). Will circle to get behind the player.
- On hit: dashes back to nearest cover and resumes stealth.
- **Stats:** 65 HP · Lunge damage: 32 · Stalk speed: 3 (while stationary-moving) · Lunge range: 4 · Drops: 4 Resonance + hide
- **Spawn guidance:** 1–2 per room. Works best in rooms with line-of-sight breaks from large vegetation. Teaches players to not focus tunnel-vision on the current threat.

**Herdcaller**
*The concept of coordination — incomplete social structure*
- A smaller creature on its own, unaggressive. Does not attack. Runs from the player.
- **Its role:** if not killed quickly, it emits a sound pulse every 5s that buffs nearby enemies (increases speed by 20%, attack rate by 15% for 8s). Nearby creatures immediately move toward the Herdcaller's position.
- Does not fight. Has moderate HP for its size. Stays at maximum range from the player.
- **Stats:** 45 HP · Speed: 10 (evasive) · Buff pulse: 5s interval · Drops: 3 Resonance
- **Design purpose:** Forces prioritization under pressure. Killing it is always the correct answer, but it's designed to be elusive.

**Canopy Drifter**
*The concept of dispersion — spreading what it carries without knowing why*
- A large, slow jellyfish-like creature that drifts near the canopy level, slightly above the player.
- Periodically releases spore clouds (AoE zones, 3-unit radius, linger for 5s). Standing in a spore cloud applies a slow and deals mild damage over time.
- Very high HP for a passive enemy. Does not pursue or react to the player. Can be damaged.
- **Stats:** 90 HP · Spore damage: 4/s · Spore slow: 25% · Release interval: 8s · Drops: rare spore material
- **Spawn guidance:** 1 per room as an environmental layer. Never the primary threat. The spore clouds reshape the room's walkable space over time.

**From existing families (surface and mid-tier):**
- **DasherMob** (RUSH mid) — introduced early in this layer
- **RobotMob** (VOLLEY mid) — introduced mid-layer
- **Shieldwall** (WEIGHT mid) — introduced mid-layer
- **Echoform** (ECHO mid) — appears in ambush rooms
- **Leecher** (PHASE mid) — appears in rooms with limited room to kite
- **Burster** (SURGE mid) — introduced late-layer

Surface-tier enemies (Scrambler, Spitter, Stumbler) still appear, now as supporting enemies in compositions.
Deep-tier enemies do not appear in Layer 2.

---

### Layer Boss: The Verdant Sovereign

*The concept of predation — hunger that has had time to become method*

The apex of the forest layer. An oversized Briar variant that has been in The Pit long enough to partially
merge with the canopy. Roots trail from its body. Parts of it ARE the environment. The arena has thick vegetation
columns that block line of sight — and that the boss uses deliberately.

**Phase 1:**
- Circles the perimeter of the arena behind the vegetation columns. Partially visible at all times.
- **Stalk strike:** disappears fully behind cover, then emerges from an unexpected column in a lunge (PHASE-adjacent). 1.5s telegraph: a specific column shudders before the lunge.
- **Herd call:** every 20s, calls 2–3 Scramblers or native Layer 2 animals. They enter from the arena edge.

**Phase 2 (below 60% HP):**
- Vegetation columns begin to fall one by one (removing cover — for both the boss and the player).
- The boss becomes more aggressive and faster. Less time between lunges.
- Exposes a **wound on its flank** (the weakpoint). Fully visible. Takes 2x damage there.
- As columns fall, the arena becomes more open — this is an inversion: in Phase 1, cover hurts you; in Phase 2, its removal is the pressure on the boss.

**On death:** collapses into the root system. The floor opens where it fell — a passage downward, choked with roots.
The entrance to Layer 3. *It wasn't the top of the food chain. It was just the closest to it.*

- **Stats:** 500 HP · Lunge damage: 38 · Herd call: 2–3 adds · Drops: Boss chest + Briar material

---

### Layer 2 Design Intent

This layer teaches:
- Managing multiple threat types simultaneously (Herdcaller creates pressure to prioritize)
- Environmental awareness (Briar, Canopy Drifter zone control)
- Mid-tier monster patterns (Dash telegraphs, spread volleys, shield geometry)
- Resource management — deaths here are punishing in a way Layer 1's weren't

The shift in tone should be felt. Players entered a dungeon in Layer 1.
They entered a predator's territory in Layer 2.

---

---

## Layer 3: The Hanging Warrens

> "You can hear it before you see it. The drop. It goes further than you want to know."

**Floors:** 11–15 (transitional layer — first signs of the rules changing)

### Aesthetic

The vast forest floor drops away. The only way forward is through a network of caverns, dens, and narrow passages
carved into the cliff face that overlooks the great drop. Some rooms are tight tunnels. Some open suddenly into
enormous cavern chambers where the far wall is open sky — and below is nothing, for as far as light reaches.

Color palette: black rock, muted blues, bioluminescent accents (acid greens, pale purples). Humid. Water on stone.
Mist rising from the drop below. Light comes from the creatures themselves.

The drop is the mechanic. Rooms have edges. Some paths run along open ledges with no railing.
Knockback is a kill condition, not just an inconvenience.

Reality starts to mutter here. Not loudly — not yet. A rock that floats briefly before remembering to fall.
A pool of water on the ceiling that drips upward. A creature that passes through a wall and seems surprised by it.
The Pit is testing things.

---

### Enemy Roster

**Native fauna (Layer 3 unique):**

**Void Crawler**
*The concept of adhesion — belonging to the surface, not the ground*
- A pale, multi-limbed creature that moves along walls and ceilings as naturally as the floor. Most attacks need the player to aim upward or sideways to hit it.
- **Drop attack:** climbs to ceiling directly above a player. Drops with full weight after a 1s pause (shadow on the floor). High damage, large knockback — designed to push the player toward the void edge.
- Can be staggered off the ceiling by hitting it, causing a fall-stun (1.5s). Then it scrambles to re-climb.
- **Stats:** 55 HP · Drop damage: 28 · Knockback: HIGH · Stagger window: during fall · Drops: 3 Resonance + adhesive material
- **Spawn guidance:** 2–3 on ceiling at the start of a room. The player may not notice them immediately. Void edge rooms only.

**Den Mother**
*The concept of propagation — creating without stopping*
- A large, sedentary creature buried in the den wall. Only the mouth is visible at room start.
- Every 4s: spits out a Scrambler-equivalent (Hatchling, 8 HP, same behavior). Up to 8 Hatchlings active.
- Cannot move. Very high HP. Its body is mostly inside the wall — only the face is targetable.
- At 50% HP: begins also spitting Leecher-equivalent Hatchlings that latch for 3 HP/s.
- **Stats:** 120 HP · Hatch interval: 4s · Max hatchlings: 8 · Drops: 6 Resonance + large material drop
- **Design intent:** A wall-mounted version of the Spawner Sac with higher HP and a harder-to-reach position. The back of cluttered rooms. Forces clearing in constrained space.

**Rimwing**
*The concept of the drop — something that has made the void its territory*
- A large bat-like creature that roosts on ledge edges. Dormant until the player approaches within 5 units of a void edge.
- **Activation:** lunges from the edge in a grab attempt. If it connects: drags the player toward the edge for 1.5s, then releases. The player ends up at the void lip with large knockback. If the player doesn't immediately move, they fall.
- Easy to hit while dormant. Very hard to hit once activated (fast, erratic flight).
- **Stats:** 40 HP · Grab damage: 10 · Grab duration: 1.5s · Post-grab knockback: toward edge · Drops: 2 Resonance
- **Spawn guidance:** Placed at every void edge in Layer 3 rooms. Punishes players who walk casually near edges.

**From existing families (mid and early deep-tier):**

Mid-tier monsters appear throughout, now in more punishing compositions given the void edges:
- **Shieldwall** (WEIGHT mid) — bashing the player toward drops
- **Binder** (PHASE deep) — **first appearance of a deep-tier enemy** — roots the player near a void edge
- **Surgeform** (RUSH deep) — **first appearance** — in large cavern chambers with room for the dash trail
- **Leecher** (PHASE mid) — in tight tunnel rooms where kiting is impossible

The transition from mid to deep tier happens here. Not all rooms have deep enemies — they appear in the later floors (13–15), as a preview of what Layer 4 will be.

---

### Layer Boss: The Rimkeeper

*The concept of the threshold — the guardian of the point of no return*

Something vast lives on the cliff face itself. Not in a room — the arena IS the cliff. An open cavern chamber
with three walls and one open side facing the void drop. The floor is a ledge, roughly 12 units wide.

The Rimkeeper clings to the void-facing wall, half inside it. Stone arms. A body that may have originally been
a creature but is now more cliff than animal. Eyes that emit the same bioluminescent light as the walls.
It moves along the void-face like the Void Crawler — horizontal, on vertical surfaces.

**Phase 1:**
- **Slam:** extends an arm across the floor. Horizontal sweeping attack, 1.5s telegraph (arm raises). High knockback — toward the void.
- **Spit:** fires volleys of rock shards from embedded protrusions. Spread cone (Barrage-like). From the wall, this fires across the full width of the ledge floor.
- Periodically shifts position along the void-face — reappears on a different section of the wall. Must re-locate its position.

**Phase 2 (below 50% HP):**
- Begins partially pulling the floor. A chunk of the ledge at the far end crumbles — reduces the safe area by ~3 units. Happens twice, reducing the total ledge from 12 units to 6. The drop is closer.
- **Pull mechanic:** emits a gravity well once every 15s. Players within 6 units of the edge are pulled toward it (2-unit pull). Must move away actively.
- More frequent slam. Slam now leaves a crack in the floor at impact (ground stays cracked, deals 3/s damage while standing on it).

**On death:** releases the wall. Falls into the drop. The camera holds on the void for a moment.
The passage beyond opens — deeper into the wall, into the dark.
*It didn't live here. It was part of here. You can feel the difference, now that it's gone.*

- **Stats:** 600 HP · Slam damage: 40 + knockback (toward void) · Shard volley: 12 per hit · Pull strength: 2 units · Drops: Boss chest + rare void material + lore fragment

---

### Layer 3 Design Intent

This layer teaches:
- Environmental lethality as a mechanic (the void is always present)
- Knockback as a kill condition (rewires how the player thinks about taking hits)
- First exposure to deep-tier enemy behaviors (Binder, Surgeform) in a context where the player already knows the base pattern
- That The Pit's rules are not fixed — the floating rocks and reversed water are background detail now, gameplay element later

The tone shifts completely from Layer 2. Layer 2 was hostile and alive.
Layer 3 is quiet, vast, and wrong. Players should feel small here.
The drop is not a threat the game adds. The drop is just the truth of where they are.

---

---

## Cross-Layer Notes

### Enemy progression by tier

| Tier | Layers present |
|------|---------------|
| Surface | 1, 2 (supporting role), 3 (rare filler) |
| Mid | 2 (primary), 3 (primary), 4 (supporting) |
| Deep | 3 (preview, late floors), 4+ (primary) |

### The reality escalation

Each layer is one step further from the surface's stable physics:
- **Layer 1:** Normal. Fantastical wildlife, but physics hold.
- **Layer 2:** Subtle. Oversized vegetation that defies scale. The Pit testing forms.
- **Layer 3:** Visible. Objects that briefly forget gravity. Water that doesn't behave. Background detail only — not gameplay yet.
- **Layer 4+:** Physics become a mechanic.

### Layer-unique materials

Each layer drops materials that are only obtainable there. These degrade when carried to the surface
(per the STORY_IDEAS.md lore: *"weapons lose unique effects, materials degrade into base components"*).
The game should reward using them before ascending — or accepting what they become when you do.

### Boss design thread

Each layer boss is the fullest expression of that layer's threat:
- **Sentinel** (L1): a guardian — teaches you to read the room
- **Verdant Sovereign** (L2): a predator — teaches you that the environment is against you
- **Rimkeeper** (L3): an obstacle — teaches you that the Pit itself is the danger
