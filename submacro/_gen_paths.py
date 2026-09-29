#!/usr/bin/env python3
"""Generate a .path file for every map in maps/, then verify every one of them
parses clean with the REAL parser extracted from VortexMacro.ahk.

The control scheme is the documented one for Prospecting, so this is not
invented: WASD walk, HOLD LMB fills/shakes the pan. Distances are deliberately
absent - a "step" ends when the screen changes, so no walking distance has to
be measured for a map nobody has walked yet.
"""
import glob
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(r"C:\VortexMacro")
MAPS = ROOT / "maps"
SRC = ROOT / "submacro" / "VortexMacro.ahk"
AHK = ROOT / "submacro" / "AutoHotkey64.exe"
KEEP = "Snowy Mountains"  # already hand-written; leave its fuller header alone

HEADER = """; {name}  -  Prospecting
; Symbolic path. No recording, no marking. Edit freely.
;
; THE LOOP (from the guides, not guessed)
;   1. Left-click diggable ground with the shovel equipped -> a timing slider
;      pops up and sweeps up and down.
;   2. Left-click when the slider is in the GREEN ZONE at the top. A 100%
;      Perfect Score raises the weight and quality of the ore in the sand.
;   3. You MUST stand in the water to pan. Walk to the water, then repeatedly
;      left-click to shake the pan; each click advances the shake bar by the
;      pan's Shake Strength and Shake Speed.
;      (A guide claiming "no water required" is wrong; the player confirms you
;      do have to stand in the water.)
;
; HOW THE DIG TIMING WORKS (no slider tracking needed)
;   The established macro for this game does not watch the slider either - it
;   computes the hold from the player's Dig Speed stat:
;       hold = Round(66900 / (digSpeed + 9))
;   The "dig" line below does the same thing, so nothing has to be read off the
;   screen. Change the stat number in that line (e.g. "dig 140") after an
;   upgrade, or edit the DigSpeed default in the macro. The value is clamped to
;   60..4000 ms so a wrong number cannot produce a nonsense hold.
;
;   step <key> <watch> <cap>   hold key until the watch point changes
;   hold <key> <ms>            hold key for a fixed time
;   click [n]                  click left mouse n times
;   wash                       legacy multi-click wash
;   wait <ms>                  pause
;
; A "step" ends when the screen changes, so no walking distance is hard-coded.
; Caps are on the Timing tab and self-tune as the loop runs.
; Watches: at_node, dig_done, at_water, wash_done
; Caps:    nodeCap, digCap, waterCap, washClicks
"""

body = """step  w      at_node   nodeCap     ; walk to diggable ground
wait  150
dig            ; HOLD left mouse; hold time comes from the Dig Speed stat
wait  400
step  s      at_water  waterCap    ; walk to the water
wait  300
click 14       ; STAND IN WATER, repeatedly click to pan
wait  500
"""

names = sorted(
    os.path.basename(p)[:-4] for p in glob.glob(str(MAPS / "*.ini"))
)
written, skipped = [], []
for n in names:
    out = MAPS / f"{n}.path"
    # NEVER clobber a route derived from the reference macro's authored
    # navigation - this generator only knows the generic loop.
    if out.exists():
        try:
            if "NAVIGATION taken from the reference" in out.read_text(encoding="utf-8", errors="replace"):
                skipped.append(n)
                continue
        except OSError:
            pass
    # Every map gets the corrected loop. The earlier bespoke Snowy Mountains
    # header described a water-based loop that the guides say is wrong, so it
    # is deliberately not preserved.
    out.write_text(HEADER.format(name=n) + "\n" + body, encoding="utf-8")
    written.append(n)

print(f"maps found: {len(names)}")
print(f"  written: {len(written)}")
print(f"  kept as-is: {skipped}")

# ---- verify EVERY generated file with the real parser -----------------
text = SRC.read_text(encoding="utf-8", errors="replace")


def grab(name: str) -> str:
    m = re.search(rf"^{re.escape(name)}\(", text, re.M)
    if not m:
        sys.exit(f"FATAL: {name} not found")
    start = m.start()
    depth = 0
    i = text.index("{", m.end())
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start : j + 1]
    sys.exit(f"FATAL: unbalanced braces in {name}")


checker = r"""
#Requires AutoHotkey v2.0
#SingleInstance Off
WatchOrder := ["at_node", "dig_done", "at_water", "wash_done"]
Caps := Map("nodeCap", 1600, "digCap", 2800, "waterCap", 1150, "washClicks", 15)
DigSpeed := 100
_RouteInt(s, dflt) {
    try
        return Integer(Trim(s))
    return dflt
}
""" + "\n\n".join([grab("_PathParseText"), grab("_InArr"), grab("_DigHoldTime"), grab("_DigSpeedDefault")]) + r"""

say(line) {
    FileAppend(line . "`n", "*")
}
total := 0, bad := 0, empty := 0, files := 0, acts := 0
Loop Files, A_ScriptDir . "\..\maps\*.path" {
    files += 1
    r := _PathParseText(FileRead(A_LoopFileFullPath, "UTF-8"))
    total += r.total
    bad += r.bad
    acts += r.steps.Length
    if (r.steps.Length = 0)
        empty += 1
    if (r.bad or r.steps.Length = 0)
        say("PROBLEM  " . A_LoopFileName . "  bad=" . r.bad . " steps=" . r.steps.Length)
}
say("VERIFY  files=" . files . "  actions=" . acts . "  badlines=" . bad . "  empty=" . empty)
ExitApp((bad or empty or files = 0) ? 1 : 0)
"""

t = ROOT / "submacro" / "_allpaths_test.ahk"
t.write_text(checker, encoding="utf-8")
print("\n=== verifying every .path with the real parser ===")
try:
    p = subprocess.run(
        [str(AHK), "/ErrorStdOut", str(t)], capture_output=True, text=True, timeout=120
    )
except subprocess.TimeoutExpired:
    sys.exit("FATAL: verification hung")
print(((p.stdout or "") + (p.stderr or "")).strip())
print(f"exit={p.returncode}")
sys.exit(0 if p.returncode == 0 else 1)
