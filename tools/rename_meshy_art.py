#!/usr/bin/env python3
"""
Strip Meshy_AI_ prefix and timestamp segment _NNNNNNNN_ before _texture from art assets.
Preserves _texture, _texture_0, etc. Run from repo root: python tools/rename_meshy_art.py
"""
from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art"


def transform_filename(name: str) -> str:
    if not name.startswith("Meshy_AI_"):
        return name
    rest = name[len("Meshy_AI_") :]
    # Timestamp block before literal "_texture" (keeps _texture_0.jpg etc.)
    rest = re.sub(r"_\d{8,}_texture", "_texture", rest)
    return rest


def main() -> None:
    if not ART.is_dir():
        raise SystemExit(f"Missing art dir: {ART}")

    pairs: list[tuple[Path, Path]] = []
    for p in ART.iterdir():
        if not p.is_file():
            continue
        new_name = transform_filename(p.name)
        if new_name == p.name:
            continue
        dest = ART / new_name
        pairs.append((p, dest))

    # Collision check
    seen: set[str] = set()
    for _, d in pairs:
        if d.name in seen:
            raise SystemExit(f"Duplicate target name: {d.name}")
        seen.add(d.name)

    old_to_new = {a.name: b.name for a, b in pairs}
    # Longest old names first for safe substring replace
    keys_sorted = sorted(old_to_new.keys(), key=len, reverse=True)

    def rewrite_text(s: str) -> str:
        for old in keys_sorted:
            s = s.replace(old, old_to_new[old])
        return s

    text_suffixes = {".gd", ".tscn", ".import", ".md", ".cfg", ".godot"}
    skip_dirs = {".git", "node_modules"}

    for path in ROOT.rglob("*"):
        if path.is_dir():
            continue
        rel = path.relative_to(ROOT)
        if rel.parts and rel.parts[0] in skip_dirs:
            continue
        if path.suffix.lower() not in text_suffixes and path.name != "filesystem_cache10":
            continue
        try:
            raw = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if "Meshy_AI_" not in raw:
            continue
        new_raw = rewrite_text(raw)
        if new_raw != raw:
            path.write_text(new_raw, encoding="utf-8", newline="\n")

    # Two-phase rename to avoid clobber (e.g. A->B and B->A not here; still use temp if needed)
    tmp_dir = ART / "_rename_tmp_meshy"
    tmp_dir.mkdir(exist_ok=True)
    for src, _ in pairs:
        interim = tmp_dir / src.name
        shutil.move(str(src), str(interim))
    for src, dst in pairs:
        interim = tmp_dir / src.name
        shutil.move(str(interim), str(dst))
    try:
        tmp_dir.rmdir()
    except OSError:
        pass

    imported = ROOT / ".godot" / "imported"
    if imported.is_dir():
        for p in list(imported.iterdir()):
            if p.name.startswith("Meshy_AI_"):
                p.unlink(missing_ok=True)

    print(f"Renamed {len(pairs)} art files; cleared matching .godot/imported caches.")
    for a, b in sorted(pairs, key=lambda x: x[0].name):
        print(f"  {a.name} -> {b.name}")


if __name__ == "__main__":
    main()
