#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/build.sh" >/dev/null

APP_PATH="$("$ROOT_DIR/scripts/app-path.sh")"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true
)"
EXECUTABLE_NAME="$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST" 2>/dev/null || true
)"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

if [[ -n "$BUNDLE_ID" ]]; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
fi

if [[ -n "$EXECUTABLE_NAME" ]]; then
  for _ in {1..50}; do
    if ! pgrep -fx "$EXECUTABLE_PATH" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

exec open "$APP_PATH"
