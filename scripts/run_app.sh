#!/usr/bin/env bash
# Launch the assembled Folderist.app bundle.
#
# IMPORTANT:
#   - Launch via `open` on a proper LS-registered .app bundle rather than
#     executing the raw binary, so LaunchServices sees a real app.
#   - NEVER run two live copies of the same bundle id (com.folderist.app) at
#     once. Quit any existing instance first.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/Folderist.app"
BUNDLE_ID="com.folderist.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: $APP_BUNDLE not found. Run scripts/build.sh or scripts/dev-build.sh first." >&2
    exit 1
fi

echo "==> Checking for a running instance of $BUNDLE_ID..."
if osascript -e "id of application \"$APP_BUNDLE\"" >/dev/null 2>&1; then
    RUNNING_PID="$(osascript -e "tell application \"System Events\" to (unix id of every process whose bundle identifier is \"$BUNDLE_ID\")" 2>/dev/null || true)"
fi

# More reliable check: pgrep against the actual bundled binary path.
BINARY_PATH="$APP_BUNDLE/Contents/MacOS/Folderist"
if pgrep -f "$BINARY_PATH" >/dev/null 2>&1; then
    echo "==> Found a running instance, quitting it first..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    # Give it a moment to quit gracefully, then force if still alive.
    for _ in 1 2 3 4 5; do
        pgrep -f "$BINARY_PATH" >/dev/null 2>&1 || break
        sleep 0.5
    done
    if pgrep -f "$BINARY_PATH" >/dev/null 2>&1; then
        pkill -f "$BINARY_PATH" || true
    fi
fi

echo "==> Launching $APP_BUNDLE..."
open "$APP_BUNDLE"
