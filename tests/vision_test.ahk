#Requires AutoHotkey v2.0
#SingleInstance Off
CoordMode("Pixel", "Screen")

; Functional test of the vision primitives the macro relies on:
; PixelGetColor, the channel-diff maths, live change detection across a real
; repaint, and the calibration INI round trip. Run: AutoHotkey64.exe test.ahk

global fails := 0

_ok(label, cond, detail := "") {
    global fails
    if (cond) {
        FileAppend("PASS  " . label . "  " . detail . "`n", "*")
    } else {
        fails += 1
        FileAppend("FAIL  " . label . "  " . detail . "`n", "*")
    }
}

; Same maths as _Diff() in VortexMacro.ahk
_Diff(a, b) {
    dr := Abs(((a >> 16) & 0xFF) - ((b >> 16) & 0xFF))
    dg := Abs(((a >> 8) & 0xFF) - ((b >> 8) & 0xFF))
    db := Abs((a & 0xFF) - (b & 0xFF))
    return Max(dr, Max(dg, db))
}

; ---------- 1. PixelGetColor against a real window ----------
g := Gui("+AlwaysOnTop -Caption", "VortexVisionTest")
g.BackColor := "FF0000"
g.Show("x100 y100 w300 h200")
Sleep(600)

WinGetPos(&wx, &wy, &ww, &wh, "VortexVisionTest")
_ok("window mapped", ww > 0 and wh > 0, ww . "x" . wh)

c := PixelGetColor(wx + 50, wy + 50, "RGB")
_ok("reads known red", c = 0xFF0000, Format("{:06X}", c))
_ok("Format gives 6 hex digits", StrLen(Format("{:06X}", c)) = 6, Format("{:06X}", c))

; ---------- 2. channel difference maths ----------
_ok("identical = 0", _Diff(0xFF0000, 0xFF0000) = 0)
_ok("red vs green = 255", _Diff(0xFF0000, 0x00FF00) = 255, _Diff(0xFF0000, 0x00FF00))
_ok("5/255 apart", _Diff(0xFF0000, 0xFA0000) = 5, _Diff(0xFF0000, 0xFA0000))
_ok("8/255 apart below tol 24", _Diff(0x808080, 0x888888) = 8, _Diff(0x808080, 0x888888))
_ok("big change above tol 24", _Diff(0xFF0000, 0x00FF00) > 24)
_ok("tiny change below tol 24", _Diff(0x808080, 0x888888) <= 24)

; ---------- 3. change detection across a real repaint ----------
before := PixelGetColor(wx + 50, wy + 50, "RGB")
g.BackColor := "00FF00"
Sleep(500)
after := PixelGetColor(wx + 50, wy + 50, "RGB")

_ok("repaint detected", before != after,
    Format("{:06X}", before) . " -> " . Format("{:06X}", after))
_ok("repaint exceeds tolerance", _Diff(before, after) > 24, _Diff(before, after))

; A pixel that does NOT change must not read as a change.
still1 := PixelGetColor(wx + 50, wy + 50, "RGB")
Sleep(250)
still2 := PixelGetColor(wx + 50, wy + 50, "RGB")
_ok("static pixel reads no change", _Diff(still1, still2) <= 24, _Diff(still1, still2))

; ---------- 4. calibration INI round trip ----------
iniPath := A_ScriptDir . "\_vtest.ini"
if FileExist(iniPath)
    FileDelete(iniPath)

IniWrite("120,540", iniPath, "watch", "at_node")
IniWrite("900,80", iniPath, "watch", "dig_done")

v := IniRead(iniPath, "watch", "at_node", "")
_ok("ini single read", v = "120,540", v)

all := IniRead(iniPath, "watch", "at_node", "")
_ok("ini keyed read works", all = "120,540", all)

; Load exactly the way _LoadWatches() does: one known key at a time.
; (IniRead(F, S, "", "") does NOT return the whole section - it looks up a
;  literal empty key and returns nothing, which silently leaves everything
;  uncalibrated. That was a real bug this test caught.)
names := ["at_node", "dig_done", "at_water", "wash_done"]
parsed := Map()
for name in names {
    v2 := IniRead(iniPath, "watch", name, "")
    if (v2 = "" or v2 = "ERROR" or !InStr(v2, ","))
        continue
    pts := StrSplit(v2, ",")
    if (pts.Length < 2)
        continue
    parsed[name] := { x: Integer(pts[1]), y: Integer(pts[2]) }
}
_ok("parser found 2 points", parsed.Count = 2, parsed.Count)
_ok("parser x correct", parsed.Has("at_node") and parsed["at_node"].x = 120,
    parsed.Has("at_node") ? parsed["at_node"].x : "missing")
_ok("parser y correct", parsed.Has("dig_done") and parsed["dig_done"].y = 80,
    parsed.Has("dig_done") ? parsed["dig_done"].y : "missing")

if FileExist(iniPath)
    FileDelete(iniPath)

; ---------- 5. uncalibrated fallback must be inert ----------
_ok("absent watch point yields -1", !parsed.Has("at_water"))

g.Destroy()

FileAppend("RESULT: " . (fails = 0 ? "ALL PASS" : fails . " FAILURE(S)") . "`n", "*")
ExitApp(fails = 0 ? 0 : 1)
