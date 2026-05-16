# Realtime Caption for Mac

Research-oriented native macOS app for exploring realtime translated subtitles from approved system or app audio.

This project is intentionally built as a debuggable reference implementation rather than a polished commercial translator. It focuses on making the macOS audio-capture pipeline, OpenAI Realtime Translation session, subtitle buffering, and failure modes visible enough to inspect and iterate on.

## Project Goals

- Test OpenAI Realtime Translation with live macOS system/app audio.
- Keep the implementation small enough to read, modify, and debug.
- Expose practical diagnostics for capture permission issues, silent audio, missing transcript events, and subtitle buffering behavior.
- Avoid fallback transcription paths so API/session failures are visible instead of hidden.
- Provide a native Swift/AppKit/SwiftUI baseline for further experiments.

## Non-Goals

- This is not positioned as a production-ready commercial subtitle product.
- It does not try to hide API quirks behind alternate models or fallback services.
- It does not optimize for zero local diagnostics; debug WAV files and redacted logs are part of the research workflow.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- OpenAI API key with access to Realtime Translation

## Build

```bash
swift build
```

Create a local `.app` bundle:

```bash
./Scripts/package_app.sh
```

The packaged app is written to:

```text
dist/Realtime Caption for Mac.app
```

The packaging script keeps SwiftPM and Clang caches inside `.build` so it can run in restricted build environments.

For Developer ID signing:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" ./Scripts/package_app.sh
NOTARYTOOL_PROFILE="your-notarytool-profile" ./Scripts/notarize_app.sh
```

## Run

Use the installed app for normal testing. macOS permissions are tied to the bundle identity and install path, so running a temporary `dist` copy can create confusing permission state.

```bash
./Scripts/package_app.sh
./Scripts/install_app.sh
open -n "/Applications/Realtime Caption for Mac.app"
```

For development:

```bash
swift run SoundTranslator
```

On first capture, macOS asks for Screen & System Audio Recording permission. You can also open the permission pane from the app settings.

If permission is enabled but capture still reports that it is unavailable, remove and re-add `Realtime Caption for Mac` in System Settings > Privacy & Security > Screen & System Audio Recording. During local development the app is ad-hoc signed, and rebuilding the bundle can leave a stale TCC permission entry. You can also reset just this app's entry:

```bash
tccutil reset ScreenCapture com.yurari.soundtranslator
```

Then reopen the packaged app and approve the permission again.

## Notes

- API keys are stored in Keychain.
- Captured audio is streamed to OpenAI while translation is running.
- Diagnostic input WAV files are saved locally under `~/Library/Logs/SoundTranslator` to help debug capture/API issues.
- Diagnostic logs store counters, event names, and transcript character counts. Transcript text is redacted from app logs and from `collect_diagnostics.sh` output.
- See [PRIVACY.md](PRIVACY.md) for the full local storage and network data boundary.
- The app sends a stable random `OpenAI-Safety-Identifier` stored in user defaults.
- Primary translation uses OpenAI Realtime Translation over WebSocket: `wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate`.
- Audio is sent as base64 24 kHz mono PCM16 with `session.input_audio_buffer.append`.
- The translation session is configured with `session.audio.output.language`.
- Captions only use native `session.output_transcript.delta` events from Realtime Translation.
- If the translation session emits `session.output_audio.delta` but no `session.output_transcript.delta`, the app treats that as an API/session failure and shows an error instead of using another transcription model.
- For specific-app capture, refresh the app list and select the target app while it is running.

## Diagnostics

The app writes diagnosis logs to:

```text
~/Library/Logs/SoundTranslator/diagnostics.log
~/Library/Logs/SoundTranslator/realtime-events.log
```

To collect the useful state for debugging:

```bash
./Scripts/collect_diagnostics.sh
```

The diagnostic output includes app identity, current non-secret settings, local WAV dump paths, audio packet counters, realtime event counters, transcript character counts, and failure reasons. It does not include the OpenAI API key, raw audio bytes, or transcript text.
