====================================================================
  VORTEX MACRO  -  PROSPECTING (Roblox)
  Portable. No installer. No dependencies to install.
====================================================================

This macro digs and washes for you in the Roblox game "Prospecting!".
You play the loop once while it records (F7), and from then on it
replays exactly what you did - so you never have to mark anything,
and it cannot get the controls wrong.

Until you record a route it falls back to a built-in step sequence.
That sequence is only a guess at the game's controls, so treat it as
a placeholder and record a route before expecting a real harvest.


--------------------------------------------------------------------
  HOW TO START
--------------------------------------------------------------------

  1. Double-click  launcher.bat
  2. Wait for the black window to say "READY".
     It starts the macro and opens Roblox at the same time.
  3. In the Roblox window, get yourself to the spot you want to
     farm. Stand where the macro should begin.
  4. Press F9, play ONE full loop by hand, then press F9 again.

  That is the whole setup. F9 saves the loop and starts running it
  immediately. Nothing to configure first - not even the location.

  The full recording walkthrough is under "RECORDING A ROUTE" below.
  F7 and F8 still work if you would rather check a recording before
  running it: F7 records, F8 replays it once, F1 runs it.

  That's it. The macro GUI window closes itself while it runs (this
  is normal - it hides so it doesn't get in your way). Bring it back
  by pressing F2.

  If the game is not focused when you press F1, nothing bad happens:
  the macro refuses to send keys to a window that isn't Roblox. See
  "Only send input while Roblox is the active window" below.


--------------------------------------------------------------------
  RECORDING A ROUTE  (do this before trusting the macro)
--------------------------------------------------------------------

  The built-in step sequence is a guess at the game's controls. It was
  written by assuming which key digs and how long that takes. If the
  guess is wrong, the macro walks around and never digs - which is
  exactly what "it just moves forward and back" looks like.

  A recording cannot get it wrong, because it is your own input:

    1. Stand where the macro should start.
    2. Press F7.  The status line shows RECORDING ROUTE.
    3. Play ONE full loop by hand, exactly the way you want it
       repeated forever: dig, walk back, wash, walk to the start
       again. Do not press F1 or F2 while recording.
    4. Press F7 again.  The macro saves it and switches to
       ROUTE REPLAY.

  Press F8 to watch it replay what you just recorded, once, before
  you commit to a long run. If it looks right, press F1 and let it
  loop. If it does not, press F7 and record again - it overwrites.

  What gets recorded: W A S D, Q E F R, Space, Shift, the left and
  right mouse buttons, and the number keys 1-5. Every press and
  release is stored with its real timing, accurate to about 10 ms.

  Routes are stored per location, beside the map file, so each map
  keeps its own recording. Switching location loads that map's route
  automatically. "Clear route" on the Map tab deletes it.

  While a route is replaying, the macro still refuses to send input
  unless Roblox is the active window, and it pauses the replay rather
  than skipping ahead if you alt-tab away.


--------------------------------------------------------------------
  CONTROLS  (these work anywhere, even in-game)
--------------------------------------------------------------------

  F9    RECORD AND RUN - press, play the loop once, press again.
        It saves the loop and starts running it straight away.
        This is the whole job in two presses.

  F7    record a route only - press, play the loop, press again to save
  F8    replay the recorded route once, to check it before running

  F1    start the macro
  F2    pause / stop the macro (and bring the GUI back)

  F3    live pixel readout  - for checking that vision can see
  F4    mark the next watch point (optional, see the Vision section)
  F5    vision status / self-test
  F6    clear all watch points for the current location

  The tray icon (green "H" near the clock) - right-click, then Exit,
  to shut the macro down completely.

  F1 does not toggle. If the macro is already running, F1 does
  nothing. Use F2 to stop.


--------------------------------------------------------------------
  THE FIVE TABS
--------------------------------------------------------------------

  MAP
    The list of locations. Highlight one, then press "Select Map".
    (Double-clicking the item does the same, and so does typing in
    the search box and pressing Enter.)

    The search box filters as you type. Typing "riv" finds every
    location with those letters in order - so "sny" finds
    "Snowy Mountains" even without perfect spelling.

    If nothing matches, the list goes EMPTY and the panel says
    "NO MATCHES - press Show all". That is the filter working, not a
    broken list. "Show all" clears it and brings back all 37.

    Selecting a location changes WHICH settings load - it does not
    move your character. You still walk to the spot yourself.

  STATUS
    Session time, how many cycles have run, and the last/average
    cycle time. Below that, the measured time for each of the four
    steps, so you can see what the macro is actually doing.

  SETTINGS
    Step ceilings - the maximum time a step may take. These are
    limits, not delays: a step normally ends earlier than this.
    Behaviour - change tolerance and key/click delays.
    The checkboxes at the bottom, including "Save settings".

  VISION
    Watch points (optional) and the auto vision controls.
    Contains "Test auto vision" - see TUNING below.

  LOG
    A running list of what the macro did, with timestamps.
    Also written to settings\vortex_session.log


--------------------------------------------------------------------
  HOW THE MACRO DECIDES WHAT TO DO
--------------------------------------------------------------------

  ROUTE REPLAY  (used whenever the location has a recording)

    The macro sends exactly the keys and clicks you recorded, at
    exactly the times you sent them. Nothing is interpreted and
    nothing is guessed - it is your own loop, repeated.

    A replay pauses rather than skips ahead if you alt-tab away, and
    every key is released when the route ends, so a button can never
    be left stuck down.

    It also checks its own work. Replaying timing alone is blind: if
    your character gets stuck, or the game stops responding, it would
    keep pressing keys at nothing for hours. So the macro watches the
    screen during every cycle. If three cycles in a row change nothing
    on screen, it stops and says so instead of farming nothing - you
    then record the route again from the right spot. Waiting for you to
    alt-tab back does not count towards those three.

  AUTO VISION  (used by the built-in steps, when there is no route)

    The built-in steps end on screen changes instead of fixed
    timings. Every one of them ends in a state where the screen
    stops changing:

      walk to the node  -> the view stops scrolling when you arrive
      dig               -> the pan fills, then stops updating
      wash              -> the pan stops changing when it is clean

    So the macro samples the game window many times a second and ends
    the step as soon as the picture goes quiet. Nothing to mark,
    nothing to measure, nothing to configure.

    Two limits keep this safe:
      floor    - a step is never ended before roughly half its usual
                 time, so a still moment at the start can't cut the
                 step short
      ceiling  - a step never runs past the time on the Settings tab

    If the screen is too busy to ever look quiet, steps simply run to
    their ceiling, and the macro behaves like a normal timed macro.
    It degrades safely rather than breaking.

  WATCH POINTS  (optional, more precise)

    If you want exact timing, you can mark a spot on screen that
    changes colour at the moment a step finishes. The macro then ends
    the step the instant that pixel changes.

    This is optional. The macro ships set to ignore watch points.
    To use them, tick "Prefer marked watch points" on the Vision tab.

  SELF-TUNING

    Each step measures how long it really took and adjusts its
    ceiling around that. Over a few cycles the ceilings converge on
    the true timings for your hardware and connection, instead of
    running on hard-coded guesses.


--------------------------------------------------------------------
  DO I NEED TO MARK ANYTHING?
--------------------------------------------------------------------

  No. Nothing needs marking, ever.

  The status bar at the top tells you which mode is active:

    "ROUTE REPLAY - 8 events, 3.2 s"
        a route is recorded and will be used - this is what you want

    "NO ROUTE YET - press F7, play the loop once, press F7 again"
        no recording exists for this location, so the built-in steps
        run instead

  Watch points still exist if you want pixel-exact timing for the
  built-in steps, but they are never required.


--------------------------------------------------------------------
  IF YOU DO WANT TO MARK POINTS
--------------------------------------------------------------------

  IMPORTANT: click your desktop first so Roblox is NOT focused.
  While the game is focused it locks the mouse to the centre of the
  screen, so every point you mark would land in the middle.

  Then, for each of the four rows on the Vision tab:
    1. Put the cursor on the spot that changes when the step is done
    2. Press F4 (or click "Mark at cursor")

  The four points, in order:
    at_node    the dig site - something different once you arrive
    dig_done   whatever changes when your pan is FULL
    at_water   the water/sluice - different once you arrive
    wash_done  whatever changes when your pan is CLEAN

  Watch points are stored per location, so each map keeps its own.
  Switching locations does not wipe the others.


--------------------------------------------------------------------
  TUNING AUTO VISION
--------------------------------------------------------------------

  Open the Vision tab and click "Test auto vision" while the game is
  doing something. It samples for three seconds and reports the
  smallest, average, and largest amount of change it saw.

  It then tells you which of these you are in:

    - "Good: the scene goes quiet and moves"  -> working correctly
    - "The screen NEVER looks still"          -> raise "Still threshold"
                                                 to about the reported
                                                 minimum value
    - "NOTHING IS BEING CAPTURED"             -> see TROUBLESHOOTING

  The three numbers on the Vision tab:
    Sample every (ms)       how often to look at the screen
                            lower = reacts faster, more CPU
    Still threshold         how little change counts as "quiet"
    Still polls in a row    how many quiet samples in a row count as
                            "finished". Higher = more certain, slower.


--------------------------------------------------------------------
  ADDING OR REMOVING A LOCATION
--------------------------------------------------------------------

  Every location is one file in the  maps  folder. The folder listing
  IS the menu - there is no list to edit anywhere else.

    To add:    create a new file in  maps  and name it after the
               location, e.g.  maps\My Spot.ini

    To remove: delete the .ini file.

  Restart the macro (or just reopen the Map tab) and the new location
  appears. A fresh install writes 37 default locations; after that
  the folder is yours.


--------------------------------------------------------------------
  FILES AND FOLDERS
--------------------------------------------------------------------

  launcher.bat              double-click this to start everything
  README.txt                this file

  submacro\
    AutoHotkey.exe          the macro engine (portable, nothing
                            installed on your PC)
    AutoHotkey32.exe        32-bit engine - try this if screen
                            reading returns black
    AutoHotkey64.exe        64-bit engine, used by default
    VortexMacro.ahk         the macro itself (plain text - readable
                            and editable)

  maps\                     one .ini per location (37 by default)
                            one .route per location you have recorded
  settings\
    vortex_config.ini       your saved settings
    vortex_session.log      what the macro did, with timestamps
  assets\
    vortex.ico / .png       the icon
  tests\
    vision_test.ahk         screen-reading tests
    settletest.ahk          "does it notice when the screen stops"
    scene_capture_test.ahk  screen capture tests
    deadcycle_test.ahk      "does it notice a stuck route"
    check_ahk_globals.py    checks the script for a class of AHK
                            scoping bug (optional, needs Python)

  Nothing is installed anywhere else on your PC. To move the macro,
  move or copy this whole folder.


--------------------------------------------------------------------
  REQUIREMENTS
--------------------------------------------------------------------

  - Windows 10 or 11
  - Roblox, running WINDOWED or BORDERLESS (not exclusive
    fullscreen - see TROUBLESHOOTING)
  - Windows display scaling at 100%
    (Settings > System > Display > Scale)
    At other scales the macro's screen coordinates drift.

  Nothing else. There is no installer and no runtime to download.


--------------------------------------------------------------------
  TROUBLESHOOTING
--------------------------------------------------------------------

  "It just walks forward and back and never digs"
    No route is recorded for this location, so the built-in steps are
    running - and those only guess at the game's controls. Press F7,
    play one loop by hand, press F7 again. See RECORDING A ROUTE above.

  The status bar shows "ROUTE NOT WORKING - RECORD IT AGAIN"
    Three cycles in a row changed nothing on screen, so the macro
    stopped instead of farming nothing. Usually the character is
    standing somewhere the recorded route no longer fits. Press F7 and
    record it again from the right starting spot.

  The status bar shows "CHECK <name>"
    That watch point has hit its ceiling three cycles in a row, so
    it probably no longer points at anything useful. Re-mark it, or
    untick "Prefer marked watch points" to go back to auto vision.

  "Vision self-test" says the screen is black / it can't read pixels
    Roblox must be WINDOWED or BORDERLESS. Exclusive fullscreen and
    some hardware-accelerated surfaces give back black for every
    pixel. If it still fails, close the macro and run the 32-bit
    engine instead - see FILES AND FOLDERS above.

  Keys are going into the wrong window
    Turn ON "Only send input while Roblox is the active window" on
    the Settings tab (it is on by default). With it on, the macro
    holds its input whenever Roblox is not focused, so an accidental
    start cannot spray keystrokes into another program.

  Nothing happens when I press F1
    Make sure Roblox is the active window and the macro is not
    already running. Check the Log tab - every start is recorded
    with the window that had focus at the time.

  "A previous macro instance would not close"
    Right-click the tray icon (green H near the clock), choose Exit,
    then run launcher.bat again.

  The macro window disappeared
    That is intentional - it hides itself while running so it stays
    out of the way. Press F2 to bring it back.

  It stopped sending input partway through
    Something took focus away from Roblox. Click the game window
    again; the macro resumes on its own.


--------------------------------------------------------------------
  RUNNING THE TESTS
--------------------------------------------------------------------

  You can double-click any file in the tests folder to re-check that
  screen reading still works on this PC. Each one prints PASS/FAIL
  lines and exits. Useful after a Windows or Roblox update.

  vision_test.ahk          checks the pixel-reading primitives
  settletest.ahk           checks that a still screen is detected
  scene_capture_test.ahk   checks that the screen can be captured
  deadcycle_test.ahk       checks the "route stopped working" rule


--------------------------------------------------------------------
  A NOTE ON FAIRNESS
--------------------------------------------------------------------

  This is a personal automation tool for a single-player-ish grinding
  loop. Using macros may be against Roblox's rules, and automated
  input can be detected. Use it at your own risk on your own account.


====================================================================
