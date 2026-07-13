#!/usr/bin/env bash
# Build, Developer ID-sign, notarize, staple, and zip Token Widget for public download.
#
# Required once on this Mac:
#   1. Developer ID Application certificate in Keychain
#   2. App Store Connect API key for notarytool (or a keychain profile)
#
# Env (API key auth):
#   APPLE_API_KEY_PATH   path to AuthKey_XXXX.p8
#   APPLE_API_KEY_ID     e.g. 7V5M44TZCG
#   APPLE_API_ISSUER    UUID from App Store Connect → Users and Access → Integrations
#
# Or keychain profile:
#   NOTARY_PROFILE      name from: xcrun notarytool store-credentials
#
# Optional:
#   DEVELOPMENT_TEAM    default XK6AQX4LZN
#   RELEASE_TAG         e.g. v1.2.1 (if set with PUBLISH=1, uploads to GitHub)
#   PUBLISH=1           create/update GitHub release with the notarized zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM="${DEVELOPMENT_TEAM:-XK6AQX4LZN}"
OUT_DIR="$ROOT/build/release"
APP_NAME="Token Widget.app"
ZIP_NAME="Token-Widget-macOS.zip"
STAGING="$OUT_DIR/staging"

die() { echo "error: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

need_cmd xcodegen
need_cmd xcodebuild
need_cmd codesign
need_cmd ditto
need_cmd xcrun

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F\" '/Developer ID Application/ {print $2; exit}')
[[ -n "${IDENTITY:-}" ]] || die "No 'Developer ID Application' certificate in Keychain.
Create one at https://developer.apple.com/account/resources/certificates/add
(CSR is at build/signing/TokenWidget_DeveloperID.certSigningRequest), install the .cer, then re-run."

echo "Using identity: $IDENTITY"
echo "Team: $TEAM"

export DEVELOPMENT_TEAM="$TEAM"
export SKIP_INSTALL=1
export CODE_SIGN_IDENTITY="$IDENTITY"
./build.sh

SRC_APP="$ROOT/build/DerivedData/Build/Products/Release/$APP_NAME"
[[ -d "$SRC_APP" ]] || die "build missing: $SRC_APP"

rm -rf "$OUT_DIR"
mkdir -p "$STAGING"
ditto "$SRC_APP" "$STAGING/$APP_NAME"
APP="$STAGING/$APP_NAME"

echo "Re-signing with Developer ID + hardened runtime + secure timestamp…"
codesign --force --deep --options runtime --timestamp \
  --sign "$IDENTITY" \
  --entitlements "$ROOT/App/Resources/TokenWidget.entitlements" \
  --generate-entitlement-der \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 || true

SUBMIT_ZIP="$OUT_DIR/Token-Widget-submit.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

echo "Submitting to Apple notary service…"
NOTARY_ARGS=(submit "$SUBMIT_ZIP" --wait)
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS+=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
  NOTARY_ARGS+=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
else
  die "Set NOTARY_PROFILE or APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER"
fi

xcrun notarytool "${NOTARY_ARGS[@]}"

echo "Stapling notarization ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

OUT_ZIP="$OUT_DIR/$ZIP_NAME"
rm -f "$OUT_ZIP"
(cd "$STAGING" && zip -ry "$OUT_ZIP" "$APP_NAME" -x "*.DS_Store")
rm -f "$SUBMIT_ZIP"

echo
echo "Notarized zip ready:"
echo "  $OUT_ZIP"
ls -lh "$OUT_ZIP"
spctl --assess --type execute --verbose=4 "$APP"

if [[ "${PUBLISH:-0}" == "1" ]]; then
  TAG="${RELEASE_TAG:-}"
  [[ -n "$TAG" ]] || die "PUBLISH=1 requires RELEASE_TAG (e.g. v1.2.1)"
  need_cmd gh
  NOTES="${RELEASE_NOTES:-Notarized macOS build (Apple Silicon). Double-click to open — no right-click Gatekeeper step.}"
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$OUT_ZIP" --clobber
  else
    gh release create "$TAG" "$OUT_ZIP" --title "Token Widget ${TAG}" --notes "$NOTES"
  fi
  echo "Published: https://github.com/adityarai7297/token-widget/releases/tag/$TAG"
fi
