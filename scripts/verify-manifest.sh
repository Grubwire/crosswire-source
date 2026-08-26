#!/bin/bash
# Verifies a manifest.json's Ed25519 signature against the engine manifest
# PUBLIC key already embedded in EngineManifest.swift. Counterpart to
# sign-manifest.sh (which signs and needs the private key/CI secret); this
# only ever needs the public key, which is public by definition -- no
# secret required to run this script anywhere, including locally.
#
# Usage: scripts/verify-manifest.sh <path-to-manifest.json>
# Looks for <manifest>.sig alongside it (same convention as sign-manifest.sh).
set -eo pipefail

MANIFEST="$1"
SIG="${MANIFEST}.sig"

if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest not found: $MANIFEST" >&2
    exit 1
fi
if [[ ! -f "$SIG" ]]; then
    echo "Error: signature file not found: $SIG" >&2
    exit 1
fi

python3 - "$MANIFEST" "$SIG" << 'PYEOF'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature

# Same public key embedded in EngineManifest.swift
# (EngineManifestClient.publicKeyHex). Public by definition.
PUBLIC_KEY_HEX = "51c6ffe71ee5c92539aeb87c3b348e9b5914f7c03c3811da09be60b06cd822fc"

manifest_path, sig_path = sys.argv[1], sys.argv[2]
key = Ed25519PublicKey.from_public_bytes(bytes.fromhex(PUBLIC_KEY_HEX))

with open(manifest_path, 'rb') as f:
    data = f.read()
with open(sig_path, 'rb') as f:
    sig = f.read()

try:
    key.verify(sig, data)
except InvalidSignature:
    print("Error: signature verification FAILED", file=sys.stderr)
    sys.exit(1)

print(f"Signature verified OK: {manifest_path}")
PYEOF
