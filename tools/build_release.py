"""Build the GitHub release zip, then verify what was actually produced.

A release artifact is not "the folder, zipped". It is a specific set of files
with the user's own state removed. Two failure modes this guards against:

  * shipping per-user state  - saved location, session log, recorded routes
  * shipping a broken engine - AutoHotkey.exe was once a symlink, and zip
                               archives store links as links, which Windows'
                               built-in extractor does not recreate

So this does not just build the zip. It reopens it and checks the contents
against the source folder, byte for byte, before reporting success.

Usage:  python tools/build_release.py
"""
import hashlib
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")

# Exactly what a user receives. Anything not matched here is excluded, so a
# new file in the working folder cannot leak into a release by accident.
INCLUDE_FILES = [
    "launcher.bat",
    "README.txt",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt",
    "THIRD-PARTY.md",
    "VERSION",
]
INCLUDE_DIRS = [
    "assets",
    "maps",
    "submacro",
    "tests",
    "tools",
    "licenses",
]

# Per-user state and build output. Belt and braces: INCLUDE_DIRS would pick
# these up, so they are removed by name after selection.
EXCLUDE_NAMES = {"__pycache__", "dist", ".git"}
EXCLUDE_SUFFIXES = (".route", ".pyc", ".log", "_result.txt")
EXCLUDE_EXACT = {
    os.path.join("settings", "vortex_config.ini"),
}

# The interpreter must be a real binary of exactly this size, or the release is
# broken for anyone who extracts it with Windows Explorer.
ENGINE_MUST_BE_REAL = ["submacro/AutoHotkey.exe", "submacro/AutoHotkey64.exe"]
MIN_ENGINE_BYTES = 900_000


def read_version():
    with open(os.path.join(ROOT, "VERSION"), encoding="utf-8") as fh:
        return fh.read().strip()


def collect():
    """Return the sorted list of relative paths that belong in the release."""
    picked = []
    for name in INCLUDE_FILES:
        p = os.path.join(ROOT, name)
        if os.path.isfile(p):
            picked.append(name)
        else:
            print("  WARNING: expected file is missing: %s" % name)

    for d in INCLUDE_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            print("  WARNING: expected folder is missing: %s" % d)
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames if x not in EXCLUDE_NAMES]
            for fn in sorted(filenames):
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, ROOT).replace("\\", "/")
                if fn.endswith(EXCLUDE_SUFFIXES):
                    continue
                if rel.replace("/", os.sep) in EXCLUDE_EXACT:
                    continue
                picked.append(rel)

    return sorted(set(picked))


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    version = read_version()
    tag = "v" + version
    os.makedirs(DIST, exist_ok=True)
    zip_path = os.path.join(DIST, "VortexMacro-%s.zip" % version)
    if os.path.exists(zip_path):
        os.remove(zip_path)

    files = collect()
    print("packaging %d files as %s" % (len(files), os.path.basename(zip_path)))

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in files:
            z.write(os.path.join(ROOT, rel.replace("/", os.sep)), "VortexMacro/" + rel)

    # ---- verify: read the archive back, do not trust the write ----------
    problems = []
    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
        inside = {n[len("VortexMacro/"):] for n in names if n.startswith("VortexMacro/")}
        missing = set(files) - inside
        if missing:
            problems.append("not in archive: %s" % sorted(missing))

        leaked = [n for n in inside
                  if n.endswith(".route") or n.endswith(".log")
                  or "__pycache__" in n or n.endswith(".pyc")]
        if leaked:
            problems.append("per-user state leaked into the archive: %s" % leaked)

        # every file must match the source byte for byte
        for rel in files:
            src = os.path.join(ROOT, rel.replace("/", os.sep))
            data = z.read("VortexMacro/" + rel)
            if len(data) != os.path.getsize(src):
                problems.append("size mismatch: %s" % rel)
            elif hashlib.sha256(data).hexdigest() != sha(src):
                problems.append("content mismatch: %s" % rel)

        # the engine specifically must be a real binary
        for engine in ENGINE_MUST_BE_REAL:
            if engine not in inside:
                problems.append("engine missing: %s" % engine)
                continue
            raw = z.read("VortexMacro/" + engine)
            if len(raw) < MIN_ENGINE_BYTES:
                problems.append("engine too small, probably a symlink: %s (%d bytes)"
                                % (engine, len(raw)))
            elif not raw.startswith(b"MZ"):
                problems.append("engine is not a PE binary: %s" % engine)

    size = os.path.getsize(zip_path)
    print()
    print("  archive : %s" % zip_path)
    print("  size    : %s bytes (%.1f MB)" % (size, size / 1048576))
    print("  entries : %d" % len(files))

    if problems:
        print()
        print("  RELEASE FAILED:")
        for p in problems:
            print("    - %s" % p)
        os.remove(zip_path)
        return 1

    print()
    print("  verified: every file matches the source byte for byte,")
    print("            no per-user state, engine is a real binary")
    print()
    print("  next: gh release create %s dist/VortexMacro-%s.zip" % (tag, version))
    return 0


if __name__ == "__main__":
    sys.exit(main())
