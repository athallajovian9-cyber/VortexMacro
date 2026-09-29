#!/usr/bin/env python3
"""Static audit of VortexMacro.ahk for the bug classes actually encountered.

Each check prints how many things it EXAMINED, not just a verdict - a checker that
matches nothing must not be able to report "clean" (a previous scan of mine did
exactly that twice).
"""
import re
from collections import Counter
from pathlib import Path

SRC = Path(r"C:\VortexMacro\submacro\VortexMacro.ahk")
text = SRC.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()

# ---------------------------------------------------------------- helpers
def defs():
    out = {}
    for i, ln in enumerate(lines, 1):
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\(([^)]*)\)\s*\{", ln)
        if m:
            out.setdefault(m.group(1), []).append(i)
    return out

D = defs()

# ------------------------------------------------- 1. builtin-name variables
BUILTINS = """Abs Ceil Chr Cos Exp Floor Format InStr Integer IsNumber IsSet Ln Log
Max Min Mod NumGet NumPut Ord Random Round Sin Sqrt StrCompare StrLen StrLower
StrReplace StrSplit StrUpper SubStr Tan Trim Type Sleep Send Click ImageSearch
PixelGetColor FileRead FileAppend FileOpen FileDelete FileExist DirCreate DirExist
IniRead IniWrite Buffer Map WinActive WinExist WinGetList WinGetPos WinGetPID
ProcessGetName ProcessExist SetTimer SetKeyDelay SendMode CoordMode MouseMove
ToolTip MsgBox RegExMatch RegExReplace GetKeyState WinActivate ControlSend
DllCall VarSetStrCapacity StrPtr CallbackCreate ObjBindMethod""".split()

hits, examined = [], 0
for ln_i, ln in enumerate(lines, 1):
    code = ln.split(";")[0]
    m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*(:=|\+=|=)", code)
    if not m:
        continue
    examined += 1
    if m.group(1) in BUILTINS:
        hits.append((ln_i, ln.strip()))
print(f"[1] builtin names used as variables : examined {examined} assignments, {len(hits)} collisions")
for i, l in hits:
    print(f"      BUG line {i}: {l}")

# ------------------------------------------------- 2. called but never defined
CALL = re.compile(r"(?<![A-Za-z0-9_])(_[A-Za-z_][A-Za-z0-9_]*|\w*[A-Za-z]\w*)\((?!=)")
called, undef = Counter(), []
for i, ln in enumerate(lines, 1):
    code = ln.split(";")[0]
    for m in CALL.finditer(code):
        n = m.group(1)
        if n.startswith("_") or n[0].isupper():
            called[n] += 1
skipped = 0
for n in sorted(called):
    if n in D:
        continue
    if n in BUILTINS or n in {"If", "While", "For", "Loop", "Switch", "Return", "Try", "Catch", "Case"}:
        skipped += 1
        continue
    if re.match(r"^(A_|Win|File|Str|Num|Process|Ini|Dir|Obj|Map|Array|RegEx|Image|Pixel|Set|Get)", n):
        skipped += 1          # builtin families, not worth enumerating
        continue
    undef.append((n, called[n]))
print(f"\n[2] functions called but not defined : examined {len(called)} distinct calls, "
      f"{skipped} known-builtin families skipped, {len(undef)} unknown")
for n, c in undef:
    print(f"      RISK {n}() called {c}x, no definition found")

# ------------------------------------------------- 3. duplicate definitions
dups = {k: v for k, v in D.items() if len(v) > 1}
print(f"\n[3] duplicate function definitions   : examined {len(D)} functions, {len(dups)} duplicated")
for k, v in dups.items():
    print(f"      BUG {k} defined at lines {v}")

# ------------------------------------------------- 4. parser/executor mismatch
parser = set(re.findall(r'else if \(d = "([a-z]+)"\)', text))
execu = set(re.findall(r'case "([a-z]+)":', text))
print(f"\n[4] directive coverage               : parser accepts {sorted(parser)}")
print(f"      executor handles {sorted(execu)}")
only_p = parser - execu
only_e = execu - parser
for d in sorted(only_p):
    print(f"      BUG parser accepts '{d}' but the executor has no case - it would do nothing")
for d in sorted(only_e):
    print(f"      note executor has '{d}' with no parser directive")

# ------------------------------------------------- 5. globals never assigned
gdecl = {}
for i, ln in enumerate(lines, 1):
    m = re.match(r"\s*(?:static\s+)?global\s+(.+)$", ln.split(";")[0])
    if m:
        for n in m.group(1).split(","):
            n = n.strip()
            if n:
                gdecl.setdefault(n, []).append(i)
assigned = set()
for ln in lines:
    code = ln.split(";")[0]
    m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*(:=|\+=)", code)
    if m:
        assigned.add(m.group(1))
risky = [(n, v) for n, v in gdecl.items() if n not in assigned and not re.match(r"^A_", n)]
print(f"\n[5] globals declared but never assigned anywhere : examined {len(gdecl)} globals, {len(risky)} risky")
for n, v in sorted(risky):
    guarded = f"IsSet({n})" in text or f"IsSet( {n} )" in text
    print(f"      {'ok  ' if guarded else 'BUG '} {n} (declared at {v[:3]}) - IsSet guard: {guarded}")

# ------------------------------------------------- 6. v1 syntax left in a v2 file
v1 = []
for i, ln in enumerate(lines, 1):
    code = ln.split(";")[0]
    if re.match(r"\s*(Send|Sleep|Click|WinActivate|SetTimer|Gui|MouseMove|PixelGetColor|IniRead|IniWrite)\s*,", code):
        v1.append((i, ln.strip()))
print(f"\n[6] AHK v1 command syntax in a v2 file : examined {len(lines)} lines, {len(v1)} suspected")
for i, l in v1[:10]:
    print(f"      line {i}: {l}")
