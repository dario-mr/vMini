#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="$ROOT_DIR/vmini/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
OUTPUT_DIR="$ROOT_DIR/vmini/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "Source image not found: $SOURCE_IMAGE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

render_icon() {
  local width="$1"
  local height="$2"
  local filename="$3"

  sips -z "$height" "$width" "$SOURCE_IMAGE" --out "$OUTPUT_DIR/$filename" >/dev/null
}

render_icon 16 16 "icon_16x16.png"
render_icon 32 32 "icon_16x16@2x.png"
render_icon 32 32 "icon_32x32.png"
render_icon 64 64 "icon_32x32@2x.png"
render_icon 128 128 "icon_128x128.png"
render_icon 256 256 "icon_128x128@2x.png"
render_icon 256 256 "icon_256x256.png"
render_icon 512 512 "icon_256x256@2x.png"
render_icon 512 512 "icon_512x512.png"
render_icon 1024 1024 "icon_512x512@2x.png"

echo "Generated app icon set in: $OUTPUT_DIR"
