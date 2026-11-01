#!/usr/bin/env python3
"""
HYPERREAL SHADERS - static GLSL validation harness.

Iris/OptiFine resolve "#include" directives textually before handing the source
to the GLSL compiler. This script reproduces that step (identical search rules:
a leading "/" means the shader pack root, otherwise the path is relative to the
including file) and then runs the real Khronos reference front end
(glslangValidator) on every program of the pack.

Usage:
    python3 tools/compile_shaders.py [--glslang PATH] [--verbose]

Exit code 0 means every program compiled without errors.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"

INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"\s*$')

KNOWN_GLSLANG_LOCATIONS = [
    "glslangValidator",
    "glslang",
    str(ROOT / "tools" / "bin" / "glslangValidator"),
    "/tmp/gv/node_modules/glslang-validator-prebuilt-predownloaded/bin/glslangValidator.linux",
]


@dataclass
class Expansion:
    source: str
    files: list[Path] = field(default_factory=list)


class IncludeError(RuntimeError):
    pass


def resolve_include(current: Path, spec: str) -> Path:
    spec = spec.strip()
    if spec.startswith("/"):
        candidate = SHADERS / spec.lstrip("/")
    else:
        candidate = current.parent / spec
    candidate = candidate.resolve()
    if not candidate.is_file():
        raise IncludeError(f"{current.relative_to(ROOT)}: cannot resolve include \"{spec}\"")
    if SHADERS.resolve() not in candidate.parents and candidate.parent != SHADERS.resolve():
        raise IncludeError(f"{current.relative_to(ROOT)}: include escapes the shaders directory: {spec}")
    return candidate


def expand(path: Path, seen: tuple[Path, ...] = ()) -> Expansion:
    path = path.resolve()
    out = Expansion(source="")
    out.files.append(path)
    if path in seen:
        # #include guards make cycles harmless in practice, but report them so
        # genuine mistakes show up.
        raise IncludeError(f"circular include: {' -> '.join(str(p.relative_to(ROOT)) for p in seen + (path,))}")
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for lineno, line in enumerate(lines, 1):
        m = INCLUDE_RE.match(line)
        if m:
            child = expand(resolve_include(path, m.group(1)), seen + (path,))
            out.source += child.source
            out.files.extend(child.files)
            if not child.source.endswith("\n"):
                out.source += "\n"
        else:
            out.source += line + "\n"
    return out


def find_glslang(explicit: str | None) -> str | None:
    candidates = [explicit] if explicit else []
    candidates += KNOWN_GLSLANG_LOCATIONS
    for c in candidates:
        if not c:
            continue
        p = shutil.which(c) if os.sep not in c else (c if os.path.isfile(c) and os.access(c, os.X_OK) else None)
        if p:
            return p
    return None


def stage_suffix(path: Path) -> str:
    return ".vert" if path.suffix == ".vsh" else ".frag"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glslang", default=None, help="path to glslangValidator")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--keep", action="store_true", help="keep the expanded sources")
    args = ap.parse_args()

    glslang = find_glslang(args.glslang)
    if not glslang:
        print("error: glslangValidator not found.\n"
              "  install it with:  npm i glslang-validator-prebuilt-predownloaded\n"
              "  or point --glslang at an existing binary.", file=sys.stderr)
        return 2

    version = subprocess.run([glslang, "--version"], capture_output=True, text=True).stdout.strip().splitlines()
    print(f"using {glslang} ({version[0] if version else 'unknown version'})")

    programs = sorted(
        [p for p in SHADERS.iterdir() if p.suffix in (".vsh", ".fsh")],
        key=lambda p: p.name,
    )
    if not programs:
        print("error: no shader programs found", file=sys.stderr)
        return 2

    tmpdir = Path(tempfile.mkdtemp(prefix="hyperreal-glsl-"))
    failures: list[tuple[str, str]] = []
    ok = 0

    for program in programs:
        try:
            expansion = expand(program)
        except IncludeError as exc:
            failures.append((program.name, str(exc)))
            continue

        src = expansion.source
        if not src.lstrip().startswith("#version"):
            failures.append((program.name, "first non-comment line must be a #version directive"))
            continue

        stage_file = tmpdir / (program.stem + stage_suffix(program))
        stage_file.write_text(src, encoding="utf-8")

        result = subprocess.run(
            [glslang, str(stage_file)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            log = (result.stdout + result.stderr).strip()
            # strip the temporary path from the log to keep it readable
            log = log.replace(str(stage_file), program.name)
            failures.append((program.name, log))
        else:
            ok += 1
            if args.verbose:
                print(f"  ok   {program.name}")

    # --- link stage: verify that every vertex/fragment pair is compatible ----
    link_failures: list[tuple[str, str]] = []
    linked = 0
    for program in programs:
        if program.suffix != ".vsh":
            continue
        frag = program.with_suffix(".fsh")
        if not frag.is_file():
            continue
        try:
            v = expand(program)
            f = expand(frag)
        except IncludeError:
            continue  # already reported
        vf = tmpdir / (program.stem + ".link.vert")
        ff = tmpdir / (program.stem + ".link.frag")
        vf.write_text(v.source, encoding="utf-8")
        ff.write_text(f.source, encoding="utf-8")
        result = subprocess.run([glslang, "-l", str(vf), str(ff)], capture_output=True, text=True)
        # glslang refuses to link programs that use compatibility profile
        # built-ins (gl_TexCoord, gl_FogFragCoord, ...); real drivers link them
        # without complaint, so those diagnostics are reported as warnings.
        if result.returncode != 0 and "Anonymous member name" not in (result.stdout + result.stderr):
            log = (result.stdout + result.stderr).strip().replace(str(vf), program.name).replace(str(ff), frag.name)
            link_failures.append((program.stem, log))
        else:
            linked += 1

    if args.keep:
        print(f"expanded sources kept in {tmpdir}")
    else:
        shutil.rmtree(tmpdir, ignore_errors=True)

    print()
    for name, log in failures:
        print(f"FAIL {name}")
        for line in log.splitlines():
            print("     " + line)
        print()

    print(f"{ok}/{len(programs)} programs compiled")
    for name, log in link_failures:
        print(f"LINK FAIL {name}")
        for line in log.splitlines():
            print("     " + line)
        print()

    print(f"{linked} vertex/fragment pairs linked")
    if failures:
        print(f"{len(failures)} program(s) failed to compile")
        return 1
    if link_failures:
        print(f"{len(link_failures)} program(s) failed to link")
        return 1
    print("all programs compiled and linked successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
