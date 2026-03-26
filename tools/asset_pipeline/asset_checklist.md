# Per-Asset Fast Lane Checklist

Use this for every new mesh before it enters gameplay scenes.

## Intake

- [ ] Category chosen (`player`, `enemy`, `weapon`, `shield`, `prop`, `tile`, `interactable`, `vfx`).
- [ ] Name follows convention: `category_name_variant_v###.glb`.
- [ ] Stored in correct `art/` folder.

## Readability

- [ ] Main silhouette is readable from elevated top-down camera.
- [ ] No thin details likely to disappear or clip.
- [ ] Shape exaggeration is clear and intentional.

## Geometry

- [ ] Removed tiny floating/internal junk geometry.
- [ ] Detail level is category-appropriate (not over-dense).
- [ ] Normals/shading look clean at gameplay distance.

## Scale and Transform

- [ ] Compared against player anchor scale.
- [ ] Pivot/origin matches category rule.
- [ ] Facing direction is consistent (`Z+` target in source pipeline).
- [ ] `audit_glb.py` run and reviewed.

## Gameplay Setup

- [ ] Collision proxy shape decided and added.
- [ ] For weapons: grip/pivot allows simple hand attachment offset.
- [ ] For shields: grip/strap pivot allows simple off-hand attachment offset.
- [ ] For rigged characters: skeleton naming/rest pose are consistent.

## In-Engine Verification

- [ ] Imported successfully in Godot.
- [ ] Looks correct in gameplay camera and room lighting.
- [ ] No major clipping in idle/run/attack.
- [ ] Accepted for prototype (or rejected with one-line reason).
