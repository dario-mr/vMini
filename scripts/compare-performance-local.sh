#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BASE_REF=""
while (( $# )); do
  case "$1" in
    --base)
      if (( $# < 2 )); then echo "--base requires a commit or ref" >&2; exit 2; fi
      BASE_REF="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/compare-performance-local.sh [--base REF]

By default, compare the current checkout with the merge base of HEAD and
origin/main. --base uses the exact commit resolved by REF.
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$BASE_REF" ]]; then
  if ! BASE_SHA="$(git rev-parse --verify "${BASE_REF}^{commit}" 2>/dev/null)"; then
    echo "Cannot resolve base commit: $BASE_REF" >&2
    exit 2
  fi
else
  # shortcut: origin/main may be stale; fetch it when the latest remote baseline matters.
  if ! git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "No local origin/main ref. Fetch it with 'git fetch origin main' or pass --base REF." >&2
    exit 2
  fi
  if ! BASE_SHA="$(git merge-base HEAD origin/main)"; then
    echo "Cannot find a merge base between HEAD and origin/main." >&2
    exit 2
  fi
fi

OUTPUT_DIR="$ROOT_DIR/profiles/performance-regression-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$(dirname "$OUTPUT_DIR")"
if ! mkdir "$OUTPUT_DIR"; then
  echo "Output directory already exists: $OUTPUT_DIR" >&2
  exit 2
fi

BASE_WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/vmini-perf-base.XXXXXX")"
WORKTREE_ADDED=0
cleanup() {
  if (( WORKTREE_ADDED )); then
    git -C "$ROOT_DIR" worktree remove --force "$BASE_WORKTREE" >/dev/null 2>&1 || rm -rf "$BASE_WORKTREE"
  else
    rmdir "$BASE_WORKTREE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

git worktree add --detach "$BASE_WORKTREE" "$BASE_SHA"
WORKTREE_ADDED=1

PERFORMANCE_TESTS=(
  Tests/vminiTests/Features/Editor/EditorEditingPerformanceTests.swift
  Tests/vminiTests/Features/Editor/SyntaxHighlighting/JavaHighlightingPerformanceTests.swift
  Tests/vminiTests/Support/PerformanceBenchmark.swift
  Tests/vminiTests/Features/Editor/SyntaxHighlighting/SyntaxHighlightingPerformanceTests.swift
)
for path in "${PERFORMANCE_TESTS[@]}"; do
  if [[ ! -f "$ROOT_DIR/$path" ]]; then
    echo "Missing current benchmark file: $path" >&2
    exit 2
  fi
  mkdir -p "$BASE_WORKTREE/$(dirname "$path")"
  rm -f "$BASE_WORKTREE/Tests/vminiTests/$(basename "$path")"
  cp -p "$ROOT_DIR/$path" "$BASE_WORKTREE/$path"
done
rsync -a --delete "$ROOT_DIR/Tests/vminiTests/PerformanceCorpus/" "$BASE_WORKTREE/Tests/vminiTests/PerformanceCorpus/"
mkdir -p "$BASE_WORKTREE/scripts"
for path in scripts/benchmark-performance.sh scripts/compare_performance.py scripts/performance-budgets.json; do
  cp -p "$ROOT_DIR/$path" "$BASE_WORKTREE/$path"
done

run_build() {
  local side="$1"
  local worktree="$2"
  local log="$OUTPUT_DIR/$side-build.log"
  if (cd "$worktree" && ./scripts/benchmark-performance.sh --build-only) >"$log" 2>&1; then
    cat "$log"
  else
    cat "$log"
    echo "$side Release build failed; see $log" >&2
    return 1
  fi
}

run_build base "$BASE_WORKTREE"
run_build candidate "$ROOT_DIR"

FAILED=0
for batch in 1 2 3; do
  if (( batch % 2 )); then
    FIRST=base
    SECOND=candidate
  else
    FIRST=candidate
    SECOND=base
  fi
  for side in "$FIRST" "$SECOND"; do
    if [[ "$side" == base ]]; then
      WORKTREE="$BASE_WORKTREE"
    else
      WORKTREE="$ROOT_DIR"
    fi
    OUTPUT="$OUTPUT_DIR/$side-$batch.json"
    if (cd "$WORKTREE" && ./scripts/benchmark-performance.sh --skip-build --cold-samples 5 --output "$OUTPUT"); then
      :
    else
      FAILED=1
    fi
  done
done

COMPARE_ARGS=(
  compare
  --budgets "$ROOT_DIR/scripts/performance-budgets.json"
  --summary "$OUTPUT_DIR/summary.md"
  --report "$OUTPUT_DIR/comparison.json"
)
for batch in 1 2 3; do
  COMPARE_ARGS+=(--base "$OUTPUT_DIR/base-$batch.json")
  COMPARE_ARGS+=(--candidate "$OUTPUT_DIR/candidate-$batch.json")
done

COMPARE_STATUS=0
python3 "$ROOT_DIR/scripts/compare_performance.py" "${COMPARE_ARGS[@]}" || COMPARE_STATUS=$?
echo "Reports and logs: $OUTPUT_DIR"
echo "Summary: $OUTPUT_DIR/summary.md"
if (( FAILED || COMPARE_STATUS )); then
  exit 1
fi
