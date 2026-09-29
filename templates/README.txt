TEMPLATE IMAGES
===============

A path file can wait for a thing to appear on screen, or click it, by name:

  await    <name> <cap-ms>     block until <name>.png is visible (or give up)
  clickimg <name> [tol]        click the centre of <name>.png if visible

Put the PNG here, named <name>.png. To make one: screenshot the game, crop
tightly around the thing you want to find (a prompt, a button, an ore), and
save it as PNG. Crop TIGHTLY - a big template with background in it will not
match when that background changes.

tol is the colour tolerance 0-255 (default 30). Raise it if the match misses
when the thing is clearly there; lower it if it matches the wrong spot.

Example path lines:
  await    DIGPROMPT 5000
  clickimg SELLBUTTON

If a template never appears, the macro logs it and carries on rather than
clicking blind.
