#!/usr/bin/env bash
#
# build-vulkan-engine.sh — rebuild the Crosswire engine's Wine with Vulkan support
#
# Background: the shipping engine is built with --without-vulkan, so DXVK
# cannot function and 3D Windows games fail to render. This script
# rebuilds wine64 (and wow64) in /tmp/wine-build/wine-src with Vulkan
# enabled, signs the resulting Mach-O binaries inside-out (Phase 1 ad-hoc),
# and swaps them into the installed engine. Existing CW patches (24945,
# 25719, 18947, 23427, 22131, 20760, 20186, 23427, 24256) are preserved
# because we build the existing patched tree, not a fresh clone.
#
# Prerequisites (verified by check_prereqs):
#   brew install bison mingw-w64
#   LunarG Vulkan SDK installed at $VULKAN_SDK_ROOT (default ~/VulkanSDK/1.4.350.0)
#   /tmp/wine-build/wine-src is the patched 11.9 tree
#
# *** VULKAN SDK SOURCE ***
# Homebrew's vulkan-loader on Apple Silicon ships an arm64-only
# libvulkan.dylib, which cannot link an x86_64 Wine. Crosswire's engine
# runs under Rosetta (x86_64-apple-darwin), so we use the LunarG Vulkan
# SDK for macOS instead — it ships a universal (arm64 + x86_64)
# libvulkan.dylib plus MoltenVK.
#
# Download:
#   https://sdk.lunarg.com/sdk/download/latest/mac/vulkan-sdk.dmg
#   (~376 MB ZIP containing the installer; confirmed 2026-05-27)
#
# Install to ~/VulkanSDK/<version>/. This script sources
# <version>/setup-env.sh to set VULKAN_SDK, PATH, PKG_CONFIG_PATH, etc.
# Override the SDK version via VULKAN_SDK_ROOT if you've installed a
# different release.
#
# Note: Wine's configure does not honour PKG_CONFIG_PATH for -lvulkan;
# it uses AC_CHECK_LIB, which needs CPPFLAGS/-I and LDFLAGS/-L to find
# the SDK's headers and dylibs. configure_step() sets both.
#
# Future option: pivot the engine to arm64-native, removing Rosetta.
# That needs llvm-mingw (brew install llvm-mingw) for PE cross-compilation
# and a from-scratch rebuild of every Mach-O .so in dlls/.
#
# Runtime: about 1.5–2 hours on M1/M2 for a fresh full build.
# Safe to re-run: build dir is rebuilt from scratch each invocation.
# Safe to abort: existing engine is only touched in the final swap step.

set -euo pipefail

BUILD_DIR="/tmp/wine-build/build-vulkan"
SRC_DIR="/tmp/wine-build/wine-src"
ENGINE_DIR="$HOME/Library/Application Support/app.Crosswire.Crosswire/Engine"
LOG_FILE="/tmp/crosswire-overnight/vulkan-build-$(date +%Y%m%dT%H%M%S).log"
# Override with: VULKAN_SDK_ROOT=~/VulkanSDK/X.Y.Z bash scripts/build-vulkan-engine.sh
VULKAN_SDK_ROOT="${VULKAN_SDK_ROOT:-$HOME/VulkanSDK/1.4.350.0}"

mkdir -p "$(dirname "$LOG_FILE")"

log() { printf '\n=== %s ===\n' "$*" | tee -a "$LOG_FILE"; }

load_vulkan_sdk() {
    # Source the LunarG SDK's setup-env.sh. It expects PKG_CONFIG_PATH to be
    # set (the script appends to it with `:` unconditionally); export an
    # empty value so it doesn't pull in literal "${PKG_CONFIG_PATH}" text.
    if [[ ! -f "$VULKAN_SDK_ROOT/setup-env.sh" ]]; then
        echo "MISSING: $VULKAN_SDK_ROOT/setup-env.sh" >&2
        echo "Install the LunarG Vulkan SDK to \$VULKAN_SDK_ROOT (default ~/VulkanSDK/1.4.350.0)." >&2
        echo "Download: https://sdk.lunarg.com/sdk/download/latest/mac/vulkan-sdk.dmg" >&2
        exit 1
    fi
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"
    # shellcheck disable=SC1091
    source "$VULKAN_SDK_ROOT/setup-env.sh" > /dev/null
}

check_prereqs() {
    log "Checking prerequisites"
    local missing=0
    for cmd in /opt/homebrew/opt/bison/bin/bison /opt/homebrew/opt/mingw-w64/bin/x86_64-w64-mingw32-gcc; do
        if [[ ! -x "$cmd" ]]; then
            echo "MISSING: $cmd" | tee -a "$LOG_FILE"
            missing=1
        fi
    done
    load_vulkan_sdk
    if ! pkg-config --exists vulkan; then
        echo "MISSING: pkg-config can't find vulkan in $VULKAN_SDK/lib/pkgconfig" | tee -a "$LOG_FILE"
        missing=1
    else
        local vk_ver
        vk_ver="$(pkg-config --modversion vulkan)"
        echo "Vulkan SDK $vk_ver found at $VULKAN_SDK" | tee -a "$LOG_FILE"
    fi
    if [[ ! -d "$SRC_DIR" ]]; then
        echo "MISSING: $SRC_DIR — wine source tree not present" | tee -a "$LOG_FILE"
        missing=1
    fi
    if [[ ! -d "$ENGINE_DIR/bin" ]]; then
        echo "MISSING: $ENGINE_DIR/bin — engine not installed" | tee -a "$LOG_FILE"
        missing=1
    fi
    if (( missing > 0 )); then
        echo "Run: brew install bison mingw-w64" >&2
        echo "And install the LunarG Vulkan SDK (see header comment)." >&2
        exit 1
    fi
    echo "All prerequisites present." | tee -a "$LOG_FILE"
}

configure_step() {
    # The existing engine is x86_64 (running under Rosetta on Apple Silicon).
    # We match the host triple so the rebuilt binaries are drop-in replacements,
    # and so x86_64-w64-mingw32 (the only mingw available locally) satisfies
    # the PE cross-compilation requirement.
    #
    # CC/CFLAGS pin -arch x86_64 explicitly. Without it, clang on Apple
    # Silicon resolves `-m64` to arm64 headers when the target SDK exposes
    # both arches, and the i386/arm64 _OSSwapInt16 helpers collide during
    # the tools/makedep host build.
    #
    # CPPFLAGS/LDFLAGS point at the LunarG SDK because Wine's AC_CHECK_LIB
    # for vulkan/MoltenVK ignores pkg-config — it needs -I/-L directly.
    log "Configuring Wine with Vulkan (build dir: $BUILD_DIR)"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/mingw-w64/bin:/opt/homebrew/bin:$PATH" \
    CC="clang -arch x86_64 -m64" \
    CFLAGS="-arch x86_64 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0" \
    CPPFLAGS="-I$VULKAN_SDK/include" \
    LDFLAGS="-L$VULKAN_SDK/lib" \
        "$SRC_DIR/configure" \
            --host=x86_64-apple-darwin \
            --enable-win64 \
            --with-vulkan \
            --without-x \
            --without-freetype \
            --disable-tests 2>&1 | tee -a "$LOG_FILE"
    if ! grep -q "SONAME_LIBVULKAN" "$BUILD_DIR/include/config.h"; then
        echo "Configure ran but Vulkan was NOT detected — see $LOG_FILE" >&2
        exit 1
    fi
    echo "Vulkan detected in config.h. OK." | tee -a "$LOG_FILE"
}

build_step() {
    log "Building Wine (this is the slow step: ~1.5–2 hours)"
    cd "$BUILD_DIR"
    PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/mingw-w64/bin:/opt/homebrew/bin:$PATH" \
        make -j"$(sysctl -n hw.ncpu)" 2>&1 | tee -a "$LOG_FILE"
}

sign_step() {
    log "Signing rebuilt Mach-O binaries (ad-hoc, Phase 1)"
    # Sign each .dylib and each Mach-O .so/executable individually.
    # Inside-out: leaf .dylibs first, then the wrappers.
    cd "$BUILD_DIR"
    find . -type f \( -name '*.dylib' -o -name '*.so' \) -print0 | \
        while IFS= read -r -d '' f; do
            if file "$f" | grep -q "Mach-O"; then
                codesign --force --sign - "$f" 2>>"$LOG_FILE" || true
            fi
        done
    # Sign wine64 / wineserver / wineboot
    for f in wine64 server/wineserver loader/wine64; do
        if [[ -f "$f" ]] && file "$f" | grep -q "Mach-O"; then
            codesign --force --sign - "$f" 2>>"$LOG_FILE" || true
        fi
    done
}

swap_step() {
    log "Swapping rebuilt binaries into engine (backups end .pre-vulkan)"
    cd "$BUILD_DIR"

    # The engine uses the unified `wine` loader (not `wine64`); the
    # Crosswire64 wrapper just execs ./wine. Modern Wine builds with
    # --enable-win64 still produce a binary called `wine64` in the build
    # dir, which is our drop-in replacement for the engine's `wine`.
    # Back up before clobbering, but only if no backup exists yet.
    declare -A SWAPS=(
        ["wine64"]="$ENGINE_DIR/bin/wine"
        ["server/wineserver"]="$ENGINE_DIR/bin/wineserver"
    )
    for src in "${!SWAPS[@]}"; do
        local dst="${SWAPS[$src]}"
        if [[ ! -f "$src" ]]; then
            echo "  WARNING: built artifact $src not found, skipping" | tee -a "$LOG_FILE"
            continue
        fi
        if [[ -f "$dst" && ! -f "$dst.pre-vulkan" ]]; then
            cp "$dst" "$dst.pre-vulkan"
            echo "  backed up: $dst.pre-vulkan" | tee -a "$LOG_FILE"
        fi
        cp -f "$src" "$dst"
        echo "  installed: $dst" | tee -a "$LOG_FILE"
    done

    # winevulkan PE DLL (the new piece that DXVK depends on).
    local winevulkan="dlls/winevulkan/winevulkan.dll"
    if [[ -f "$winevulkan" ]]; then
        local target="$ENGINE_DIR/lib/wine/x86_64-windows/winevulkan.dll"
        if [[ -f "$target" && ! -f "$target.pre-vulkan" ]]; then
            cp "$target" "$target.pre-vulkan"
            echo "  backed up: $target.pre-vulkan" | tee -a "$LOG_FILE"
        fi
        cp -f "$winevulkan" "$target"
        echo "  installed: $target" | tee -a "$LOG_FILE"
    fi
}

verify_step() {
    log "Verifying Vulkan is now reported by Wine"
    PATH="$ENGINE_DIR/bin:$PATH" \
        "$ENGINE_DIR/bin/Crosswire64" winecfg --help 2>&1 | grep -i vulkan | tee -a "$LOG_FILE" || true
    echo "Tip: launch a DXVK-using app and check the run log for 'winevulkan' / 'MoltenVK'." | tee -a "$LOG_FILE"
}

main() {
    echo "Vulkan engine rebuild — log: $LOG_FILE"
    check_prereqs
    configure_step
    build_step
    sign_step
    swap_step
    verify_step
    log "Done. Backups end .pre-vulkan; to revert: mv X.pre-vulkan X"
}

main "$@"
