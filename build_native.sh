#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$ROOT_DIR/build"
mkdir -p "$OUT_DIR"
TMP_OUT="$OUT_DIR/libfanbridge.dylib.tmp"
FINAL_OUT="$OUT_DIR/libfanbridge.dylib"

clang \
  -dynamiclib \
  -fPIC \
  -O2 \
  -Wall \
  -Wextra \
  -framework Foundation \
  -framework IOKit \
  -framework CoreFoundation \
  -L/usr/lib \
  "$ROOT_DIR/native/smc_bridge.c" \
  "$ROOT_DIR/native/fan_bridge.m" \
  -lIOReport \
  -o "$TMP_OUT"

mv -f "$TMP_OUT" "$FINAL_OUT"

echo "Built $FINAL_OUT"
