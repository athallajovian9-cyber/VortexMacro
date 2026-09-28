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

; One StretchBlt of the whole region into a tiny bitmap => a scene signature.
CaptureSig(sx, sy, sw, sh, gw, gh) {
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", gw, "Int", gh, "Ptr")
    hOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
    DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 3)
    DllCall("StretchBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", gw, "Int", gh
        , "Ptr", hdcScreen, "Int", sx, "Int", sy, "Int", sw, "Int", sh
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

; Mean absolute per-channel difference, 0..255.
SigDelta(a, b, gw, gh) {
    total := 0
    loop gw * gh {
        off := (A_Index - 1) * 4
        total += Abs(NumGet(a, off, "UChar") - NumGet(b, off, "UChar"))
        total += Abs(NumGet(a, off + 1, "UChar") - NumGet(b, off + 1, "UChar"))
        total += Abs(NumGet(a, off + 2, "UChar") - NumGet(b, off + 2, "UChar"))
    }
    return total / (gw * gh * 3)
}

GW := 32, GH := 18
RX := 200, RY := 200, RW := 800, RH := 450

; ---- 1. speed ----
t0 := A_TickCount
loop 10
    s := CaptureSig(RX, RY, RW, RH, GW, GH)
dt := A_TickCount - t0
_ok("capture is fast enough", dt < 100, dt . " ms for 10 captures (" . Round(dt / 10, 1) . " ms each)")

; ---- 2. does it capture anything at all? ----
nonBlack := 0
loop GW * GH {
    off := (A_Index - 1) * 4
    if (NumGet(s, off, "UChar") + NumGet(s, off + 1, "UChar") + NumGet(s, off + 2, "UChar") > 12)
        nonBlack += 1
}
_ok("capture returns real pixels (not a black rectangle)", nonBlack > (GW * GH * 0.5),
    nonBlack . "/" . (GW * GH) . " non-black")

; ---- 3. does it DETECT change? ----
g := Gui("+AlwaysOnTop -Caption", "SigProbe")
g.BackColor := "FF0000"
g.Show("x" . (RX + 100) . " y" . (RY + 100) . " w400 h250")
Sleep(500)

base := CaptureSig(RX, RY, RW, RH, GW, GH)
g.BackColor := "00FF00"
Sleep(500)
after := CaptureSig(RX, RY, RW, RH, GW, GH)
d1 := SigDelta(base, after, GW, GH)
_ok("detects a real screen change", d1 > 3, "delta " . Round(d1, 2))

; ---- 4. does it report STILLNESS as still? ----
s1 := CaptureSig(RX, RY, RW, RH, GW, GH)
Sleep(300)
s2 := CaptureSig(RX, RY, RW, RH, GW, GH)
d2 := SigDelta(s1, s2, GW, GH)
_ok("unchanged scene reads as still", d2 < d1 / 2, "still delta " . Round(d2, 2) . " vs changed " . Round(d1, 2))

g.Destroy()
Sleep(400)
s3 := CaptureSig(RX, RY, RW, RH, GW, GH)
d3 := SigDelta(base, s3, GW, GH)
_ok("window removed returns near baseline", d3 < d1 / 2, "delta " . Round(d3, 2))

FileAppend("RESULT: " . (fails = 0 ? "ALL PASS" : fails . " FAILURE(S)") . "`n", "*")
ExitApp(fails = 0 ? 0 : 1)
