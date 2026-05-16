#!/usr/bin/env bash
set -euo pipefail

pids="$(pgrep -x SoundTranslator 2>/dev/null || true)"

if [[ -z "$pids" ]]; then
  pids="$(ps -axo pid=,command= 2>/dev/null | awk '/\/Applications\/Realtime Caption for Mac\.app\/Contents\/MacOS\/SoundTranslator/ { print $1 }' || true)"
fi

if [[ -z "$pids" ]]; then
  echo "Realtime Caption for Mac is not running."
  exit 0
fi

while IFS= read -r pid; do
  [[ -n "$pid" ]] || continue
  kill "$pid"
done <<< "$pids"

echo "Stopped Realtime Caption for Mac: ${pids//$'\n'/, }"
