#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build_tests"
BIN="$BUILD_DIR/display_arrangement_tests"

mkdir -p "$BUILD_DIR"

swiftc \
  -O \
  -framework Foundation \
  -framework CoreGraphics \
  "$ROOT_DIR/orcv/DisplayArrangement.swift" \
  "$ROOT_DIR/tests/DisplayArrangementTests.swift" \
  -o "$BIN"

"$BIN"
