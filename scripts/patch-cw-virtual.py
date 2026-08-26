#!/usr/bin/env python3
"""
Apply CW HACKs for dlls/ntdll/unix/virtual.c to a Gcenx/wine 11.x source tree.

Backports:
  - CW HACK 24945: on a write fault to a w|x page, toggle exec off+on to
    force Rosetta to invalidate its translation cache. Without this the
    process loops forever taking the same write fault.
  - CW HACK 25719: same idea for exec faults on already-executable pages.
  - CW HACK 18947: after NtWriteVirtualMemory, toggle the executable bit
    on the affected range so Rosetta re-translates modified code (matters
    for JIT debuggers and any cross-process code patcher, including the
    JVM safepoint poll).

Usage:  patch-cw-virtual.py <path-to-wine-src>

Idempotent: a second run detects the marker and exits 0.

Wraps scripts/patches/cw-virtual.patch via `git apply`. See
patch-cw-signal.py for the rationale behind the wrapper layout.
"""
import os
import subprocess
import sys

MARKER = "CW Hack 24945"   # unique to this patch set
TARGET = "dlls/ntdll/unix/virtual.c"
PATCH_REL = "scripts/patches/cw-virtual.patch"


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
    print(f"  {TARGET}: patched (CW HACK 24945 + 25719 + 18947)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
