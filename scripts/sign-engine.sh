#!/bin/bash
# Signs every Mach-O file under the engine directory, inside-out (libraries first,
# executables last). Non-Mach-O files (shell wrappers, PE .dll, data) are skipped.
#
# Usage: scripts/sign-engine.sh <path-to-Engine-dir>
#
# Phase 1 (ad-hoc, no Developer ID):
#   IDENTITY=-  (default)
#   RUNTIME and ENTITLEMENTS unset
#
# Phase 2 (Developer ID):
#   IDENTITY="Developer ID Application: NAME (TEAMID)"
#   RUNTIME="--options runtime --timestamp"
#   ENTITLEMENTS="scripts/engine.entitlements"
set -eo pipefail

ENGINE="$1"
IDENTITY="${IDENTITY:--}"
RUNTIME="${RUNTIME:-}"
ENTITLEMENTS="${ENTITLEMENTS:-}"

runtime_args=()
if [[ -n "$RUNTIME" ]]; then
    read -ra runtime_args <<< "$RUNTIME"
fi

ent_args=()
if [[ -n "$ENTITLEMENTS" ]]; then
    ent_args=(--entitlements "$ENTITLEMENTS")
fi

signed=0
skipped=0

while IFS= read -r f; do
    desc="$(file -b "$f")"
    if [[ "$desc" == *"Mach-O"*"executable"* ]]; then
        codesign --force --sign "$IDENTITY" "${runtime_args[@]}" "${ent_args[@]}" "$f"
        (( signed++ ))
    elif [[ "$desc" == *"Mach-O"* ]]; then
        # Libraries (.dylib, Mach-O .so): no entitlements even in Phase 2.
        codesign --force --sign "$IDENTITY" "${runtime_args[@]}" "$f"
        (( signed++ ))
    else
        (( skipped++ ))
    fi
done < <(find "$ENGINE" -type f)

echo "sign-engine: signed $signed, skipped $skipped (non-Mach-O)"
