#!/usr/bin/env bash
set -euo pipefail

log_dir="$HOME/Library/Logs/SoundTranslator"
app="/Applications/Realtime Caption for Mac.app"

sanitize_diagnostics() {
  sed \
    -e "s#$HOME#~#g" \
    -E \
    -e 's/(session\.[^|]*transcript[^|]* \| ).*/\1[redacted]/' \
    -e 's/(delta=).*( display=)/\1[redacted]\2/' \
    -e 's/(display=).*/\1[redacted]/' \
    -e 's/(transcript=).*/\1[redacted]/' \
    -e 's/(DEBUG_WAV_SELECTED path=)[^ ]+/\1[redacted]/' \
    -e 's/(INPUT_AUDIO_DUMP_(START|STOP)( format=[^ ]+ sample_rate=[^ ]+ channels=[^ ]+ bits_per_sample=[^ ]+)? path=)[^ ]+/\1[redacted]/'
}

echo "===== Realtime Caption for Mac Diagnostics ====="
date -u "+utc_now=%Y-%m-%dT%H:%M:%SZ"
echo

echo "===== Installed App ====="
if [[ -d "$app" ]]; then
  /usr/libexec/PlistBuddy -c "Print :CFBundleName" "$app/Contents/Info.plist" 2>/dev/null | sed 's/^/bundle_name=/'
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null | sed 's/^/bundle_id=/'
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null | sed 's/^/version=/'
  /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist" 2>/dev/null | sed 's/^/build=/'
  if [[ -f "$app/Contents/MacOS/SoundTranslator" ]]; then
    stat -f "binary_modified=%Sm" "$app/Contents/MacOS/SoundTranslator" 2>/dev/null || true
  fi
  codesign --verify --deep --strict "$app" >/dev/null 2>&1 && echo "codesign=ok" || echo "codesign=failed"
else
  echo "installed_app=missing"
fi
echo

echo "===== Running Process ====="
running_process="$(pgrep -fl SoundTranslator 2>/dev/null || true)"
if [[ -z "$running_process" ]]; then
  running_process="$(ps -axo pid=,command= 2>/dev/null | awk '/\/Applications\/Realtime Caption for Mac\.app\/Contents\/MacOS\/SoundTranslator/ { print $0 }' || true)"
fi
if [[ -n "$running_process" ]]; then
  echo "$running_process"
else
  echo "running_process=none"
fi
echo

echo "===== User Defaults ====="
defaults_domain="com.yurari.soundtranslator"
legacy_defaults_domain="com.gamst.soundtranslator"
for key in \
  targetLanguage \
  captureSystemAudio \
  selectedBundleIdentifier \
  selectedProcessID \
  overlayOpacity \
  overlayFontSize \
  showDockIcon
do
  value="$(defaults read "$defaults_domain" "$key" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(defaults read "$legacy_defaults_domain" "$key" 2>/dev/null || true)"
  fi
  if [[ -n "$value" ]]; then
    echo "$key=$value"
  fi
done
echo

echo "===== Recent Input Audio Dumps ====="
if compgen -G "$log_dir/input-audio-*.wav" >/dev/null; then
  ls -lh "$log_dir"/input-audio-*.wav | tail -n 10 | sed "s#$HOME#~#g"
else
  echo "input_audio_dumps=missing"
fi
echo

echo "===== Recent Diagnostics Log ====="
if [[ -f "$log_dir/diagnostics.log" ]]; then
  tail -n 260 "$log_dir/diagnostics.log" | sanitize_diagnostics
else
  echo "diagnostics.log=missing"
fi
echo

echo "===== Recent Realtime Events Log ====="
if [[ -f "$log_dir/realtime-events.log" ]]; then
  tail -n 260 "$log_dir/realtime-events.log" | sanitize_diagnostics
else
  echo "realtime-events.log=missing"
fi
