# VortexMacro

A macro for the Roblox game **Prospecting**. You play one loop by hand and it
repeats exactly that loop, for as long as you leave it running.

Most game macros make you guess at the controls, or drag image-recognition
boxes over buttons that move the next time the UI updates. This one does
neither. It records what you actually did — which keys, in what order, held
for how long — and plays it back. When it has nothing recorded, it falls back
to a small set of built-in steps driven by watching the screen change.

---

## Read this first

Two things are true and neither is a formality.

**1. Automating the game is against Roblox's rules.** Using a macro can get
your account banned. That is the deal. If that risk is not acceptable to you,
do not use this.

**2. This is a tool for one player's own session.** It is not an exploit, it
does not touch the game's memory, and it does not talk to the game in any way
a keyboard does not. It presses the same keys you press. But it is still
automation, and automation is what the rules are about.

**Use it on your own account, at your own risk.**

---

## What it does

- **Records a route and replays it.** Press F7, play your loop once by hand,
  press F7 again. Press F8 to watch it replay that loop once. Press F1 to run
  it forever.
- **One route per location.** Routes live next to the map data as
  `maps\<Location>.route` and load automatically when you pick that location.
- **Knows when to stop.** If three cycles in a row change nothing on screen —
  you got stuck, a mob pinned you, the game hung — it stops and tells you,
  instead of pressing keys at nothing all night.
- **Never types into the wrong window.** Input is only ever sent while the
  game is the foreground window. Alt-tab away and it waits. Come back and it
  carries on. This is on by default and is not a setting to casually turn off.
- **Releases every key when it stops.** A panic stop cannot leave a movement
  key held down.

## Requirements

- Windows 10 or 11, 64-bit
- Roblox, running the game **windowed or borderless** — not exclusive
  fullscreen, which can block screen capture
- Nothing else. The [release zip](../../releases) includes the AutoHotkey
  interpreter, so there is nothing to install.

## Install

1. Download `VortexMacro-<version>.zip` from
   [Releases](../../releases).
2. Extract it anywhere — Desktop, a folder, a USB stick. No installer, no
   admin rights, no registry entries.
3. Double-click `launcher.bat`.

Extract it *before* running. Running `launcher.bat` from inside the zip
archive will not work, and Windows will not warn you why.

## Quick start

```
1.  Double-click launcher.bat
2.  Pick your location on the Map tab
3.  Get in game, stand where you want the loop to begin
4.  Press F7              <- recording starts
5.  Play one full loop by hand, then press F7 again
6.  Press F8              <- replays it once so you can check it
7.  Press F1              <- runs it until you press F2
```

Full walkthrough with the reasoning behind each step is in `README.txt`.

### Keys

```
F1    start / resume             F5    vision self-test
F2    pause / stop               F6    clear watch points
F3    live pixel readout         F7    start / stop recording
F4    mark next watch point      F8    play the recorded route once
                                 Tray  right-click to exit
```

## How it decides what to do

1. **Route replay** — if `maps\<Location>.route` exists, it is replayed.
2. **Auto vision** — otherwise the built-in steps run, and each step ends when
   the screen stops changing rather than after a fixed guessed delay.

A recorded route always wins, because it is the only one of the two that knows
what the game's controls actually are.

## Limits, honestly

- **Routes are timing, not understanding.** Replay repeats your timing. If the
  game hitches mid-cycle, or your character gets shoved, the rest of that cycle
  is mistimed. The next cycle starts clean.
- **A route only fits the spot it was recorded from.** Start the loop anywhere
  else and it will not line up.
- **Synthetic input is not guaranteed to be accepted.** Roblox runs anti-cheat
  that can refuse injected keystrokes. If F8 replays but nothing happens in
  game, that is the cause, and no amount of macro fixing will change it.
- **Screen capture can return black** on exclusive-fullscreen. Use windowed or
  borderless. F5 samples the screen and tells you if this is happening.
- **No route ships with the project.** Routes encode one player's run, so each
  person records their own. Until you record one, the built-in steps run, and
  they are a guess.

## What's in here

```
launcher.bat              starts it: closes old instances, finds the game,
                          launches the macro
README.txt                the full tutorial, written for the person using it
submacro/VortexMacro.ahk  the macro itself
submacro/AutoHotkey*.exe  the interpreter (release zip only)
maps/                     37 locations, one .ini each
maps/<Location>.route     your recordings (created by you, not shipped)
assets/                   icon and screenshot
tests/                    standalone checks you can double-click
tools/                    development scripts that need Python
licenses/                 third-party license texts
```

## Tests

Each test is a standalone script. Double-click one, read the PASS/FAIL lines,
and it exits. Worth re-running after a Windows or Roblox update.

```
vision_test.ahk          pixel-reading primitives
settletest.ahk           "does it notice when the screen stops changing"
scene_capture_test.ahk   can the screen be captured at all
deadcycle_test.ahk       "does it notice a route that stopped working"
```

The two Python tools in `tools/` are static checks over the source, for
development:

```
tools/audit_ahk.py         calls to undefined functions, dead code, duplicate
                           definitions, missing global declarations, hotkeys
                           bound to nothing
tools/check_ahk_globals.py scoping bugs specific to AutoHotkey functions
```

Run either with a path to the script:

```
python tools/audit_ahk.py submacro/VortexMacro.ahk
```

Both exit non-zero if they find anything, so they can gate a release.

## Credits

- Interpreter: [AutoHotkey](https://www.autohotkey.com) v2, GPL-2.0 — see
  `THIRD-PARTY.md`.
- Location list cross-checked against the community wiki.

## License

VortexMacro's own code is MIT — see `LICENSE.txt`. That does not cover the bundled
AutoHotkey interpreter, which keeps its own license.
