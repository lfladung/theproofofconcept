# Codex Thread Summary (2026-03-26)

This file captures the practical outcomes from the Codex planning thread and stores them inside the project.

## Project Context

- Game: small 3D multiplayer dungeon crawler (Spiral Knights inspired)
- Engine: Godot
- Priority: fast prototype iteration, consistency, low art overhead
- AI generation source: Meshy

## Scale Anchors Measured

- Player sample: `art/characters/player/Base_Model_V01.glb`
  - Approx bounds extents: `X=2.025, Y=1.222, Z=2.998`
  - Longest axis ~ `2.998` (used as character anchor)
- Sword sample: `art/equipment/weapons/Sword_texture.glb`
  - Approx bounds extents: `X=0.351, Y=1.899, Z=0.214`
  - Longest axis ~ `1.899`
  - Ratio vs player anchor: `0.633` (good for one-hand weapon in this project scale)

## Fast-Lane Pipeline Added

- `tools/asset_pipeline/FAST_LANE_PIPELINE.md`
- `tools/asset_pipeline/meshy_prompt_templates.md`
- `tools/asset_pipeline/asset_checklist.md`
- `tools/asset_pipeline/audit_glb.py`
- `tools/asset_pipeline/README.md`

`tools/COMMANDS.md` was updated with quick pipeline command references.

## Core Prompt Block Locked In

The modular equipment prompt block (armor/helmet/weapon requirements) has been included in:

- `tools/asset_pipeline/meshy_prompt_templates.md`

It includes project scale guidance:

- Character longest dimension around `3.0` units
- One-hand weapon length around `1.8` to `2.0` units

## Shield Equipment Expansion (Added)

Shield is now considered a first-class equipment piece in the same pipeline.

Recommended first target (prototype):

- Off-hand shield longest dimension around `1.2` to `1.7` units
- Ratio vs player anchor approximately `0.40` to `0.57`
- Slightly oversized thickness/readability for top-down camera
- Attachment expectation: off-hand socket/bone (left hand for current knight rig)

Prompt/template/checklist updates include shield guidance so intake stays consistent.

## Quick Command to Validate New Assets

Run from repo root:

```powershell
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Sword_texture.glb --category weapon --anchor art/characters/player/Base_Model_V01.glb
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Shield_texture.glb --category shield --anchor art/characters/player/Base_Model_V01.glb
```

## Equipment System Design Status

Design direction documented in thread:

- Shared skeleton strategy for base body + skinned armor + skinned helmet
- Socket strategy for rigid helmet/weapon/shield
- Runtime swap flow via `EquipmentItem` resources and equip/unequip manager
- Body part hide toggles for clipping control

Implementation into gameplay code is not yet performed in this summary step.

## Recommended Immediate Next Steps

1. Build/confirm player visual slot nodes (`ArmorSlot`, `HelmetSlot`, `WeaponSlot`, `ShieldSlot`).
2. Add `EquipmentItem` resource + simple equipment manager script.
3. Convert one sword, one shield, and one armor item into first runtime-swappable assets.
4. Add a quick block/readability test for shield silhouette in gameplay camera.
5. Create a tiny asset test scene using gameplay camera angle for intake checks.
