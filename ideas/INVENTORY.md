Inventory System Design

Core Principles

The inventory should reinforce the clean split between run power and meta power:

- In runs, Infusions define temporary combat expression.
- Between runs, gear tiers and gems define permanent progression.

The inventory should enforce:

- Commitment over hoarding
- Clarity over clutter
- Expression over accumulation
- Runs over storage

Player Mental Model

During a run, I shape my power through Infusions.

After the run, I upgrade my gear tier and tune it with gems.

1. Inventory Categories

Split inventory into 4 distinct domains:

Category	Purpose	Storage Type
Gear	Player identity	Fixed slots plus optional tiny stash
Gems	Build expression	Limited grid
Materials	Progression currency	Abstract counters
Run State	Infusions/resonance	Not stored as inventory items

Removed Category

There is no separate modifier inventory for inscriptions, attunement, or tempering.

Those systems are removed as standalone concepts:

- Infusions own in-run power
- Gear tiers own permanent specialization
- Gems own flexible customization

2. Gear Inventory

Structure

Players do not have a traditional gear inventory.

Equipped Slots

- Sword
- Armor
- Helmet
- Shield
- Handgun
- Bomb

Optional Small Arsenal

Allow a very limited stash:

- 1 equipped item per slot
- 1-2 stored items per slot

Why This Works

- Encourages attachment
- Forces meaningful decisions
- Prevents loot clutter
- Supports tier commitment

3. Gear Object Structure

Each gear item contains:

- Tier 1-3
- Pillar alignment from its tier path
- Promotion Progress
- Gem sockets
- Familiarity level

Gear does not contain:

- In-run infusion state
- Tempering state
- Attunement trees
- Inscription tracks
- Detached upgrade modifiers

Gear is a long-term identity object, not disposable loot.

4. Gems Inventory

Concept

Gems are the only flexible between-run build customization system.

They modify how gear behaves without taking over the gear's identity and without
becoming another in-run layer.

Structure: Limited Grid

- Start: about 6-8 slots
- Expandable to about 12-16 max

Gem Properties

- Pillar type
- Behavior-changing effect
- Durability or fatigue
- Optional rarity or variant

Lifecycle

- Use gem
- Gem weakens over time
- Gem eventually needs refreshing or replacement

Design Intent

- Encourages rotation
- Prevents best-loadout-forever behavior
- Keeps runs feeding back into build choices
- Makes customization readable

5. Materials

Key Rule

Materials do not take inventory space.

They are tracked as abstract counters categorized by pillar.

Clarity Rule

Materials push you deeper into a pillar.

Materials Only Do

- Pay Promotion costs for tier upgrades
- Craft gems
- Refresh or repair fatigued gems

Materials Do Not Do

- Fund attunement
- Fund inscriptions
- Fund tempering
- Create extra upgrade trees
- Become sortable inventory items

Why

- No clutter
- No management friction
- Clear economy purpose
- Decisions stay focused on tiers and gems

6. Run State

During a run, the player has temporary state, not inventory.

Run State Includes

- Active Infusions
- Infusion thresholds or expression state
- Resonance
- Temporary effects
- Objective progress

Run State Does Not Include

- Persistent upgrade items
- Tempering levels
- Attunement choices
- Inscription activators
- Inventory sorting

Infusions are the only in-run build-shaping system.

7. Familiarity

Familiarity is passive background progression.

It may be shown as item flavor or small progress context, but it should not become
a major decision surface.

Rules

- No separate screen required
- No build-defining choices
- No upgrade tree
- Small capped bonuses only

8. Inventory Actions

Gear

- Equip
- Swap from small arsenal
- View tier identity
- View Promotion Progress
- Evolve tier when eligible

Gems

- Socket
- Unsocket
- Replace
- Craft
- Refresh or repair fatigue
- Discard
- Compare effects

Materials

- Spend through tier upgrade and gem actions
- Never drag, sort, stack, or store manually

Run State

- Viewed through HUD/reward screens, not inventory
- Infusion choices happen in run reward flows, not the loadout inventory

9. Capacity Pressure

Use light pressure, not frustration.

Pressure Comes From

- Limited gem slots
- Limited gear stash
- Gem fatigue

Pressure Does Not Come From

- Weight systems
- Stack limits
- Grid Tetris
- Junk selling
- Loot vacuum behavior

10. Progression Hooks

Inventory can evolve slightly over time:

- Add one gem slot
- Add one stash slot per gear type
- Unlock new gem types
- Improve gem crafting or refresh options

Never Unlock

- Huge bag sizes
- Infinite storage
- Sorting gameplay
- Junk economy loops

11. Example Player Experience

Early Game

- One gear choice per slot
- Two or three gems
- Simple tier and gem decisions
- Infusions teach the live pillar fantasy during runs

Mid Game

- Two gear choices per slot
- Six to ten gems
- Tier paths and gem customization become meaningful
- Infusion choices start shaping each run differently

Late Game

- Specialized gear
- Rotating gem strategies
- Inventory becomes loadout optimization, not storage
- Runs remain fresh through Infusion/reward variation

12. Anti-Patterns to Avoid

- Loot explosions
- Sorting gameplay
- Selling junk
- Plus-one-percent gear drops
- Inventory as progression
- Separate attunement trees
- Separate inscription tracks
- Player-facing tempering gear states

Final Inventory Model

What the player manages:

- Six equipped gear items
- A small optional gear stash
- A limited gem collection
- Pillar material totals

What the player does not manage:

- Generic currency piles
- Upgrade junk
- Attunement nodes
- Inscription tracks
- Tempering levels
- Run rewards as clutter objects

The key insight:

Inventory is not storage.

Inventory is your build surface between runs.

Inventory UI - High-Level Structure

You have 3 primary screens:

- Loadout Screen
- Gear Detail Screen
- Gem Management Screen

Optional later:

- Evolution Screen, if tier upgrade decisions outgrow Gear Detail

1. Loadout Screen

Purpose

The player sees the build at a glance, swaps gear, checks gems, and understands
what tier path they are pursuing between runs.

Layout

 -------------------------------------------------
|                  PLAYER                         |
|                                                |
|   [Helmet]                                     |
|   [Armor]      (Core Summary)                  |
|   [Shield]                                     |
|                                                |
|   [Sword]   [Handgun]   [Bomb]                 |
|                                                |
|-----------------------------------------------|
| Gems                                          |
| [G1] [G2] [G3] [G4] [G5] [G6]                 |
|-----------------------------------------------|
| Materials                                     |
| Edge: 120   Flow: 80   Surge: 45              |
 -------------------------------------------------

Key Elements

Gear Slots

- Always visible
- Strong visual identity
- Show tier
- Show pillar path
- Show Promotion Progress when relevant

Core Summary

Keep it minimal:

- Damage
- Survivability
- Speed or utility

Gem Bar

- Shows socketed or active gems
- Displays icon and fatigue state
- Click opens Gem Management

Materials

- Minimal display
- Pillar totals only
- No inventory slots

Primary Actions

- Click gear to inspect or evolve
- Click gem to manage
- Hover for quick behavior explanations

2. Gear Detail Screen

Purpose

Deep dive into one gear item.

The goal is:

I understand how this item plays and what its next permanent tier will become.

Layout

 -------------------------------------------------
| < Back                                          |
|                                                 |
|     [GEAR MODEL / ICON LARGE]                  |
|                                                 |
| Name: Execution Blade                          |
| Tier: 3 Edge                                   |
| Familiarity: Masterwork                        |
| Promotion: Complete                            |
|                                                 |
|-----------------------------------------------|
| Current Identity                               |
| - Execute below 20% HP                         |
| - Crits amplify execution threshold            |
|-----------------------------------------------|
| Next Tier                                      |
| - Unlocks from Promotion Progress + materials  |
|-----------------------------------------------|
| Gem Sockets                                    |
| [Slot 1] [Slot 2] [Slot 3]                     |
|-----------------------------------------------|
| Actions:                                      |
| [Evolve] [Modify Gems]                         |
 -------------------------------------------------

Key Elements

Behavior Panel

This replaces stat walls.

Explain:

- What the item does
- What the tier path means
- What the next tier changes
- What gems can modify

Promotion Panel

Shows:

- Current Promotion Progress
- Requirements
- Material cost
- Next tier identity

Gem Sockets

Clicking a socket opens Gem Management filtered to that slot.

Actions

- Evolve
- Modify Gems

No Actions

- Attune
- Inscribe
- Temper

3. Gem Management Screen

Purpose

This is the main between-run customization surface.

Layout

 -------------------------------------------------
| < Back                                          |
|                                                 |
| Equipped Gems                                  |
| [G1] [G2] [G3] [G4] [G5] [G6]                 |
|                                                 |
|-----------------------------------------------|
| Inventory Gems                                 |
| [ ] [ ] [ ] [ ] [ ] [ ]                       |
| [ ] [ ] [ ] [ ] [ ] [ ]                       |
|-----------------------------------------------|
| Selected Gem Details                           |
| Name: Edge Bleed Gem                           |
| Effect: Crits apply bleed                      |
| Fatigue: strong                                |
| Synergy: Strong with Edge crit gear            |
|-----------------------------------------------|
| Actions:                                      |
| [Equip] [Replace] [Refresh] [Discard]          |
 -------------------------------------------------

Key Elements

Equipped vs Inventory Separation

Top equals active.

Bottom equals available.

Fatigue Visualization

Use readable bars, cracks, dimming, or similar simple states.

Contextual Suggestions

Optional but useful:

- Strong with current tier
- Reinforces current pillar
- Good for crit chaining

Interaction Flow

- Click gem to inspect
- Click equipped slot to replace
- Use click-to-swap or drag/drop, whichever stays simple

4. Critical UX Systems

Tooltips Everywhere

On hover, explain:

- Behavior
- Synergy
- Why the gem or gear path matters
- What next tier changes

Color Language

Each pillar should have consistent color across:

- Gear
- Gems
- Infusions
- Effects
- UI highlights

Feedback Signals

- Infusions: live HUD/VFX and reward presentation
- Gem fatigue: cracks, dimming, or fatigue bar
- Promotion: progress bar fills
- Tier upgrade: strong identity reveal

Comparison Mode

Later feature.

Hold a key to compare behavior differences, not just numbers.

5. Flow Summary

Between Runs

- Open Loadout
- Check gear tier paths
- Review Promotion Progress
- Adjust gems
- Spend materials
- Start run

During Run

Minimal inventory UI.

Only show:

- Infusion HUD
- Resonance/reward choices
- Essential temporary effects
- Objective/progression feedback

After Run

- See rewards
- See Promotion Progress
- See materials and gem changes
- Return to Loadout
- Make one or two meaningful changes

Final Insight

The UI is not about managing items.

It is about helping players understand their build between runs while keeping
in-run decisions inside the Infusion/reward flow.
