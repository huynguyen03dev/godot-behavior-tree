#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Resolve Godot binary: override via GODOT_BIN > PATH 'godot' > ~/.local/bin/godot
if [ -n "${GODOT_BIN:-}" ]; then
    GODOT="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
    GODOT="godot"
elif [ -x "$HOME/.local/bin/godot" ]; then
    GODOT="$HOME/.local/bin/godot"
else
    echo "Error: Godot binary not found. Set GODOT_BIN or install godot." >&2
    exit 1
fi

# Detect platform library extension
UNAME_S="$(uname -s 2>/dev/null || echo "Unknown")"
case "$UNAME_S" in
    Darwin*)
        RELEASE_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.release.dylib"
        DEBUG_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.debug.dylib"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        RELEASE_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.release.dll"
        DEBUG_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.debug.dll"
        ;;
    *)
        if [ "${OS:-}" = "Windows_NT" ]; then
            RELEASE_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.release.dll"
            DEBUG_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.debug.dll"
        else
            RELEASE_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.release.so"
            DEBUG_LIB="$REPO_ROOT/addons/godot_bt_native/bin/libgodot_bt_native.debug.so"
        fi
        ;;
esac

# Check for native extension library binary on disk
if [ ! -f "$RELEASE_LIB" ] && [ ! -f "$DEBUG_LIB" ]; then
    echo "Error: Native extension library not found. Run 'bash rust/build.sh --release-only' (requires rustup) to build it." >&2
    exit 1
fi

# Run preflight environment check script in headless Godot
"$GODOT" --headless --path . -s res://game/tools/check_env.gd
CHECK_CODE=$?

if [ $CHECK_CODE -ne 0 ]; then
    case $CHECK_CODE in
        2)
            echo "Error (code 2): GDExtension failed to load. Please rebuild the extension: bash rust/build.sh --release-only" >&2
            ;;
        3)
            echo "Error (code 3): Godot engine version is too old. Godot >= 4.6 is required." >&2
            ;;
        4)
            echo "Error (code 4): Missing required game files (ghost_main.json or main.tscn)." >&2
            ;;
        *)
            echo "Error (code $CHECK_CODE): Preflight environment check failed." >&2
            ;;
    esac
    exit $CHECK_CODE
fi

# Launch the game
exec "$GODOT" --path . res://game/scenes/main.tscn "$@"
