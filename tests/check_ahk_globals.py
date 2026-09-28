"""Find AHK v2 functions that assign a global without declaring it.

AHK v2 rule: a function may READ a global freely, but an assignment to a name
makes that name LOCAL for the whole function. So `if !WaitHeld` followed later
by `WaitHeld := true` inside the same function fails at runtime with
"This local variable has not been assigned a value" -- and the error points at
the *read*, which is not where the mistake is.

This checks exactly that: for every function scope, an identifier that is
ASSIGNED in the scope, is a known top-level global, and is not listed in the
scope's `global` declaration.
"""
import re
import sys

PATH = r"C:\VortexMacro\submacro\VortexMacro.ahk"

text = open(PATH, encoding="utf-8", errors="replace").read()
lines = text.splitlines()

# --- top-level globals: assignments at column 0 in the auto-execute section ---
top_globals = set()
for ln in lines:
    m = re.match(r'^([A-Za-z_]\w*)\s*(?::=|\+=|-=|\*=|/=)', ln)
    if m:
        top_globals.add(m.group(1))

ASSIGN = re.compile(r'(?<![\w.])([A-Za-z_]\w*)\s*(?::=|\+=|-=|\*=|/=)')
GLOBAL = re.compile(r'^\s*global\s+(.+?)\s*(?:;.*)?$')
# a function definition or a hotkey block, both of which own their own scope
SCOPE = re.compile(r'^([A-Za-z_]\w*\s*\([^)]*\)\s*\{|F\d+::\s*\{)')

scopes = []
cur = None
for i, ln in enumerate(lines, 1):
    if SCOPE.match(ln):
        cur = {"line": i, "sig": ln.strip(), "declared": set(), "assigned": {}}
        scopes.append(cur)
        continue
    if cur is None:
        continue
    if ln.startswith("}"):                      # end of scope
        cur = None
        continue
    if ln.lstrip().startswith(";"):
        continue
    g = GLOBAL.match(ln)
    if g and not cur["declared"]:
        for part in g.group(1).split(","):
            part = part.strip()
            if part:
                cur["declared"].add(part)
        continue
    for m in ASSIGN.finditer(ln):
        cur["assigned"].setdefault(m.group(1), i)

# names that are locals by convention / AHK builtins worth ignoring
IGNORE = {
    "A_Index", "A_TickCount", "A_ScriptDir", "A_ScreenWidth", "A_ScreenHeight",
    "A_LoopFileName", "A_ScriptName", "A_WorkingDir", "A_Now",
}

problems = []
for s in scopes:
    for name, line in s["assigned"].items():
        if name in s["declared"] or name in IGNORE:
            continue
        if name in top_globals:
            problems.append((s["line"], s["sig"], name, line))

print(f"top-level globals found: {len(top_globals)}")
print(f"scopes scanned: {len(scopes)}")
print()
if not problems:
    print("OK - no undeclared global assignments")
else:
    print(f"{len(problems)} PROBLEM(S): assign a global without declaring it")
    for scope_line, sig, name, line in problems:
        print(f"  line {line:>5}: '{name}' assigned, but not in the global list of")
        print(f"                scope at line {scope_line}: {sig}")
        print(f"                -> reading '{name}' earlier in that scope will throw")
sys.exit(1 if problems else 0)
