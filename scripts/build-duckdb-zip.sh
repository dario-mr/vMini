#!/bin/zsh
# Rebuilds Packages/DuckDB/Cduckdb.xcframework.zip from DuckDB's prebuilt macOS library. Run when bumping DuckDB.

set -euo pipefail

VERSION="1.1.3"
SHA256="35d2d1c7da9770ccd70590f50313045382a44d06070580c0abf4e8eb2cccc405"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT_DIR/Packages/DuckDB/Cduckdb.xcframework.zip"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL -o "$WORK_DIR/lib.zip" \
  "https://github.com/duckdb/duckdb/releases/download/v$VERSION/libduckdb-osx-universal.zip"
echo "$SHA256  $WORK_DIR/lib.zip" | shasum -a 256 -c --status || { echo "Checksum mismatch for libduckdb-osx-universal.zip v$VERSION" >&2; exit 1; }
unzip -q "$WORK_DIR/lib.zip" -d "$WORK_DIR/lib"

# macOS frameworks need the versioned layout for codesign and embedding.
FRAMEWORK="$WORK_DIR/Cduckdb.framework"
VERSION_DIR="$FRAMEWORK/Versions/A"
mkdir -p "$VERSION_DIR/Headers" "$VERSION_DIR/Modules" "$VERSION_DIR/Resources"
cp "$WORK_DIR/lib/libduckdb.dylib" "$VERSION_DIR/Cduckdb"
cp "$WORK_DIR/lib/duckdb.h" "$VERSION_DIR/Headers/"
install_name_tool -id "@rpath/Cduckdb.framework/Versions/A/Cduckdb" "$VERSION_DIR/Cduckdb"

cat >"$VERSION_DIR/Modules/module.modulemap" <<'EOF'
framework module Cduckdb {
  umbrella header "duckdb.h"
  export *
}
EOF

cat >"$VERSION_DIR/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Cduckdb</string>
  <key>CFBundleIdentifier</key>
  <string>org.duckdb.Cduckdb</string>
  <key>CFBundleName</key>
  <string>Cduckdb</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
</dict>
</plist>
EOF

ln -s A "$FRAMEWORK/Versions/Current"
for entry in Cduckdb Headers Modules Resources; do
  ln -s "Versions/Current/$entry" "$FRAMEWORK/$entry"
done
codesign --force --sign - "$FRAMEWORK"

xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$WORK_DIR/Cduckdb.xcframework" >/dev/null
rm -f "$OUTPUT"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$WORK_DIR/Cduckdb.xcframework" "$OUTPUT"
