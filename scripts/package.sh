#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/vmini.xcodeproj"
SCHEME="${SCHEME:-vMini}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/exportOptions.plist"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

cat >"$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM:-}</string>
</dict>
</plist>
EOF

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

  APP_PATH="$(find "$EXPORT_PATH" -maxdepth 2 -name '*.app' -print -quit)"
else
  APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Packaged app not found at: $APP_PATH" >&2
  exit 1
fi

ZIP_PATH="$BUILD_DIR/$SCHEME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

print -r -- "App: $APP_PATH"
print -r -- "Zip: $ZIP_PATH"
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  print -r -- "Note: DEVELOPMENT_TEAM is not set, so this archive uses local signing only."
fi
