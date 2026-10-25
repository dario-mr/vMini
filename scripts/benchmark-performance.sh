#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_ONLY=0
SKIP_BUILD=0
COLD_SAMPLES=5
OUTPUT_PATH=""
while (( $# )); do
  case "$1" in
    --build-only) BUILD_ONLY=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --cold-samples) shift; COLD_SAMPLES="$1" ;;
    --output) shift; OUTPUT_PATH="$1" ;;
    -h|--help)
      print "Usage: ./scripts/benchmark-performance.sh [--build-only] [--skip-build] [--cold-samples N] [--output FILE]"
      exit 0
      ;;
    *) print -u2 "Unknown option: $1"; exit 2 ;;
  esac
  shift
done

if [[ "$COLD_SAMPLES" != <-> ]] || (( COLD_SAMPLES < 5 )); then
  print -u2 "--cold-samples must be an integer of at least 5"
  exit 2
fi

if (( BUILD_ONLY && SKIP_BUILD )); then
  print -u2 "--build-only and --skip-build cannot be combined"
  exit 2
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$ROOT_DIR/profiles/benchmark-$(date '+%Y%m%d-%H%M%S')/performance-results.json"
fi
mkdir -p "$(dirname "$OUTPUT_PATH")"

if (( BUILD_ONLY )); then
  swift test -c release list >/dev/null
  exit 0
fi

if (( ! SKIP_BUILD )); then
  swift test -c release list >/dev/null
fi

BENCHMARK_FILTER='SyntaxHighlightingPerformanceTests/testReleasePerformanceCorpus|JavaHighlightingPerformanceTests/testReleaseJavaHighlighting|EditorEditingPerformanceTests/testWarmEditingScenarios'
WARM_LOG="${OUTPUT_PATH%.json}.warm.log"
LOGS=("$WARM_LOG")
TEST_FAILED=0

if VMINI_RUN_PERFORMANCE_BENCHMARK=1 swift test -c release --skip-build --no-parallel --filter "$BENCHMARK_FILTER" >"$WARM_LOG" 2>&1; then
  cat "$WARM_LOG"
else
  cat "$WARM_LOG"
  TEST_FAILED=1
fi

for sample in {1..$COLD_SAMPLES}; do
  COLD_LOG="${OUTPUT_PATH%.json}.cold-$sample.log"
  LOGS+=("$COLD_LOG")
  if VMINI_RUN_PERFORMANCE_BENCHMARK=1 VMINI_PERFORMANCE_SCENARIO=cold \
    swift test -c release --skip-build --no-parallel \
      --filter 'EditorEditingPerformanceTests/testColdMarkdownSQLInitialization' >"$COLD_LOG" 2>&1; then
    cat "$COLD_LOG"
  else
    cat "$COLD_LOG"
    TEST_FAILED=1
  fi
done

set +e
VMINI_PERF_TEST_FAILED="$TEST_FAILED" python3 scripts/compare_performance.py collect \
  --source-root "$ROOT_DIR" \
  --revision "$(git rev-parse HEAD)" \
  --build-configuration Release \
  --output "$OUTPUT_PATH" \
  --logs "${LOGS[@]}"
REPORT_STATUS=$?
set -e

if (( TEST_FAILED || REPORT_STATUS )); then
  exit 1
fi
