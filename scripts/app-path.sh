#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/vmini.xcodeproj"
SCHEME="TextEditorApp"
CONFIGURATION="${CONFIGURATION:-Debug}"

BUILD_SETTINGS="$(
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings
)"

TARGET_BUILD_DIR="$(
  print -r -- "$BUILD_SETTINGS" |
    awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
)"

FULL_PRODUCT_NAME="$(
  print -r -- "$BUILD_SETTINGS" |
    awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }'
)"

if [[ -z "$TARGET_BUILD_DIR" || -z "$FULL_PRODUCT_NAME" ]]; then
  echo "Unable to resolve built app path from xcodebuild settings." >&2
  exit 1
fi

print -r -- "$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
