import glob, json, re, subprocess
from pathlib import Path
SRC = Path('VortexMacro.ahk'); text = SRC.read_text(encoding='utf-8', errors='replace')
def grab(n):
    m = re.search(rf"^{re.escape(n)}\(", text, re.M)
    s = m.start(); d = 0
    i = text.index("{", m.end())
    for j in range(i, len(text)):
        if text[j] == "{": d += 1
        elif text[j] == "}":
            d -= 1
            if d == 0: return text[s:j+1]
    raise SystemExit(f"unbalanced {n}")
funcs = [grab(n) for n in ("_PathParseText","_InArr","_DigHoldTime","_DigSpeedDefault")]
files = sorted(glob.glob(r"C:\VortexMacro\maps\*.path"))
lst = ",".join('"' + f.replace("\\", "\\\\") + '"' for f in files)
ahk = f'''#Requires AutoHotkey v2.0
#SingleInstance Off
WatchOrder := ["at_node","dig_done","at_water","wash_done"]
Caps := Map("nodeCap",1600,"digCap",2800,"waterCap",1150,"washClicks",15)
DigSpeed := 100
_RouteInt(s, dflt) {{
    try
        return Integer(Trim(s))
    return dflt
}}
{chr(10).join(funcs)}

files := [{lst}]
bad := 0, empty := 0, acts := 0
for f in files {{
    r := _PathParseText(FileRead(f, "UTF-8"))
    bad += r.bad
    acts += r.steps.Length
    if (r.steps.Length = 0)
        empty += 1
    if (r.bad or r.steps.Length = 0)
        FileAppend("PROBLEM  " . f . "  bad=" . r.bad . " steps=" . r.steps.Length . "`n", "*")
}}
FileAppend("VERIFY  files=" . files.Length . "  actions=" . acts . "  badlines=" . bad . "  empty=" . empty . "`n", "*")
ExitApp((bad or empty) ? 1 : 0)
'''
p = Path('_verify_paths.ahk'); p.write_text(ahk, encoding='utf-8')
r = subprocess.run([str(Path('AutoHotkey64.exe').resolve()), '/ErrorStdOut', str(p.resolve())],
                   capture_output=True, text=True, timeout=180)
print(((r.stdout or '') + (r.stderr or '')).strip())
print(f"  exit={r.returncode}")
