#!/usr/bin/env bash
# Build a distributable zip for GitHub Releases (non-developer download).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export SKIP_INSTALL=1
./build.sh

APP="$ROOT/build/DerivedData/Build/Products/Release/Token Widget.app"
OUT_DIR="$ROOT/build/release"
OUT_ZIP="$OUT_DIR/Token-Widget-macOS.zip"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

(cd "$(dirname "$APP")" && zip -ry "$OUT_ZIP" "$(basename "$APP")" -x "*.DS_Store")

echo "Release zip ready:"
echo "  $OUT_ZIP"
ls -lh "$OUT_ZIP"
echo
echo "Publish with:"
echo "  gh release create v1.2.0 \"$OUT_ZIP\" --title \"Token Widget v1.2.0\" --notes-file -"
