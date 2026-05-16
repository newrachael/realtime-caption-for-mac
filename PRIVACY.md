# Privacy

Realtime Caption for Mac is a local macOS app that streams user-approved system or app audio to OpenAI Realtime Translation so it can display translated subtitles.

## Data Sent To OpenAI

- Captured audio is converted to 24 kHz mono PCM16 and sent to OpenAI while translation is running.
- The app uses `gpt-realtime-translate` through `wss://api.openai.com/v1/realtime/translations`.
- The selected target language is sent in the realtime session configuration.
- A stable random `OpenAI-Safety-Identifier` is stored in local user defaults and sent with requests.

## Data Stored Locally

- The OpenAI API key is stored in macOS Keychain.
- App preferences are stored in macOS UserDefaults under `com.yurari.soundtranslator`.
- Diagnostic logs are written under `~/Library/Logs/SoundTranslator`.
- Diagnostic input WAV files are written under `~/Library/Logs/SoundTranslator` for capture/API debugging.

## Diagnostic Logs

Diagnostic logs include app identity, non-secret settings, audio packet counters, realtime event counters, transcript character counts, and failure reasons.

Transcript text is redacted in app diagnostic logs and in `Scripts/collect_diagnostics.sh` output. The diagnostics script also prints only a fixed allowlist of UserDefaults keys instead of dumping the full preferences domain.

## User Control

You can delete local diagnostics at any time:

```bash
rm -rf ~/Library/Logs/SoundTranslator
```

You can delete app preferences with:

```bash
defaults delete com.yurari.soundtranslator
```

You can remove the stored OpenAI API key by clearing the API key field in the app settings and saving.
