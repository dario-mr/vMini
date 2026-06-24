#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_DURATION="45s"
DEFAULT_OUTPUT_ROOT="$ROOT_DIR/profiles"
TIME_LIMIT="$DEFAULT_DURATION"
OUTPUT_ROOT="$DEFAULT_OUTPUT_ROOT"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: scripts/profile-interactions.sh [options]

Record a vMini interaction trace from the command line using xctrace.

Options:
  --duration <time>     Trace duration, e.g. 20s, 1m. Default: 45s
  --output-dir <path>   Directory where the timestamped run folder is created.
                        Default: ./profiles
  --skip-build          Reuse the existing build instead of building first
  --help                Show this help text

Example:
  scripts/profile-interactions.sh --duration 30s
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      TIME_LIMIT="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_ROOT"

if [[ "$SKIP_BUILD" -ne 1 ]]; then
  "$ROOT_DIR/scripts/build.sh" >/dev/null
fi

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

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Executable not found at: $EXECUTABLE_PATH" >&2
  exit 1
fi

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

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$OUTPUT_ROOT/interaction-profile-$TIMESTAMP"
TRACE_PATH="$RUN_DIR/vmini.trace"
TOC_PATH="$RUN_DIR/trace-toc.xml"
META_PATH="$RUN_DIR/run-info.txt"

mkdir -p "$RUN_DIR"

cat > "$META_PATH" <<EOF
timestamp=$TIMESTAMP
app_path=$APP_PATH
executable_path=$EXECUTABLE_PATH
duration=$TIME_LIMIT
trace_path=$TRACE_PATH
EOF

cat <<EOF
Recording interaction trace to:
  $TRACE_PATH

During the next $TIME_LIMIT, reproduce these actions:
  1. Bring vMini to the foreground from the Dock while it is already open
  2. Switch tabs a few times
  3. Click files from the sidebar folders section

The recording starts as soon as xctrace launches the app.
EOF

set +e
xcrun xctrace record \
  --template "Time Profiler" \
  --instrument "Points of Interest" \
  --time-limit "$TIME_LIMIT" \
  --output "$TRACE_PATH" \
  --launch -- "$EXECUTABLE_PATH"
RECORD_EXIT_CODE=$?
set -e

if [[ "$RECORD_EXIT_CODE" -ne 0 && ! -d "$TRACE_PATH" ]]; then
  echo "xctrace failed before saving a trace (exit $RECORD_EXIT_CODE)." >&2
  exit "$RECORD_EXIT_CODE"
fi

if [[ "$RECORD_EXIT_CODE" -ne 0 ]]; then
  echo "xctrace exited with status $RECORD_EXIT_CODE, but the trace was saved. Continuing with export." >&2
fi

xcrun xctrace export --input "$TRACE_PATH" --toc --output "$TOC_PATH"

cat <<EOF

Saved files:
  Trace: $TRACE_PATH
  TOC:   $TOC_PATH
  Meta:  $META_PATH

Open the trace in Instruments if you want the timeline UI:
  open "$TRACE_PATH"
EOF
