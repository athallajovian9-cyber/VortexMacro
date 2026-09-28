#Requires AutoHotkey v2.0
; Does _SigBlank actually tell a black surface from a picture of a game?
; The live test found the macro blaming a route for a capture failure, so the
; detector that separates those two cases must be right.
OUTF := A_ScriptDir . "\blanksig.txt"
Say(s) => FileAppend(s . "`n", OUTF)

pass := 0
fail := 0
Check(ok, what) {
    global pass, fail
    if (ok) {
        pass += 1
        Say("  PASS  " . what)
    } else {
        fail += 1
        Say("  FAIL  " . what)
    }
}

; mirror of the app's implementation
SigBlank(buf, gw := 32, gh := 18) {
    lit := 0
    loop gw * gh {
        off := (A_Index - 1) * 4
        if (NumGet(buf, off, "UChar") + NumGet(buf, off + 1, "UChar")
            + NumGet(buf, off + 2, "UChar") > 24)
            lit += 1
    }
    return (lit < gw * gh * 0.05)
}
Capture(r, gw := 32, gh := 18) {
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem  := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm     := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", gw, "Int", gh, "Ptr")
    hOld    := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
    DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 3)
    DllCall("StretchBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", gw, "Int", gh
        , "Ptr", hdcScreen, "Int", r.x, "Int", r.y, "Int", r.w, "Int", r.h
        , "UInt", 0x00CC0020)
    bi := Buffer(56, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", gw, bi, 4), NumPut("Int", -gh, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 16, bi, 14)
    NumPut("UInt", 0, bi, 16), NumPut("UInt", gw * gh * 4, bi, 20)
    buf := Buffer(gw * gh * 4, 0)
    DllCall("GetDIBits", "Ptr", hdcMem, "Ptr", hbm, "UInt", 0, "UInt", gh
        , "Ptr", buf, "Ptr", bi, "UInt", 0)
    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hOld)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    return buf
}

g := Gui("+AlwaysOnTop -Caption +ToolWindow", "surface")
g.Show("x80 y80 w400 h260")
Sleep(400)

r := { x: 80, y: 80, w: 400, h: 260 }

g.BackColor := "000000"
Sleep(400)
b1 := SigBlank(Capture(r))
Say("pure black surface      -> blank = " . (b1 ? "yes" : "NO"))
Check(b1, "a black surface is reported as blank")

g.BackColor := "010102"
Sleep(400)
b2 := SigBlank(Capture(r))
Say("near-black (1,1,2)      -> blank = " . (b2 ? "yes" : "NO"))
Check(b2, "a near-black surface is still blank (compression noise)")

g.BackColor := "3A6EA5"
Sleep(400)
b3 := SigBlank(Capture(r))
Say("mid blue surface        -> blank = " . (b3 ? "yes" : "NO"))
Check(!b3, "a normal coloured surface is NOT blank")

g.BackColor := "0F1317"
Sleep(400)
b4 := SigBlank(Capture(r))
Say("dark UI surface         -> blank = " . (b4 ? "yes" : "NO"))
Check(!b4, "a very dark but real UI is NOT blank (16,19,23 - the macro's own theme)")

g.Destroy()
Say("")
Say(pass . " passed, " . fail . " failed")
ExitApp(fail ? 1 : 0)
