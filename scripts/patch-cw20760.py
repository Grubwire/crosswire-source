#!/usr/bin/env python3
"""
Apply CW HACK 20760 (WoW64 lretq thunk — Rosetta 2 SIGUSR1 race fix) to
dlls/wow64cpu/cpu.c in a Gcenx/wine 11.x source tree.

Backports:
  - CW HACK 20760: replace ljmp with lretq in the WoW64 32->64 transition
    when running under Rosetta 2 (both entry CALLF and return lretq path).
    Also detects Rosetta at process init and uses CALLF (0x1d) rather than
    JMPF (0x2d) in the syscall/unix-call thunk structures.

Usage:  patch-cw20760.py <path-to-wine-src>

Idempotent: a second run detects the marker and exits 0.

Wraps scripts/patches/cw-20760.patch via `git apply`. See patch-cw-signal.py
for the rationale behind the wrapper layout.

Note (carried over from the original implementation): no #ifdef __APPLE__
guards inside cpu.c. wow64cpu.dll is cross-compiled by MinGW which does not
define __APPLE__, so guards would silently compile to nothing. The runtime
Rosetta detection (is_rosetta2 inside the patch) handles the non-Rosetta
case at runtime instead.
"""
import os
import subprocess
import sys

MARKER = "CW HACK 20760"
TARGET = "dlls/wow64cpu/cpu.c"
PATCH_REL = "scripts/patches/cw-20760.patch"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src_root = sys.argv[1]
    if not os.path.isdir(src_root):
        raise SystemExit(f"not a directory: {src_root}")

    target_path = os.path.join(src_root, TARGET)
    with open(target_path) as f:
        text = f.read()
    if MARKER in text:
        print(f"  {TARGET}: already patched (found {MARKER!r}), skipping")
        return 0

    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(here)
    patch_path = os.path.join(repo_root, PATCH_REL)
    if not os.path.isfile(patch_path):
        raise SystemExit(f"patch file missing: {patch_path}")

    print(f"Applying {PATCH_REL} to {src_root}")
    subprocess.run(
        ["git", "apply", "--whitespace=nowarn", patch_path],
        cwd=src_root,
        check=True,
    )
    print(f"  {TARGET}: patched (CW HACK 20760: lretq thunk + CALLF entry + Rosetta detection)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
