You are picking up an in-progress project with prior work already done. Read this
whole brief before acting. Everything here was verified in the previous session;
where something is NOT verified, it says so explicitly — do not assume more than
what is stated.

================================================================================
THE GAME: "Prospecting" (Roblox)
================================================================================
Mechanics that determine what any automation must do:

DIGGING — a hold, released on a HORIZONTAL gauge
  Hold the left mouse button on diggable ground. A HORIZONTAL gauge appears with a
  moving slider. You must RELEASE so the slider sits inside the GREEN indicator.
  Result: a "Perfect" dig gives 100% material quality and increases the weight and
  value of the find; missing it lowers sand quality and the weight of everything
  after. NOTE: the gauge is horizontal — an earlier session wasted effort hunting a
  vertical slider that does not exist.

  The slider's travel is a function of the player's DIG SPEED stat, so the hold that
  lands in the green can be COMPUTED rather than read off the screen:
      hold_ms = Round(66900 / (digSpeed + 9))     clamped to 60..4000
  That formula comes from the established macro for this game (Orenate). Watching
  the gauge directly would be exact where the formula is an approximation — that is
  the known next improvement.

PANNING — repeated clicks, while standing in water
  Once the pan is filled, the panning minigame triggers. Standing in water, click
  repeatedly to shake the pan; each click advances the shake bar by the pan's SHAKE
  STRENGTH and SHAKE SPEED. The clip count matters more than the timing.

SHOVEL TOUGHNESS GATES THE BIOME — and failure is SILENT
  Every biome has a strict Toughness Level. If the shovel's Dig Strength is below
  the area's requirement, YOU CANNOT EXTRACT ANYTHING from that ground at all. For a
  macro this is the worst failure mode: it walks, it clicks, it digs, it yields
  nothing — indistinguishable from being broken. Progression advice from the game:
  upgrade the SHOVEL first to unlock higher-paying biomes, then the pan for speed
  and luck.

CONTROLS
  WASD walk | Space jump | 1-0 equip tool slot | G backpack | Shift shiftlock
  (camera lock) | I / O zoom in-out.

LUCK is a REROLL, not a percentage: the game rolls a random number (lower = rarer),
rerolls it once per point of Luck, and keeps the rarest result. There is a built-in
decay for common items so they never become impossible.

OTHER SYSTEMS (no macro impact yet, recorded so you don't rediscover them)
  * Prospector Kit: 1 necklace, 1 charm, up to 8 rings. Crafted at a Blacksmith anvil.
  * Glowing Altar, in Rubble Creek Deposits: hold Aurorite/Etherite with the tool
    equipped for a random permanent enchant. Target "Lucky" / "Blessed" (+10 luck).
  * Hidden Crystal Caverns shop: behind the waterfall, gated on Emerald + Diamond +
    Starfire. Sells the Worldshaker Pan and Earth Breaker Shovel.
  * Sluices: placed in moving water, harvest continuously including offline.
  * Treasure maps: equip, then follow the on-screen arrow until it points down.
  * World relics: Rainstone (River Rapids), Solar Token (Solar Flare), Snow Globe
    (blizzard, +5000 Luck), Mythic Summon / Void Shard (11x money, Voidtorn).

TOUGHNESS BY BIOME (from the player; "-" = not stated)
  none: Rubble Creek (T1-2), Spawn, Town, Store, Dock, Sluice Shack
  T3: Sunset Beach | T4: Crystal Cavern River, Fortune River, Fortune River Delta,
  Volcanic Sands | T5: Azuralite Oasis | T7: Fungal Marsh / Wastes

================================================================================
THE PROJECT: VortexMacro
================================================================================
Public repo: https://github.com/athallajovian9-cyber/VortexMacro
Latest release: v1.2.1 (zip attached to the GitHub Release).

An AutoHotkey **v2** macro. It bundles its own interpreter at
submacro/AutoHotkey64.exe, so a user needs no dependencies. It automates one dig →
pan loop on Prospecting, driven by per-map path files.

ARCHITECTURE
  maps/<Location>.path     One symbolic file per map. THE central design decision:
                           a map's loop is editable TEXT, not compiled code.
  maps/<Location>.ini      Per-map watch points (x,y screen samples).
  maps/<Location>.route    An optional recorded replay; takes priority over .path.
  maps/tiers.ini           Biome -> Toughness table, used by the tier gate.
  maps/locations.ini       Canonical in-game location list + aliases.
  submacro/VortexMacro.ahk The whole macro (~2,700 lines).
  templates/               PNGs for `await` / `clickimg`.
  tools/build_release.py   Builds and byte-verifies the release zip.
  GAME_MECHANICS.md        The mechanics above, in-repo.

PATH FILE DIRECTIVES
  step  <key> <watch> <cap>   hold a key until the screen changes at a watch point
  hold  <key> <ms>            hold a key for a fixed time
  dig                         hold left mouse; duration from the Dig Speed stat
  click [n]                   click left mouse n times
  clickimg <name> [tol]       click a template wherever it appears (AHK ImageSearch)
  await   <name> <cap-ms>     block until a template appears
  wash                        legacy multi-click wash
  release                     release every key a cycle might have left held
  wait    <ms>                pause
  ";" starts a comment, including mid-line.

CYCLE PRIORITY: recorded route > path file > built-in step sequence.

WATCH POINTS
  Four per map: at_node, dig_done, at_water, wash_done. A `step` ends when its watch
  point changes on screen; with none marked it falls back to a "scene settled" test
  over a 32x18 capture grid. There is also an auto-watch learner that watches one
  dig cycle and keeps the cells that change RARELY BUT SHARPLY (HUD indicators),
  rejecting scenery — HUD cells flip once or twice a cycle, scenery churns.

TESTS — run these after any change
  submacro/_path_test.py       parser + shipping-file assertions. Extracts functions
                               VERBATIM from VortexMacro.ahk, so it tests the real code.
  submacro/_verify_paths.py    parses all maps/*.path
  submacro/_audit.py           builtin-name collisions, ByRef call sites, duplicate
                               definitions, parser/executor directive coverage, leftover
                               AHK v1 syntax

================================================================================
TRAPS — all of these bit the previous session. Read them before editing.
================================================================================
1. A parse check does NOT prove the script runs. `Ahk2Exe` compiles happily even when
   the script throws on execution. Real example: `ceil := Caps[key]` — `Ceil()` is an
   AHK v2 builtin, so assigning to that name throws "This Func cannot be used as an
   output variable" the moment it runs. Ahk2Exe never complained.
2. AHK v2 ByRef needs `&` at the CALL SITE as well as in the declaration.
   `F(&out)` + a call `F(x)` leaves `x` unassigned; you get only a load-time warning,
   and the caller then does arithmetic on nothing.
3. `Map.Delete(key)` THROWS on a missing key ("Item has no value"). Guard with `.Has()`.
   A recorded route legitimately OPENS with a release (the hotkey that stopped the
   previous recording), so an unguarded delete aborts the whole load.
4. Loaders must be called at STARTUP, not only when something changes. A loader
   reached only from a `SetLocation`-style function that early-returns on "no change"
   means a normal launch reads nothing, and the UI honestly reports "none".
5. A name is not a location. If a folder scan treats every file of an extension as an
   entry, data files placed there become selectable options.
6. Renaming a location orphans its data. The macro derives EVERY filename from the
   location name, so renaming the map but not its .route silently reverts to "no
   route" and loses a recording.
7. Trailing comments: strip `;`-to-end-of-line BEFORE tokenising, or a bare directive
   followed by a comment parses as `directive ;` and is rejected.
8. Verify your own verifier. Two audit passes in the previous session reported "0
   problems" while being unable to see the bug: one compared ByRef args positionally
   from index 0, another only matched calls at the start of a line when every real
   call sat inside `if (...)`. A scan must (a) find the known instances and (b) fail on
   a deliberately broken input, or its clean verdict is worthless.
9. Never run this macro while the user may be in another game — it injects real
   keystrokes into the focused window. The macro has a foreground guard
   (`guardInput`); do not disable it.
10. Never hand-edit Hermes config.yaml — use the CLI. (Only relevant if you are a
    Hermes agent.)

================================================================================
WHAT IS NOT VERIFIED — be honest about this
================================================================================
The sequence has NEVER been validated in-game. Tests cover the parser, the file
format, the tier gate and the route loader — not whether the walks, the dig hold and
the panning clicks actually land in Prospecting. Do not claim it works.

OPEN QUESTIONS
  * Location granularity. The game's list gives zones ("Rubble Creek, Toughness 1
    & 2"); the reference macro has separate per-deposit routes (RUBBLE CREEK SANDS,
    RUBBLE CREEK DEPOSITS). Zone-level was confirmed for one case (the in-game name
    is "Snowy Mountain", singular) but the merge across all maps is not done.
  * The player's actual DIG SPEED stat. The path files assume 100. If digs land early
    or late, this number is what to change — set it per line (`dig 140`).
  * The location list is probably incomplete: names such as Snowy Shores, Dock,
    Underground Maze, Waterfall Temple, Infernal Heart, Deeproot Spring and Haunted
    Creek are unconfirmed.

================================================================================
WHAT TO DO
================================================================================
1. Get the macro running end to end in-game before adding anything. Read
   settings/vortex_session.log afterwards: it reports which mode loaded and, each
   cycle, "Route cycle moved the screen - max change N". A max change near zero means
   the replay is firing but the game is not responding.
2. Then, in priority order:
   a. Set the Dig Speed stat so the dig hold is correct.
   b. Validate the walks in one or two maps, then propagate the fix across all 37.
   c. Finish the zone-vs-deposit-area reconciliation of the location list.
3. The single most valuable improvement available: replace the formula-based dig with
   one that WATCHES the horizontal gauge and releases in the green. `await` /
   `clickimg` (AHK ImageSearch) already exist as the pattern for screen-driven steps.

WORKING STYLE FOR THIS PROJECT
  * Verify before asserting. Measure, read the raw output, and say what is unverified.
  * Prefer one correct answer over a list of options.
  * A tool that guesses is worse than no tool at all.
  * Report what you actually did, including bugs you introduced and then fixed.
