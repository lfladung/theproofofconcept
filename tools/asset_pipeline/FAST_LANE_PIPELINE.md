# Fast Lane Asset Pipeline (Godot + Meshy)

This is the speed-first pipeline for this repo:

`C:/git/dungeonGame/dungeonGameConvertToMultplayer`

Goal: get usable assets into gameplay fast, with enough structure to scale later.

## 0) Ground Rules (Do These Every Time)

- Keep a single scale anchor: `art/characters/player/Base_Model_V01.glb`.
- Target top-down readability: bold silhouette, low tiny detail, strong shape contrast.
- Prefer one clean material per asset for prototype.
- Keep pivots predictable:
  - Characters/enemies: feet center.
  - Weapons: grip at origin.
  - Props/interactables: base center.
  - Tiles: snap corner or center (pick one and keep it).

## 1) Category Lanes

- Player character:
  - Use one base rig/skeleton and reuse it.
  - Keep animation clips separate (idle/run/attack/hit/death).
- Enemies:
  - Riggers only for movers; static for traps/turrets.
  - Reuse shared enemy rig if possible.
- Weapons:
  - Static mesh only.
  - Attach to hand socket with local offset.
- Shields:
  - Static mesh only.
  - Attach to off-hand socket with local offset.
  - Prioritize front-face readability in top-down camera.
- Props/interactables:
  - Static mesh + simple collision proxy.
- Dungeon tiles/modular pieces:
  - Strict snap dimensions and pivot consistency.
- VFX placeholders:
  - Very simple geo; real look comes from Godot shader/particles.

## 2) Fast Generation in Meshy

Use templates from `tools/asset_pipeline/meshy_prompt_templates.md`.

Recommendation by type:

- Text-to-3D: props, tiles, simple weapons, filler enemies.
- Image-to-3D: player/enemy families where style lock matters.
- Hybrid: hero assets (player variants, bosses).

## 3) 10-Minute Cleanup Pass

Before import, do only this:

1. Delete tiny floating bits and hidden interior geo.
2. Reduce detail if silhouette is unchanged.
3. Normalize scale near expected category size.
4. Set pivot/origin correctly for category.
5. Name file as `category_name_variant_v###.glb`.
6. Plan collision proxy shape now (box/capsule/convex).

Skip perfection. If it reads well in camera and collides correctly, ship it.

## 4) Audit the GLB in Seconds

Use:

```powershell
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Sword_texture.glb --category weapon --anchor art/characters/player/Base_Model_V01.glb
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Shield_texture.glb --category shield --anchor art/characters/player/Base_Model_V01.glb
```

The script reports:

- bounds and longest axis
- ratio versus anchor
- category range check (pass/warn)
- skeleton/animation counts

If scale fails, regenerate or resize once and move on.

## 5) Import to Godot

1. Drop `.glb` under the existing category folder in `art/`.
2. Let Godot auto-import.
3. Create or update scene in `scenes/visuals` or relevant `scenes/entities`.
4. Add simple collision shape.
5. Test in gameplay camera quickly.

## 6) Prototype Acceptance Criteria

Accept the asset when all are true:

- readable from gameplay camera
- scale feels right next to player
- no major clipping during core actions
- collision feels fair
- naming/path are organized

If these pass, do not polish yet.

## 7) Suggested First Sprint (Fast)

1. 1 player visual baseline (already present)
2. 2 enemy placeholders (melee + ranged)
3. 1 sword + 1 shield + 1 ranged weapon placeholder
4. 5 props (door, chest, barrel, pillar, bush)
5. 4 modular pieces (floor, wall, corner, doorway)

Ship this set first, then iterate style.
