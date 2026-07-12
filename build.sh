#!/usr/bin/env bash
# Build + optionally install Token Widget for local use / contributors.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Install Xcode or run: xcode-select --install" >&2
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

# Optional: export DEVELOPMENT_TEAM=XXXXXXXXXX before running.
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Using DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
  # Inject into the generated project via xcodegen settings env isn't automatic —
  # pass through xcodebuild instead.
  TEAM_ARGS=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
else
  TEAM_ARGS=()
fi

xcodegen generate

echo "Building for $ARCH…"
xcodebuild -scheme TokenWidget -configuration Release \
  -derivedDataPath "$ROOT/build/DerivedData" \
  -destination "platform=macOS,arch=$ARCH" \
  ONLY_ACTIVE_ARCH=YES "ARCHS=$ARCH" \
  CODE_SIGN_STYLE=Automatic \
  "${TEAM_ARGS[@]}" \
  build

PRODUCTS="$ROOT/build/DerivedData/Build/Products/Release"
APP="$PRODUCTS/Token Widget.app"

if [[ ! -d "$APP" ]]; then
  echo "Build succeeded but app missing at: $APP" >&2
  exit 1
fi

# Prefer an explicit identity; otherwise ad-hoc sign so the binary runs locally.
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$CODE_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  IDENTITY=$(security find-identity -v -p codesigning | awk -F\" '/Apple Development/ {print $2; exit}')
else
  IDENTITY="-"
fi

echo "Signing with: $IDENTITY"
codesign --force --sign "$IDENTITY" --timestamp=none \
  --entitlements "$ROOT/App/Resources/TokenWidget.entitlements" \
  --generate-entitlement-der \
  "$APP"

if [[ "${SKIP_INSTALL:-0}" != "1" ]]; then
  DEST="/Applications/Token Widget.app"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "Installed → $DEST"
  echo "Open with: open \"$DEST\""
else
  echo "Built → $APP"
  echo "Skipped install (SKIP_INSTALL=1)."
fi
