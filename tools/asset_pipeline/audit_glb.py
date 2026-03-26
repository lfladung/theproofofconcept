#!/usr/bin/env python3
"""
Fast lane GLB audit tool for this project.

Usage example:
  python tools/asset_pipeline/audit_glb.py \
    --path art/equipment/weapons/Sword_texture.glb \
    --category weapon \
    --anchor art/characters/player/Base_Model_V01.glb

  python tools/asset_pipeline/audit_glb.py \
    --path art/equipment/weapons/Shield_texture.glb \
    --category shield \
    --anchor art/characters/player/Base_Model_V01.glb
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any

CATEGORY_RATIO_RANGES = {
    "player": (0.9, 1.1),
    "enemy": (0.35, 1.1),
    "weapon": (0.5, 0.72),
    "shield": (0.35, 0.62),
    "prop": (0.1, 1.0),
    "tile": (0.8, 3.0),
    "interactable": (0.15, 1.2),
    "vfx": (0.05, 1.0),
}


def _load_glb_json(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("File too small to be a valid GLB")

    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("Not a GLB file")
    if version not in (2,):
        raise ValueError(f"Unsupported GLB version: {version}")

    off = 12
    json_chunk = None
    while off + 8 <= len(data):
        chunk_len, chunk_type = struct.unpack_from("<II", data, off)
        off += 8
        chunk_data = data[off : off + chunk_len]
        off += chunk_len
        if chunk_type == 0x4E4F534A:  # JSON
            json_chunk = chunk_data
            break

    if json_chunk is None:
        raise ValueError("JSON chunk not found in GLB")

    return json.loads(json_chunk.decode("utf-8"))


def _bounds_from_accessors(gltf: dict[str, Any]) -> tuple[list[float], list[float]] | None:
    meshes = gltf.get("meshes", [])
    accessors = gltf.get("accessors", [])
    if not meshes or not accessors:
        return None

    min_v = [float("inf"), float("inf"), float("inf")]
    max_v = [float("-inf"), float("-inf"), float("-inf")]
    found = False

    for mesh in meshes:
        for prim in mesh.get("primitives", []):
            pos_idx = prim.get("attributes", {}).get("POSITION")
            if pos_idx is None:
                continue
            if pos_idx < 0 or pos_idx >= len(accessors):
                continue

            acc = accessors[pos_idx]
            a_min = acc.get("min")
            a_max = acc.get("max")
            if a_min is None or a_max is None or len(a_min) < 3 or len(a_max) < 3:
                continue

            found = True
            for i in range(3):
                min_v[i] = min(min_v[i], float(a_min[i]))
                max_v[i] = max(max_v[i], float(a_max[i]))

    if not found:
        return None

    return min_v, max_v


def _audit(path: Path) -> dict[str, Any]:
    gltf = _load_glb_json(path)
    bounds = _bounds_from_accessors(gltf)

    out: dict[str, Any] = {
        "path": str(path),
        "nodes": len(gltf.get("nodes", [])),
        "meshes": len(gltf.get("meshes", [])),
        "skins": len(gltf.get("skins", [])),
        "animations": len(gltf.get("animations", [])),
        "materials": len(gltf.get("materials", [])),
        "bounds": None,
        "extents": None,
        "longest_axis": None,
        "longest": None,
    }

    if bounds is not None:
        min_v, max_v = bounds
        ext = [max_v[i] - min_v[i] for i in range(3)]
        axis_names = ["X", "Y", "Z"]
        longest_idx = max(range(3), key=lambda i: ext[i])

        out["bounds"] = {"min": min_v, "max": max_v}
        out["extents"] = ext
        out["longest_axis"] = axis_names[longest_idx]
        out["longest"] = ext[longest_idx]

    return out


def _fmt_float(v: float | None) -> str:
    if v is None:
        return "n/a"
    return f"{v:.4f}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit GLB scale and metadata for fast-lane ingestion.")
    parser.add_argument("--path", required=True, help="Path to GLB file")
    parser.add_argument(
        "--category",
        choices=sorted(CATEGORY_RATIO_RANGES.keys()),
        help="Asset category for ratio check",
    )
    parser.add_argument(
        "--anchor",
        help="Anchor GLB path used for ratio checks (typically player base model)",
    )
    parser.add_argument("--strict", action="store_true", help="Exit non-zero on warnings")

    args = parser.parse_args()

    path = Path(args.path)
    if not path.is_file():
        print(f"ERROR: missing file: {path}")
        return 2

    result = _audit(path)

    print("=== GLB Audit ===")
    print(f"path:         {result['path']}")
    print(f"nodes:        {result['nodes']}")
    print(f"meshes:       {result['meshes']}")
    print(f"materials:    {result['materials']}")
    print(f"skins:        {result['skins']}")
    print(f"animations:   {result['animations']}")

    if result["extents"] is None:
        print("bounds:       unavailable (POSITION accessor min/max missing)")
        print("verdict:      WARN")
        return 1 if args.strict else 0

    ext = result["extents"]
    print(
        "extents xyz:  "
        + ", ".join(_fmt_float(v) for v in ext)
        + f" (longest={result['longest_axis']} {_fmt_float(result['longest'])})"
    )

    warnings: list[str] = []

    anchor_longest = None
    if args.anchor:
        anchor_path = Path(args.anchor)
        if not anchor_path.is_file():
            warnings.append(f"Anchor missing: {anchor_path}")
        else:
            anchor_result = _audit(anchor_path)
            anchor_longest = anchor_result.get("longest")
            if anchor_longest is None or anchor_longest <= 0:
                warnings.append("Anchor has no usable bounds")
            else:
                ratio = float(result["longest"]) / float(anchor_longest)
                print(
                    f"anchor_longest:{_fmt_float(anchor_longest)}  ratio_to_anchor:{ratio:.4f}"
                )

                if args.category:
                    lo, hi = CATEGORY_RATIO_RANGES[args.category]
                    if ratio < lo or ratio > hi:
                        warnings.append(
                            f"Category '{args.category}' ratio {ratio:.4f} out of suggested range [{lo:.2f}, {hi:.2f}]"
                        )
                    else:
                        print(
                            f"category_check:{args.category} PASS (range {lo:.2f}..{hi:.2f})"
                        )

    if args.category in ("weapon", "shield") and result["skins"] > 0:
        warnings.append("Weapons/shields should usually be unskinned for socket attachment")

    if args.category in ("player", "enemy") and result["skins"] == 0:
        warnings.append("Character-like assets are easier to animate if skinned")

    if warnings:
        print("verdict:      WARN")
        for msg in warnings:
            print(f"warn:         {msg}")
        return 1 if args.strict else 0

    print("verdict:      PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
