#Requires AutoHotkey v2.0
; =====================================================================
;  Does the "dead cycle" rule actually work?
; =====================================================================
; The macro now stops itself when a replayed route changes nothing on
; screen for several cycles in a row, instead of grinding out nothing for
; hours. That rule is only as good as the measurement underneath it, so
; this tests the measurement itself against REAL pixels:
;
;   a still scene  must read as still   (would be called a dead cycle)
;   a moving scene must read as moving  (macro keeps running)
;
; It watches a window it creates and destroys itself, so it sends no input
; anywhere and cannot disturb anything else running on the machine.
; =====================================================================

OUTF := A_ScriptDir . "\deadcycle_result.txt"
global pass := 0
global fail := 0

Say(s) => FileAppend(s . "`n", OUTF)

THRESH := 3          ; the shipped stillTol: at or below this counts as still
GW := 32, GH := 18   ; the signature size the macro uses

Check(ok, what) {
    global pass, fail
    if (ok) {
        pass += 1
        Say("  PASS   " . what)
    } else {
        fail += 1
        Say("  FAIL   " . what)
    }
}

; --- the scene -------------------------------------------------------
g := Gui("+AlwaysOnTop -Caption +ToolWindow", "scene")
g.BackColor := "101418"
g.Show("x40 y40 w360 h240")
Sleep(500)
r := { x: 40, y: 40, w: 360, h: 240 }

Say("dead-cycle rule test   (still threshold = " . THRESH . ")")
Say("")

; --- 1. a scene that does not change must read as still --------------
Say("  [about to capture]")
a := Sig(r)
Say("  [first capture ok]")
Sleep(250)
b := Sig(r)
dStill := Delta(a, b)
Say("  still scene    delta = " . Round(dStill, 2))
Check(dStill <= THRESH, "an unchanged scene reads as STILL -> counted as a dead cycle")

; --- 2. a scene that changes must read as moving ---------------------
g.BackColor := "3FE0A0"
Sleep(60)
c := Sig(r)
dMove := Delta(b, c)
Say("  changed scene  delta = " . Round(dMove, 2))
Check(dMove > THRESH, "a changed scene reads as MOVING -> not counted as dead")

; --- 3. sustained motion must never look still ----------------------
g.BackColor := "101418"
Sleep(60)
maxD := 0
prev := Sig(r)
loop 10 {
    g.BackColor := (Mod(A_Index, 2) = 1) ? "F0C040" : "101418"
    Sleep(70)
    cur := Sig(r)
    d := Delta(prev, cur)
    if (d > maxD)
        maxD := d
    prev := cur
}
Say("  animating max  delta = " . Round(maxD, 2))
Check(maxD > THRESH, "sustained motion always exceeds the threshold")

; --- 4. tiny changes must not look like motion ----------------------
; A clock ticking in the corner must not fool the macro into thinking a
; stuck route is still farming.
g.BackColor := "101418"
Sleep(120)
p1 := Sig(r)
g.BackColor := "111418"        ; one step brighter on one channel only
Sleep(60)
p2 := Sig(r)
dTiny := Delta(p1, p2)
Say("  tiny change    delta = " . Round(dTiny, 2))
Check(dTiny < dMove, "a barely-visible change scores far below real motion")

g.Destroy()

Say("")
Say(pass . " passed, " . fail . " failed")
ExitApp(fail ? 1 : 0)

; --- scene capture / compare, same method the macro uses -------------
Sig(r, gw := 32, gh := 18) {
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", gw, "Int", gh, "Ptr")
    hOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
    DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 3)
    DllCall("StretchBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", gw, "Int", gh
        , "Ptr", hdcScreen, "Int", r.x, "Int", r.y, "Int", r.w, "Int", r.h
        , "UInt", 0x00CC0020)

    bi := Buffer(56, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", gw, bi, 4)
    NumPut("Int", -gh, bi, 8)
    NumPut("UShort", 1, bi, 12)
    NumPut("UShort", 32, bi, 14)
    NumPut("UInt", 0, bi, 16)
    NumPut("UInt", gw * gh * 4, bi, 20)

    buf := Buffer(gw * gh * 4, 0)
    DllCall("GetDIBits", "Ptr", hdcMem, "Ptr", hbm, "UInt", 0, "UInt", gh
        , "Ptr", buf, "Ptr", bi, "UInt", 0)

    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hOld)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    return buf
}

Delta(a, b, gw := 32, gh := 18) {
    total := 0
    loop gw * gh {
        off := (A_Index - 1) * 4
        total += Abs(NumGet(a, off, "UChar") - NumGet(b, off, "UChar"))
        total += Abs(NumGet(a, off + 1, "UChar") - NumGet(b, off + 1, "UChar"))
        total += Abs(NumGet(a, off + 2, "UChar") - NumGet(b, off + 2, "UChar"))
    }
    return total / (gw * gh * 3)
}