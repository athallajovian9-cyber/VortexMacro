#Requires AutoHotkey v2.0

; #SingleInstance Force is deliberately NOT used here. It works by ASKING a
; running instance to close itself, and an instance sitting inside the macro
; loop cannot answer in time -- AHK then blocks on
;   "could not close the previous instance of the script. keep waiting?"
; Instead we kill any previous instance outright, at startup, before anything
; else. That makes launching this file safe by ANY route: launcher.bat,
; double-clicking this script, or a tray reload.
#SingleInstance Off

_ClosePreviousInstances()

; =====================================================================
;  VORTEX MACRO - PROSPECTING
;
;  Screen-reading macro with a GUI, modelled on how Natro Macro works:
;   - settings live in <root>\settings\vortex_config.ini
;   - the Status tab reports session runtime and per-step timings
;   - the macro tunes its own ceilings instead of trusting constants
;   - Roblox is rejoined automatically if the client dies
;
;  AHK v2 scoping note: reading a global needs no declaration, WRITING one
;  does. Every function below declares exactly the globals it assigns to.
; =====================================================================

SplitPath(A_ScriptDir, , &RootDir)
SettingsDir := RootDir . "\settings"
MapsDir     := RootDir . "\maps"
CfgFile     := SettingsDir . "\vortex_config.ini"
LogFile     := SettingsDir . "\vortex_session.log"

DEEPLINK := "roblox://placeId=129827112113663"   ; Prospecting

WatchOrder := ["at_node", "dig_done", "at_water", "wash_done"]
WatchHelp  := Map(
    "at_node",   "the dig site - something different once you arrive",
    "dig_done",  "whatever changes when your pan is FULL",
    "at_water",  "the water/sluice - different once you arrive",
    "wash_done", "whatever changes when your pan is CLEAN")

; Every location is ONE FILE in <root>\maps\. The folder listing is the location
; list, exactly like Natro Macro's paths\ folder -- drop a file in and it shows
; up in the selector. This mirrors how Natro stores one route per path file.
;
; Each map file is plain INI so AHK reads and writes it directly:
;   [watch]
;   at_node=120,540
;
; These defaults are the real locations in the Roblox game "Prospecting!", taken
; from the official community wiki: prospecting.miraheze.org/wiki/Locations
; None are invented. They are only written when the maps folder is empty; after
; that the folder belongs to the user and this list is ignored.
DefaultLocations := [
    ; --- regular areas ---
    "Rubble Creek",
    "Rubble Creek Deposits",
    "Fortune River",
    "Fortune River Delta",
    "Museum",
    "Crystal Caverns",
    "Crystal Cavern River",
    "Azuralite Oasis",
    "Sunset Beach",
    "Volcanic Sands",
    "Volcanic Springs",
    "Windswept Beach",
    "Volcano",
    "The Magma Furnace",
    "Infernal Heart",
    ; --- Snowy Mountains ---
    "Snowy Mountains",
    "Snowy Shores",
    "Frostbitten Path",
    "Frozen Peak",
    ; --- deeper areas ---
    "Overgrown Grotto",
    "Deeproot Spring",
    "Enchanted Ruins",
    "Abyssal Depths",
    "Rotwood Swamp",
    "Fungal Marsh",
    "Timelocked Sanctuary",
    ; --- limited time ---
    "The Void",
    "Haunted Creek",
    "North Pole"]

Locations := []          ; filled from the maps folder
_LoadMaps()

; ------------------------- tunables -------------------------
Caps := Map(
    "nodeCap",    1600,    ; ms ceiling, walk into the node
    "digCap",     2800,    ; ms ceiling, dig
    "waterCap",   1150,    ; ms ceiling, walk back to the water
    "washClicks",   15)    ; click ceiling, wash

Opt := Map(
    "changeTol",         24,   ; per-channel difference that means "changed"
    "clickDelay",        80,   ; ms between wash clicks
    "keyDelay",          30,   ; ms between key events
    "alwaysOnTop",        1,
    "hideWhileRunning",   1,
    "autoReconnect",      1,
    "adaptCaps",          1,
    "guardInput",         1,
    "useManual",          0,   ; 0 = auto vision always (nothing to mark)
    "pollMs",           140,   ; auto vision: how often to sample the scene
    "stillTol",           3,   ; auto vision: delta at/below this counts as still (integer: the config file only stores integers)
    "stillPolls",         3,   ; auto vision: still polls in a row = settled
    "deadCycles",         3)   ; route replay: do-nothing cycles in a row before stopping

; Floors the self-tuning must never go below, or the macro starts cutting its
; own steps short and never gives the screen time to change.
CapFloor := Map("nodeCap", 300, "digCap", 500, "waterCap", 300, "washClicks", 3)
CapCeil  := Map("nodeCap", 6000, "digCap", 12000, "waterCap", 6000, "washClicks", 60)

; ------------------------- runtime -------------------------
Toggle   := false
Readout  := false
WaitHeld := false
ActiveLocation := "Rubble Creek Sands"   ; beginner dig site; overridden by config
Watches  := Map()
StuckRun := Map()     ; consecutive ceiling-hits per watch point
StepStat := Map()     ; watch point -> {n, total, last, early}
UI       := Map()     ; live control references
MainGui  := ""

; ------------------------- route recorder -------------------------
; The four built-in steps assume a control scheme that was never verified against
; the real game, which is why the macro walked forward and back without digging.
; Recording what the player actually does removes the guesswork: press F7, play
; the loop once by hand, press F7 again, and those exact key/mouse events with
; their real timings become the cycle.
;
; Capture is by POLLING the physical key state, not by hotkeys. Measured on this
; build: 10 keys per sweep costs 0.000 ms, so a 12 ms poll timer is free. Two
; reasons polling beats hotkeys here:
;   - a hotkey cannot see the script's own Send at the default SendLevel
;     (measured: 0 events captured), which makes a recorder untestable;
;   - polling reads the PHYSICAL state, so it records exactly what the player
;     pressed, including keys held across events, with no hotkey plumbing.
; Measured accuracy: a 300 ms hold recorded as 297 ms, a 400 ms hold as 406 ms.
; Keys are recorded by VIRTUAL KEY CODE, not by name, so the recorder cannot be
; missing a key. An earlier version watched a hand-written list of 17 names
; (w a s d q e f r space shift LButton RButton 1-5) and silently recorded
; nothing at all for any key outside it -- which is indistinguishable from a
; broken recorder when the key it misses happens to be the one you press.
; Sweeping all 254 VKs costs 0.408 ms (measured: 500 sweeps in 204 ms), which
; is 3.4% of one core at a 10 ms timer, so the list bought nothing.
VK_MOUSE     := Map(0x01, "LButton", 0x02, "RButton", 0x04, "MButton"
                  , 0x05, "XButton1", 0x06, "XButton2")
RouteRec     := []     ; [{t, k, d, x, y}] - t is ms since record start
RouteDown    := Map()  ; vk -> 1/0, last polled physical state
RouteClient  := { x: 0, y: 0, w: 0, h: 0 }   ; cursor positions are stored
IsRecording  := false                        ; relative to this, so a window
RouteT0      := 0                            ; that has moved still replays
HasRoute     := false  ; a route was loaded for the active location
RouteDead    := 0      ; consecutive cycles that changed nothing on screen
RouteMaxDelta := 0     ; biggest scene change seen during the last replay
RouteHeld    := false  ; last replay was stalled waiting for Roblox to be focused
LocArmed     := false  ; true once the window is up; see _PickLocation

SessionStart := A_TickCount
Cycles       := 0
LastCycleMs  := 0
TotalCycleMs := 0

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")
SendMode("Event")

_EnsureSettingsDir()
_LoadConfig()
_LoadWatches()
_RouteLoad()          ; a recorded route supersedes the built-in step sequence
_InitStepStats()

SetKeyDelay(Opt["keyDelay"], 20)

_BuildGui()

; =====================================================================
;  GUI
; =====================================================================
_BuildGui() {
    global UI, Opt, MainGui, WatchOrder

    g := Gui("+Resize +MinSize680x600", "Vortex Macro - Prospecting")
    g.BackColor := "0F1317"
    g.MarginX := 0
    g.MarginY := 0

    ; ---- header ----
    g.SetFont("s15 Bold cFFFFFF", "Segoe UI")
    g.Add("Text", "x14 y10 w400", "VORTEX MACRO")
    g.SetFont("s8 c6C7A89", "Segoe UI")
    g.Add("Text", "x14 y36 w400", "PROSPECTING   -   vision build")

    UI["status"] := g.Add("Text", "x14 y58 w640 h28 +Background0F1317", "IDLE")
    UI["status"].SetFont("s14 Bold c8A9BA8", "Consolas")
    UI["sub"] := g.Add("Text", "x14 y88 w640 h18 +Background0F1317", "")
    UI["sub"].SetFont("s8 c6C7A89", "Segoe UI")

    tab := g.Add("Tab3", "x12 y108 w656 h440 +Background0F1317", ["Map", "Status", "Settings", "Vision", "Log"])
    UI["tab"] := tab

    ; ================= TAB 1 : MAP =================
    tab.UseTab(1)
    g.SetFont("s9 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y148 w620 +Background0F1317",
        "LOCATION      watch points are stored per location, so switching maps keeps your calibration")

    UI["search"] := g.Add("Edit", "x28 y176 w300 +Background101418 cFFFFFF", "")
    UI["search"].SetFont("s9 cFFFFFF", "Consolas")
    UI["search"].OnEvent("Change", (*) => _FilterLocations())
    UI["btnAll"] := g.Add("Button", "x338 y175 w120 h24", "Show all")
    UI["btnAll"].OnEvent("Click", (*) => _ShowAllLocations())

    UI["loclist"] := g.Add("ListBox", "x28 y208 w430 h230 +Background101418 cFFFFFF", Locations)
    UI["loclist"].SetFont("s9 cFFFFFF", "Consolas")
    UI["loclist"].OnEvent("Change", (*) => _PickLocation())
    UI["loclist"].OnEvent("DoubleClick", (*) => _SelectMap())

    UI["locNow"] := g.Add("Text", "x470 y208 w180 h120 +Background0F1317", "")
    UI["locNow"].SetFont("s8 c8FA0C0", "Consolas")

    ; Clicking the list already picks a location, but a highlight alone gives no
    ; sense of having committed to anything. This button makes the choice
    ; explicit, and being the default button means Enter works too.
    UI["btnSel"] := g.Add("Button", "x470 y336 w180 h30 +Default", "Select Map")
    UI["btnSel"].OnEvent("Click", (*) => _SelectMap())
    UI["btnCalib"] := g.Add("Button", "x470 y372 w180 h30", "Calibrate this location")
    UI["btnCalib"].OnEvent("Click", (*) => _GoToVisionTab())
    UI["btnClrLoc"] := g.Add("Button", "x470 y408 w180 h30", "Clear this location")
    UI["btnClrLoc"].OnEvent("Click", (*) => _ClearWatches())

    ; --- route recording ---
    ; The built-in steps are a guess at the game's controls; a recording is not.
    ; This row is the primary control once a location has been recorded.
    UI["btnRec"] := g.Add("Button", "x28 y446 w200 h28", "Record route (F7)")
    UI["btnRec"].OnEvent("Click", (*) => _RouteToggle())
    UI["btnPlay"] := g.Add("Button", "x238 y446 w120 h28", "Play once (F8)")
    UI["btnPlay"].OnEvent("Click", (*) => _RoutePlayOnce())
    UI["btnClrRoute"] := g.Add("Button", "x368 y446 w90 h28", "Clear route")
    UI["btnClrRoute"].OnEvent("Click", (*) => _RouteClear())
    UI["routeInfo"] := g.Add("Text", "x28 y478 w430 h18 +Background0F1317", "")
    UI["routeInfo"].SetFont("s8 c8FA0C0", "Consolas")

    ; The tab control is x12 y108 w656 h440, so its content ends at y548. Anything
    ; placed lower than that is silently clipped, which is why these stay above it.
    g.SetFont("s8 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y502 w620 +Background0F1317",
        "Press F7, play the loop by hand (walk, dig, walk back, wash), then press F7 again.")
    g.Add("Text", "x28 y518 w620 +Background0F1317",
        "F8 replays it once. Select Map only picks the calibration - walk to the spot first.")

    ; ================= TAB 2 : STATUS =================
    tab.UseTab(2)
    g.SetFont("s9 c6C7A89", "Segoe UI")

    _StatRow(g, 148, "Session",       "vSession")
    _StatRow(g, 170, "Cycles",        "vCycles")
    _StatRow(g, 192, "Last cycle",    "vLastCycle")
    _StatRow(g, 214, "Average cycle", "vAvgCycle")

    g.Add("Text", "x28 y246 w620 +Background0F1317", "STEP TIMINGS     measured vs ceiling - the ceiling tunes itself")
    g.SetFont("s8 c4A5568", "Segoe UI")

    _StepRow(g, 270, "walk to node",  "vNode")
    _StepRow(g, 292, "dig",           "vDig")
    _StepRow(g, 314, "walk to water", "vWater")
    _StepRow(g, 336, "wash",          "vWash")

    UI["progress"] := g.Add("Progress", "x28 y366 w624 h12 Range0-100", 0)

    UI["btnStart"] := g.Add("Button", "x28 y392 w150 h34", "START   (F1)")
    UI["btnStart"].OnEvent("Click", _OnStart)
    UI["btnPause"] := g.Add("Button", "x188 y392 w150 h34", "PAUSE   (F2)")
    UI["btnPause"].OnEvent("Click", _OnPause)
    UI["btnReset"] := g.Add("Button", "x348 y392 w150 h34", "RESET STATS")
    UI["btnReset"].OnEvent("Click", _OnResetStats)

    ; ================= TAB 3 : SETTINGS =================
    tab.UseTab(3)
    g.SetFont("s9 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y148 w620 +Background0F1317", "STEP CEILINGS      an upper bound, not a delay")

    _Row(g, 174, "Walk to node (ms)", "nodeCap",    Caps["nodeCap"])
    _Row(g, 200, "Dig (ms)",          "digCap",     Caps["digCap"])
    _Row(g, 226, "Walk to water (ms)", "waterCap",  Caps["waterCap"])
    _Row(g, 252, "Wash (clicks)",     "washClicks", Caps["washClicks"])

    g.Add("Text", "x28 y286 w620 +Background0F1317", "BEHAVIOUR")

    _Row(g, 310, "Change tolerance", "changeTol",  Opt["changeTol"])
    _Row(g, 336, "Click delay (ms)", "clickDelay", Opt["clickDelay"])
    _Row(g, 362, "Key delay (ms)",   "keyDelay",   Opt["keyDelay"])

    UI["cbAdapt"] := g.Add("Checkbox", "x152 y392 w480", "Self-tune ceilings from what actually happens")
    UI["cbAdapt"].Value := Opt["adaptCaps"]
    UI["cbTop"] := g.Add("Checkbox", "x152 y412 w480", "Keep window always on top")
    UI["cbTop"].Value := Opt["alwaysOnTop"]
    UI["cbHide"] := g.Add("Checkbox", "x152 y432 w480", "Hide window while the macro runs")
    UI["cbHide"].Value := Opt["hideWhileRunning"]
    UI["cbRecon"] := g.Add("Checkbox", "x152 y452 w480", "Rejoin automatically if Roblox closes")
    UI["cbRecon"].Value := Opt["autoReconnect"]
    UI["cbGuard"] := g.Add("Checkbox", "x152 y472 w480", "Only send input while Roblox is the active window")
    UI["cbGuard"].Value := Opt["guardInput"]

    UI["btnSave"] := g.Add("Button", "x152 y500 w150 h30", "Save settings")
    UI["btnSave"].OnEvent("Click", (*) => _SaveConfig())

    ; ================= TAB 4 : VISION =================
    tab.UseTab(4)
    g.SetFont("s9 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y148 w620 +Background0F1317",
        "WATCH POINTS      mark a spot that LOOKS DIFFERENT when the step is done")

    y := 178
    for name in WatchOrder {
        g.Add("Text", "x28 y" . y . " w110 cFFFFFF", name)
        UI["w_" . name] := g.Add("Text", "x146 y" . y . " w290 +Background0F1317", "")
        UI["wb_" . name] := g.Add("Button", "x446 y" . (y - 5) . " w200 h25", "Mark at cursor")
        UI["wb_" . name].OnEvent("Click", _MakeMarkHandler(name))
        y += 28
    }

    g.SetFont("s8 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y" . (y + 10) . " w620 +Background0F1317",
        "Mark with Roblox UNFOCUSED - click your desktop first. While the game is")
    g.Add("Text", "x28 y" . (y + 26) . " w620 +Background0F1317",
        "focused it locks the mouse to the centre, so every point would land there.")

    UI["btnTest"] := g.Add("Button", "x28 y" . (y + 52) . " w160 h30", "Vision self-test")
    UI["btnTest"].OnEvent("Click", (*) => _VisionReport())
    UI["btnRead"] := g.Add("Button", "x198 y" . (y + 52) . " w160 h30", "Live readout (F3)")
    UI["btnRead"].OnEvent("Click", (*) => _ToggleReadout())
    UI["btnClear"] := g.Add("Button", "x368 y" . (y + 52) . " w160 h30", "Clear points (F6)")
    UI["btnClear"].OnEvent("Click", (*) => _ClearWatches())
    UI["vCapture"] := g.Add("Text", "x28 y" . (y + 90) . " w620 +Background0F1317", "")
    UI["vCapture"].SetFont("c3FE0A0")

    ; --- auto vision tuning (the zero-setup path) ---
    g.SetFont("s9 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y" . (y + 124) . " w620 +Background0F1317",
        "AUTO VISION      needs nothing marked - each step ends when the screen stops changing")

    _Row(g, y + 150, "Sample every (ms)",   "pollMs",     Opt["pollMs"])
    _Row(g, y + 176, "Still threshold",     "stillTol",   Opt["stillTol"])
    _Row(g, y + 202, "Still polls in a row", "stillPolls", Opt["stillPolls"])

    UI["btnAuto"] := g.Add("Button", "x440 y" . (y + 148) . " w210 h28", "Test auto vision")
    UI["btnAuto"].OnEvent("Click", (*) => _AutoVisionTest())

    UI["cbManual"] := g.Add("Checkbox", "x152 y" . (y + 230) . " w480", "Prefer marked watch points (off = always auto)")
    UI["cbManual"].Value := Opt["useManual"]

    ; ================= TAB 5 : LOG =================
    tab.UseTab(5)
    UI["log"] := g.Add("Edit", "x28 y148 w620 h300 ReadOnly +Background101418 c9FE8B0 -Wrap", "")
    UI["log"].SetFont("s8 c9FE8B0", "Consolas")
    g.Add("Button", "x28 y456 w130 h28", "Clear log").OnEvent("Click", (*) => (UI["log"].Value := ""))

    tab.UseTab()

    g.OnEvent("Close", _OnClose)

    UI["gui"] := g
    MainGui := g

    _ApplyOpts()
    g.Show("w680 h600")
    _ApplyIcon()
    _RefreshVisionTab()
    _SetLocPanelStatus(0, "")
    _RefreshUI()
    SetTimer(_RefreshUI, 250)
    SetTimer(_ArmLocations, -700)   ; see _ArmLocations: suppresses the first paint selection
    if (FreshConfig) {
        _SaveConfig()
        _Log("First run - wrote default settings to " . CfgFile)
    }
    _Log("Ready. " . _CalibSummary())
}

_OnClose(*) {
    global Toggle
    Toggle := false
    ExitApp()
}

; Window + tray icon. Normally <root>\assets\vortex.ico, but a couple of other
; sensible locations are tried so reorganising the folders cannot silently cost
; the user their icon. A missing or broken icon must never stop the macro from
; starting, so nothing here throws -- it is reported in the log instead. An
; earlier version failed silently and left the default engine icon in place
; with no way to tell, so it now always says what it did.
_IconPath() {
    global RootDir, MapsDir
    for d in [RootDir . "\assets", MapsDir . "\assets", A_ScriptDir . "\assets"] {
        p := d . "\vortex.ico"
        if FileExist(p)
            return p
    }
    return ""
}

_ApplyIcon() {
    global MainGui
    ico := _IconPath()
    if (ico = "") {
        _Log("Icon: no assets\vortex.ico found - keeping the default engine icon")
        return
    }
    try TraySetIcon(ico)
    try {
        hIcon := DllCall("LoadImage", "Ptr", 0, "Str", ico, "UInt", 1
            , "Int", 0, "Int", 0, "UInt", 0x10, "Ptr")      ; IMAGE_ICON, LR_LOADFROMFILE
        if hIcon {
            hwnd := MainGui.Hwnd
            SendMessage(0x0080, 1, hIcon, , "ahk_id " . hwnd)   ; WM_SETICON, ICON_BIG
            SendMessage(0x0080, 0, hIcon, , "ahk_id " . hwnd)   ; WM_SETICON, ICON_SMALL
            _Log("Icon: applied from " . ico)
        } else {
            _Log("Icon: LoadImage failed for " . ico . " - keeping the default")
        }
    } catch as e {
        _Log("Icon: could not apply (" . e.Message . ")")
    }
}

_ApplyOpts() {
    global Opt, MainGui
    MainGui.Opt(Opt["alwaysOnTop"] ? "+AlwaysOnTop" : "-AlwaysOnTop")
}

; one label + value row
_StatRow(g, y, label, key) {
    global UI
    g.SetFont("s9 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y" . y . " w160 +Background0F1317", label)
    UI[key] := g.Add("Text", "x198 y" . y . " w450 +Background0F1317", "-")
    UI[key].SetFont("s9 cFFFFFF", "Consolas")
}

; one step-timing row (name + detail)
_StepRow(g, y, label, key) {
    global UI
    g.SetFont("s9 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y" . y . " w120 +Background0F1317", label)
    UI[key] := g.Add("Text", "x156 y" . y . " w490 +Background0F1317", "-")
    UI[key].SetFont("s8 c9FE8B0", "Consolas")
}

; one editable settings row
_Row(g, y, label, key, value) {
    global UI
    g.SetFont("s9 c6C7A89", "Segoe UI")
    g.Add("Text", "x28 y" . y . " w120 +Background0F1317", label)
    e := g.Add("Edit", "x152 y" . (y - 3) . " w110 +Background101418 cFFFFFF", value)
    e.SetFont("s9 cFFFFFF", "Consolas")
    UI["e_" . key] := e
}

; =====================================================================
;  GUI ACTIONS
; =====================================================================
_OnStart(*) {
    global Toggle, Opt, MainGui, RouteDead
    if (Toggle)
        return
    MouseGetPos(&cx, &cy)
    _Log("START | fg=[" . WinGetTitle("A") . "] cursor=" . cx . "," . cy)
    RouteDead := 0
    Toggle := true
    if (Opt["hideWhileRunning"])
        MainGui.Hide()
    SetTimer(SuperMacroLoop, -1)
}

_OnPause(*) {
    global Toggle, Opt, MainGui, WaitHeld
    Toggle := false
    WaitHeld := false      ; so the next start logs the "holding input" line again
    _Log("PAUSE")
    if (Opt["hideWhileRunning"])
        MainGui.Show()
    _SetStatus("IDLE", "c8A9BA8")
}

_OnResetStats(*) {
    global Cycles, TotalCycleMs, LastCycleMs, SessionStart, StuckRun
    Cycles := 0
    TotalCycleMs := 0
    LastCycleMs := 0
    SessionStart := A_TickCount
    StuckRun := Map()
    _InitStepStats()
    _Log("Statistics reset.")
    _RefreshUI()
}

_MakeMarkHandler(name) {
    return (*) => _MarkWatch(name)
}

_MarkWatch(name) {
    global Watches, UI
    MouseGetPos(&mx, &my)
    Watches[name] := { x: mx, y: my }
    _SaveWatch(name, mx, my)
    UI["vCapture"].Text := "Marked [" . name . "] at " . mx . "," . my
    _Log("Marked [" . name . "] at " . mx . "," . my)
    _RefreshVisionTab()
    _RefreshUI()
}

_ToggleReadout() {
    global Readout
    Readout := !Readout
    if (Readout) {
        SetTimer(_ReadoutTick, 60)
        _Log("Live readout ON - move the cursor over the game to inspect pixels.")
    } else {
        SetTimer(_ReadoutTick, 0)
        ToolTip()
        _Log("Live readout OFF.")
    }
}

_RefreshVisionTab() {
    global Watches, UI
    for name in WatchOrder {
        if Watches.Has(name) {
            w := Watches[name]
            UI["w_" . name].Text := "marked   " . w.x . "," . w.y
            UI["w_" . name].SetFont("s9 c3FE0A0", "Consolas")
        } else {
            UI["w_" . name].Text := "unset  -  fixed timing"
            UI["w_" . name].SetFont("s9 cF0C040", "Consolas")
        }
    }
}

_ReadoutTick() {
    MouseGetPos(&mx, &my)
    c := PixelGetColor(mx, my, "RGB")
    ToolTip("x" . mx . "  y" . my . "   #" . Format("{:06X}", c), mx + 18, my + 18)
}

; =====================================================================
;  UI REFRESH
; =====================================================================
_InitStepStats() {
    global StepStat
    StepStat := Map()
    for n in WatchOrder
        StepStat[n] := { n: 0, total: 0, last: 0, early: 0 }
}

_FmtMs(ms) {
    if (ms <= 0)
        return "-"
    return (ms < 1000) ? Round(ms) . " ms" : Format("{:.2f}", ms / 1000) . " s"
}

_SessionText() {
    global SessionStart
    sec := (A_TickCount - SessionStart) // 1000
    return Format("{:02}:{:02}:{:02}", sec // 3600, Mod(sec // 60, 60), Mod(sec, 60))
}

_RefreshUI() {
    global UI, Cycles, LastCycleMs, TotalCycleMs, Toggle, IsRecording, RouteRec

    if !UI.Has("vSession")
        return

    if (Toggle) {
        UI["vSession"].Text := _SessionText()
    } else {
        UI["vSession"].Text := _SessionText()
    }

    UI["vCycles"].Text    := Cycles
    UI["vLastCycle"].Text := _FmtMs(LastCycleMs)
    UI["vAvgCycle"].Text  := Cycles ? _FmtMs(TotalCycleMs / Cycles) : "-"

    UI["vNode"].Text  := _StepText("at_node")
    UI["vDig"].Text   := _StepText("dig_done")
    UI["vWater"].Text := _StepText("at_water")
    UI["vWash"].Text  := _StepText("wash_done")

    UI["sub"].Text := _CalibSummary() . "        " . (Toggle ? "macro running" : "macro idle")

    if UI.Has("routeInfo") {
        if IsRecording
            UI["routeInfo"].Text := "RECORDING - " . RouteRec.Length . " events so far   (F7 to stop)"
        else
            UI["routeInfo"].Text := "route: " . _RouteSummary()
    }
}

_StepText(name) {
    global StepStat, Caps
    s := StepStat[name]
    key := _CapKeyFor(name)
    isClicks := (name = "wash_done")
    unit := isClicks ? " clicks" : " ms"
    ceil := Caps[key]
    if (s.n = 0)
        return "no data yet                                        ceiling " . Round(ceil) . unit
    return "avg " . Round(s.total / s.n) . unit
        . "   last " . Round(s.last) . unit
        . "   ceiling " . Round(ceil) . unit
        . "   early-stop " . s.early . "/" . s.n
}

_CapKeyFor(name) {
    switch name {
        case "at_node":  return "nodeCap"
        case "dig_done": return "digCap"
        case "at_water": return "waterCap"
    }
    return "washClicks"
}

_CalibSummary() {
    global Watches, ActiveLocation, Opt, HasRoute
    if HasRoute
        return ActiveLocation . "   |   ROUTE REPLAY   -   " . _RouteSummary()

    n := 0
    for name in WatchOrder
        if Watches.Has(name)
            n += 1
    if (!Opt["useManual"])
        vision := "AUTO VISION (scene settle)"
    else if (n = 0)
        vision := "manual mode, but no watch points marked"
    else
        vision := "manual vision   -   " . n . "/4 watch points marked"

    ; No recording yet: the built-in steps are the only thing to run, and they are
    ; the part that was never verified. Say so rather than quietly looking ready.
    return ActiveLocation . "   |   NO ROUTE YET - press F9, play the loop once, press F9 again"
        . "   |   " . vision
}

_SetProgress(pct) {
    global UI
    if UI.Has("progress")
        UI["progress"].Value := pct
}

_SetStatus(txt, colour := "cFFFFFF") {
    global UI
    if !UI.Has("status")
        return
    UI["status"].Text := txt
    UI["status"].SetFont("s14 Bold " . colour, "Consolas")
}

; =====================================================================
;  ROUTE RECORDER
; =====================================================================
; Records the player doing the loop by hand, then replays it. This exists because
; the built-in step sequence encodes an assumption about the game's controls that
; was never verified - it moved the character but never dug. A recording cannot
; make that mistake: it repeats exactly what worked.
;
; Routes live beside the map files, one per location, so each map keeps its own.

; ---- recorder primitives ---------------------------------------------------

; Physical state of any virtual key. GetAsyncKeyState reads injected input as
; well as real input, which is what makes the recorder testable at all.
_VkDown(vk) {
    return (DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000) ? 1 : 0
}

; How a key is written into a route file. Mouse buttons get their readable AHK
; name; every other key is stored as a virtual key code, so no name list is
; needed and nothing can fall outside it.
_VkToken(vk) {
    global VK_MOUSE
    return VK_MOUSE.Has(vk) ? VK_MOUSE[vk] : "vk" . Format("{:02X}", vk)
}

; A human-readable name, for the log and the status line only. Falls back to
; the raw token, so an unmapped key is reported rather than dropped.
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

; One recorded event, with the cursor position at that moment, relative to the
; game's client area. While the game holds the cursor locked that position is
; the centre, which is still the right thing to replay.
_RouteEvent(vk, dir) {
    global RouteT0, RouteClient
    MouseGetPos(&mx, &my)
    return { t: A_TickCount - RouteT0, k: _VkToken(vk), d: dir
           , x: mx - RouteClient.x, y: my - RouteClient.y }
}

; May a route file contain this token? Anything the recorder can emit, plus
; the "m" cursor-move token.
_IsRouteKey(k) {
    global VK_MOUSE
    if (k = "m")
        return true
    for vk, name in VK_MOUSE {
        if (name = k)
            return true
    }
    return RegExMatch(k, "^vk[0-9A-Fa-f]{2}$") ? true : false
}

; A stored token back to something a person reads: "vk57" -> "w".
_TokenName(tok) {
    if (tok = "m")
        return "mouse-move"
    if (SubStr(tok, 1, 2) = "vk")
        return _VkName(("0x" . SubStr(tok, 3)) + 0)
    return tok
}

; The distinct keys in the route, named. This is the direct answer to the only
; question that matters after a recording: did it capture the keys I pressed?
_RouteKeyNames() {
    global RouteRec
    seen := Map()
    s := ""
    for e in RouteRec {
        if (e.k = "m" or seen.Has(e.k))
            continue
        seen[e.k] := true
        s .= (s = "" ? "" : ", ") . _TokenName(e.k)
    }
    return (s = "" ? "(no keys - mouse movement only)" : s)
}

_RouteFile() {
    global MapsDir, ActiveLocation
    return MapsDir . "\" . ActiveLocation . ".route"
}

_RouteBegin() {
    global RouteRec, RouteDown, IsRecording, RouteT0, Toggle, ActiveLocation, RouteClient
    if IsRecording
        return
    if Toggle
        _OnPause()                       ; never record while the macro drives the game
    RouteRec := []
    ; Cursor positions are stored relative to the game's client area, captured
    ; once here, so the replay still lands correctly if the window moves.
    RouteClient := _GameRect()
    ; Seed every key, so a key already held at the moment recording starts is
    ; not immediately logged as a fresh press.
    RouteDown := Map()
    vk := 1
    while (vk <= 254) {
        RouteDown[vk] := _VkDown(vk)
        vk += 1
    }
    RouteT0 := A_TickCount
    IsRecording := true
    SetTimer(_RoutePoll, 10)
    _SetStatus("RECORDING ROUTE", "cF0C040")
    _SetProgress(0)
    _Log("Route recording STARTED for " . ActiveLocation
        . " - play the loop by hand now, then press F7 again to stop.")
}

_RoutePoll() {
    global RouteRec, RouteDown, IsRecording
    if (!IsRecording)
        return
    ; Every virtual key, by code. Nothing can be outside this sweep.
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

_RouteEnd() {
    global RouteRec, RouteDown, IsRecording, HasRoute
    if (!IsRecording)
        return
    SetTimer(_RoutePoll, 0)
    IsRecording := false

    ; A key still held when recording stops would replay as pressed-forever, so
    ; close every open press and release it for real.
    closed := 0
    vk := 1
    while (vk <= 254) {
        if (RouteDown.Get(vk, 0)) {
            RouteRec.Push(_RouteEvent(vk, "up"))
            Send("{" . _VkToken(vk) . " up}")
            RouteDown[vk] := 0
            closed += 1
        }
        vk += 1
    }

    if (RouteRec.Length = 0) {
        _SetStatus("RECORDED NOTHING", "cFF6B4A")
        _Log("Route recording stopped - no input was captured, so nothing was saved.")
        return
    }

    f := FileOpen(_RouteFile(), "w", "UTF-8")
    for e in RouteRec
        f.WriteLine(e.t . "`t" . e.k . "`t" . e.d)
    f.Close()

    HasRoute := true
    _SetStatus("ROUTE SAVED", "c8FA0C0")
    _Log("Route recording STOPPED - " . RouteRec.Length . " events over "
        . Round(RouteRec[RouteRec.Length].t / 1000, 1) . " s"
        . (closed ? " (closed " . closed . " held key(s))" : "")
        . " -> " . _RouteFile())
    _Log("  keys recorded: " . _RouteKeyNames())
    _RefreshUI()
}

; Load the route for the active location.
;
; The route file is plain text the user can open and edit, and it can also be
; truncated by a crash halfway through a write. Two rules follow:
;   * a bad line means "skip that line", never an exception. This runs at
;     startup, so throwing here would stop the app from opening at all.
;   * a recording cut short mid-hold would replay as a key pressed forever, so
;     any press left without a release is closed at the end of the route.
_RouteLoad() {
    global RouteRec, HasRoute, ActiveLocation

    RouteRec := []
    HasRoute := false
    f := _RouteFile()
    if !FileExist(f)
        return false

    raw := []
    bad := 0
    Loop Read, f {
        line := Trim(A_LoopReadLine)
        if (line = "" or SubStr(line, 1, 1) = ";")
            continue
        parts := StrSplit(line, "`t")
        if (parts.Length < 3) {
            bad += 1
            continue
        }
        t   := _RouteInt(parts[1], -1)
        key := Trim(parts[2])
        dir := StrLower(Trim(parts[3]))
        ; "m" is a cursor move and carries no direction; everything else is a
        ; key press or a key release.
        okDir := (key = "m") ? (dir = "-") : (dir = "down" or dir = "up")
        if (t < 0 or t > 3600000 or !_IsRouteKey(key) or !okDir) {
            bad += 1
            continue
        }
        e := { t: t, k: key, d: dir }
        ; Positions are optional. A route written by an older build, or by hand,
        ; is still a valid route - just one that clicks wherever the cursor is.
        if (parts.Length >= 5) {
            e.x := _RouteInt(parts[4], 0)
            e.y := _RouteInt(parts[5], 0)
        }
        raw.Push(e)
    }

    if (raw.Length = 0) {
        if (bad)
            _Log("Route file for " . ActiveLocation . " is unreadable ("
                . bad . " bad line(s)) - using the built-in steps.")
        return false
    }

    ; Timings are offsets from the start of the recording and the replay waits
    ; for each one in turn, so rows out of order would make it wait for a
    ; moment that has already passed and collapse the rest into one burst.
    _RouteSort(raw)

    ; Close any press that has no release, at the point the recording stopped.
    open := Map()
    for e in raw {
        if (e.d = "down")
            open[e.k] := true
        else
            open.Delete(e.k)
    }
    if (open.Count > 0) {
        when := raw[raw.Length].t + 40
        for k, v in open
            raw.Push({ t: when, k: k, d: "up" })
        _RouteSort(raw)
        _Log("Route ended with " . open.Count . " key(s) still held - added"
            . " the missing release(s) so nothing can stay pressed down.")
    }

    RouteRec := raw
    HasRoute := true
    if (bad)
        _Log("Route for " . ActiveLocation . " loaded, " . bad
            . " bad line(s) skipped.")
    return true
}

; Digits, optionally signed. Sign matters because cursor positions are stored
; relative to the window and can legitimately be negative on a shifted window;
; the caller range-checks the timestamp itself. Deliberately strict, because
; this reads a file the user can edit and Integer() throws on anything else.
_RouteInt(s, fallback) {
    s := Trim(s)
    if RegExMatch(s, "^-?\d+$")
        return Integer(s)
    return fallback
}

; Insertion sort by time. Recordings are written in order, so this is close to
; linear on real data, and it avoids depending on Array.Sort's callback form.
_RouteSort(arr) {
    n := arr.Length
    Loop n - 1 {
        i := A_Index + 1
        cur := arr[i]
        j := i - 1
        while (j >= 1 and arr[j].t > cur.t) {
            arr[j + 1] := arr[j]
            j -= 1
        }
        arr[j + 1] := cur
    }
}

_RouteClear() {
    global RouteRec, HasRoute, ActiveLocation
    f := _RouteFile()
    if FileExist(f)
        FileDelete(f)
    RouteRec := []
    HasRoute := false
    _SetStatus("ROUTE CLEARED", "cFF6B4A")
    _Log("Route for " . ActiveLocation . " deleted - back to the built-in steps.")
    _RefreshUI()
}

_RouteSummary() {
    global RouteRec, HasRoute
    if !HasRoute
        return "no route yet - using the built-in steps"
    return RouteRec.Length . " events, "
        . Round(RouteRec[RouteRec.Length].t / 1000, 1) . " s - "
        . _RouteKeyNames()
}

; Replay the recorded events at their original timings.
_RoutePlay() {
    global RouteRec, Toggle, Opt, RouteMaxDelta, RouteHeld, RouteClient

    if (RouteRec.Length = 0)
        return false

    ; Sample the scene while replaying, so the caller can tell whether this cycle
    ; actually did anything. A raw replay is blind - it repeats the recorded
    ; timings whether or not the game responded - so without this a stuck or
    ; desynced route would quietly grind out nothing for hours.
    r := _GameRect()
    RouteClient := r             ; recorded cursor positions are relative to this
    prev := _CaptureSig(r)
    RouteMaxDelta := 0
    RouteHeld := false
    held := Map()                ; what THIS route pressed and has not released,
    lastSample := A_TickCount    ; so the cleanup cannot disturb the player

    t0 := A_TickCount
    for e in RouteRec {
        ; Wait until this event is due, staying interruptible and honouring the
        ; same "only while Roblox is focused" guard as live input. The clock is
        ; PAUSED while waiting rather than skipped, so a guard stall cannot
        ; fast-forward the rest of the route into one burst.
        while (Toggle) {
            if (Opt["guardInput"] and !_GameFocused()) {
                RouteHeld := true
                _SetStatus("WAITING FOR ROBLOX", "cFF6B4A")
                gStart := A_TickCount
                while (Toggle and !_GameFocused())
                    Sleep(300)
                t0 += A_TickCount - gStart
                if (!Toggle)
                    break
                _SetStatus("REPLAYING ROUTE", "c8FA0C0")
            }
            if (A_TickCount - t0 >= e.t)
                break
            Sleep(5)
            if (A_TickCount - lastSample >= Opt["pollMs"]) {
                lastSample := A_TickCount
                cur := _CaptureSig(r)
                d := _SigDelta(prev, cur)
                prev := cur
                if (d > RouteMaxDelta)
                    RouteMaxDelta := d
            }
        }
        if (!Toggle)
            break

        ; Put the cursor back where it was when this event was recorded, before
        ; the click lands, because a click only means something at a position.
        ; While the game holds the cursor locked this moves it to the centre,
        ; which is where it already is, so it costs nothing.
        if (HasProp(e, "x"))
            MouseMove(RouteClient.x + e.x, RouteClient.y + e.y, 0)

        if (e.k = "m")
            continue

        Send("{" . e.k . " " . e.d . "}")
        if (e.d = "down")
            held[e.k] := true
        else
            held.Delete(e.k)
    }

    ; Release only what this route left down. Releasing every key in the list, as
    ; an earlier version did, would also let go of a key the player is holding.
    for k, v in held
        Send("{" . k . " up}")
    return true
}

; Play the route once, independent of the main loop - for testing right after a
; recording, without committing to a full farming run.
_RoutePlayOnce(*) {
    global RouteRec, ActiveLocation, Toggle
    if (RouteRec.Length = 0) {
        _SetStatus("NO ROUTE FOR " . ActiveLocation, "cFF6B4A")
        _Log("Play requested, but " . ActiveLocation . " has no recorded route.")
        return
    }
    _Log("Playing route once for " . ActiveLocation . " (" . RouteRec.Length . " events)")
    _SetStatus("PLAYING ROUTE ONCE", "c8FA0C0")
    wasRunning := Toggle
    Toggle := true                     ; _RoutePlay treats Toggle as its run flag
    _RoutePlay()
    Toggle := wasRunning
    _SetStatus(wasRunning ? "RUNNING" : "IDLE", wasRunning ? "c6FC5F0" : "c8A9BA8")
}

; ---- the one-key flow ------------------------------------------------------
; The alternative to this macro is a tiny recorder you point at the screen that
; needs no setup at all, so requiring a location to be chosen before recording
; is a step the competition does not have. F9 does the common case in two
; presses and asks nothing:
;
;     press 1  ->  recording starts
;     press 2  ->  recording stops and the loop starts running, immediately
;     press 3  ->  it stops
;
; The selected location only decides which route FILE this is saved into, so
; nothing has to be configured first and the default is good enough.
_QuickToggle(*) {
    global IsRecording, Toggle, HasRoute, ActiveLocation

    ; Already running: this press means stop.
    if (!IsRecording and Toggle) {
        _OnPause()
        return
    }

    ; Recording: stop, then run what was just captured, so the whole job is
    ; two presses and no separate "play" step.
    if IsRecording {
        _RouteEnd()
        if (!HasRoute) {
            _SetStatus("NOTHING RECORDED", "cFF6B4A")
            return
        }
        _Log("Quick start: looping the route for " . ActiveLocation . " now.")
        _OnStart()
        return
    }

    ; Idle: start recording.
    _RouteBegin()
}

_RouteToggle(*) {
    global IsRecording
    if IsRecording
        _RouteEnd()
    else
        _RouteBegin()
}

; =====================================================================
;  MAIN LOOP
; =====================================================================
SuperMacroLoop() {
    global Toggle, Cycles, LastCycleMs, TotalCycleMs, Opt, WaitHeld

    while (Toggle) {
        ; Safety first: never type into whatever happens to be in front. If the
        ; user alt-tabs away (or the macro was started by accident), hold all
        ; input instead of spraying WASD and clicks into another program.
        if (Opt["guardInput"] and !_GameFocused()) {
            _SetStatus("WAITING FOR ROBLOX", "cFF6B4A")
            _SetProgress(0)
            if !WaitHeld
                _Log("Roblox is not the active window - holding input.")
            WaitHeld := true
            while (Toggle and !_GameFocused())
                Sleep(400)
            if (Toggle)
                _Log("Roblox focused again - resuming.")
            WaitHeld := false
            continue
        }

        tCycle := A_TickCount

        ; A recorded route replaces the built-in steps completely. The built-in
        ; sequence assumes a control scheme that was never confirmed against the
        ; real game - which is exactly why it walked forward and back without
        ; digging. Once a route exists, what the player actually did is replayed.
        if HasRoute
            _RunRouteCycle()
        else
            _RunStepCycle()

        Cycles += 1
        LastCycleMs := A_TickCount - tCycle
        TotalCycleMs += LastCycleMs
        _SetProgress(100)
        _RefreshUI()

        ; --- smart: is the game still even there? ---
        _AutoReconnect()
    }
}

; The original hard-coded four steps, kept as the fallback for any location that
; has no recording. Still end-conditioned by auto vision rather than raw timing,
; so it degrades better than a blind Sleep chain even here.
_RunStepCycle() {
    ; --- 1. walk into the node ---
    _SetStatus("WALKING TO NODE", "c6FC5F0")
    _SetProgress(10)
    _Step("w", "at_node", "nodeCap")
    Sleep(150)

    ; --- 2. dig ---
    _SetStatus("DIGGING", "cF0C040")
    _SetProgress(35)
    _Step("mouse", "dig_done", "digCap")
    Sleep(250)

    ; --- 3. walk back to the water ---
    _SetStatus("WALKING TO WATER", "c6FC5F0")
    _SetProgress(65)
    _Step("s", "at_water", "waterCap")
    Sleep(300)

    ; --- 4. wash ---
    _SetStatus("WASHING", "c8FA0C0")
    _SetProgress(85)
    _Wash()
    Sleep(400)
}

; One cycle driven by the recording instead of by guessed steps.
_RunRouteCycle() {
    global RouteMaxDelta, Opt, RouteDead, Toggle, MainGui, RouteHeld

    _SetStatus("REPLAYING ROUTE", "c8FA0C0")
    _SetProgress(50)
    _RoutePlay()
    Sleep(250)

    ; A cycle spent waiting for Roblox says nothing about whether the route still
    ; works, so it must never be counted as a dead one - otherwise alt-tabbing away
    ; for a moment would stop the macro with "recording is broken".
    if (RouteHeld) {
        _SetStatus("WAITING FOR ROBLOX", "cFF6B4A")
        return
    }
    if (!Toggle)
        return

    ; Did that cycle actually do anything? If nothing on screen changed at all,
    ; the route no longer matches the game - the character is stuck, the wrong
    ; map is loaded, or the game stopped responding. A blind replay carries on
    ; regardless; stop instead, because a run that farms nothing is worse than
    ; one that stops and says why.
    if (RouteMaxDelta <= Opt["stillTol"]) {
        RouteDead += 1
        _Log("Route cycle did nothing - the screen never changed   (dead cycle "
            . RouteDead . " of " . Opt["deadCycles"] . ")")
        if (RouteDead >= Opt["deadCycles"]) {
            Toggle := false
            _SetStatus("ROUTE NOT WORKING - RECORD IT AGAIN", "cF0C040")
            _Log("STOPPED: " . RouteDead . " cycles in a row changed nothing on screen, "
                . "so the route no longer matches the game. Press F7 and record it again "
                . "from the right starting spot.")
            if (Opt["hideWhileRunning"])
                MainGui.Show()
        }
    } else {
        if (RouteDead)
            _Log("Route is moving again - resetting the dead-cycle count.")
        RouteDead := 0
    }
}

; Run one step. Statistics, self-tuning and stuck detection are shared; only the
; rule that decides the step is finished differs:
;   - watch point marked  -> stop when that pixel changes  (precise)
;   - nothing marked      -> stop when the whole scene settles  (zero setup)
_Step(key, watchName, capKey) {
    global Toggle, Caps, Opt, StepStat, StuckRun, Watches

    t0 := A_TickCount
    useManual := Opt["useManual"] and Watches.Has(watchName)

    if (useManual)
        done := _RunManual(key, watchName, Caps[capKey])
    else
        done := _RunAuto(key, Caps[capKey])

    elapsed := A_TickCount - t0

    s := StepStat[watchName]
    s.n += 1
    s.total += elapsed
    s.last := elapsed
    if (done)
        s.early += 1

    ; --- self-tuning: converge the ceiling onto what actually happens ---
    if (Opt["adaptCaps"]) {
        if (done) {
            target := Max(elapsed * 1.35, CapFloor[capKey])
            Caps[capKey] := Round(Min(Max(0.7 * Caps[capKey] + 0.3 * target, CapFloor[capKey]), CapCeil[capKey]))
        } else {
            ; we ran out of time, so we clearly needed more
            Caps[capKey] := Round(Min(Caps[capKey] * 1.25, CapCeil[capKey]))
        }
    }

    ; --- stuck detection: only meaningful when a point was meant to change ---
    if (!useManual or done) {
        StuckRun[watchName] := 0
    } else {
        StuckRun[watchName] := (StuckRun.Has(watchName) ? StuckRun[watchName] : 0) + 1
        if (StuckRun[watchName] = 3) {
            _Log("WARNING: '" . watchName . "' hit its ceiling 3 cycles running.")
            _Log("         The watch point may be wrong, or the game moved on.")
            _SetStatus("CHECK " . watchName, "cFF6B4A")
            Sleep(700)
        }
    }

    Sleep(120)
}

; Hold until a MARKED pixel changes.
_RunManual(key, watchName, capMs) {
    global Toggle
    base := _SampleWatch(watchName)
    _HoldKey(key, "down")
    changed := _WaitChange(watchName, base, capMs)
    _HoldKey(key, "up")
    return changed
}

; Hold until the SCENE SETTLES. Needs nothing marked.
;
; The floor matters: without it a step could settle instantly (a static camera
; while a hold key is down) and be cut short before anything happened. The floor
; is derived from the self-tuning ceiling, so it tracks the learned duration.
_RunAuto(key, capMs) {
    global Toggle, Opt

    r := _GameRect()
    floorMs := Round(capMs * 0.55)
    stopper := Max(Opt["stillPolls"], 2)

    prev := _CaptureSig(r)
    t0 := A_TickCount
    stillRun := 0

    _HoldKey(key, "down")

    while (Toggle) {
        Sleep(Opt["pollMs"])
        cur := _CaptureSig(r)
        d := _SigDelta(prev, cur)
        prev := cur

        if (d <= Opt["stillTol"])
            stillRun += 1
        else
            stillRun := 0

        el := A_TickCount - t0
        if (stillRun >= stopper and el >= floorMs) {
            _HoldKey(key, "up")
            return true
        }
        if (el >= capMs)
            break
    }

    _HoldKey(key, "up")
    return false
}

_HoldKey(key, dir) {
    if (key = "mouse")
        Click(dir)
    else
        Send("{" . key . " " . dir . "}")
}

_Wash() {
    global Toggle, Caps, Opt, StepStat, StuckRun, Watches

    t0 := A_TickCount
    n := 0
    done := false
    useManual := Opt["useManual"] and Watches.Has("wash_done")

    if (useManual) {
        base := _SampleWatch("wash_done")
        while (Toggle and n < Caps["washClicks"]) {
            Click()
            n += 1
            Sleep(Opt["clickDelay"])
            if (base >= 0 and _Changed("wash_done", base)) {
                done := true
                break
            }
        }
    } else {
        ; Nothing marked: keep clicking until the pan stops changing on screen.
        ; Require a few clicks first, or a pan that never animates would "settle"
        ; immediately and stop the step before it did anything.
        r := _GameRect()
        prev := _CaptureSig(r)
        stillRun := 0
        while (Toggle and n < Caps["washClicks"]) {
            Click()
            n += 1
            Sleep(Opt["clickDelay"])
            cur := _CaptureSig(r)
            if (_SigDelta(prev, cur) <= Opt["stillTol"])
                stillRun += 1
            else
                stillRun := 0
            prev := cur
            if (stillRun >= 2 and n >= 3) {
                done := true
                break
            }
        }
    }

    elapsed := A_TickCount - t0
    s := StepStat["wash_done"]
    s.n += 1
    s.total += elapsed
    s.last := elapsed
    if (done)
        s.early += 1

    if (Opt["adaptCaps"]) {
        if (done)
            Caps["washClicks"] := Round(Min(Max(0.7 * Caps["washClicks"] + 0.3 * (n * 1.3), 3), 60))
        else
            Caps["washClicks"] := Min(Caps["washClicks"] + 2, 60)
    }

    if (done) {
        StuckRun["wash_done"] := 0
    } else {
        StuckRun["wash_done"] := (StuckRun.Has("wash_done") ? StuckRun["wash_done"] : 0) + 1
        if (StuckRun["wash_done"] = 3)
            _Log("WARNING: 'wash_done' never settled across 3 cycles.")
    }
}

; =====================================================================
;  SMART: RECONNECT
; =====================================================================
_AutoReconnect() {
    global Opt

    if (!Opt["autoReconnect"])
        return
    if ProcessExist("RobloxPlayerBeta.exe")
        return

    _Log("Roblox is not running - rejoining via deeplink.")
    _SetStatus("RECONNECTING", "cFF6B4A")
    try {
        Run(DEEPLINK)
    } catch as e {
        _Log("Rejoin failed: " . e.Message)
        return
    }
    Sleep(15000)   ; give the client time to reach the server
}

; =====================================================================
;  AUTO VISION   (works with nothing marked at all)
; =====================================================================
; PixelGetColor costs ~5 ms per call (measured: 60 calls = 313 ms), so sampling
; the screen pixel by pixel is hopeless -- one poll would stall the macro for a
; third of a second. Instead the whole game view is StretchBlt'd into a single
; tiny 32x18 bitmap per poll (~5 ms for the lot, measured) and those 576
; downsampled pixels become a "scene signature".
;
; Comparing two signatures channel by channel gives a scene delta. Measured
; separation on a real screen change: 47.2 when something moved, 0.00 when
; nothing did. That gap is wide enough to be safe.
;
; Why this removes the need to mark anything: every single step in this macro
; already ENDS in a state where the screen stops changing.
;     walk  -> the view stops scrolling once the wall is hit and you arrive
;     dig   -> the pan fills, then the indicator stops updating
;     wash  -> the pan stops changing once it is clean
; So "hold until the scene settles" is a universal end condition. Nothing to
; mark, nothing to measure, nothing to configure.
;
; A marked watch point still wins when one exists: it is a more precise signal,
; so manual and auto are chosen per step rather than by a global mode switch.

_GameRect() {
    for hwnd in WinGetList() {
        try {
            if (ProcessGetName(WinGetPID("ahk_id " . hwnd)) != "RobloxPlayerBeta.exe")
                continue
            WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " . hwnd)
            if (cw > 200 and ch > 150)
                return { x: cx, y: cy, w: cw, h: ch }
        }
    }
    ; Client not up yet: fall back to the whole screen so auto vision still has
    ; something to watch (it just sees more than the game).
    return { x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight }
}

_CaptureSig(r, gw := 32, gh := 18) {
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", gw, "Int", gh, "Ptr")
    hOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
    DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 3)   ; COLORONCOLOR
    DllCall("StretchBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", gw, "Int", gh
        , "Ptr", hdcScreen, "Int", r.x, "Int", r.y, "Int", r.w, "Int", r.h
        , "UInt", 0x00CC0020)                                ; SRCCOPY

    bi := Buffer(56, 0)
    NumPut("UInt", 40, bi, 0)          ; biSize
    NumPut("Int", gw, bi, 4)           ; biWidth
    NumPut("Int", -gh, bi, 8)          ; biHeight: negative = top-down rows
    NumPut("UShort", 1, bi, 12)        ; biPlanes
    NumPut("UShort", 32, bi, 14)       ; biBitCount
    NumPut("UInt", 0, bi, 16)          ; biCompression = BI_RGB
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

; Mean absolute per-channel difference, 0..255. Alpha is ignored.
_SigDelta(a, b, gw := 32, gh := 18) {
    total := 0
    loop gw * gh {
        off := (A_Index - 1) * 4
        total += Abs(NumGet(a, off, "UChar") - NumGet(b, off, "UChar"))
        total += Abs(NumGet(a, off + 1, "UChar") - NumGet(b, off + 1, "UChar"))
        total += Abs(NumGet(a, off + 2, "UChar") - NumGet(b, off + 2, "UChar"))
    }
    return total / (gw * gh * 3)
}

; Reports, with numbers, whether auto vision can actually see this game change.
; Without this the user is guessing at the still threshold.
_AutoVisionTest(*) {
    global Opt

    r := _GameRect()
    prev := _CaptureSig(r)
    mn := 9999, mx := -1, sum := 0, n := 0
    t0 := A_TickCount
    while (A_TickCount - t0 < 3000) {
        Sleep(Opt["pollMs"])
        cur := _CaptureSig(r)
        d := _SigDelta(prev, cur)
        prev := cur
        mn := Min(mn, d)
        mx := Max(mx, d)
        sum += d
        n += 1
    }
    if (n = 0)
        n := 1

    verdict := ""
    if (mx < 1)
        verdict := "NOTHING IS BEING CAPTURED. The game may not be visible on screen,`n"
            . "or the surface cannot be captured (run the Vision self-test first).`n"
            . "Auto vision cannot work like this."
    else if (mn > Opt["stillTol"])
        verdict := "The screen NEVER looks still - even the quietest sample (" . Round(mn, 2) . ")`n"
            . "is above the still threshold (" . Opt["stillTol"] . "). Raise the threshold to`n"
            . "roughly the 'min' value above, or every step will run to its ceiling."
    else
        verdict := "Good: the scene goes quiet (" . Round(mn, 2) . ") and moves (" . Round(mx, 2) . "),`n"
            . "so settling is detectable. Threshold " . Opt["stillTol"] . " sits between them."

    MsgBox("Auto vision - 3 second sample`n`n"
        . "region   " . r.w . "x" . r.h . " at " . r.x . "," . r.y . "`n"
        . "samples  " . n . "`n"
        . "delta    min " . Round(mn, 2) . "   avg " . Round(sum / n, 2) . "   max " . Round(mx, 2) . "`n"
        . "settled  when delta <= " . Opt["stillTol"] . " for " . Opt["stillPolls"] . " samples in a row`n`n"
        . verdict, "Vortex Auto Vision", "Iconi")
}

; =====================================================================
;  VISION ENGINE
; =====================================================================
; A watch point is a screen coordinate the user marks. The macro samples its
; colour when an action begins, then waits for that colour to CHANGE. Nothing
; about the game's art is baked in here, so no colour is ever guessed: the one
; thing that must be true is that the pixel looks different when the step ends.
;
; Any unset watch point degrades that step back to the plain fixed ceiling.

_SampleWatch(name) {
    global Watches
    if !Watches.Has(name)
        return -1
    w := Watches[name]
    return PixelGetColor(w.x, w.y, "RGB")
}

_Changed(name, baseline) {
    global Watches, Opt
    if (baseline < 0 or !Watches.Has(name))
        return false
    w := Watches[name]
    return _Diff(PixelGetColor(w.x, w.y, "RGB"), baseline) > Opt["changeTol"]
}

_WaitChange(watchName, baseline, capMs) {
    global Toggle
    t0 := A_TickCount
    while (Toggle) {
        if (baseline >= 0 and _Changed(watchName, baseline))
            return true
        if (A_TickCount - t0 >= capMs)
            return false
        Sleep(35)
    }
    return false
}

_Diff(a, b) {
    dr := Abs(((a >> 16) & 0xFF) - ((b >> 16) & 0xFF))
    dg := Abs(((a >> 8) & 0xFF) - ((b >> 8) & 0xFF))
    db := Abs((a & 0xFF) - (b & 0xFF))
    return Max(dr, Max(dg, db))
}

; True only when the Roblox client itself owns the foreground. Used to stop the
; macro from typing into another program if the user alt-tabs away.
_GameFocused() {
    hwnd := WinActive("A")
    if (!hwnd)
        return false
    try {
        return (ProcessGetName(WinGetPID("ahk_id " . hwnd)) = "RobloxPlayerBeta.exe")
    } catch {
        return false
    }
}

; =====================================================================
;  DIAGNOSTICS
; =====================================================================
; Screen capture on a hardware-accelerated or exclusive-fullscreen surface can
; return a uniform black rectangle for every pixel, which silently destroys
; every colour test. Detect it and say so rather than reporting "all good".
_VisionReport(*) {
    global Watches, Opt

    WinGetPos(&wx, &wy, &ww, &wh, "A")
    if (ww = "" or ww <= 0) {
        MsgBox("No foreground window to sample.", "Vortex Vision", "Icon!")
        return
    }

    distinct := Map()
    loop 5 {
        ix := A_Index
        x := wx + (ww * ix) // 6
        loop 5 {
            iy := A_Index
            distinct[PixelGetColor(x, wy + (wh * iy) // 6, "RGB")] := true
        }
    }

    txt := "Screen capture: "
    if (distinct.Count <= 2) {
        txt .= "NOT USABLE`n"
            . "  Only " . distinct.Count . " distinct colour(s) across 25 samples.`n"
            . "  Hardware-accelerated or exclusive-fullscreen surfaces often return`n"
            . "  black for every pixel. Run Roblox WINDOWED or BORDERLESS.`n"
            . "  If it still fails, try a 32-bit AutoHotkey host - Natro Macro ships`n"
            . "  AutoHotkey32.exe for exactly this reason.`n"
    } else {
        txt .= "working (" . distinct.Count . " distinct colours in 25 colour samples)`n"
    }

    txt .= "`nDisplay scale must be 100% (96 DPI), or every coordinate is off by`n"
    txt .= "the scaling factor and every watch point lands on the wrong pixel.`n"

    txt .= "`nWatch points (change tolerance " . Opt["changeTol"] . "):"
    for n in WatchOrder {
        if Watches.Has(n) {
            w := Watches[n]
            txt .= "`n  [x] " . n . "   at " . w.x . "," . w.y
        } else {
            txt .= "`n  [ ] " . n . "   unset - fixed timing"
        }
    }

    txt .= "`n`nF3 = live pixel readout     F4 = mark next point     F6 = clear"
    MsgBox(txt, "Vortex Vision", "Iconi")
}

_Log(msg) {
    global LogFile, UI
    line := FormatTime(A_Now, "HH:mm:ss") . "  " . msg
    try FileAppend(line . "`r`n", LogFile)
    if (UI.Has("log"))
        UI["log"].Value := line . "`r`n" . UI["log"].Value
}

; =====================================================================
;  CONFIG
; =====================================================================
_EnsureSettingsDir() {
    global SettingsDir
    if !DirExist(SettingsDir)
        DirCreate(SettingsDir)
}

_LoadConfig() {
    global CfgFile, Caps, Opt, FreshConfig, ActiveLocation, Locations
    FreshConfig := !FileExist(CfgFile)
    if (FreshConfig)
        return
    loc := IniRead(CfgFile, "options", "location", "")
    if (loc != "" and loc != "ERROR" and _InLocations(loc))
        ActiveLocation := loc
    for k, v in Caps {
        got := IniRead(CfgFile, "caps", k, "")
        if (got != "" and got != "ERROR")
            Caps[k] := Integer(got)
    }
    for k, v in Opt {
        got := IniRead(CfgFile, "options", k, "")
        if (got != "" and got != "ERROR")
            Opt[k] := Integer(got)
    }
}

_SaveConfig() {
    global CfgFile, Caps, Opt, UI, ActiveLocation

    ; pull the edit fields back in first
    for k, ctrl in UI {
        if (SubStr(k, 1, 2) = "e_") {
            key := SubStr(k, 3)
            val := Trim(ctrl.Value)
            if (val ~= "^\d+$") {
                if Caps.Has(key)
                    Caps[key] := Integer(val)
                else if Opt.Has(key)
                    Opt[key] := Integer(val)
            }
        }
    }
    if UI.Has("cbAdapt")
        Opt["adaptCaps"] := UI["cbAdapt"].Value
    if UI.Has("cbTop")
        Opt["alwaysOnTop"] := UI["cbTop"].Value
    if UI.Has("cbHide")
        Opt["hideWhileRunning"] := UI["cbHide"].Value
    if UI.Has("cbRecon")
        Opt["autoReconnect"] := UI["cbRecon"].Value
    if UI.Has("cbGuard")
        Opt["guardInput"] := UI["cbGuard"].Value
    if UI.Has("cbManual")
        Opt["useManual"] := UI["cbManual"].Value

    for k, v in Caps
        IniWrite(v, CfgFile, "caps", k)
    for k, v in Opt
        IniWrite(v, CfgFile, "options", k)

    SetKeyDelay(Opt["keyDelay"], 20)
    IniWrite(ActiveLocation, CfgFile, "options", "location")
    _ApplyOpts()
    _Log("Configuration saved to " . CfgFile)
}

; =====================================================================
;  MAPS  (one file per location in <root>\maps\)
; =====================================================================
_MapFile(name) {
    global MapsDir
    return MapsDir . "\" . name . ".ini"
}

_EnsureMapsDir() {
    global MapsDir
    if !DirExist(MapsDir)
        DirCreate(MapsDir)
}

; The folder listing IS the location list, so the user adds a location by adding
; a file. Missing defaults are written once so a fresh install has something to
; pick from; after that the folder belongs to the user.
_LoadMaps() {
    global MapsDir, Locations, DefaultLocations
    _EnsureMapsDir()

    Locations := []
    loop files, MapsDir . "\*.ini" {
        name := SubStr(A_LoopFileName, 1, -4)
        if (name != "")
            Locations.Push(name)
    }

    if (Locations.Length = 0) {
        for name in DefaultLocations {
            f := MapsDir . "\" . name . ".ini"
            IniWrite(name, f, "map", "name")
        }
        for name in DefaultLocations
            Locations.Push(name)
    }
}

; Read each known watch point explicitly. Reading a whole section relies on
; IniRead's omitted-Key behaviour, which does not work when the argument is
; passed as an empty string -- it is looked up as a literal key and returns
; nothing, silently leaving every point uncalibrated.
_LoadWatches() {
    global Watches, ActiveLocation
    Watches := Map()
    f := _MapFile(ActiveLocation)
    if !FileExist(f)
        return
    for name in WatchOrder {
        v := IniRead(f, "watch", name, "")
        if (v = "" or v = "ERROR" or !InStr(v, ","))
            continue
        pts := StrSplit(v, ",")
        if (pts.Length < 2)
            continue
        Watches[name] := { x: Integer(pts[1]), y: Integer(pts[2]) }
    }
}

_SaveWatch(name, x, y) {
    global ActiveLocation
    IniWrite(x . "," . y, _MapFile(ActiveLocation), "watch", name)
}

_ClearWatches() {
    global Watches, ActiveLocation
    f := _MapFile(ActiveLocation)
    for name in WatchOrder
        IniWrite("", f, "watch", name)
    Watches := Map()
    _Log("Watch points cleared for " . ActiveLocation . " - these steps are back to fixed timing.")
    _RefreshVisionTab()
    _SetLocPanelStatus(0, "")
    _RefreshUI()
}

_NextUnsetWatch() {
    global Watches
    for n in WatchOrder
        if !Watches.Has(n)
            return n
    return ""
}

; =====================================================================
;  LOCATION SELECTOR
; =====================================================================
_InLocations(name) {
    for l in Locations
        if (l = name)
            return true
    return false
}

; Subsequence match, so "rcs" finds "Rubble Creek Sands".
;
; Do NOT use InStr's StartingPos argument here. Measured on this AHK build
; (v2.0.28), InStr("rubble creek sands", "c", false, 1, 2) returns 0 even
; though 'c' sits at index 8; the same call with StartingPos omitted returns 8.
; Searching a SubStr slice and advancing by the RELATIVE offset is correct and
; does not depend on that argument behaving.
_Subseq(hay, needle) {
    h := StrLower(hay)
    pos := 1
    for ch in StrSplit(StrLower(needle)) {
        if (pos > StrLen(h))
            return false
        rel := InStr(SubStr(h, pos), ch, false)
        if (!rel)
            return false
        pos += rel
    }
    return true
}

_FilterLocations() {
    global UI, Locations
    if !UI.Has("loclist")
        return
    needle := UI.Has("search") ? Trim(UI["search"].Value) : ""
    lb := UI["loclist"]
    lb.Delete()

    shown := []
    for loc in Locations {
        if (needle = "" or InStr(loc, needle, false) or _Subseq(loc, needle))
            shown.Push(loc)
    }
    if (shown.Length)
        lb.Add(shown)

    _SetLocPanelStatus(shown.Length, needle)
}

_ShowAllLocations() {
    global UI
    if UI.Has("search")
        UI["search"].Value := ""
    _FilterLocations()
}

_SetLocPanelStatus(shown, needle) {
    global UI, ActiveLocation, Watches
    if !UI.Has("locNow")
        return
    n := 0
    for name in WatchOrder
        if Watches.Has(name)
            n += 1
    txt := "ACTIVE`n" . ActiveLocation . "`n`n"
    txt .= (n > 0) ? (n . "/4 watch points`nmarked") : "auto vision -`nnothing to mark"
    if (needle != "") {
        ; A filter that matches nothing empties the list, which reads as "the map
        ; list is broken". Say so plainly instead of leaving a blank box.
        txt .= (shown = 0) ? "`n`nNO MATCHES -`npress Show all" : "`n`nmatch: " . shown . "/" . Locations.Length
    }
    UI["locNow"].Text := txt
}

; Fires as soon as the highlight moves. Cheap, so the Vision tab always matches
; whatever is highlighted.
_PickLocation() {
    global UI, LocArmed
    if !LocArmed
        return                     ; the selection Windows reports as the list first paints
    if !UI.Has("loclist")
        return
    _SetLocation(UI["loclist"].Text, false)
}

; The ListBox fires a Change event the first time it paints, selecting row 1 of
; whatever is in it. That selection used to run _PickLocation and silently replace
; the saved location - and with it the saved route - about a second after startup.
; Locations are only accepted from a deliberate action once the window has settled.
_ArmLocations() {
    global LocArmed
    LocArmed := true
}

; The Select Map button, a double-click, or Enter in the search box. Unlike a
; bare highlight this always confirms out loud, even when the location is
; already the active one, so pressing it never looks like it did nothing.
_SelectMap() {
    global UI
    if !UI.Has("loclist")
        return
    sel := UI["loclist"].Text
    if (sel = "") {
        _SetStatus("NO LOCATION HIGHLIGHTED", "cFF6B4A")
        return
    }
    _SetLocation(sel, true)
}

_SetLocation(name, force) {
    global ActiveLocation, CfgFile
    if (name = "" or !_InLocations(name))
        return
    if (!force and name = ActiveLocation)
        return
    ActiveLocation := name
    _LoadWatches()
    _RouteLoad()
    IniWrite(name, CfgFile, "options", "location")
    _RefreshVisionTab()
    _SetLocPanelStatus(0, "")
    _RefreshUI()
    _Log("Location set to " . name . " - " . _CalibSummary())
    _SetStatus("MAP: " . name, "c8FA0C0")
}

_GoToVisionTab() {
    global UI
    if UI.Has("tab")
        UI["tab"].Value := 4   ; 1 Map, 2 Status, 3 Settings, 4 Vision, 5 Log
}

; =====================================================================
;  HOTKEYS
; =====================================================================
F1:: _OnStart()
F2:: _OnPause()
F3:: _ToggleReadout()

F4:: { ; mark the next unset watch point at the cursor
    name := _NextUnsetWatch()
    if (name = "") {
        ToolTip("All watch points are set. F6 clears them.")
        SetTimer(() => ToolTip(), -2500)
        return
    }
    _MarkWatch(name)
    ToolTip("Marked [" . name . "]`n" . WatchHelp[name])
    SetTimer(() => ToolTip(), -3000)
}

F5:: _VisionReport()
F6:: _ClearWatches()
; F7 records a route: press once to start, play the loop by hand, press again to
; stop and save. F8 replays what was just recorded, once, so the result can be
; checked before committing to a full run.
; F9 is the whole job in two presses - record, then it runs - for anyone who
; does not want to think about locations or separate play keys.
F7:: _RouteToggle()
F8:: _RoutePlayOnce()
F9:: _QuickToggle()

; =====================================================================
;  STARTUP
; =====================================================================
;  Kill every OTHER AutoHotkey process running this same script.
;  Matched on the command line, so any unrelated AutoHotkey scripts the user
;  happens to have are left untouched.
; =====================================================================
_ClosePreviousInstances() {
    selfPid := DllCall("GetCurrentProcessId", "UInt")
    killed := 0

    try {
        for proc in ComObjGet("winmgmts:").ExecQuery(
            "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name LIKE 'AutoHotkey%'") {

            if (proc.ProcessId = selfPid)
                continue

            cmdLine := String(proc.CommandLine)
            if (cmdLine = "" or !InStr(cmdLine, "VortexMacro.ahk"))
                continue

            Run(A_WinDir "\System32\taskkill.exe /F /PID " proc.ProcessId, , "Hide")
            killed += 1
        }
    } catch {
        ; WMI unavailable. launcher.bat guards the same case, so a double
        ; launch still stays a non-event there.
    }

    if (killed)
        Sleep(600)
}
