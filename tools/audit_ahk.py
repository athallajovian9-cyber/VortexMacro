"""Static audit for the AHK v2 macro.

Finds the bug classes that are invisible at a glance and only show up at
runtime, or not at all:

  1. calls to functions that are never defined   -> runtime crash
  2. functions defined but never referenced      -> dead code, silent feature loss
  3. duplicate function definitions              -> the later one silently wins
  4. assignments to a global without `global`    -> "local variable has not been
                                                    assigned a value" at runtime
  5. hotkeys bound to an undefined function      -> key silently does nothing

Comments and string literals are stripped first, because a name inside either is
not a call or a definition.
"""
import re
import sys
from collections import defaultdict

# AHK v2 built-ins the macro legitimately calls. Anything called that is in
# neither this set nor the file's own definitions is a likely runtime crash.
BUILTINS = {
    # core / output
    "FileAppend", "FileOpen", "FileDelete", "FileExist", "FileRead", "FileCopy",
    "DirCreate", "DirExist", "DirDelete", "IniWrite", "IniRead", "IniDelete",
    "MsgBox", "InputBox", "ToolTip", "TrayTip", "Sleep", "ExitApp", "Reload",
    "Run", "RunWait", "ProcessClose", "ProcessExist", "ProcessGetName",
    "ProcessGetPID", "ProcessSetPriority", "ControlSend", "ControlClick",
    "ControlGetText", "ControlGetPos", "ControlSetText", "ControlFocus",
    "ControlGetFocus", "ControlMove", "ControlGet", "Control",
    # windows / input
    "WinExist", "WinActivate", "WinActive", "WinGetTitle", "WinGetClass",
    "WinGetPos", "WinGetClientPos", "WinGetList", "WinGetControlsHwnd",
    "WinGetControls", "WinGetPID", "WinGetProcessName", "WinMove", "WinClose",
    "WinKill", "WinMinimize", "WinRestore", "WinSetAlwaysOnTop", "WinSetTitle",
    "WinWait", "WinWaitActive", "WinWaitClose", "MouseGetPos", "MouseMove",
    "MouseClick", "MouseClickDrag", "Click", "Send", "SendInput", "SendEvent",
    "SendPlay", "SendText", "SendMode", "SetKeyDelay", "SetMouseDelay",
    "SetWinDelay", "SetControlDelay", "SetDefaultMouseSpeed", "GetKeyState",
    "GetKeyName", "GetKeyVK", "GetKeySC", "KeyWait", "BlockInput", "CoordMode",
    "Hotkey", "HotIf", "HotIfWinActive", "HotIfWinExist", "A_ThisHotkey",
    # strings / numbers / collections
    "StrLen", "SubStr", "InStr", "StrReplace", "StrSplit", "StrUpper",
    "StrLower", "StrTrim", "StrPut", "StrGet", "Trim", "LTrim", "RTrim",
    "Format", "FormatTime", "Round", "Floor", "Ceil", "Abs", "Mod", "Max",
    "Min", "Sqrt", "Sin", "Cos", "Tan", "Log", "Ln", "Exp", "Random", "Sort",
    "Type", "IsNumber", "IsInteger", "IsFloat", "IsObject", "IsSet", "Chr",
    "Ord", "String", "Integer", "Float", "Number", "Map", "Array", "Buffer",
    "ObjBindMethod", "ObjHasOwnProp", "ObjOwnPropCount", "ObjGetCapacity",
    "VerCompare", "StrPtr", "VarSetStrCapacity", "DllCall", "NumPut", "NumGet",
    "CallbackCreate", "CallbackFree", "ComObjGet", "ComObject", "ComCall",
    "ComValue", "ComObjActive", "ComObjCreate", "ComObjQuery", "ComObjType",
    "ComObjValue", "Trim", "IsAlpha", "IsAlnum", "IsSpace", "IsDigit",
    # gui
    "Gui", "ListView", "TreeView", "Menu", "MenuBar", "StatusBar", "ImageList",
    "IL_Create", "IL_Add", "IL_Destroy", "OnMessage", "OnExit", "OnError",
    "SetTimer", "SetTitleMatchMode", "SetStoreCapsLockMode", "A_Clipboard",
    "ClipWait", "Persistent", "Suspend", "Pause", "Thread", "Critical",
    "DetectHiddenWindows", "DetectHiddenText", "ListLines", "KeyHistory",
    "OutputDebug", "InstallKeybdHook", "InstallMouseHook", "Edit", "EditGetLineCount",
    "PixelGetColor", "PixelSearch", "ImageSearch", "SendMessage", "PostMessage",
    "SplitPath", "TraySetIcon", "WinSetTransColor", "WinSetTransparent",
    "MenuSetIcon", "GetKeyState", "SetCapsLockState", "SetNumLockState",
    "RegExMatch", "RegExReplace", "StrCompare", "StrPtr", "Trim", "WinSetTitle",
    "ObjHasOwnProp", "ObjBindMethod", "IsLabel", "WinGetCount", "WinGetID",
    "WinGetIDLast", "WinGetMinMax", "WinGetTransparent", "WinGetTransColor",
    "MenuBar", "Menu", "StatusBarGetText", "ImageList", "GuiCtrlFromHwnd",
    "GuiFromHwnd", "DriveGetType", "FileGetSize", "FileGetTime", "FileGetAttrib",
    "FileGetVersion", "FileSetTime", "FileSetAttrib", "FileCreateShortcut",
    "DirCopy", "DirMove", "FileMove", "EnvGet", "EnvSet", "A_Args",
}

# language keywords that are followed by "(" and must not be treated as calls
KEYWORDS = {
    "if", "else", "while", "for", "loop", "return", "switch", "case", "break",
    "continue", "try", "catch", "throw", "global", "local", "static", "until",
    "in", "not", "and", "or", "is", "new", "get", "set", "class", "extends",
}

CALL_RE = re.compile(r"(?<![\w.])([A-Za-z_][A-Za-z0-9_]*)\s*\(")
# [^\S\n]* rather than \s*: \s matches newlines, which lets the pattern start on
# the blank line ABOVE a definition and report its line number one too low.
DEF_RE = re.compile(r"^[^\S\n]*([A-Za-z_][A-Za-z0-9_]*)[^\S\n]*\(([^)]*)\)[^\S\n]*\{", re.M)
HOTKEY_RE = re.compile(r"^\s*([^\s:]+(?::[^\s:]+)*)::\s*(.*)$", re.M)


def strip_noise(src):
    """Remove comments and string literals so names inside them are ignored."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # line comment
        if c == ";" and (i == 0 or src[i - 1] != "`"):
            while i < n and src[i] != "\n":
                i += 1
            continue
        # block comment
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        # string literal (double quotes, ` escapes inside)
        if c == '"':
            i += 1
            while i < n:
                if src[i] == "`":
                    i += 2
                    continue
                if src[i] == '"':
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out)


def audit(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    clean = strip_noise(src)
    lines = clean.split("\n")

    defs = defaultdict(list)
    for m in DEF_RE.finditer(clean):
        name = m.group(1)
        line = clean[:m.start(1)].count("\n") + 1
        if name.lower() in KEYWORDS:
            continue
        defs[name].append(line)

    calls = defaultdict(list)
    for i, line in enumerate(lines, 1):
        for m in CALL_RE.finditer(line):
            name = m.group(1)
            if name.lower() in KEYWORDS:
                continue
            # skip a definition line's own signature
            if DEF_RE.match(line) and DEF_RE.match(line).group(1) == name:
                continue
            calls[name].append(i)

    problems = 0

    print("=" * 68)
    print(" 1. CALLS TO UNDEFINED FUNCTIONS  (runtime crash)")
    print("=" * 68)
    unknown = {n: v for n, v in calls.items()
               if n not in defs and n not in BUILTINS}
    if not unknown:
        print("  none")
    for n, ls in sorted(unknown.items()):
        problems += 1
        print("  %-28s called at line(s) %s" % (n, ", ".join(map(str, ls))))

    print()
    print("=" * 68)
    print(" 2. DEFINED BUT NEVER REFERENCED  (dead code)")
    print("=" * 68)
    dead = 0
    for name, dls in sorted(defs.items()):
        uses = 0
        for i, line in enumerate(lines, 1):
            if i in dls:
                continue
            uses += len(re.findall(r"\b%s\b" % re.escape(name), line))
        if uses == 0:
            dead += 1
            problems += 1
            print("  %-28s defined at line %s, never used" % (name, dls[0]))
    if not dead:
        print("  none")

    print()
    print("=" * 68)
    print(" 3. DUPLICATE DEFINITIONS  (the later one silently wins)")
    print("=" * 68)
    dupes = {n: ls for n, ls in defs.items() if len(ls) > 1}
    if not dupes:
        print("  none")
    for n, ls in sorted(dupes.items()):
        problems += 1
        print("  %-28s defined at lines %s" % (n, ", ".join(map(str, ls))))

    print()
    print("=" * 68)
    print(" 4. GLOBALS ASSIGNED WITHOUT A DECLARATION  (runtime error)")
    print("=" * 68)
    # top-level assignments create the globals
    globals_ = set()
    depth = 0
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if depth == 0:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?::=|\+=|-=|\*=|/=)", stripped)
            if m:
                globals_.add(m.group(1))
        depth += line.count("{") - line.count("}")

    # each function scope: which globals does it assign, and does it declare them
    flagged = []
    cur = None
    cur_decl = set()
    cur_assign = set()
    for i, line in enumerate(lines, 1):
        m = DEF_RE.match(line)
        if m and m.group(1).lower() not in KEYWORDS:
            cur = m.group(1)
            cur_decl = set()
            cur_assign = set()
            depth = line.count("{") - line.count("}")
            continue
        if cur is None:
            continue
        depth += line.count("{") - line.count("}")
        gm = re.match(r"^\s*global\s+(.+)$", line)
        if gm:
            for part in gm.group(1).split(","):
                part = part.strip()
                if part:
                    cur_decl.add(part)
        am = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::=|\+=|-=|\*=|/=)", line)
        if am:
            cur_assign.add(am.group(1))
        if depth <= 0 and i > 1:
            for name in sorted(cur_assign & globals_ - cur_decl):
                flagged.append((cur, name, i))
            cur = None

    if not flagged:
        print("  none")
    for fn, name, line in flagged:
        problems += 1
        print("  %-24s assigns global '%s' without declaring it" % (fn, name))

    print()
    print("=" * 68)
    print(" 5. HOTKEYS BOUND TO UNDEFINED FUNCTIONS  (key does nothing)")
    print("=" * 68)
    bad = 0
    for m in HOTKEY_RE.finditer(clean):
        key, body = m.group(1), m.group(2).strip()
        if not body or body.startswith("{") or body.startswith(";"):
            continue
        fm = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", body)
        if fm and fm.group(1) not in defs and fm.group(1) not in BUILTINS:
            bad += 1
            problems += 1
            print("  %-10s -> %s   (not defined)" % (key, fm.group(1)))
    if not bad:
        print("  none")

    print()
    print("=" * 68)
    print("functions defined: %d   distinct names called: %d" % (len(defs), len(calls)))
    print("problems found: %d" % problems)
    print("=" * 68)
    return problems


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else \
        r"C:\VortexMacro\submacro\VortexMacro.ahk"
    sys.exit(1 if audit(path) else 0)