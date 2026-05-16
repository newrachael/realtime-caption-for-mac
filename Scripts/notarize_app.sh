#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/Realtime Caption for Mac.app"
ZIP_PATH="$ROOT_DIR/dist/RealtimeCaptionForMac.zip"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
  echo "Set NOTARYTOOL_PROFILE to an xcrun notarytool keychain profile name." >&2
  exit 1
fi

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"
