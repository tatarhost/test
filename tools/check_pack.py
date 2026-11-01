#!/usr/bin/env python3
"""
HYPERREAL SHADERS - static consistency checks for the shader pack.

These checks do not need Minecraft. They validate the parts of the pack that a
GLSL compiler cannot see:

  * program/buffer wiring (DRAWBUFFERS vs declared outputs)
  * accidental framebuffer feedback loops (sampling a buffer that is written)
  * colortex formats for every buffer that is used
  * shaders.properties option screens / sliders / presets vs settings.glsl
  * translation keys for every screen, option and preset (en_us, ru_ru)
  * block.properties ids vs the constants in lib/materials.glsl
  * render state directives required by the architecture

Usage: python3 tools/check_pack.py [-v]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compile_shaders import SHADERS, ROOT, expand, IncludeError  # noqa: E402

PROPERTIES = SHADERS / "shaders.properties"
SETTINGS = SHADERS / "lib" / "settings.glsl"

problems: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    problems.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

DRAWBUFFERS_RE = re.compile(r"/\*\s*DRAWBUFFERS\s*:\s*([0-9]+)\s*\*/")
RENDERTARGETS_RE = re.compile(r"/\*\s*RENDERTARGETS\s*:\s*([0-9,\s]+)\*/")
OUT_LOCATION_RE = re.compile(r"layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*out\s+\w+\s+\w+")
SAMPLER_RE = re.compile(r"uniform\s+sampler2D\s+(colortex\d+)\s*;")
FORMAT_RE = re.compile(r"^\s*const\s+int\s+colortex(\d+)Format\s*=\s*(\w+)\s*;")
KNOWN_FORMATS = {
    "R8", "R16", "R16F", "R32F",
    "RG8", "RG16", "RG16F", "RG32F",
    "RGB8", "RGB16", "RGB16F", "RGB32F",
    "RGBA8", "RGBA16", "RGBA16F", "RGBA32F",
    "RGB10_A2", "R11F_G11F_B10F",
    "RGB8_SNORM", "RGBA8_SNORM", "SRGB8", "SRGB8_ALPHA8",
}


def format_directives(src: str) -> dict[int, tuple[str, bool]]:
    """Format directives exactly as Iris and OptiFine find them.

    Both loaders split the *expanded* program source into lines and look for
    lines whose first token is "const", so a directive inside a block comment is
    still found. We also track whether the line really is commented out, because
    an uncommented "const int colortex0Format = RGBA16F;" cannot compile.
    """
    found: dict[int, tuple[str, bool]] = {}
    in_comment = False
    for line in src.splitlines():
        was_in_comment = in_comment
        m = FORMAT_RE.match(line)
        if m:
            found[int(m.group(1))] = (m.group(2), was_in_comment)
        stripped = re.sub(r"/\*.*?\*/", "", line)
        if in_comment:
            if "*/" in stripped:
                in_comment = False
        elif "/*" in stripped:
            in_comment = "*/" not in stripped.split("/*", 1)[1]
    return found


def source_of(path: Path) -> str:
    try:
        return expand(path).source
    except IncludeError as exc:
        err(str(exc))
        return ""


def strip_comments(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    return src


# ---------------------------------------------------------------------------
# 1. program list / include sanity
# ---------------------------------------------------------------------------

programs = sorted(p for p in SHADERS.iterdir() if p.suffix in (".vsh", ".fsh"))
if not programs:
    err("no programs found")

for p in programs:
    src = source_of(p)
    if not src.lstrip().startswith("#version"):
        err(f"{p.name}: #version must be the first line")

for lib in sorted((SHADERS / "lib").glob("*.glsl")):
    if "#version" in lib.read_text():
        err(f"lib/{lib.name}: #include files must not contain a #version directive")

# ---------------------------------------------------------------------------
# 2. buffer wiring
# ---------------------------------------------------------------------------

written: dict[str, set[int]] = {}
sampled: dict[str, set[int]] = {}

for p in programs:
    if p.suffix != ".fsh":
        continue
    src = source_of(p)
    clean = strip_comments(src)
    m = DRAWBUFFERS_RE.search(src) or RENDERTARGETS_RE.search(src)
    if m:
        if m.re is RENDERTARGETS_RE:
            indices = [int(d) for d in re.findall(r"\d+", m.group(1))]
        else:
            indices = [int(d) for d in m.group(1)]
        written[p.name] = set(indices)
        locations = [int(x) for x in OUT_LOCATION_RE.findall(clean)]
        if locations:
            if sorted(locations) != sorted(range(len(locations))):
                err(f"{p.name}: output locations must be 0..{len(locations) - 1} in declaration order")
            if len(locations) != len(indices):
                err(f"{p.name}: {len(locations)} outputs declared but DRAWBUFFERS lists {len(indices)} targets")
        for i in indices:
            if i > 7:
                err(f"{p.name}: colortex{i} written, the pack keeps all buffers within colortex0-7")
        if len(set(indices)) != len(indices):
            err(f"{p.name}: duplicate target in DRAWBUFFERS")
    elif p.name not in ("final.fsh", "shadow.fsh", "gbuffers_clouds.fsh"):
        warn(f"{p.name}: no DRAWBUFFERS directive, defaults to colortex0")
    sampled[p.name] = set(int(x[len('colortex'):]) for x in SAMPLER_RE.findall(clean))

for name, writes in written.items():
    overlap = writes & sampled.get(name, set())
    if overlap:
        err(f"{name}: framebuffer feedback - samples colortex{sorted(overlap)} while writing it")

for name, reads in sampled.items():
    if name.startswith("gbuffers_") or name.startswith("shadow"):
        illegal = {i for i in reads if i < 4}
        if illegal:
            err(f"{name}: gbuffer programs cannot sample colortex{sorted(illegal)} (Iris and OptiFine "
                f"only expose colortex4-15 to world programs)")

all_written = set().union(*written.values()) if written else set()
formats: set[int] = set()
for p in programs:
    if p.suffix != ".fsh":
        continue
    for index, (name, commented) in format_directives(source_of(p)).items():
        formats.add(index)
        if name not in KNOWN_FORMATS:
            err(f"{p.name}: colortex{index}Format = {name} is not a valid Iris texture format")
        if not commented:
            err(f"{p.name}: colortex{index}Format must sit inside a block comment, "
                f"otherwise the GLSL compiler rejects the identifier")
for i in sorted(all_written):
    if i not in formats:
        warn(f"colortex{i} is written but has no format directive (defaults to RGBA8)")

# ---------------------------------------------------------------------------
# 3. shaders.properties vs settings.glsl
# ---------------------------------------------------------------------------

settings_text = SETTINGS.read_text()
declared_options = {n for n in re.findall(r"^#define\s+([A-Z0-9_]+)", settings_text, re.M) if not n.endswith("_GLSL")}
const_options = set(re.findall(r"^const\s+\w+\s+([A-Za-z0-9_]+)\s*=", settings_text, re.M))
all_options = declared_options | const_options

props = PROPERTIES.read_text()
prop_lines = [ln for ln in props.splitlines() if ln.strip() and not ln.strip().startswith("#")]
prop_text = "\n".join(re.sub(r"\\\s*$", "", ln) for ln in prop_lines)


def prop_values(key: str) -> list[str]:
    values: list[str] = []
    for line in prop_text.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k.strip() == key:
            values.extend(v.split())
    return values


referenced: set[str] = set()
main_screens: list[str] = []
for k, v in [ln.split("=", 1) for ln in prop_text.splitlines() if "=" in ln]:
    k = k.strip()
    if k == "screen":
        main_screens.extend(v.split())
    elif k == "sliders":
        referenced.update(x for x in v.split() if x)
    elif k.startswith("screen.") and not k.endswith(".columns"):
        name = k[len("screen."):]
        if name not in main_screens:
            err(f"shaders.properties: screen.{name} is defined but not listed in 'screen'")
        referenced.update(x for x in v.split() if x)

for scr in main_screens:
    if f"screen.{scr}" not in prop_text:
        err(f"shaders.properties: screen '{scr}' is listed but never defined")

profiles: dict[str, dict[str, str]] = {}
for line in prop_text.splitlines():
    if line.startswith("profile.") and "=" in line:
        name, rest = line.split("=", 1)
        entries = {}
        for token in rest.split():
            if "=" not in token:
                err(f"shaders.properties: malformed preset entry '{token}' in {name}")
                continue
            k, v = token.split("=", 1)
            entries[k] = v
            referenced.add(k)
        profiles[name.strip()[len("profile."):]] = entries

for opt in sorted(referenced):
    if opt not in all_options:
        err(f"shaders.properties references option '{opt}' which is not declared in lib/settings.glsl")

for opt in sorted(declared_options):
    if opt not in referenced:
        warn(f"option {opt} is declared but not exposed in any screen")

# required render state
if not re.search(r"^clouds\s*=\s*off", prop_text, re.M):
    err("shaders.properties must disable vanilla clouds (clouds=off) - the pack renders volumetric clouds")
for prog in ("gbuffers_water", "gbuffers_hand_water"):
    if not re.search(rf"^blend\.{prog}\s*=\s*off", prop_text, re.M):
        err(f"shaders.properties must disable blending for {prog} (G-buffer integrity)")

# ---------------------------------------------------------------------------
# 4. translation keys
# ---------------------------------------------------------------------------

for lang in ("en_us", "ru_ru"):
    path = SHADERS / "lang" / f"{lang}.lang"
    if not path.is_file():
        err(f"missing language file lang/{lang}.lang")
        continue
    text = path.read_text()
    keys = set(re.findall(r"^([A-Za-z0-9_.]+)\s*=", text, re.M))
    for screen in main_screens:
        if f"screen.{screen}" not in keys:
            err(f"lang/{lang}.lang: missing key screen.{screen}")
    for opt in sorted(referenced):
        if opt in const_options:
            continue
        if f"option.{opt}" not in keys:
            err(f"lang/{lang}.lang: missing key option.{opt}")
    for prof in profiles:
        if f"profile.{prof}" not in keys:
            err(f"lang/{lang}.lang: missing key profile.{prof}")

# ---------------------------------------------------------------------------
# 5. block.properties vs materials.glsl ids
# ---------------------------------------------------------------------------

materials = (SHADERS / "lib" / "materials.glsl").read_text()
mat_ids = {name: int(value) for name, value in re.findall(r"const float (ID_[A-Z_]+)\s*=\s*(\d+)\.0;", materials)}
block_props = (SHADERS / "block.properties").read_text()
block_ids: dict[int, list[str]] = {}
for line in block_props.splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    m = re.match(r"block\.(\d+)\s*=\s*(.+)$", line)
    if not m:
        err(f"block.properties: unexpected line '{line}'")
        continue
    block_ids.setdefault(int(m.group(1)), []).extend(m.group(2).split())
    for name in m.group(2).split():
        if not re.match(r"^minecraft:[a-z0-9_]+$", name):
            err(f"block.properties: '{name}' is not a valid 1.20.4 block id")

for name, value in sorted(mat_ids.items()):
    if name == "ID_NONE":
        continue
    if value not in block_ids:
        warn(f"materials.glsl defines {name} = {value} but block.properties has no entry for it")

for value in block_ids:
    if value not in mat_ids.values():
        warn(f"block.properties uses id {value} which has no ID_* constant in materials.glsl")

# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

if warnings:
    print("warnings:")
    for w in warnings:
        print("  - " + w)
    print()

if problems:
    print("problems:")
    for p in problems:
        print("  - " + p)
    print()
    print(f"{len(problems)} problem(s) found")
    sys.exit(1)

print(f"pack structure OK ({len(programs)} programs, {len(all_options)} options, "
      f"{len(profiles)} presets, {len(warnings)} warning(s))")
