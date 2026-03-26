# Meshy Prompt Templates (Fast Lane)

Use one shared style prefix for every asset, then append a category suffix.

## Shared Style Prefix

```text
Stylized action-dungeon game asset for a Spiral Knights inspired top-down camera.
Readable silhouette from elevated angled gameplay view.
Chunky forms, slightly exaggerated proportions, clean shape language.
Avoid tiny thin details, avoid noisy surface clutter.
Game-ready, simple geometry, no baked animation.
Centered at origin, facing forward (Z+), consistent project scale.
Use clean stylized textures/materials with strong value contrast.
```

## Scale Targets (Current Project)

- Character longest dimension target: around 3.0 units.
- One-hand sword length target: 1.8 to 2.0 units.
- Off-hand shield longest dimension target: 1.2 to 1.7 units.
- Keep category ratios consistent to player anchor.

## Player Character Suffix

```text
Humanoid chibi knight adventurer for modular equipment system.
Clear torso, head, arms, and hands for gear readability.
Simple armor plates, broad readable silhouette, no thin dangling parts.
Rig-friendly topology and clean limb separation.
```

## Enemy Suffix

```text
Dungeon enemy for quick gameplay readability.
Distinct silhouette from player at a glance.
Exaggerated main feature (horns, jaw, shell, or weapon arm) and simple secondary forms.
No fragile protrusions; compact combat silhouette.
```

## Weapon Suffix (One-Hand)

```text
One-handed melee weapon for top-down action combat.
Grip aligned to origin for easy hand socket attachment.
Readable blade/head shape from distance.
Keep thickness chunky enough to be visible in motion.
Target total length near 1.8 to 2.0 units.
```

## Shield Suffix (Off-Hand)

```text
Off-hand combat shield for top-down action combat.
Readable front face shape from elevated camera.
Broad silhouette and slightly chunky thickness for distance readability.
Grip/strap area aligned near origin for easy off-hand attachment.
Target longest dimension near 1.2 to 1.7 units.
```

## Prop Suffix

```text
Environment prop for compact dungeon rooms.
Simple stylized forms, readable at medium distance.
No tiny breakable detail, no hidden geometry.
Flat base for stable placement and simple collisions.
```

## Dungeon Tile / Modular Piece Suffix

```text
Modular dungeon piece for grid-like snapping.
Clean edges, predictable silhouette, no overhang that breaks tile adjacency.
Designed to align with other pieces using consistent dimensions and pivot.
```

## Interactable Suffix

```text
Interactive dungeon object with obvious function from silhouette.
Large readable top shape, clear front side, simple mechanical forms.
Compact footprint and collision-friendly geometry.
```

## VFX Placeholder Mesh Suffix

```text
Simple placeholder mesh to drive in-engine VFX.
Very low detail geometry, clean topology, no texture complexity required.
Designed to be combined with Godot particles/shaders.
```

## Modular Equipment Prompt Block (Copy/Paste)

```text
This model is for a modular character system.

Requirements:
- Designed to fit a humanoid base model
- Clean silhouette, slightly exaggerated proportions
- Avoid thin details that may clip
- Centered at origin
- Facing forward (Z+)
- Consistent scale across all assets (match project anchor; character longest dimension around 3.0 units)
- Simple geometry, game-ready
- No baked animation
- No complex rig required (will attach to existing skeleton)

For armor:
- Should cover torso and upper legs
- Slightly oversized to avoid clipping

For helmet:
- Fully covers head
- Slightly oversized

For weapon:
- Sized to fit in one hand (target length around 1.8 to 2.0 units)
- Grip aligned to origin for easy attachment

For shield:
- Off-hand scale target longest dimension around 1.2 to 1.7 units
- Front face silhouette readable from top-down view
- Grip/strap pivot aligned for simple left-hand socket attachment
```
