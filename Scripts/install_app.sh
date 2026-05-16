#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Realtime Caption for Mac.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT_DIR/Scripts/package_app.sh"
fi

ditto "$SOURCE_APP" "$TARGET_APP"
echo "$TARGET_APP"
