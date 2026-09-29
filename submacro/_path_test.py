#!/usr/bin/env python3
"""Test the real _PathParseText, extracted verbatim from VortexMacro.ahk.

Also parses the actual Snowy Mountains.path so the shipped file is verified,
not just synthetic input. A stray token in a path line would be SENT into the
game as literal keystrokes, so the injection cases matter.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(r"C:\VortexMacro")
SRC = ROOT / "submacro" / "VortexMacro.ahk"
AHK = ROOT / "submacro" / "AutoHotkey64.exe"
TEST = ROOT / "submacro" / "_path_test.ahk"
RES = ROOT / "submacro" / "_path_result.txt"
REAL = ROOT / "maps" / "Snowy Mountains.path"

text = SRC.read_text(encoding="utf-8", errors="replace")


def grab(name: str) -> str:
    m = re.search(rf"^{re.escape(name)}\(", text, re.M)
    if not m:
        sys.exit(f"FATAL: {name} not found - the test would be vacuous")
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


funcs = [grab("_PathParseText"), grab("_InArr"), grab("_DigHoldTime"), grab("_DigSpeedDefault")]
print("extracted verbatim:")
for f in funcs:
    print("   " + f.splitlines()[0].strip())

# The real globals the parser reads, copied from the source's own definitions.
globals_src = """
WatchOrder := ["at_node", "dig_done", "at_water", "wash_done"]
Caps := Map("nodeCap", 1600, "digCap", 2800, "waterCap", 1150, "washClicks", 15)
DigSpeed := 100
_RouteInt(s, dflt) {
    try
        return Integer(Trim(s))
    return dflt
}
"""

harness = r"""
#Requires AutoHotkey v2.0
#SingleInstance Off
RESFILE := A_ScriptDir . "\_path_result.txt"
try FileDelete(RESFILE)
say(line) {
    FileAppend(line . "`n", "*")
    try FileAppend(line . "`r`n", RESFILE)
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

; ---- case 1: the SHIPPING file, parsed for real ----------------------
real := _PathParseText(FileRead(A_ScriptDir . "\..\maps\Snowy Mountains.path", "UTF-8"))
say("shipping file: " . real.steps.Length . " actions, " . real.bad . " bad, "
    . real.total . " non-comment lines")
check("shipping path has no bad lines", real.bad = 0)
check("shipping path has 8 actions", real.steps.Length = 8)
check("shipping path: walk to ground is w/at_node", (real.steps[1].d = "step"
    and real.steps[1].key = "w" and real.steps[1].watch = "at_node"))
check("shipping path: dig became a mouse hold", (real.steps[3].d = "hold"
    and real.steps[3].key = "mouse"))
check("shipping path: hold ms = Round(66900/(100+9)) = 614", real.steps[3].ms = 614)
check("shipping path: walk to water is s/at_water", (real.steps[5].d = "step"
    and real.steps[5].key = "s" and real.steps[5].watch = "at_water"))
check("shipping path: panning is repeated clicks", (real.steps[7].d = "click"
    and real.steps[7].n = 14))
check("shipping path: no slider waits left", (real.steps[4].ms = 400))

; ---- case 2: comments and blanks are ignored -------------------------
t2 := "; a comment`n`n   `nstep w at_node nodeCap`n"
r2 := _PathParseText(t2)
check("comments/blanks ignored", (r2.steps.Length = 1 and r2.bad = 0 and r2.total = 1))

; ---- case 3: rejection of anything unusable -------------------------
t3 := "step w at_node nodeCap`n"
   . "step w nope nodeCap`n"          ; bad watch name
   . "step w at_node nopeCap`n"       ; bad cap name
   . "step`n"                          ; too few fields
   . "bogus w at_node nodeCap`n"      ; unknown directive
   . "step {Enter} at_node nodeCap`n" ; INJECTION: braces would be sent literally
   . "step w at_node`n"                ; only 3 fields
r3 := _PathParseText(t3)
say("rejection case: " . r3.steps.Length . " kept, " . r3.bad . " rejected")
check("only the valid line survives", (r3.steps.Length = 1 and r3.bad = 6))
check("no step object carries a brace token", (r3.steps[1].key = "w"))

; ---- case 4: numeric bounds -----------------------------------------
t4 := "hold w 500`n"
   . "hold w 0`n"            ; too short
   . "hold w 999999`n"       ; over the 60s cap
   . "hold w abc`n"          ; not a number
   . "wait 250`n"
   . "wait -5`n"             ; negative
r4 := _PathParseText(t4)
say("bounds case: " . r4.steps.Length . " kept, " . r4.bad . " rejected")
check("hold/wait bounds enforced", (r4.steps.Length = 2 and r4.bad = 4))
check("hold ms kept correctly", r4.steps[1].ms = 500)
check("wait 0 is allowed", (_PathParseText("wait 0`n").steps.Length = 1))

; ---- case 4b: the click directive -----------------------------------
r6 := _PathParseText("click`n")
check("bare click means 1", (r6.steps.Length = 1 and r6.steps[1].n = 1))
check("click 5 keeps 5", _PathParseText("click 5`n").steps[1].n = 5)
r7 := _PathParseText("click 0`nclick 21`nclick abc`n")
check("click bounds enforced", (r7.steps.Length = 0 and r7.bad = 3))

; ---- case 4c: the dig directive (stat-driven hold) -------------------
r8 := _PathParseText("dig`n")
check("dig defaults to DigSpeed 100 -> 614ms", (r8.steps.Length = 1
    and r8.steps[1].d = "hold" and r8.steps[1].key = "mouse" and r8.steps[1].ms = 614))
check("dig 200 -> Round(66900/209) = 320", _PathParseText("dig 200`n").steps[1].ms = 320)
check("dig 1 -> clamped 4000, NOT the reference's truncated 669",
    _PathParseText("dig 1`n").steps[1].ms = 4000)
check("dig 10000 -> clamped up to 60", _PathParseText("dig 10000`n").steps[1].ms = 60)
r9 := _PathParseText("dig 0`ndig abc`ndig -5`n")
check("dig rejects bad speeds", (r9.steps.Length = 0 and r9.bad = 3))

; ---- case 4e: template directives -----------------------------------
rT := _PathParseText("await DIGPROMPT 5000`nclickimg SELLBTN 40`nawait BAD/NAME 100`nclickimg 9x 300`n")
check("await/clickimg parsed, bad ones rejected", (rT.steps.Length = 2 and rT.bad = 2))
check("await keeps name + cap", (rT.steps[1].d = "await" and rT.steps[1].img = "DIGPROMPT"
    and rT.steps[1].cap = 5000))
check("clickimg keeps tol", (rT.steps[2].d = "clickimg" and rT.steps[2].img = "SELLBTN"
    and rT.steps[2].tol = 40))
check("path traversal in template name rejected", (_PathParseText("await ../evil 100`n").bad = 1))
check("clickimg tol out of range rejected", (_PathParseText("clickimg OK 300`n").bad = 1))

; ---- case 4d: trailing comments -------------------------------------
; Covered by the shipping-file assertions above: that file contains
; "dig   ; comment", so "no bad lines" + "dig became a mouse hold" fail if
; comment stripping ever regresses. Kept here as a note, not a second check.
check("comment-only line still skipped", (_PathParseText("; just a comment`n").steps.Length = 0))

; ---- case 5: junk input cannot throw --------------------------------
r5 := _PathParseText("")
check("empty text is safe", (r5.steps.Length = 0 and r5.bad = 0))

say("RESULT fails=" . fails)
ExitApp(fails = 0 ? 0 : 1)
"""

TEST.write_text(globals_src + "\n\n" + "\n\n".join(funcs) + "\n\n" + harness, encoding="utf-8")
print(f"\ntest script: {TEST.name} ({len(TEST.read_text(encoding='utf-8').splitlines())} lines)")

print("\n=== running under the bundled AHK v2 ===")
try:
    p = subprocess.run(
        [str(AHK), "/ErrorStdOut", str(TEST)], capture_output=True, text=True, timeout=90
    )
except subprocess.TimeoutExpired:
    sys.exit("FATAL: test hung - treat as failure")
out = (p.stdout or "") + (p.stderr or "")
print(f"exit={p.returncode}")
print(out.strip() or "(no stdout; see result file)")
if RES.exists():
    print("--- result file ---")
    print(RES.read_text(encoding="utf-8", errors="replace").strip())
sys.exit(0 if p.returncode == 0 else 1)
