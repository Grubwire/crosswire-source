#!/bin/bash
# Fetches the currently-promoted engine for CHANNEL (prod or beta), verifies
# it (manifest signature + archive SHA-256, same checks the app does at
# runtime), extracts it into APP/Contents/Resources/Engine, writes a
# build-time engine-version.json there, and signs it (ad-hoc Phase 1 by
# default -- IDENTITY/RUNTIME/ENTITLEMENTS are read from the environment
# by sign-engine.sh, same as engine-bundle.yml already does).
#
# Usage: scripts/bundle-engine-into-app.sh <path-to-.app> <prod|beta>
#
# Reads only from the PUBLIC download.grubwire.io host -- no R2/AWS
# credentials needed. Confirmed reachable from both the self-hosted
# runner (residential IP, unaffected by the Cloudflare bot-protection
# that blocks hosted-CI/datacenter IPs) and local development.
set -eo pipefail

APP="$1"
CHANNEL="$2"

if [[ -z "$APP" || -z "$CHANNEL" ]]; then
    echo "Usage: scripts/bundle-engine-into-app.sh <path-to-.app> <prod|beta>" >&2
    exit 1
fi
if [[ "$CHANNEL" != "prod" && "$CHANNEL" != "beta" ]]; then
    echo "Error: channel must be 'prod' or 'beta', got '$CHANNEL'" >&2
    exit 1
fi
if [[ ! -d "$APP" ]]; then
    echo "Error: app bundle not found: $APP" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

HOST="https://download.grubwire.io/engine/${CHANNEL}"

echo "=== fetching ${CHANNEL} manifest ==="
curl -sL --fail -o "$WORK/engine-manifest.json" "${HOST}/engine-manifest.json"
curl -sL --fail -o "$WORK/engine-manifest.json.sig" "${HOST}/engine-manifest.json.sig"
bash "$SCRIPT_DIR/verify-manifest.sh" "$WORK/engine-manifest.json"

ENGINE_URL=$(python3 -c "import json; print(json.load(open('$WORK/engine-manifest.json'))['url'])")
EXPECTED_SHA=$(python3 -c "import json; print(json.load(open('$WORK/engine-manifest.json'))['sha256'])")
ENGINE_VERSION=$(python3 -c "import json; print(json.load(open('$WORK/engine-manifest.json'))['engineVersion'])")
UPSTREAM_TAG=$(python3 -c "import json; print(json.load(open('$WORK/engine-manifest.json'))['upstreamTag'])")

echo "=== downloading engine archive (${ENGINE_VERSION}) ==="
curl -sL --fail -o "$WORK/engine.tar.xz" "$ENGINE_URL"
ACTUAL_SHA=$(shasum -a 256 "$WORK/engine.tar.xz" | awk '{print $1}')
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    echo "Error: engine archive SHA-256 mismatch (got $ACTUAL_SHA, expected $EXPECTED_SHA)" >&2
    exit 1
fi
echo "Archive verified: $EXPECTED_SHA"

echo "=== extracting into app bundle ==="
mkdir -p "$WORK/extract"
tar -xJf "$WORK/engine.tar.xz" -C "$WORK/extract"
# engine-bundle.yml's "Repack as tar.xz" step always names the top-level
# directory "engine" (tar -cJf ... engine/) -- confirmed from that
# workflow's own source, not assumed.
if [[ ! -d "$WORK/extract/engine" ]]; then
    echo "Error: archive did not contain an 'engine/' top-level directory" >&2
    exit 1
fi

ENGINE_DEST="$APP/Contents/Resources/Engine"
rm -rf "$ENGINE_DEST"
mv "$WORK/extract/engine" "$ENGINE_DEST"

python3 -c "
import json
with open('$ENGINE_DEST/engine-version.json', 'w') as f:
    json.dump({'engineVersion': '$ENGINE_VERSION', 'upstreamTag': '$UPSTREAM_TAG'}, f, indent=2, sort_keys=True)
"

echo "=== signing bundled engine (ad-hoc Phase 1 unless IDENTITY is set) ==="
bash "$SCRIPT_DIR/sign-engine.sh" "$ENGINE_DEST"

echo "=== verifying bundled engine ==="
WRAPPER="$ENGINE_DEST/bin/Crosswire64"
if [[ ! -f "$WRAPPER" ]]; then
    echo "Error: bundled engine missing Crosswire64 at $WRAPPER" >&2
    exit 1
fi
if [[ ! -x "$WRAPPER" ]]; then
    echo "Error: bundled Crosswire64 is not executable" >&2
    exit 1
fi
# Crosswire64 itself is a shell wrapper (scripts/generate-wrappers.sh) that
# execs the real wine (or wine64, depending on Gcenx vintage) Mach-O binary
# -- sign-engine.sh intentionally leaves shell wrappers unsigned, so verify
# the Mach-O binary the wrapper actually execs into instead of the wrapper.
WRAPPED_TARGET=$(sed -n 's#.*exec "\$DIR/\([^"]*\)".*#\1#p' "$WRAPPER")
if [[ -z "$WRAPPED_TARGET" ]]; then
    echo "Error: could not determine wrapped binary from $WRAPPER" >&2
    exit 1
fi
BIN="$ENGINE_DEST/bin/$WRAPPED_TARGET"
if [[ ! -f "$BIN" ]]; then
    echo "Error: bundled engine missing wrapped binary at $BIN" >&2
    exit 1
fi
if [[ ! -x "$BIN" ]]; then
    echo "Error: bundled $WRAPPED_TARGET is not executable" >&2
    exit 1
fi
if ! file "$BIN" | grep -q "Mach-O"; then
    echo "Error: bundled $WRAPPED_TARGET is not a Mach-O binary: $(file "$BIN")" >&2
    exit 1
fi

echo "=== bundled ${CHANNEL} engine ${ENGINE_VERSION} into $APP ==="
