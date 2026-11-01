#!/usr/bin/env python3
"""
Build the distributable shader pack archive.

The archive has a single top level entry, "shaders/", so that it can be dropped
into .minecraft/shaderpacks/ without extracting it, and so that extracting it
produces a folder that also works as a pack root.

Usage: python3 tools/build_zip.py [--out dist] [--name HYPERREAL-SHADERS-v1.0]
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"

# Files that must never end up in a release archive.
EXCLUDED_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini"}
EXCLUDED_SUFFIXES = {".bak", ".orig", ".rej", ".tmp", ".swp", ".pyc", ".kate-swp"}

# Everything the pack needs, and nothing else.
REQUIRED = [
    "shaders.properties",
    "block.properties",
    "composite.fsh",
    "composite.vsh",
    "final.fsh",
    "final.vsh",
    "shadow.fsh",
    "shadow.vsh",
    "lib/settings.glsl",
    "lib/uniforms.glsl",
    "lib/buffers.glsl",
    "lib/post.glsl",
    "lang/ru_ru.lang",
    "lang/en_us.lang",
]


def collect(base: Path) -> list[Path]:
    files = []
    for path in sorted(base.rglob("*")):
        if not path.is_file():
            continue
        if path.name in EXCLUDED_NAMES or path.suffix in EXCLUDED_SUFFIXES:
            continue
        files.append(path)
    return files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "dist"))
    parser.add_argument("--name", default="HYPERREAL-SHADERS-v1.0")
    args = parser.parse_args()

    if not SHADERS.is_dir():
        print(f"error: {SHADERS} not found", file=sys.stderr)
        return 1

    missing = [rel for rel in REQUIRED if not (SHADERS / rel).is_file()]
    if missing:
        for rel in missing:
            print(f"error: missing required file shaders/{rel}", file=sys.stderr)
        return 1

    files = collect(SHADERS)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    archive = out_dir / f"{args.name}.zip"

    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in files:
            # arcname keeps the "shaders/" prefix: the archive must be directly
            # usable inside .minecraft/shaderpacks/.
            arcname = "shaders/" + path.relative_to(SHADERS).as_posix()
            info = zipfile.ZipInfo(arcname, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, path.read_bytes())

    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        bad = zf.testzip()

    if bad is not None:
        print(f"error: corrupt entry {bad}", file=sys.stderr)
        return 1

    tops = {name.split("/")[0] for name in names}
    if tops != {"shaders"}:
        print(f"error: archive must contain exactly one top level folder, got {sorted(tops)}",
              file=sys.stderr)
        return 1

    print(f"{archive.relative_to(ROOT)}")
    print(f"  {len(names)} entries, {archive.stat().st_size / 1024:.1f} KiB")
    print("  top level: shaders/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
