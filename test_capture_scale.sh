#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build_tests"
BIN="$BUILD_DIR/capture_scale_tests"

mkdir -p "$BUILD_DIR"

swiftc \
  -O \
  -framework Foundation \
  -framework CoreGraphics \
  "$ROOT_DIR/orcv/CaptureScale.swift" \
  "$ROOT_DIR/tests/CaptureScaleTests.swift" \
  -o "$BIN"

"$BIN"
