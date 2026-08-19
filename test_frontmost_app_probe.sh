#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build_tests"
BIN="$BUILD_DIR/frontmost_app_probe_tests"

mkdir -p "$BUILD_DIR"

swiftc \
  -O \
  -framework Foundation \
  -framework CoreGraphics \
  "$ROOT_DIR/orcv/FrontmostAppProbe.swift" \
  "$ROOT_DIR/tests/FrontmostAppProbeTests.swift" \
  -o "$BIN"

"$BIN"
