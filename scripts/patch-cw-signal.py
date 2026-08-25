#!/usr/bin/env python3
"""
Apply CW HACKs for dlls/ntdll/unix/signal_x86_64.c to a Gcenx/wine 11.x source tree.

Backports:
  - CW HACK 22131: fake-success NtSetContextThread debug-register sets under
    Rosetta (both 64-bit and 32-bit wow64 paths). Without this the JVM kills
    itself the first time it tries to install a hardware breakpoint.
  - CW HACK 23427: emulate XGETBV (xcr0) for Rosetta, which doesn't expose
    AVX state via the host CPUID path; plus Sequoia-aware AVX-512 bits.
  - CW HACK 24256: cache sysctl proc_translated in signal_init_process so
    the rest of the file can read `is_rosetta2` from a signal-safe variable;
    plus the read-side fixup in save_context — under Rosetta the mxcsr in a
    signal context is stale, so re-read the live register with stmxcsr. Without
    it, threads suspended via usr1_handler (JIT safepoints) resume with a bad
    mxcsr and the JVM fast-fails (0xc0000409) once the JIT is enabled.
  - CW HACK 24265: on macOS 14+ the syscall dispatcher entry (sigsys_handler)
    likewise gets a corrupt mxcsr under Rosetta; correct it and, since Rosetta
    re-applies the stale value, redirect through __restore_mxcsr_thunk which
    reloads mxcsr from amd64_thread_data before the dispatcher prolog. This is
    the fix for the JVM safepoint-suspension stall (#93, the SWG patcher hang).

Usage:  patch-cw-signal.py <path-to-wine-src>

Idempotent: a second run detects the marker and exits 0.

Wraps scripts/patches/cw-signal.patch via `git apply`. The .patch file is
a normal unified diff against stock Gcenx/wine 11.9; using `git apply`
keeps the script robust to whitespace nits that marker-anchored string
replacement would trip on.
"""
import os
import subprocess
import sys

MARKER = "CW Hack 24265"   # newest hack in this set; unique idempotency marker
TARGET = "dlls/ntdll/unix/signal_x86_64.c"
PATCH_REL = "scripts/patches/cw-signal.patch"


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

    # Resolve patch file relative to this script, so the workflow can invoke
    # the script from any cwd without worrying about path resolution.
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
    print(f"  {TARGET}: patched (CW HACK 22131 + 23427 + 24256 + 24265)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
