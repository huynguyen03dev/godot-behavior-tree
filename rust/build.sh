#!/usr/bin/env bash
# Build the Rust GDExtension runtime and install it into the Godot addon dir.
# Usage: bash rust/build.sh [--debug-only|--release-only]   (default: both)
set -euo pipefail
cd "$(dirname "$0")"

source "$HOME/.cargo/env" 2>/dev/null || true

BIN_DIR="../addons/godot_bt_native/bin"
mkdir -p "$BIN_DIR"

# Detect host OS
UNAME_S="$(uname -s 2>/dev/null || echo "Unknown")"
case "$UNAME_S" in
    Linux*)
        LIB_SRC_PREFIX="lib"
        LIB_SRC_EXT=".so"
        DEST_EXT=".so"
        ;;
    Darwin*)
        LIB_SRC_PREFIX="lib"
        LIB_SRC_EXT=".dylib"
        DEST_EXT=".dylib"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        LIB_SRC_PREFIX=""
        LIB_SRC_EXT=".dll"
        DEST_EXT=".dll"
        ;;
    *)
        # Fallback check for Windows if running under PowerShell / CMD bash
        if [ "${OS:-}" = "Windows_NT" ]; then
            LIB_SRC_PREFIX=""
            LIB_SRC_EXT=".dll"
            DEST_EXT=".dll"
        else
            echo "Unknown operating system: $UNAME_S, defaulting to .so"
            LIB_SRC_PREFIX="lib"
            LIB_SRC_EXT=".so"
            DEST_EXT=".so"
        fi
        ;;
esac

build_one() {
    local profile="$1"
    local config="$2" # debug or release
    if [ "$profile" = "release" ]; then
        echo "==> cargo build --release"
        cargo build --release
    else
        echo "==> cargo build (debug)"
        cargo build
    fi

    local src_file="target/$profile/${LIB_SRC_PREFIX}godot_bt_native${LIB_SRC_EXT}"
    local dest_file="$BIN_DIR/libgodot_bt_native.${config}${DEST_EXT}"

    if [ -f "$src_file" ]; then
        cp -f "$src_file" "$dest_file"
        echo "    installed -> $dest_file"
    else
        echo "ERROR: Compiled binary not found at $src_file" >&2
        exit 1
    fi
}

case "${1:-both}" in
    --debug-only)   build_one debug   debug ;;
    --release-only) build_one release release ;;
    both)
        build_one debug   debug
        build_one release release
        ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

echo "done. Restart the Godot editor (or rerun headless) to pick up new binaries."
