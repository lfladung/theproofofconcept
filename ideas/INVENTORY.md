Inventory System Design (Aligned with Your Progression)
Core Principles

Your inventory should enforce:

Commitment over hoarding
Clarity over clutter
Expression over accumulation
Runs > storage
1. Inventory Categories (Hard Separation)

Split inventory into 4 distinct domains:

Category	Purpose	Storage Type
Gear	Player identity	Fixed slots
Gems	Build expression	Limited grid
Materials	Progression currency	Abstract (no slots)
Modifiers	System upgrades (inscriptions/attunement)	Bound to gear
2. Gear Inventory (No Hoarding)
Structure

Players do NOT have a traditional gear inventory.

Instead:

Equipped Slots Only
Sword
Armor
Helmet
Shield
Handgun
Bomb

👉 That’s it.

Optional: Small Arsenal (Recommended)

Allow a very limited stash:

1–2 extra items per slot (max)

Example:

1 equipped sword + 2 stored swords
Why This Works
Encourages attachment
Forces meaningful decisions
Prevents Diablo-style clutter
Supports your tier commitment system
3. Gear Object Structure

Each gear item contains:

Tier (1–3)
Pillar alignment
Attunement
Inscriptions (progression nodes)
Gem sockets
Familiarity level

👉 Gear is a long-term object, not disposable loot.

4. Gems Inventory (Expression Layer)

This is your main flexible inventory system.

Structure: Limited Grid
Start: ~6–8 slots
Expandable to ~12–16 max
Gem Properties

Each gem has:

Pillar type
Effect (behavior modifier)
Durability / fatigue
Optional rarity/variant
Lifecycle
Used → weakens over time
Eventually breaks or becomes inactive
Must be replaced
Design Intent
Encourages rotation
Prevents “best loadout forever”
Keeps players engaging with runs
5. Materials (No Inventory)
Key Rule

Materials do NOT take inventory space.

They are tracked as:

Abstract counters
Categorized by pillar
Why
No clutter
No management friction
Keeps focus on decisions, not sorting
6. Inscriptions & Attunement (Bound Systems)

These do not exist in inventory.

They are:

Attached directly to gear
Upgraded via UI trees
Why
Prevents “upgrade item hoarding”
Keeps progression tied to identity
Simplifies mental model
7. Run Inventory (Separate Context)

During a run, the player has temporary state, not inventory:

Infusions (build)
Tempering level
Temporary effects

👉 None of this persists as items.

8. Inventory Actions (Critical UX Layer)
Gear
Equip
Swap (from small arsenal)
Evolve (Tier upgrade)
Attune
Inscribe
Gems
Socket / unsocket
Replace
Discard
Compare effects
Materials
Spend (no dragging, no slots)
9. Capacity Pressure (Important)

You want light pressure, not frustration.

Pressure comes from:
Limited gem slots
Limited gear stash
NOT from:
Weight systems ❌
Stack limits ❌
Grid Tetris ❌
10. Progression Hooks

Inventory should evolve slightly over time:

Unlocks
+1 gem slot
+1 stash slot per gear type
New gem types (not space)
Never unlock:
Huge bag sizes
Infinite storage
Loot vacuum gameplay
11. Example Player Experience
Early Game
1 weapon, 2–3 gems
Simple decisions
Learning systems
Mid Game
2 weapon choices per slot
6–10 gems
Build shaping begins
Late Game
Fully specialized gear
Rotating gem strategies
Inventory = loadout optimization, not storage
12. Anti-Patterns to Avoid

❌ Loot explosions
❌ Sorting gameplay
❌ Selling junk
❌ “+1% better” gear drops
❌ Inventory as progression

Final Inventory Model
What the player manages
6 equipped gear items
~10 gems
Small gear stash (optional)
What the player does NOT manage
Materials
Currency
Upgrade items
Run rewards as objects
The Key Insight

Inventory is not storage.
Inventory is your build surface

Inventory UI — High-Level Structure

You have 3 primary screens:

Loadout Screen (default hub)
Gear Detail Screen
Gem Management Screen

Optional later:
4. Evolution / Progression Screen (upgrade-focused)

1. Loadout Screen (Main Screen)
Purpose

This is the player’s home base:

View build at a glance
Swap gear
Manage gems quickly
Layout

 -------------------------------------------------
|                  PLAYER                         |
|                                                |
|   [Helmet]                                     |
|   [Armor]      (Core Stats Summary)            |
|   [Shield]                                     |
|                                                |
|   [Sword]   [Handgun]   [Bomb]                 |
|                                                |
|-----------------------------------------------|
| Gems (Quick Bar)                              |
| [G1] [G2] [G3] [G4] [G5] [G6]                 |
|-----------------------------------------------|
| Materials (minimal display)                    |
| Edge: 120   Flow: 80   Surge: 45              |
 -------------------------------------------------

 Key Elements
1. Gear Slots (Centerpiece)
Always visible
Strong visual identity (big icons or 3D models)
Show:
Tier (1–3)
Pillar alignment (color-coded)
Attunement (small icon)
Tempering preview (optional glow effect)

👉 Clicking opens Gear Detail Screen

2. Core Stats Summary (Right Side)

Keep it minimal:

Damage
Survivability
Speed / Utility

👉 No deep stat sheet here — just confidence metrics

3. Gem Quick Bar (Bottom)
Shows currently socketed gems
Displays:
Icon
Remaining durability (bar or cracks)
Click → opens Gem Management Screen
4. Materials (Bottom Corner)
Non-interactive
Clean numbers only
No clutter
Primary Actions
Click gear → inspect / modify
Click gem → manage
Hover → quick tooltip (CRITICAL for clarity)

2. Gear Detail Screen
Purpose

Deep dive into a single gear item

Layout
 -------------------------------------------------
| < Back                                          |
|                                                 |
|     [GEAR MODEL / ICON LARGE]                  |
|                                                 |
| Name: Execution Blade                          |
| Tier: 3 (Edge)                                 |
| Attunement: Edge II                            |
| Familiarity: Masterwork                        |
|                                                 |
|-----------------------------------------------|
| Behavior Panel                                 |
| - Execute below 20% HP                         |
| - Crits amplify execution threshold            |
|-----------------------------------------------|
| Inscriptions                                  |
| [Flow I] [Flow II] [Flow III]                  |
|-----------------------------------------------|
| Gem Sockets                                   |
| [Slot 1] [Slot 2] [Slot 3]                     |
|-----------------------------------------------|
| Actions:                                      |
| [Evolve] [Attune] [Modify Gems]               |
 -------------------------------------------------
Key Elements
1. Behavior Panel (MOST IMPORTANT)

This replaces “stat walls”

Explains what the item does
Uses plain language
Highlights synergy

👉 This is where players learn your game

2. Inscriptions Panel
Visual progression track
Shows:
Locked vs unlocked
Next upgrade
3. Gem Sockets
Click slot → opens Gem Management (filtered to that slot)
4. Actions
Evolve (if eligible)
Attune (if available)
Modify gems
UX Goal

👉 “I understand how this item plays”

3. Gem Management Screen
Purpose

This is your main decision surface

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
| Durability: ███░░                              |
| Synergy: High with Edge Attunement            |
|-----------------------------------------------|
| Actions:                                      |
| [Equip] [Replace] [Discard]                   |
 -------------------------------------------------
Key Elements
1. Equipped vs Inventory Separation
Top = active
Bottom = available

👉 Prevents confusion instantly

2. Durability Visualization
Bars, cracks, fading color
Must be readable at a glance
3. Contextual Suggestions (Optional but HIGH VALUE)
“Strong with current build”
“Boosted by attunement”
Interaction Flow
Click gem → inspect
Click equipped slot → replace
Drag/drop OR click-to-swap (keep it simple)
UX Goal

👉 “I can experiment quickly without friction”

5. Critical UX Systems (Do NOT Skip)
1. Tooltips Everywhere

On hover:

Explain behavior
Show synergy
Show WHY something is good
2. Color Language

Each pillar = consistent color across:

Gear
Gems
Effects
UI highlights
3. Feedback Signals
Tempering → glow / heat effect
Gems degrading → cracks / dimming
Promotion → progress bar fills
4. Comparison Mode (Later)
Hold key → compare gear side-by-side
Focus on behavior differences, not numbers
6. Flow Summary (Player Journey)
Between Runs
Open Loadout
Check gear
Adjust gems
Review progression
Start run
During Run (Minimal UI)
No inventory screen
Only:
Infusion UI
Tempering indicator
After Run
See rewards
Return to Loadout
Make meaningful changes
Final Insight

Your UI is not about managing items.
It’s about helping players understand their build instantly.