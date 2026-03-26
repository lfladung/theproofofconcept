# Asset Pipeline Kit

Files:

- `FAST_LANE_PIPELINE.md`: step-by-step workflow for quick asset throughput.
- `meshy_prompt_templates.md`: reusable prompt blocks.
- `asset_checklist.md`: per-asset gate list.
- `audit_glb.py`: quick GLB bounds/scale validator.

## Quick Commands

Run from repo root:

```powershell
python tools/asset_pipeline/audit_glb.py --path art/characters/player/Base_Model_V01.glb
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Sword_texture.glb --category weapon --anchor art/characters/player/Base_Model_V01.glb
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Shield_texture.glb --category shield --anchor art/characters/player/Base_Model_V01.glb
```

Use `--strict` to fail on warnings:

```powershell
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Sword_texture.glb --category weapon --anchor art/characters/player/Base_Model_V01.glb --strict
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Shield_texture.glb --category shield --anchor art/characters/player/Base_Model_V01.glb --strict
```
