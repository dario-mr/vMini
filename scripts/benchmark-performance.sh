#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VMINI_RUN_PERFORMANCE_BENCHMARK=1 swift test -c release --filter SyntaxHighlightingTests/testReleasePerformanceCorpus
