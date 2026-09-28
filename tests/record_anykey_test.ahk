#Requires AutoHotkey v2.0
; =====================================================================
;  Does the recorder capture keys outside the old hard-coded list?
; =====================================================================
;  The first version of the recorder watched a hand-written list of 17
;  key names (w a s d q e f r space shift LButton RButton 1-5) and
;  silently recorded NOTHING for any key outside it. That is
;  indistinguishable from a broken recorder when the key it misses
;  happens to be the one you press, which is the worst possible way for
;  a recorder to fail.
;
;  Keys are now recorded by virtual key code, so nothing can fall
;  outside the sweep. This checks that against real key state, using
;  keys the old list did NOT contain, plus one it did as a control.
;
;  The primitives below mirror submacro\VortexMacro.ahk.
; =====================================================================

OUTF := A_ScriptDir . "\record_anykey_result.txt"
W(s) => FileAppend(s . "`n", OUTF)

pass := 0
fail := 0

VK_MOUSE := Map(0x01, "LButton", 0x02, "RButton", 0x04, "MButton"
              , 0x05, "XButton1", 0x06, "XButton2")

_VkDown(vk) => (DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000) ? 1 : 0

_VkToken(vk) {
    global VK_MOUSE
    return VK_MOUSE.Has(vk) ? VK_MOUSE[vk] : "vk" . Format("{:02X}", vk)
}

_VkName(vk) {
    static cache := Map()
    if cache.Has(vk)
        return cache[vk]
    n := _VkToken(vk)
    if (SubStr(n, 1, 2) = "vk") {
        try n := GetKeyName(n)
        if (n = "")
            n := "vk" . Format("{:02X}", vk)
    }
    cache[vk] := n
    return n
}

_TokenName(tok) {
    if (tok = "m")
        return "mouse-move"
    if (SubStr(tok, 1, 2) = "vk")
        return _VkName(("0x" . SubStr(tok, 3)) + 0)
    return tok
}

; ---- the recorder, same shape as the app's _RoutePoll -----------------
RouteRec := []
RouteDown := Map()
RouteClient := { x: 100, y: 100 }      ; stand-in for the game window origin
Recording := true

_RouteEvent(vk, dir) {
    global RouteRec, RouteClient
    MouseGetPos(&mx, &my)
    return { t: A_TickCount, k: _VkToken(vk), d: dir
           , x: mx - RouteClient.x, y: my - RouteClient.y }
}

Poll() {
    global RouteRec, RouteDown, Recording
    if (!Recording)
        return
    vk := 1
    while (vk <= 254) {
        s := _VkDown(vk)
        if (s != RouteDown.Get(vk, 0)) {
            RouteDown[vk] := s
            RouteRec.Push(_RouteEvent(vk, s ? "down" : "up"))
        }
        vk += 1
    }
}

W("recorder key coverage   (VK sweep against real key state)")
W("")

SetTimer(Poll, 10)
Sleep(120)

TARGETS := [{ name: "z",     was: false }, { name: "Tab",   was: false }
          , { name: "F9",    was: false }, { name: "Enter", was: false }
          , { name: "w",     was: true  }]
for t in TARGETS {
    Send("{" . t.name . " down}")
    Sleep(45)
    Send("{" . t.name . " up}")
    Sleep(45)
}
Send("{LButton down}")
Sleep(45)
Send("{LButton up}")
Sleep(45)

Recording := false
SetTimer(Poll, 0)
Sleep(60)

got := Map()
withPos := 0
for e in RouteRec {
    got[e.k] := true
    if HasProp(e, "x")
        withPos += 1
}

W("  events captured: " . RouteRec.Length
    . "   every event carries a cursor position: "
    . (withPos = RouteRec.Length ? "yes" : "NO"))
W("")

for t in TARGETS {
    tok := _VkToken(GetKeyVK(t.name))
    ok := got.Has(tok)
    tag := t.was ? "  (was in the old list)" : "  (NOT in the old list)"
    W("  " . (ok ? "PASS" : "FAIL") . "  " . Format("{:-7}", t.name)
        . " -> " . Format("{:-9}", tok) . " reads as '"
        . _TokenName(tok) . "'" . tag)
    if ok
        pass += 1
    else
        fail += 1
}

okBtn := got.Has("LButton")
W("  " . (okBtn ? "PASS" : "FAIL") . "  LButton -> LButton    (mouse button)")
if okBtn
    pass += 1
else
    fail += 1

W("")
W("  distinct tokens seen: " . got.Count)
W("")
W(pass . " passed, " . fail . " failed")
ExitApp(fail ? 1 : 0)
