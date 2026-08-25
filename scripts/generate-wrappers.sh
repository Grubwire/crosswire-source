#!/bin/bash
# Generates the Crosswire-named entry-point wrapper scripts in Engine/bin/.
# Usage: scripts/generate-wrappers.sh <path-to-Engine-bin>
# Called by engine-bundle.yml after extracting the Gcenx archive.
#
# Wine 9+ unified the wine and wine64 binaries into a single `wine` that
# dispatches both 32-bit and 64-bit via WoW64. Older builds still ship a
# separate `wine64`. The wrappers below pick whichever exists at bundle
# time so the same script generation works against any Gcenx vintage.
set -euo pipefail

BIN="$1"

resolve_target() {
    local preferred="$1"  # binary the wrapper most wants (e.g. wine64)
    local fallback="$2"   # what to use if preferred is absent (e.g. wine)
    if [ -e "$BIN/$preferred" ]; then
        echo "$preferred"
    elif [ -e "$BIN/$fallback" ]; then
        echo "$fallback"
    else
        echo "ERROR: neither $BIN/$preferred nor $BIN/$fallback exists" >&2
        exit 1
    fi
}

make_wrapper() {
    local name="$1"   # wrapper name (e.g. Crosswire64)
    local target="$2" # target binary (e.g. wine64 or wine)
    cat > "$BIN/$name" << EOF
#!/bin/sh
# Crosswire engine wrapper. Ensures the engine's bundled dylibs (FreeType,
# etc.) are discoverable to wine and every child process it spawns.
#
# Why DYLD_FALLBACK_LIBRARY_PATH and not DYLD_LIBRARY_PATH:
# wine's win32u.so calls dlopen("libfreetype.6.dylib") with a bare leaf name.
# macOS dlopen only searches DYLD_LIBRARY_PATH + /usr/lib for bare names,
# but DYLD_LIBRARY_PATH gets stripped across exec for restricted binaries
# (and effectively across Rosetta and wine's preloader chain). Fallback is
# not in dyld's strip list, so it propagates into services.exe / plugplay /
# explorer / installer children. Without this the engine prints "Wine cannot
# find the FreeType font library" 10x per app run and blocks any GUI wizard.
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
ENGINE_LIB="\$(dirname "\$DIR")/lib"
export DYLD_FALLBACK_LIBRARY_PATH="\${ENGINE_LIB}:\${DYLD_FALLBACK_LIBRARY_PATH:-/usr/local/lib:/usr/lib}"
exec "\$DIR/$target" "\$@"
EOF
    chmod +x "$BIN/$name"
}

WINE_BIN=$(resolve_target wine64 wine)
WINESERVER_BIN=$(resolve_target wineserver64 wineserver)
WINEBOOT_BIN=$(resolve_target wineboot64 wineboot)

make_wrapper Crosswire64     "$WINE_BIN"
make_wrapper Crosswireserver "$WINESERVER_BIN"
make_wrapper Crosswireboot   "$WINEBOOT_BIN"

echo "Generated wrappers:"
echo "  Crosswire64     -> $WINE_BIN"
echo "  Crosswireserver -> $WINESERVER_BIN"
echo "  Crosswireboot   -> $WINEBOOT_BIN"
