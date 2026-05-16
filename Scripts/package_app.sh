#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Realtime Caption for Mac"
PRODUCT_NAME="SoundTranslator"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
LEGACY_APP_DIR="$DIST_DIR/Sound Translator.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/cache" "$ROOT_DIR/.build/configuration" "$ROOT_DIR/.build/security" "$ROOT_DIR/.build/clang-module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"
swift build \
  -c release \
  --cache-path "$ROOT_DIR/.build/cache" \
  --config-path "$ROOT_DIR/.build/configuration" \
  --security-path "$ROOT_DIR/.build/security" \
  --manifest-cache local

rm -rf "$APP_DIR" "$LEGACY_APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/SoundTranslator.entitlements" "$RESOURCES_DIR/SoundTranslator.entitlements"

SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-"-"}"
if command -v codesign >/dev/null 2>&1; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - --entitlements "$ROOT_DIR/Resources/SoundTranslator.entitlements" "$APP_DIR"
  else
    codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --sign "$SIGN_IDENTITY" \
      --entitlements "$ROOT_DIR/Resources/SoundTranslator.entitlements" \
      "$APP_DIR"
  fi
fi

echo "$APP_DIR"
