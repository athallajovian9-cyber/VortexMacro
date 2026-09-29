#!/usr/bin/env python3
"""Extract the auto-watch functions VERBATIM from VortexMacro.ahk and exercise
them with synthetic screen data. Testing a copy I retyped would prove nothing;
this pulls the real source text out of the shipping file.

Three cases:
  1. a HUD-like cell  -> changes rarely but sharply -> MUST be kept
  2. a scenery cell   -> changes on nearly every sweep -> MUST be rejected
  3. a dead cell      -> never changes -> MUST be rejected
plus: a fully static screen must be reported as unusable, not as "learned".
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(r"C:\VortexMacro")
SRC = ROOT / "submacro" / "VortexMacro.ahk"
AHK = ROOT / "submacro" / "AutoHotkey64.exe"
TEST = ROOT / "submacro" / "_autowatch_test.ahk"

text = SRC.read_text(encoding="utf-8", errors="replace")


def grab(name: str) -> str:
    """Pull one top-level function definition out by brace matching."""
    m = re.search(rf"^{re.escape(name)}\(", text, re.M)
    if not m:
        sys.exit(f"FATAL: {name} not found in {SRC} - the test would be vacuous")
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
    sys.exit(f"FATAL: unbalanced braces extracting {name}")


funcs = [grab("_ClassifySig"), grab("_SigDeltaMasked"), grab("_CellDelta")]

harness = r"""
#Requires AutoHotkey v2.0
#SingleInstance Off
SetKeyDelay 0
RESFILE := A_ScriptDir . "\_autowatch_result.txt"
try FileDelete(RESFILE)
say(line) {
    FileAppend(line . "`n", "*")          ; stdout
    try FileAppend(line . "`r`n", RESFILE) ; and a file, in case stdout is detached
}
fails := 0
check(name, cond) {
    global fails
    if (cond)
        say("PASS  " . name)
    else {
        say("FAIL  " . name)
        fails += 1
    }
}

; ---- build synthetic event arrays -------------------------------------
; 576 cells (32x18). sweeps = 40 (a 20s learn at 400ms sweepMs, ~50 sweeps;
; 40 is representative). maxEv = floor(40 * 0.35) = 14.
NSW := 40
N := 576
ev := Buffer(N * 4, 0)

; cell 0   : the HUD indicator, changed twice in 40 sweeps  -> KEEP
NumPut("Int", 2, ev, 0 * 4)
; cell 1   : scenery, changed on 35 of 40 sweeps           -> REJECT (over maxEv)
NumPut("Int", 35, ev, 1 * 4)
; cell 2   : dead pixel, never changed                     -> REJECT (under minEv)
NumPut("Int", 0, ev, 2 * 4)
; cell 3   : borderline scenery at exactly maxEv+1         -> REJECT
NumPut("Int", 15, ev, 3 * 4)
; cell 4   : quiet HUD second indicator, changed once      -> KEEP
NumPut("Int", 1, ev, 4 * 4)
; cells 5..100 : scenery                                    -> REJECT
loop 96
    NumPut("Int", 30, ev, (4 + A_Index) * 4)
; everything else stays 0 (dead)

r := _ClassifySig(ev, N, NSW)

check("maxEv is floor(40*0.35) = 14", r.maxEv = 14)
check("HUD cell 0 kept", NumGet(r.mask, 0, "UChar") = 1)
check("HUD cell 4 kept", NumGet(r.mask, 4, "UChar") = 1)
check("scenery cell 1 rejected", NumGet(r.mask, 1, "UChar") = 0)
check("dead cell 2 rejected", NumGet(r.mask, 2, "UChar") = 0)
check("borderline cell 3 rejected", NumGet(r.mask, 3, "UChar") = 0)
check("exactly 2 cells kept", r.kept = 2)

; ---- masked delta must ignore unkept cells ---------------------------
; Two captures that differ ONLY in a scenery cell (1) must read as ZERO
; change once masked, because scenery is excluded from the settle test.
; Build captures where cell 1 differs by 250 and cell 0 is identical.
a := Buffer(N * 4, 0)
b := Buffer(N * 4, 0)
loop N {
    i := A_Index - 1
    NumPut("UChar", 100, a, i * 4)
    NumPut("UChar", 100, b, i * 4)
}
NumPut("UChar", 250, b, 1 * 4)        ; scenery cell churns
check("masked delta ignores excluded scenery", _SigDeltaMasked(a, b, r.mask) = 0)

; Now also differ in the HUD cell -> must register.
NumPut("UChar", 160, b, 0 * 4)        ; HUD cell's BLUE channel flips by 60
d := _SigDeltaMasked(a, b, r.mask)
; 2 kept cells x 3 channels = 6 samples, and only one channel moved, by 60
; -> 60/6 = 10. Units are the mean per-channel delta, the same units _SigDelta
; returns, which is what stillTol is compared against. The expectation has to
; be in those units or the whole settle threshold is meaningless.
check("masked delta sees the HUD change", Abs(d - 10) < 0.01)

; _CellDelta sanity
check("_CellDelta reads max channel", _CellDelta(a, b, 0) = 60)
check("_CellDelta on unchanged cell", _CellDelta(a, b, 5) = 0)

; ---- a fully static screen must NOT look learned ---------------------
ev2 := Buffer(N * 4, 0)               ; every cell 0 events
r2 := _ClassifySig(ev2, N, NSW)
check("all-dead screen keeps nothing", r2.kept = 0)

say("RESULT fails=" . fails)
ExitApp(fails = 0 ? 0 : 1)
"""

TEST.write_text(harness, encoding="utf-8")
print(f"extracted verbatim: {', '.join(f.splitlines()[0].strip() for f in funcs)}")

inc = TEST.with_suffix(".inc.ahk")
inc.write_text("\n\n".join(funcs) + "\n", encoding="utf-8")

full = inc.read_text(encoding="utf-8") + "\n\n" + harness
TEST.write_text(full, encoding="utf-8")
print(f"test script: {TEST} ({len(full.splitlines())} lines)")

print("\n=== running under the bundled AHK v2 ===")
try:
    p = subprocess.run(
        [str(AHK), "/ErrorStdOut", str(TEST)], capture_output=True, text=True, timeout=90
    )
except subprocess.TimeoutExpired:
    sys.exit("FATAL: test hung - not a syntax pass, treat as failure")
out = (p.stdout or "") + (p.stderr or "")
print(f"exit={p.returncode}")
print(out.strip() or "(no output)")
sys.exit(0 if p.returncode == 0 else 1)
