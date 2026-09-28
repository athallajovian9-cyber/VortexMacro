#Requires AutoHotkey v2.0
; =====================================================================
;  Does the replay actually press the keys it says it presses?
; =====================================================================
;  Routes store keys as virtual key codes ("vk57"), because a list of
;  friendly names silently missed anything outside it. That makes
;  Send("{vk57 down}") the single most load-bearing line in the replay
;  path, and it had never been verified. If the syntax is wrong, replay
;  is broken for every key.
;
;  This INJECTS REAL INPUT, so it owns the desktop while it runs:
;    * it builds its own window, activates it, and parks the cursor on it,
;      so no keystroke or click can reach whatever the user had focused;
;    * it restores the previous foreground window and cursor at the end.
;  Never point this at the live desktop with the user's own window focused.
; =====================================================================

OUTF := A_ScriptDir . "\replay_vk_result.txt"
W(s) => FileAppend(s . "`n", OUTF)

pass := 0
fail := 0
Check(ok, what) {
    global pass, fail
    if (ok) {
        pass += 1
        W("  PASS  " . what)
    } else {
        fail += 1
        W("  FAIL  " . what)
    }
}

Down(vk) => (DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000) ? 1 : 0

; whatever the user was looking at, so it can be handed back
prevWin := DllCall("GetForegroundWindow", "Ptr")
MouseGetPos(&prevX, &prevY)

; ---- our own sandbox to type into ------------------------------------
g := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "VortexMacro replay test")
g.BackColor := "101418"
g.SetFont("s10 cE8F5E9", "Consolas")
g.AddText(, "Input is being sent to THIS window on purpose.`nIt closes in a few seconds.")
g.Show("x60 y60 w520 h300")
WinActivate("ahk_id " . g.Hwnd)
Sleep(350)

WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " . g.Hwnd)
MouseMove(cx + cw // 2, cy + ch // 2, 0)      ; park the cursor over our window
Sleep(150)

W("replay path   (does sending a virtual-key token press the real key?)")
W("")
W("  sandbox window: " . cx . "," . cy . " " . cw . "x" . ch)
W("")

CASES := [{ tok: "vk57", vk: 0x57, name: "w" }
        , { tok: "vk09", vk: 0x09, name: "Tab" }
        , { tok: "vk78", vk: 0x78, name: "F9" }
        , { tok: "vk0D", vk: 0x0D, name: "Enter" }
        , { tok: "vk20", vk: 0x20, name: "space" }
        , { tok: "LButton", vk: 0x01, name: "mouse-left" }]

; ---- 1. every token must produce a real, visible press AND release ----
for c in CASES {
    Send("{" . c.tok . " down}")
    Sleep(70)
    sawDown := Down(c.vk)
    Send("{" . c.tok . " up}")
    Sleep(70)
    sawUp := !Down(c.vk)
    W("  " . c.name . "  (" . c.tok . ")")
    Check(sawDown, "  press is visible to the OS  (vk 0x" . Format("{:02X}", c.vk) . ")")
    Check(sawUp, "  release clears it - nothing left held")
}

; ---- 2. a held token must stay held for the right duration ------------
W("")
W("  hold timing (the replay waits on this same clock)")
t0 := A_TickCount
Send("{vk57 down}")
while (A_TickCount - t0 < 300)
    Sleep(5)
Send("{vk57 up}")
el := A_TickCount - t0
W("    asked 300 ms, measured " . el . " ms")
Check(Abs(el - 300) <= 30, "  a 300 ms hold lands within 30 ms")

; ---- 3. cursor positioning, the other thing added this session --------
W("")
W("  cursor positioning")
target := { x: cx + cw - 80, y: cy + ch - 60 }
MouseMove(target.x, target.y, 0)
Sleep(40)
MouseGetPos(&nx, &ny)
W("    asked " . target.x . "," . target.y . "   OS reports " . nx . "," . ny)
Check(nx = target.x and ny = target.y, "  MouseMove lands exactly where asked")

relx := nx - cx
rely := ny - cy
W("    stored relative to the window -> " . relx . "," . rely)
Check(relx = cw - 80 and rely = ch - 60, "  relative coords round-trip exactly")

; ---- 4. nothing may be left down when a replay ends -------------------
W("")
W("  cleanup")
stillDown := 0
for c in CASES
    if Down(c.vk)
        stillDown += 1
W("    tokens still held after all tests: " . stillDown)
Check(stillDown = 0, "  no key left held when the replay finished")

; ---- hand the desktop back -------------------------------------------
g.Destroy()
MouseMove(prevX, prevY, 0)
try WinActivate("ahk_id " . prevWin)
Sleep(120)

W("")
W(pass . " passed, " . fail . " failed")
ExitApp(fail ? 1 : 0)
