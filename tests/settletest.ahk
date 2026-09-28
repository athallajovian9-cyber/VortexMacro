#Requires AutoHotkey v2.0
CoordMode("Pixel", "Screen")
global fails := 0
_ok(l, c, d := "") {
    global fails
    if (c)
        FileAppend("PASS  " . l . "  " . d . "`n", "*")
    else {
        fails += 1
        FileAppend("FAIL  " . l . "  " . d . "`n", "*")
    }
}

CaptureSig(sx, sy, sw, sh, gw, gh) {
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", gw, "Int", gh, "Ptr")
    hOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
    DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 3)
    DllCall("StretchBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", gw, "Int", gh
        , "Ptr", hdcScreen, "Int", sx, "Int", sy, "Int", sw, "Int", sh, "UInt", 0x00CC0020)
    bi := Buffer(56, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", gw, bi, 4), NumPut("Int", -gh, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
    NumPut("UInt", 0, bi, 16), NumPut("UInt", gw * gh * 4, bi, 20)
    buf := Buffer(gw * gh * 4, 0)
    DllCall("GetDIBits", "Ptr", hdcMem, "Ptr", hbm, "UInt", 0, "UInt", gh
        , "Ptr", buf, "Ptr", bi, "UInt", 0)
    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hOld)
    DllCall("DeleteObject", "Ptr", hbm), DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    return buf
}
SigDelta(a, b, gw, gh) {
    t := 0
    loop gw * gh {
        o := (A_Index - 1) * 4
        t += Abs(NumGet(a, o, "UChar") - NumGet(b, o, "UChar"))
        t += Abs(NumGet(a, o + 1, "UChar") - NumGet(b, o + 1, "UChar"))
        t += Abs(NumGet(a, o + 2, "UChar") - NumGet(b, o + 2, "UChar"))
    }
    return t / (gw * gh * 3)
}

GW := 32, GH := 18
RX := 150, RY := 150, RW := 600, RH := 400

g := Gui("+AlwaysOnTop -Caption", "SettleProbe")
g.BackColor := "202020"
g.Show("x" . RX . " y" . RY . " w" . RW . " h" . RH)
Sleep(500)

; A scene that CHANGES for 1.5 s and is then perfectly still. The settle loop
; must refuse to stop while it is moving, then stop promptly once it is quiet.
animating := true
TickAnim() {
    global animating, g
    if (animating)
        g.BackColor := Format("{:06X}", Random(0x303030, 0xFFFFFF))
}
StopAnim() {
    global animating
    animating := false
}
SetTimer(TickAnim, 120)
SetTimer(StopAnim, -1500)

stillTol := 2.5, stillPolls := 3, pollMs := 140, floorMs := 500, capMs := 8000

prev := CaptureSig(RX, RY, RW, RH, GW, GH)
t0 := A_TickCount
stillRun := 0
settled := false
settleAt := 0
mx := 0

while (A_TickCount - t0 < capMs) {
    Sleep(pollMs)
    cur := CaptureSig(RX, RY, RW, RH, GW, GH)
    d := SigDelta(prev, cur, GW, GH)
    prev := cur
    mx := Max(mx, d)
    if (d <= stillTol)
        stillRun += 1
    else
        stillRun := 0
    el := A_TickCount - t0
    if (stillRun >= stillPolls and el >= floorMs) {
        settled := true
        settleAt := el
        break
    }
}
animating := false
SetTimer(TickAnim, 0)
total := A_TickCount - t0

_ok("saw real motion while animating", mx > 5, "max delta " . Round(mx, 2))
_ok("did NOT settle during the motion", settleAt > 1400, "settled at " . settleAt . " ms (motion ran 1500 ms)")
_ok("did settle", settled = true, settled)
_ok("settled promptly after motion stopped", settleAt > 1400 and settleAt < 3200, settleAt . " ms")
_ok("finished well before the ceiling", total < capMs - 2000, total . " ms vs cap " . capMs)

g.Destroy()
FileAppend("RESULT: " . (fails = 0 ? "ALL PASS" : fails . " FAILURE(S)") . "`n", "*")
ExitApp(fails = 0 ? 0 : 1)
