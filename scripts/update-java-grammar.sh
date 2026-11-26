#!/bin/zsh
# Re-vendors Packages/TreeSitterJavaGrammar from an upstream tree-sitter-java tag, e.g. v0.23.5.
# Afterwards run `swift test`: SyntaxHighlightingIssueTests fails if the new grammar can't parse the Java sample,
# and it crashes if TreeSitterSyntaxGrammar's extra Java query names node types the grammar dropped.

set -euo pipefail

TAG="${1:?usage: update-java-grammar.sh <tree-sitter-java tag, e.g. v0.23.5>}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Packages/TreeSitterJavaGrammar"
GRAMMAR_DIR="$PACKAGE_DIR/Sources/TreeSitterJavaGrammar"
QUERIES_DIR="$PACKAGE_DIR/Sources/TreeSitterJavaGrammarQueries"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" \
  https://github.com/tree-sitter/tree-sitter-java "$WORK_DIR/upstream"
UPSTREAM="$WORK_DIR/upstream"
COMMIT="$(git -C "$UPSTREAM" rev-parse --short HEAD)"

cp "$UPSTREAM/src/parser.c" "$GRAMMAR_DIR/parser.c"
rm -rf "$GRAMMAR_DIR/tree_sitter"
cp -R "$UPSTREAM/src/tree_sitter" "$GRAMMAR_DIR/tree_sitter"
cp "$UPSTREAM/bindings/swift/TreeSitterJava/java.h" "$GRAMMAR_DIR/include/tree_sitter_java.h"
cp "$UPSTREAM/queries/highlights.scm" "$QUERIES_DIR/highlights.scm"
cp "$UPSTREAM/LICENSE" "$PACKAGE_DIR/LICENSE"

sed -i '' -E "s|^// Vendored from tree-sitter-java [^ ]+ \([0-9a-f]+\)|// Vendored from tree-sitter-java $TAG ($COMMIT)|" \
  "$PACKAGE_DIR/Package.swift"

echo "Vendored tree-sitter-java $TAG ($COMMIT) with grammar ABI $(sed -nE 's/^#define LANGUAGE_VERSION ([0-9]+)/\1/p' "$GRAMMAR_DIR/parser.c")."
echo "Now run: swift test"
