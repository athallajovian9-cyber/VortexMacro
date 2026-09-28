# Third-party software

VortexMacro's own code is MIT (see LICENSE.txt). It runs on software written by
other people, listed here.

## AutoHotkey

- **What it is:** the interpreter that runs `submacro\VortexMacro.ahk`. The
  release zip includes it so the macro works without a separate install.
- **Version:** 2.0.28
- **Copyright:** (C) 2003-2024 Chris Mallett and the AutoHotkey Foundation
- **License:** GNU General Public License, version 2 (full text in
  `licenses\AutoHotkey-GPL-2.0.txt`). The AutoHotkey project appends additional
  third-party notices to the end of that same file, including a BSD-3-Clause
  notice naming the University of Cambridge and Google Inc.
- **Source code:** <https://github.com/AutoHotkey/AutoHotkey>
- **Website:** <https://www.autohotkey.com>

### Files shipped

All three are unmodified binaries as distributed by the AutoHotkey project.
None has been rebuilt, patched or otherwise altered.

```
submacro\AutoHotkey64.exe   1284608 bytes   sha256 373181727d1ae858564d4daa...
submacro\AutoHotkey.exe     1284608 bytes   sha256 373181727d1ae858564d4daa...
submacro\AutoHotkey32.exe    989184 bytes   sha256 461ab9fc31d12658e50cadbb...
```

- `AutoHotkey64.exe` is the 64-bit interpreter, and is what `launcher.bat` runs.
- `AutoHotkey.exe` is the same 64-bit binary under the name AHK uses by
  convention, so a plain double-click on a `.ahk` file works. It is a copy
  rather than a second build, which is why the hash is identical.
- `AutoHotkey32.exe` is the 32-bit interpreter, shipped only as a fallback for
  a 32-bit Windows install, where the 64-bit binary cannot run at all.

To check a copy yourself:

```
certutil -hashfile submacro\AutoHotkey64.exe SHA256
```

The hash printed should begin `373181727d1ae858564d4daa`.

## License boundary

AutoHotkey is licensed under the GPL, not the MIT license used by this project.
It is redistributed here unmodified, together with its license text and a link
to its source, which is what the GPL requires. Its license does not extend to
VortexMacro's own code, and VortexMacro's MIT license does not extend to it.

## No affiliation

VortexMacro is not affiliated with, endorsed by, or connected to Roblox
Corporation, AutoHotkey, or the developer of the game it automates. All
trademarks belong to their owners.
