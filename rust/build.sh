#!/usr/bin/env bash
# Build the Rust GDExtension runtime and install it into the Godot addon dir.
# Usage: bash rust/build.sh [--debug-only|--release-only]   (default: both)
set -euo pipefail
cd "$(dirname "$0")"

source "$HOME/.cargo/env" 2>/dev/null || true

BIN_DIR="../addons/godot_bt_native/bin"
mkdir -p "$BIN_DIR"

build_one() {
    local profile="$1" out="$2"
    if [ "$profile" = "release" ]; then
        echo "==> cargo build --release"
        cargo build --release
    else
        echo "==> cargo build (debug)"
        cargo build
    fi
    cp -f "target/$profile/libgodot_bt_native.so" "$BIN_DIR/$out"
    echo "    installed -> $BIN_DIR/$out"
}

case "${1:-both}" in
    --debug-only)   build_one debug   libgodot_bt_native.debug.so ;;
    --release-only) build_one release libgodot_bt_native.release.so ;;
    both)
        build_one debug   libgodot_bt_native.debug.so
        build_one release libgodot_bt_native.release.so
        ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

echo "done. Restart the Godot editor (or rerun headless) to pick up new binaries."
