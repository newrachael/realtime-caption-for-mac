#!/usr/bin/env bash
set -euo pipefail

bundle_id="com.yurari.soundtranslator"

echo "Resetting macOS capture permissions for $bundle_id"
tccutil reset ScreenCapture "$bundle_id" >/dev/null 2>&1 || true
tccutil reset AudioCapture "$bundle_id" >/dev/null 2>&1 || true

echo "Done. Reopen Realtime Caption for Mac, then grant Screen & System Audio Recording when macOS asks."
