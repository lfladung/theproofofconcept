# Monster Ideas

Enemies are incomplete concepts emerging from the Pit. The same concept appears at every depth —
but near the surface it's partial and broken, and deeper it becomes more fully realized, sometimes
dangerously over-expressed.

Each family shares a core idea. The same creature, becoming more of what it is.

---

## Family: FLOW
*The concept of direct pursuit — momentum as a force*

> Near the surface: it barely knows how to move. Deeper: it has become the act of moving.

**Lore:** These creatures were born with a single instruction that hasn't finished writing itself. 
At the surface they stumble toward you because they have no other idea. By mid-depth they've learned to anticipate, to close distance deliberately. 
In the deep, they've stopped being creatures that move — they've become movement itself, leaving wreckage behind them like evidence they were ever here.

**Visual identity:** The Rush family always leans forward.
At the surface, asymmetrical and half-formed, too much weight in the front. 
Mid-tier: compact, low to the ground, crystalline (shardling art). 
Deep: elongated, blurred — the silhouette looks like speed, with ghost-trails of itself left behind.

---

### Scrambler *(Surface)*

**Concept addition over baseline:** just a body that moves

- Runs directly at the player. No navigation — aims at current position and holds course.
- Gets stuck on walls and corners. Doesn't course-correct until it fully stops.
- Deals contact damage on collision. No attack animation.
- **Stats:** 15 HP · Speed: 14 · Contact damage: 8 · Drops: 1 Resonance
- **Counterplay:** Trivial alone. Corner it or let it run into a wall. Dangerous in groups because
  they cover different angles and the contact damage stacks if you stop moving.
- **Spawn guidance:** 4–6 in open rooms. 2–3 in corridors. Always the first enemy a player meets.

---

### Dasher *(Mid)*

**Concept addition:** gains intention — it anticipates where you'll be

- Navigates around obstacles toward the player.
- Stops at dash range (~7 units). Telegraph: glowing directional arrow builds on the ground over 1s.
- Arrow locks to player position at telegraph start — dashes through that point even if the player moves.
- On hit during telegraph: interrupted, enters stun (1s).
- After dash: brief recovery (0.3s) before resuming chase.
- **Stats:** 50 HP · Chase speed: 12 · Dash speed: ~28 · Dash damage: 25 · Drops: 2 Resonances
- **Counterplay:** Move perpendicular during the telegraph. The arrow is the tell — learn to read it
  as the commit signal. Interrupting during the telegraph is high-reward but requires getting close.
- **Spawn guidance:** 1–3. In tight corridors, even 1 is threatening. Pairs well with anything that forces the player to stay still.

---

### Flowform *(Deep)*

**Concept addition:** gains consequence — it leaves the room worse than it found it

- All Dasher behaviors, but: telegraph shortened to 0.5s, dash speed increased.
- Dash leaves a glowing ground trail that lingers for 3s and deals damage on contact (~5/s).
- Cannot be interrupted during the dash itself (only during telegraph).
- **On death:** immediately splits into two Scramblers at 40% HP each. They spawn at the death position.
- **Stats:** 80 HP · Chase speed: 14 · Dash damage: 30 · Trail damage: 5/s · Drops: 4 Resonances
- **Counterplay:** Kill it near a wall or corner so the Scramblers spawn contained. Fight it in open
  space to avoid the trail. Prioritize the telegraph window — it's your only interrupt opportunity.
- **Spawn guidance:** Never more than 2 in a room. The trail coverage + split means one Surgeform
  turns a room into a hazard zone on its own.

**Encounter compositions (Rush):**
- Tutorial: 4 Scramblers, open room, no obstacles
- Pressure: 2 DasherMobs + 1 Surgeform — the Surgeform forces constant movement while the Dashers telegraph
- Gauntlet: 1 Surgeform + 4 Scramblers — kill Surgeform carefully, the death-split feeds into the existing pack

---

## Family: VOLLEY
*The concept of projection — sending part of yourself outward*

> Near the surface: it throws blindly. Deeper: it has perfected the act of reaching out.

**Lore:** Something in these creatures discovered distance. They found they could extend beyond their own body — send a piece of themselves somewhere else. 
Near the surface this is crude, almost accidental. 
They fling without aim, surprised by the act. Deeper, the Pit has had time to refine the idea. 
By the deep layer the creature no longer thinks of the projectile as separate from itself. It is still the arrow when it arrives.

**Visual identity:** All have a visible "output" — a protrusion, a barrel, a mouth. The Spitter has one
unformed opening, like a wound. The Volley has structured barrel ports (hence the spread). The Barrage has multiple secondary extensions — eyes, arms, tendrils — each capable of launching. 
As the tier increases, the creature looks more like it was designed to fire rather than a creature that learned to.

---

### Spitter *(Surface)*

**Concept addition over baseline:** discovers it can reach the player without approaching

- Fires one slow, lobbed projectile toward the player's current position. Aim is imprecise (±15°).
- Retreats slowly if the player closes within 4 units. Does not fight in melee.
- Long reload: fires every 3.5s. Retreating does not cancel the reload.
- Projectile is large and slow enough to see clearly — the threat is volume and zone coverage.
- **Stats:** 25 HP · Move speed: 4 (retreat only) · Projectile speed: 7 · Projectile damage: 10 · Drops: 1 Resonance
- **Counterplay:** Walk toward it — it will retreat rather than fight. Chase it down. Slow projectiles
  let you dodge by moving rather than reacting. With multiple Spitters the stagger of their fire rates creates a continuous field even without coordination.
- **Spawn guidance:** 3–5 together. The overlap of their fire rhythms creates area denial. Single
  Spitters are trivial. Works well at the back of a room behind melee enemies.

---

### Volley *(Mid)*

**Concept addition:** learns to aim, learns to spread

- Maintains distance. Closes to ~10 units, then holds.
- Telegraph: arc/cone builds on ground (1s). Fires 3 projectiles in a spread when cone fills.
- After firing: cooldown (1.6s), then reposition to maintain distance.
- Disrupted by hits — cancels charge, enters brief stagger.
- **Stats:** 60 HP · Move speed: 7 · Projectile speed: 18 · Projectile damage: 12 each · Drops: 3 Resonances
- **Counterplay:** Aggressive pressure disrupts its charge. The spread cone is a visible tell — dodge sideways from the center. At close range it becomes a melee target with no fallback.
- **Spawn guidance:** 1–2 in mid-depth rooms. Behind a Shieldwall is a strong combination — forces the player to flank while dodging volleys.

---

### Barrage *(Deep)*

**Concept addition:** the shot is no longer a single moment — it has a follow-up

- Slow movement (~4 units/s). High HP. Does not interrupt its attack cycle when hit.
- **Phase 1 (immediate):** telegraphed spread volley, same pattern as RobotMob (5 projectiles, wider spread).
- **Phase 2 (3s later):** fires 3 homing projectiles from secondary ports. These slowly track the player's current position. Homing speed is low — they're meant to punish players who stop after dodging the spread.
- Homing projectiles have their own HP (20 each) and can be destroyed by hitting them.
- After both phases: 3s cooldown, then repeats.
- **Stats:** 120 HP · Move speed: 4 · Spread damage: 14 · Homing damage: 18 · Drops: 6 Resonances
- **Counterplay:** Kill the homing projectiles if you can't outrun them. Keep moving after dodging
  the spread — standing still to fight is what the follow-up punishes. Aggressive melee is risky because it doesn't interrupt; high burst damage is rewarded here.
- **Spawn guidance:** Always solo or with 1 weak add (Spitter or Scrambler). 
Two Barrages staggering their two-phase attacks is extremely punishing and should be reserved for very late rooms.

**Encounter compositions (Volley):**
- Safe intro: 3 Spitters in a room with obstacles — teaches dodging slow projectiles while navigating
- Pressure: 1 RobotMob + 2 Scramblers — the Scramblers prevent the player from freely advancing
- Skill check: 1 Barrage — teaches the two-phase pattern, punishes passive play
- Combination: 1 Barrage + 1 Shieldwall pushing from the front — Barrage fires over the top

---

## Family:  MASS
*The concept of mass — gravity, presence, immovability*

> Near the surface: it falls. Deeper: it has become the thing that cannot be moved.

**Lore:** Gravity is the Pit's first language. These creatures are the concept of weight, of permanence, of the force that makes things stay. 
At the surface this is incomplete — it's just a body that hasn't learned to resist falling forward. 
Deeper, the Weight family has learned to project presence: first through a shield, then by bending the space around it. 
The Warden doesn't fight you. It makes the room smaller.

**Visual identity:** All Weight enemies look dense and grounded. No sharp angles — mass, not precision.
The Stumbler is rough and barely shaped, like a stone that started becoming something. The Shieldwall
is more defined, but the most finished part of it is the shield — the body behind it is still crude.
The Warden looks architectural: like a moving structure, not a creature. Its outline is stable and heavy even when standing still.

---

### Stumbler *(Surface)*

**Concept addition over baseline:** has one attack, poorly executed

- Walks in a straight line toward the player. No pathfinding — same as Scrambler but slower.
- At melee range: raises up and stomps. AoE circle (radius ~2.5 units). High knockback, moderate damage.
- Telegraph: shadow circle expands on the ground over 1.2s before the stomp.
- Easily staggered and repositioned — knockback sends it off course significantly.
- **Stats:** 40 HP · Speed: 4 · Stomp damage: 20 · Stomp AoE: 2.5r · Drops: 2 Resonances
- **Counterplay:** Stay mobile. The telegraph is long and obvious. Knock it into a corner or wall to
  reset its approach. Solo it's a slow tutorial on reading ground telegraphs.
- **Spawn guidance:** 2–3 together, or 1 with faster pressure enemies. The Stumbler's role is
  to create "stop moving" risk while other enemies demand that you move.

---

### Shieldwall *(Mid)*

**Concept addition:** learns to orient — makes the player solve a geometry problem

- Moves toward the player. The shield always faces the player (rotates at ~80°/s).
- Front face: fully immune to all damage. Must be attacked from the side (45°+ off-center) or rear.
- **Shield bash:** every 4s, lunges forward ~2 units and slams the shield. Short range, high knockback,
  no damage. Telegraphed by a forward lean (0.5s).
- **Exposed state:** after being hit from behind 3 times within 5s, the shield drops for 2s (2x damage window).
  Then it resets its back-hit counter.
- **Stats:** 70 HP · Speed: 6 · Shield bash knockback: high · Back damage multiplier: 1.5x · Exposed: 2x · Drops: 4 Resonances
- **Counterplay:** Circle-strafe behind it. In multiplayer, one player draws attention while the other flanks. The bash is a positioning tool — if you're against a wall when it hits, you lose your angle.
- **Spawn guidance:** Pairs with anything that fires from range (Spitter, RobotMob). The Shieldwall
  limits the player's repositioning options while the ranged enemy punishes the paths they're forced into.

---

### The Warden *(Deep — Boss Tier)*

**Concept addition:** stops trying to reach the player — makes the player unable to leave

- Large, slow (~3 units/s). Always present, never rushing.
- **Gravity field:** passive, radius ~8 units. Players inside move 40% slower. Visual: distortion effect around The Warden, a subtle pull on particles/debris.
- **Ground slam:** raises one arm, then slams. AoE radius ~4.5 units, telegraphed by spreading floor
  cracks (1.5s). High damage, large knockback. Used every 6–8s.
- **Immunity phase:** every 30s, The Warden goes fully immune for 4s (gray glow). Its weak point (a bright spot on the back) appears. Hitting the weak point ends the phase immediately. If no one hits it, the phase ends naturally and The Warden performs a slam immediately after.
- **On death:** collapses. Spawns 3 Shieldwall enemies at 50% HP at its position.
- **Stats:** 300 HP · Speed: 3 · Slam damage: 45 · Gravity slow: 40% · Phase duration: 4s · Drops: 15 Resonances
- **Counterplay:** The gravity field is the core threat — it turns the slam from dodgeable to unavoidable
  if you're not careful. In multiplayer: one player baits the slam while the other stays at range.
  The immunity phase requires awareness of positioning — the weak point is on the back, which is the
  safe side, so it rewards players who were already flanking.
- **Spawn guidance:** Always a solo encounter. The room should be large enough that the gravity field
  doesn't cover the whole space. Do not add other enemies — the post-death Shieldwall spawn is the add phase.

**Encounter compositions (Weight):**
- Introduction: 2 Stumblers in an open room — learn the stomp telegraph with low stakes
- Pressure: 1 Shieldwall + 2 Spitters at the back — forced flanking under fire
- Boss: The Warden alone, large room — gravity field teaches positioning as a resource
- Late-depth mix: 2 Shieldwalls + 1 Barrage — Barrage has cover, Shieldwalls restrict flanking options

---

## Family: ECHO
*The concept of repetition — one becomes many*

> Near the surface: it makes copies without knowing why. Deeper: it has become the act of repetition itself.

**Lore:** Echo creatures didn't evolve — they iterated. Something in them discovered the loop: that a thing done once could be done again, and again. 
Near the surface this is mechanical and blind: a brood sac that pulses and splits, without purpose or direction. 
Deeper, the Echo family begins to understand what it's copying. The Splitter learns from the player specifically. The Triad is three versions of the same idea that won't collapse into one — or can't.

**Visual identity:** All Echo enemies look layered or doubled. The Spawner Sac pulses like something under pressure, with visible buds on its surface — each bud is a future Scrambler, half-formed. 

The Splitter looks slightly mirrored: its surface is reflective, and when it copies the player's style its geometry shifts. The Triad's three bodies share a visual "base texture" but each is run through a different filter — they look like the same sketch redrawn by three different hands.

---

### Splitter *(Surface)*

**Concept addition over baseline:** multiplies instead of attacking

- Stationary or very slow drift (~1 unit/s). Does not pursue the player.
- Every 6s: releases 1–2 Splinters (tiny, fast, 8 HP, contact damage 5). Up to 5 Splinters active at once.
- No direct attack. High HP for its depth tier.
- When all Splinters are killed, it accelerates spawning briefly (one immediate spawn).
- **Stats:** 60 HP · Speed: 1 · Spawn interval: 6s · Max minions: 5 · Drops: 3 Resonances + 1 per Splinter
- **Counterplay:** Kill it first. The longer it lives the more crowded the room. AoE attacks are particularly efficient — they can hit the Sac and clear Splinters simultaneously. In multiplayer, one player can pressure the Sac while the other manages Splinters.
- **Spawn guidance:** Often positioned in the back of a room, or behind another enemy. Removing it is straightforward but requires ignoring other threats temporarily — that's the tension.

---

### Echoform *(Mid)*

**Concept addition:** learns from the player specifically — becomes a threat shaped by you

- On spawn: 3s observation phase. Watches the player, backs away to keep space, and tracks attack style (melee vs. ranged).
- After observation: adapts its behavior to mirror the player's dominant approach:
  - **Melee player:** Echoform becomes an aggressive rusher (DasherMob patterns, shorter telegraph)
  - **Ranged player:** Echoform keeps distance and fires volleys (RobotMob patterns, slightly weaker)
- **Reflection:** each time it takes damage, it emits a 30%-power version of the hit back at the attacker (reflected projectile, or a short melee lunge if hit in melee).
- At 50% HP: reflection count doubles (2 reflections per hit instead of 1).
- **Stats:** 70 HP · Reflected damage: 30% of incoming · Drops: 5 Resonances
- **Counterplay:** Use the attack type it doesn't copy — if it mirrors melee, fight it at range and vice versa. In multiplayer it observes the highest-damage player and mirrors them specifically.
  Dealing small, frequent hits generates many weak reflections; fewer big hits is safer.
- **Spawn guidance:** 1 per room at most. Pairs well with a Spawner Sac — the Sac produces pressure
  while the Echoform adapts. Don't spawn it alongside enemies that match the player's loadout.

---

### Triad *(Deep)*

**Concept addition:** multiplicity made intentional — it sustains a growing loop of adaptive copies

- One slow-moving **Triad Core** that continuously generates **Echo Units**.
- Every 5s: spawns 1 Echo Unit, up to 3 active at once.
- If all Echo Units are killed, the Core immediately spawns 1 replacement so the pressure returns.
- Echo Units are created from a snapshot of player behavior at spawn time:
  - **Melee-focused player:** mini-rusher
  - **Ranged-focused player:** mini-shooter
- Echo Units do not adapt after spawning.
- Echo Units are readable on spawn: they begin tiny, grow to their final 50%-size silhouette, can still be damaged during the growth window, and only begin moving/attacking once fully formed.
- The Core emits a light pulse occasionally, but its main role is to sustain the loop rather than deal heavy damage itself.
- On Core death, all Echo Units destabilize and die shortly after so the room does not leave cleanup enemies behind.
- **Stats:** Core HP: 120 · Core Speed: 2 · Spawn interval: 5s · Max Echo Units: 3 · Echo Unit HP: ~25–35 · Drops: 10–12 Resonances total
- **Counterplay:** Keep the number of active Echo Units low and avoid letting the Core keep re-establishing pressure. Burst windows matter, but the main test is solving your own behavior being mirrored back at you over time.
- **Spawn guidance:** Always a solo encounter. The Triad IS the room. No other enemies.

**Encounter compositions (Echo):**
- Swarm intro: 1 Spawner Sac + 4 Scramblers — Sac regenerates pressure, teach prioritization
- Mirror room: 1 Echoform + 2 Lurkers (from Phase family) — limited visibility makes the Echoform harder to read
- Puzzle combat: Triad alone, open room — give players space to solve the mechanic
- Late depth: 1 Echoform + 1 Spawner Sac — Echoform adapts while the Sac floods

---

## Family: PHASE
*The concept of presence — existing between states*

> Near the surface: it keeps forgetting it exists. Deeper: it has mastered the space between.

**Lore:** Phase creatures are concepts that never fully committed to existing. They found the in-between —
the gap between the moment of being here and the moment of being gone — and made a home of it. Near the
surface this is confused and involuntary. The Lurker phases in, attacks, and immediately forgets itself
again. Deeper, the Phase family has learned to use the in-between as a weapon. The Binder doesn't need
to be untouchable. It needs you to be unable to leave.

**Visual identity:** All Phase enemies have transparency as a core visual trait. The Lurker at baseline
is almost wireframe — you can see the environment through it. The Leecher is eel-like, translucent,
and when latched you can visually see the HP transfer through its body. The Binder's most visible
feature is its tethers — glowing threads suspended in space. The body is compact and secondary, almost
irrelevant compared to the web it builds.

---

### Lurker *(Surface)*

**Concept addition over baseline:** only partially present — attacks briefly then disappears

- Spends most of its time faded (translucent, no hitbox, no collision).
- Every 4–6s: phases in near the player (within 2–3 units). Performs one swipe (melee hit). Then
  fades out again.
- **Fade-in telegraph:** ground ripple/shimmer at the target position, 0.8s before it appears.
- If hit while phased in: immediately fades out and relocates to a random room position.
- Relocation is instant and ignores geometry — it can appear anywhere in the room.
- **Stats:** 30 HP · Phase-in damage: 15 · Phase interval: 4–6s · Drops: 2 Resonances
- **Counterplay:** Watch the floor, not the enemy. The shimmer is the tell. If you miss the shimmer,
  create space immediately after being hit to avoid the follow-up. In a group, Lurkers stagger their
  timers naturally — it becomes a pattern-recognition challenge.
- **Spawn guidance:** 2–3 in a room. The stagger of their phase timers means the floor has multiple
  shimmers at different points, requiring attention splitting. In dark or cluttered rooms this is
  significantly harder.

---

### Leecher *(Mid)*

**Concept addition:** the in-between is not where it hides — it's how it feeds

- Floats toward the player. Standard navigation.
- On contact: latches on. While latched:
  - Drains 5 HP/s from the player and heals itself at the same rate
  - Cannot take damage
  - Player cannot roll/dash (input suppressed)
  - Player must press a "break free" input (multiple taps, or a single dodge-type action — TBD)
- A **teammate** can hit it to detach instantly.
- If it drains 30 total HP while latched: disengages voluntarily, fully healed, repositions.
- Solo: if you've been drained 15 HP, breaking free costs a healing item. In multiplayer: easy to detach with a teammate.
- **Stats:** 50 HP · Drain rate: 5 HP/s · Detach threshold: 30 HP drained · Drops: 4 Resonances
- **Counterplay:** Don't let it latch. It's slow — kite it and deal damage before contact. In co-op,
  communicate who's being targeted and the other player hits it off. Going down to a Leecher solo is
  almost always a resource issue, not a skill issue.
- **Spawn guidance:** 1–2 per room. Never in a room where there are high-damage enemies that punish
  standing still — being latched and taking external damage simultaneously is brutally punishing.
  Best used in rooms where the Leecher is the primary threat.

---

### The Binder *(Deep)*

**Concept addition:** doesn't become untouchable — makes the player unable to move

- Standard movement (~6 units/s). Will keep moderate distance (5–8 units).
- **Tether projectile:** fires a slow, bright projectile (~8 units/s). On hit: roots the player for 0.8s.
  The tether visually connects The Binder to the rooted player.
- While the player is rooted: The Binder immediately charges in for a heavy melee hit (2x normal damage).
- Up to 3 tethers can be active at once. A second tether hit while rooted refreshes the root duration.
- **Pull:** if a rooted player uses a dash/roll to escape, The Binder pulls them back to the root
  position once. This happens once per root instance.
- **Stats:** 90 HP · Tether speed: 8 · Root duration: 0.8s · Tether hit damage: 10 · Charge hit damage: 30 · Drops: 6 Resonances
- **Counterplay:** The tether is slow and visible — dodge it. If rooted, use the dash *after* the
  charge animation starts (the pull only cancels the dash, not the follow-up dodge opportunity). In
  multiplayer: one player can draw tether fire while the other attacks The Binder freely.
- **Spawn guidance:** 1 per room. Pairs extremely well with Shieldwalls — the Shieldwall limits
  the player's flanking options while The Binder roots them in place. Combined, these two create
  a positioning trap.

**Encounter compositions (Phase):**
- Introduction: 2 Lurkers in a dimly lit room — learn to track the shimmer
- Cooperation check: 1 Leecher + 2 Scramblers — can't freely dodge the Scramblers while latched
- Control check: 1 Binder + 1 Shieldwall — Binder roots, Shieldwall closes
- Hard room: 1 Binder + 2 Lurkers — Lurkers phase in while the Binder fires tethers

---

## Family: EDGE 
*The concept of lethality — intent reduced to a single, perfect point*

> Near the surface: it doesn't quite know where to aim. Deeper: it cannot miss.

**Lore:** Edge creatures are born from the idea that something should end. Not rage, not force — just the
certainty that a line can be drawn between "alive" and "not." At the surface, that idea is incomplete:
they strike, but without true direction. By mid-depth they understand alignment — that the body, the
weapon, and the intention must all point the same way. In the deep, there is no longer a creature making
the cut. There is only the cut itself, appearing exactly where it needs to be.

**Visual identity:** All Edge enemies have a clear leading point — a tip, blade, or line that defines their
danger. Surface: asymmetrical, the "edge" is present but misaligned with the body. Mid: clean, symmetrical,
body and weapon fully aligned. Deep: abstract — composed of planes and lines, sometimes lacking a body entirely.
The silhouette always communicates direction.

---

### Skewer *(Surface)*

**Concept addition over baseline:** has a "point" — but doesn't yet understand alignment

- Moves toward the player in a mostly straight line. Weak pathing — slight course correction, but often drifts off-angle.
- Performs a linear stab: short wind-up (~0.8s), then lunges forward ~3 units.
- The stab direction is locked at the start of the wind-up — poor tracking if the player moves.
- Hitbox is narrow and front-loaded — damage is highest at the tip, low on the sides.
- After the lunge: long recovery (~0.9s), briefly immobile.
- **Stats:** 30 HP · Speed: 7 · Lunge damage: 18 (tip), 8 (body) · Drops: 1 Resonance
- **Counterplay:** Step slightly to the side — it will miss completely. Punish during recovery. The danger is standing directly in front of it or getting clipped by multiple at once.
- **Spawn guidance:** 3–5 in open rooms. Works as a "lane denial" enemy — encourages lateral movement early.

---

### Glaiver *(Mid)*

**Concept addition:** gains alignment — direction becomes intentional and readable

- Navigates cleanly around obstacles. Maintains medium distance (~5 units).
- **Line strike:** telegraph (~0.7s): a thin glowing line appears on the ground, extending from the Glaiver forward.
- After telegraph: performs a fast dash slash along that line (~6–8 units).
- Line locks at telegraph start — does not track after committing.
- Can chain into a second angled slash (30° offset) if the first misses.
- Brief recovery (~0.3s), then repositions.
- Interruptible during telegraph — cancels the attack and stuns (~0.6s).
- **Stats:** 65 HP · Speed: 9 · Slash damage: 28 · Drops: 3 Resonances
- **Counterplay:** Read the line, move perpendicular. Aggressive players can interrupt during telegraph for high reward. Getting caught in both chained slashes is lethal.
- **Spawn guidance:** 1–3. Strong in rooms with obstacles — forces the player to respect angles and positioning.

---

### Razorform *(Deep)*

**Concept addition:** becomes inevitability — the attack is no longer tied to movement

- Does not "approach" traditionally. Repositions instantly or near-instantly within ~6–10 units.
- **Cut manifestation:** telegraph (~0.4s): a thin, bright line appears anywhere in the room (not necessarily from the creature).
- After telegraph: the line executes instantly, dealing high damage along its full length.
- Can queue multiple cuts (up to 2–3 active telegraphs at once).
- Cuts can originate at different angles, forcing layered dodging.
- No traditional recovery — instead has a short global cooldown (~1.2s) between cut sequences.
- **On death:** emits a final radial burst of short-range cuts (star pattern).
- **Stats:** 110 HP · Cut damage: 40 · Telegraph: 0.4s · Active cuts: up to 3 · Drops: 6 Resonances
- **Counterplay:** Watch the floor — not the enemy. Movement must be deliberate; panic dodging often moves you into another cut. Pre-positioning and reading patterns is key.
- **Spawn guidance:** Always 1. Pairs well with movement-restricting enemies (Binder, Shieldwall). Avoid multiple Razorforms — overlapping cuts become unreadable.

**Family mechanics (Edge):**

- **Directional damage:** All Edge enemies deal maximum damage at the leading point/line; side/back hits are significantly weaker → reinforces positioning as the core skill.
- **Commitment:** Attacks are fully committed once telegraphed — no mid-attack correction → creates clear punish windows.
- **Telegraph compression:** Surface: long, forgiving; Mid: readable but fast; Deep: minimal, pattern-based → same language, increased execution requirement.

**Encounter compositions (Edge):**
- Lane denial: 4–5 Skewers, open room — teaches stepping off the stab line
- Obstacle puzzle: 2 Glaiver + light cover — read lines and use geometry
- Control nightmare: 1 Razorform + 1 Binder — roots and cuts punish panic movement
- Front lock: 1 Razorform + 1 Shieldwall — limited flanks while floor telegraphs demand space

---

## Family: SURGE
*The concept of accumulation — building toward a single moment*

> Near the surface: it doesn't know it's going to explode. Deeper: it has become the explosion.

**Lore:** These creatures are concepts under pressure. They were given one instruction — build — with
no corresponding instruction to stop. Near the surface they discharge immediately, almost by accident,
and die in the act. Deeper, the concept has learned patience. The Burster has discovered that the
moment is sweeter after waiting. The Detonator no longer exists for its own explosion — it exists to
make everything else explode. The concept has externalized itself.

**Visual identity:** All Surge enemies glow and radiate. The Fizzler is tiny and sparks constantly, as
if leaking what it's holding. The Burster grows visibly brighter over time — at full charge it's almost
too bright to look at, with cracks visible in its surface. The Detonator vents steam and energy from
fissures in its body; the Fizzlers it spawns literally emerge from these cracks, pinching off.

---

### Fizzler *(Surface)*

**Concept addition over baseline:** exists only to reach its single moment

- Tiny and very fast (~18 units/s). Runs directly at the player, no pathfinding.
- On contact with the player or any surface: small explosion (radius ~1.5 units), low damage,
  moderate knockback.
- Dying (from damage) also triggers the explosion — it detonates on death regardless.
- **Chain detonation:** Fizzler explosions trigger other Fizzlers within their blast radius.
- 1 HP — one hit kills it. The explosion is the main interaction.
- **Stats:** 1 HP · Speed: 18 · Explosion damage: 12 · Explosion radius: 1.5 · Drops: 0 Resonance (too small to shed anything)
- **Counterplay:** Hit it before it reaches you. AoE attacks are efficient — one hit clears a pack.
  The chain detonation is a threat and a tool: luring Fizzlers together then triggering one can clear
  a group, but in a tight corridor it can chain into you.
- **Spawn guidance:** 5–8 in a group. The individual Fizzler is trivial — the pack and the chain are
  the mechanic. Introduce them in an open room first so the chain behavior is clearly visible.

---

### Burster *(Mid)*

**Concept addition:** learns patience — becomes more dangerous the longer it lives

- Chases the player with normal navigation (~9 units/s).
- Has a charge meter that fills over ~7s of active pursuit. Visual: glow ramps from dim to blinding.
- At full charge: detonates. Large explosion (radius ~4 units), high damage.
- **Damage interrupt:** taking significant damage (>15 in one hit) resets the charge meter.
- Explosion radius triggers any Fizzlers caught inside — chain potential.
- Takes extra knockback throughout (the charge makes it unstable).
- **Stats:** 55 HP · Speed: 9 · Full charge time: 7s · Explosion damage: 50 · Explosion radius: 4 · Drops: 4 Resonances
- **Counterplay:** Two approaches — stun/interrupt it to keep the charge low (but it will keep
  rebuilding), or kill it quickly before it charges (risky if near other Fizzlers). In an open room
  kiting it is viable; in tight spaces managing the charge timer is the core challenge.
- **Spawn guidance:** 1–2 in a room. A single Burster is a timer the player must manage. Two Bursters
  on different charge schedules means there's never a "safe" moment. Never pair with Fizzlers in a
  tight room — the chain detonation becomes too punishing.

---

### The Detonator *(Deep)*

**Concept addition:** doesn't explode itself — it has become the source of all explosions

- Slow (~3 units/s), walks toward the player but never rushes.
- High HP. **Cannot be stunned or interrupted.**
- **Spawns Fizzlers:** every 5s, a Fizzler pinches off from a crack in its body. Up to 6 Fizzlers
  active at once.
- **Vent window:** every 10s, The Detonator vents (glows white, brief stagger). Takes 2x damage for
  1.5s. This is the only damage window.
- **On death:** massive explosion (radius ~7 units, damage 80). Instantly detonates all Fizzlers and
  Bursters within a large area of the room.
- **Design note on kill order:** Players who kill The Detonator with Fizzlers and Bursters nearby will
  chain-detonate the room. Correct play is to clear the room of Surgers first, then vent-burst The
  Detonator. This should be learnable in the first encounter.
- **Stats:** 250 HP · Speed: 3 · Vent window: 1.5s (2x damage) · Death explosion: 80 dmg, 7r · Drops: 14 Resonances
- **Counterplay:** Clear the Fizzlers. Time the vent window — attack in bursts, not continuously.
  Position away from Fizzler clusters before landing the killing blow. In multiplayer, one player
  manages Fizzlers while the other watches the vent timer.
- **Spawn guidance:** Always a solo boss-type encounter. The room composition is: The Detonator +
  whatever Fizzlers it spawns during the fight. Do not pre-spawn Bursters in the same room —
  the chain detonation on death should be a choice, not an unavoidable punishment.

**Encounter compositions (Surge):**
- Chain tutorial: 5 Fizzlers in a tight corridor — learn chain detonation before it matters
- Timer fight: 1 Burster + 4 Scramblers — manage the Burster timer while dealing with pressure
- Controlled chaos: 2 Bursters with different spawn timings — never a safe moment
- Boss encounter: The Detonator alone — room starts empty, Fizzlers build up over the fight

---

## Cross-Family Synergies


---

## Design Notes

### What families give you
- **Tutorialization through encounter design** — Scramblers in room 1 teach Rush mechanics for free.
  Later, a Surgeform is immediately legible.
- **Depth as escalation, not replacement** — surface enemies remain useful at any depth when combined
  with deep enemies. A Warden + pack of Scramblers is dangerous differently than a Warden alone.
- **Counterplay diversity** — each family rewards different player builds: Surge rewards AoE, Phase
  rewards mobility, Weight rewards patience and positioning, Echo rewards burst damage, Edge rewards
  lateral positioning and reading committed ground lines.
`
### Multiplayer-specific notes
- **Leecher:** trivial with a teammate, genuine threat solo. Scales naturally with group size.
- **Triad:** requires explicit coordination — the 3s window needs communication.
- **Echoform:** observes highest-damage player in multiplayer. Can mirror a build the other player
  doesn't carry counters for.
- **Warden:** gravity field affects all players — spacing matters.
- **Binder:** tethering one player frees the other. Creates a "protect the rooted player" moment.

### What makes a good family member
Each tier adds exactly one layer:
- **Surface → Mid:** gains intentionality (targeting, telegraph, decision-making)
- **Mid → Deep:** gains consequence (field control, combos, death effects, persistence)

The player should be able to recognize the family from the surface variant and read the deep variant
as "the same idea, more dangerous" rather than "a new enemy."
