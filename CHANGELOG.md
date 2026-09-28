# Changelog

## 1.1.1

The first build tested against a **live Roblox session**, rather than synthetic
screens. That test found a bug worth a release on its own.

**A blank screen capture was blamed on your route.** If the game is on
exclusive fullscreen or a hardware-accelerated surface, GDI can hand the macro a
pure-black rectangle. That reads as "the screen never changed", which is exactly
what a broken route looks like — so after three cycles the macro stopped and
told the user to re-record a route that was never the problem.

The capture is now checked for being blank, and that case stops with the real
explanation instead:

```
STOPPED: screen capture is coming back blank (a single flat colour), so the
  macro cannot tell whether the route works. This happens on exclusive
  fullscreen and hardware-accelerated surfaces. Set the game to Windowed or
  Borderless and retry - the route itself is probably fine.
```

Verified against real pixels (`tests/blankcapture_test.ahk`, 4/4): pure black
and near-black surfaces are detected as blank, a normal colour is not, and a
very dark but real UI is not — including this program's own dark theme at
(16,19,23), which is the false positive that would have broken it.

**`run` argument.** `VortexMacro.ahk run` starts the main loop immediately
instead of waiting for F1. It exists because a script cannot press another
script's hotkeys — injected keyboard input is invisible to them — so it was the
only way to exercise a real replay without a human at the keyboard.

**Every route cycle now logs what it measured:**

```
Route cycle moved the screen - max change 9.4 (threshold 3)
```

"It ran but nothing happened" was the hardest failure to diagnose from outside.
Now it is one readable line.

**Verified on the replay path** (`tests/replay_vk_test.ahk`, 16/16): every
stored token presses a real key visible to the OS and releases clean, a 300 ms
hold lands at 312 ms, `MouseMove` lands exactly where asked, relative
coordinates round-trip, and nothing is left held when the replay ends. The test
builds its own window, parks the cursor on it, and restores the previous
foreground window — it injects real input, so it must never run against the
live desktop.

**Also confirmed live:** the foreground guard held input while the game was not
focused and resumed by itself when it was, in a real session rather than a
synthetic window.

## 1.1.0

**Why this build exists.** A tiny free recorder already does plain
record-and-replay, and it does it well. If that is all this did, there would be
no reason to use it. So this release removes the reasons it was harder than
that recorder, and makes the two things that recorder cannot do explicit.

**The recorder no longer has a key list.** It previously watched 17 hard-coded
key names (`w a s d q e f r space shift LButton RButton 1-5`) and silently
recorded nothing at all for any key outside it — which is indistinguishable
from a broken recorder when the key it misses is the one you press. Keys are
now recorded by virtual key code, so nothing can fall outside the sweep.
Measured: all 254 virtual keys cost **0.408 ms per sweep** (500 sweeps in
204 ms), 3.4% of one core at a 10 ms timer, so the list bought nothing.
Verified against real key state with `tests/record_anykey_test.ahk`: `z`,
`Tab`, `F9` and `Enter` — none of which the old list contained — are all
captured, with `w` kept as a control. 6/6 pass.

**Cursor positions are recorded and replayed.** A click only means something at
a position. Every event now stores the cursor position relative to the game's
client area, captured once per recording, so a window that has moved still
replays in the right place. While the game holds the cursor locked this records
the centre and replays to the centre, which is where it already is.

**The release key only releases what it pressed.** The old cleanup released
every key in the key list when a cycle ended, which would also let go of a key
the player was holding. It now tracks exactly what the route pressed and
releases only that.

**`F9` — the whole job in two presses.** The competing recorder needs no setup
at all, and requiring a location to be chosen before recording was a step it
does not have. F9 records on the first press and, on the second, saves the loop
and starts running it immediately. Nothing has to be configured first; the
selected location only decides which route file it is saved into. `F7`/`F8`
remain for anyone who wants to inspect a recording before running it.

**The status line now names the keys it recorded**, so "did it capture what I
did?" is answered directly instead of requiring a replay to find out:

```
route: 12 events, 6.0 s - w, space, LButton
```

**Fixed while doing the above:** the route loader rejected signed numbers, but
cursor positions relative to a window can legitimately be negative, so a route
recorded on a shifted window would have had those positions silently zeroed.

## 1.0.0

First release.

**The macro now does what it claims.** Earlier builds moved forward and back
and never dug, because the built-in steps were a guess at the game's controls.
Keyboard input landed; the mouse action did not. Guessing harder was not going
to fix it, so the input layer was replaced with record and replay: play one
loop by hand, it repeats that loop.

- **Route recorder.** F7 records keys and holds by polling key state, not by
  hooking hotkeys — a script cannot see its own `Send`, which is why the first
  attempt captured zero events. F8 replays once for checking, F1 loops it.
- **Routes are per-location**, stored beside the map data as
  `maps\<Location>.route`, and load automatically when you switch location.
- **Dead-cycle detection.** A blind replay would press keys at a frozen game
  forever. Screen change is measured during each cycle; three cycles in a row
  that change nothing stops the macro and says so. Cycles spent waiting for the
  game to be focused do not count towards that.
- **Foreground guard.** Input is sent only while the game is the active window,
  and every key is released on stop.

**Bugs found and fixed during the audit:**

- `WaitHeld` — a local-variable crash. An assignment anywhere in a function
  makes that name local for the whole function, so a later read hit an
  unassigned local. Found by scanning every function scope for assignments to
  globals that the scope never declared; all 77 scopes now clean.
- **Startup silently overwrote the saved location.** The location list emits a
  change event as it first paints, which fired the handler and replaced the
  saved location roughly a second after launch — loading the wrong route for
  the wrong map, every time.
- **GUI text was clipped with no error.** The tab control's content area ends
  at y548; lines laid out below it never rendered.
- **Replay counted "waiting for the game window" as a dead cycle**, which would
  have stopped the macro with a "recording is broken" message whenever the user
  alt-tabbed away.
- **A damaged route file crashed the app at startup.** The loader called
  `Integer()` on the raw text of each row; `Integer("abc")` throws, and the
  loader runs from the auto-execute section, so an error there means a dialog
  and no start at all — for a file the user is invited to open and edit.
  The loader now skips unreadable rows instead of throwing, rejects unknown key
  names and directions, sorts rows that are out of order (previously an
  out-of-order row made the replay collapse the rest of the route into one
  burst), and closes any key that was still held when the recording stopped, so
  a truncated file cannot replay as a key pressed forever. Verified against a
  file containing all five kinds of damage at once: 4 bad rows skipped, 1
  missing release synthesised, app started normally.

**Packaging:**

- `AutoHotkey.exe` was a symlink. Zip archives store symlinks as links and
  Windows' built-in extractor does not recreate them, so the release would have
  shipped a dead interpreter. Both binaries are real files now.
- Added MIT license, third-party attribution for the GPL-2.0 AutoHotkey
  interpreter, and a release builder that verifies what it produced.

**Tooling:**

- `tools/audit_ahk.py` — static checks for calls to undefined functions, dead
  code, duplicate definitions, missing global declarations, and hotkeys bound
  to nothing. Verified against a copy with four deliberately planted bugs; it
  catches all four.
- `tools/check_ahk_globals.py` — the AutoHotkey-specific scoping scan.
- `tests/deadcycle_test.ahk` — proves the stop-on-no-change rule distinguishes
  a frozen screen from a moving one, on real pixels.
