#!/bin/bash
# Signs a manifest.json with the engine manifest Ed25519 private key.
# Produces manifest.json.sig (raw 64-byte signature) alongside the manifest.
#
# Usage: scripts/sign-manifest.sh <path-to-manifest.json>
#
# Requires the private key PEM file at ENGINE_MANIFEST_KEY_FILE (env), or
# reads the raw hex seed from ENGINE_MANIFEST_SIGNING_KEY (env, CI secret).
#
# ENGINE_MANIFEST_KEY_FILE path uses openssl (needs brew openssl on macOS,
# not LibreSSL, for -rawin support). ENGINE_MANIFEST_SIGNING_KEY path uses
# Python's cryptography library, which avoids all openssl version quirks.
set -eo pipefail

MANIFEST="$1"
SIG="${MANIFEST}.sig"

if [[ -n "${ENGINE_MANIFEST_KEY_FILE:-}" ]]; then
    # Local use: sign with PEM file. Use Homebrew openssl if available (LibreSSL
    # does not support -rawin). Falls back to system openssl as a last resort.
    OPENSSL="$(brew --prefix openssl 2>/dev/null)/bin/openssl"
    [[ -x "$OPENSSL" ]] || OPENSSL="openssl"
    "$OPENSSL" pkeyutl -sign \
        -inkey "$ENGINE_MANIFEST_KEY_FILE" \
        -rawin \
        -in "$MANIFEST" \
        -out "$SIG"
elif [[ -n "${ENGINE_MANIFEST_SIGNING_KEY:-}" ]]; then
    # CI use: sign with raw hex seed via Python's cryptography library.
    # This avoids openssl -rawin compatibility issues across LibreSSL and
    # OpenSSL versions. ENGINE_MANIFEST_SIGNING_KEY is read from the env by
    # the Python script, not passed on the command line.
    python3 - "$MANIFEST" "$SIG" << 'PYEOF'
import sys, os
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

manifest_path, sig_path = sys.argv[1], sys.argv[2]
key = Ed25519PrivateKey.from_private_bytes(
    bytes.fromhex(os.environ['ENGINE_MANIFEST_SIGNING_KEY'])
)
with open(manifest_path, 'rb') as f:
    data = f.read()
with open(sig_path, 'wb') as f:
    f.write(key.sign(data))
PYEOF
else
    echo "Error: set ENGINE_MANIFEST_KEY_FILE or ENGINE_MANIFEST_SIGNING_KEY" >&2
    exit 1
fi

echo "Signed $MANIFEST -> $SIG ($(wc -c < "$SIG" | tr -d ' ') bytes)"
