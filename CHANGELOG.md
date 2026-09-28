# Changelog

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
