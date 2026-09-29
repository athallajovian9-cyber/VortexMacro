#!/usr/bin/env python3
"""Turn the reference macro's per-location navigation scripts into VortexMacro
.path files.

Source: inspiredby/OrnateMacroV1.4.8/Modules/Script1..20.ahk, each mapped to a
location by Controller.ahk's scriptLabels array. Those scripts are hand-authored
navigation paths - `Send {key down}` / `Sleep N` / `Send {key up}` - which is
exactly what a VortexMacro `hold` directive expresses.

Only the NAVIGATION is taken. The dig and the panning clicks come from the
control scheme the player confirmed, because the reference does those in code
with pixel probes that cannot be expressed as a path.

Caution, by design:
  * a location is only written when its name matches a VortexMacro map EXACTLY
    after normalisation - no fuzzy guessing that could point a map at the wrong
    route. Anything unmatched is reported instead.
  * HotbarMove() is skipped: it repositions the mouse for the reference macro's
    own pixel probes, not for movement.
  * the reference's known bugs are not carried over (GetHoldTime truncation, the
    CenterOfT undefined-variable branch).
"""
import glob
import os
import re
from pathlib import Path

ROOT = Path(r"C:\VortexMacro")
SRC = ROOT / "inspiredby" / "OrnateMacroV1.4.8"
MAPS = ROOT / "maps"

# --- 1. read the location -> script table ---------------------------------
ctrl = (SRC / "Modules" / "Controller.ahk").read_text(encoding="utf-8", errors="replace")
m = re.search(r"scriptLabels\s*:?=\s*\[(.*?)\]", ctrl, re.S)
if not m:
    raise SystemExit("FATAL: scriptLabels not found - refusing to guess the mapping")
labels = [x.strip().strip('"').strip("'") for x in m.group(1).split(",") if x.strip()]


def norm(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"^the\s+", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return " ".join(s.split())


# --- 2. VortexMacro's own map names ---------------------------------------
map_files = {norm(p.stem): p for p in MAPS.glob("*.ini")}

# The reference's own labels contain typos. These two are unambiguous - same
# game, same area, one transposition apart - so they are aliased EXPLICITLY
# rather than by a fuzzy matcher that could silently point the wrong route at a
# map. Anything not listed here stays unmatched and is reported.
ALIASES = {
    norm("OVERGROWN GOTTO"): "Overgrown Grotto",
    norm("FUNGAL MARCH"): "Fungal Marsh",
}
for _alias, _real in ALIASES.items():
    _t = map_files.get(norm(_real))
    if _t is None:
        raise SystemExit(f"FATAL: alias target '{_real}' is not a VortexMacro map")
    map_files[_alias] = _t

# --- 3. translate one reference script into directives --------------------
SKIP = re.compile(r"^(#|SendMode|SetKeybind|SetWorkingDir|HotbarMove|SendReset"
                  r"|InvTotemClick|EquipmentPick|ScrollTP|UiUniversal|UITop)")


def translate(path: Path, nav_delay_ms: int):
    out, note, pending = [], [], None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        # the all-keys-up safety line
        if re.match(r"^Send,\s*\{w up\}", line):
            out.append(("release", None, None))
            continue
        if SKIP.match(line):
            continue
        # a hold: {key down}
        mdown = re.match(r"^Send,\s*\{([A-Za-z0-9]+) down\}$", line)
        if mdown:
            pending = mdown.group(1).lower()
            continue
        # a tap: Send, {key} or Send, {key 2}
        mtap = re.match(r"^Send,\s*\{([A-Za-z0-9]+)(\s+\d+)?\}$", line)
        if mtap:
            out.append(("hold", mtap.group(1).lower(), 50))
            continue
        # a plain key up closes the hold opened above (its time came from Sleep)
        mup = re.match(r"^Send,\s*\{([A-Za-z0-9]+) up\}$", line)
        if mup:
            pending = None
            continue
        # Sleep, N  or  Sleep, %navigationDelay%
        ms = re.match(r"^Sleep,\s*%navigationDelay%", line)
        if ms:
            if pending:
                out.append(("hold", pending, nav_delay_ms)); pending = None
            else:
                out.append(("wait", None, nav_delay_ms))
            continue
        ms = re.match(r"^Sleep,\s*(\d+)\s*$", line)
        if ms:
            n = int(ms.group(1))
            if pending:
                out.append(("hold", pending, n)); pending = None
            elif n >= 40:
                out.append(("wait", None, n))
            continue
        if re.match(r"^Click", line):
            out.append(("click", None, 1))
            continue
        note.append(line)
    if pending:
        note.append(f"ended with {pending} still held - dropped")
    return out, note


def render(name: str, script: str, acts, notes) -> str:
    L = [
        f"; {name}  -  Prospecting",
        ";",
        f"; NAVIGATION taken from the reference macro ({script}), which is",
        "; hand-authored per location: Send {key down} / Sleep N / Send {key up},",
        "; expressed here as `hold`. Only the navigation is theirs.",
        ";",
        "; The dig and the panning clicks below come from the control scheme the",
        "; player confirmed: hold left mouse to dig, stand in water and click to pan.",
        "; Dig length is computed from the Dig Speed stat (see `dig`).",
        ";",
        "; Not carried over from the reference: HotbarMove() (it repositions the",
        "; mouse for their own pixel probes) and their known bugs.",
    ]
    if notes:
        L += [";", "; Lines this translator did not understand (kept for review):"]
        L += [f";   {n}" for n in notes[:8]]
    L += ["", "release            ; clear any key a previous cycle left held"]
    for d, key, ms in acts:
        if d == "hold":
            L.append(f"hold  {key:<5} {ms}")
        elif d == "wait":
            L.append(f"wait  {ms}")
        elif d == "click":
            L.append("click 1")
        elif d == "release":
            L.append("release")
    L += [
        "",
        "dig                ; HOLD left mouse to dig (time from the Dig Speed stat)",
        "wait  400",
        "click 14           ; pan: stand in water and click repeatedly",
        "wait  500",
        "",
    ]
    return "\n".join(L)


written, unmatched, errs = [], [], []
nav_delay = 1000
for i, label in enumerate(labels, 1):
    script = f"Script{i}.ahk" if (SRC / "Modules" / f"Script{i}.ahk").exists() else f"script{i}.ahk"
    p = SRC / "Modules" / script
    if not p.exists():
        errs.append(f"Script{i} missing for {label}")
        continue
    target = map_files.get(norm(label))
    if target is None:
        unmatched.append(label)
        continue
    acts, notes = translate(p, nav_delay)
    if not acts:
        errs.append(f"{label}: no movement extracted")
        continue
    target.with_suffix(".path").write_text(render(target.stem, script, acts, notes), encoding="utf-8")
    written.append((target.stem, script, len(acts)))

print(f"  reference locations : {len(labels)}")
print(f"  matched a VortexMacro map and written: {len(written)}")
for name, script, n in written:
    print(f"     {name:<26} <- {script}  ({n} nav actions)")
print(f"\n  no matching VortexMacro map ({len(unmatched)}): {unmatched}")
if errs:
    print(f"\n  PROBLEMS ({len(errs)}):")
    for e in errs:
        print("     " + e)
print(f"\n  total .path files now: {len(list(MAPS.glob('*.path')))}")