# Fennec

Menu-bar push-to-talk dictation for macOS: hold Right Option, speak, release, and the
transcript is pasted into whatever input is focused, including terminals and TUI agents
like opencode, Codex CLI, and Claude Code.

Recognition runs fully on device with [Desert Ant Voz](https://desertant.com/models/voz/),
a Parakeet TDT 0.6B v3 build for the Apple Neural Engine. Nothing is uploaded.

## Requirements

- macOS 26 on Apple Silicon
- Swift 6.2+. The Command Line Tools toolchain is enough; full Xcode is not required.
  Tests use the swift-testing package because CLT bundles no Testing module.

## Build and install

```bash
./scripts/build-app.sh --install
```

The first run creates a local self-signed code signing identity ("Fennec Local Signing")
so Microphone, Input Monitoring, and Accessibility grants survive rebuilds. macOS may ask
for keychain access once; approve it.

## Use

- Hold **Right Option** and speak; release to insert the text.
- Press **Escape** while holding to cancel.
- Hold **Shift** when releasing to press Return after the paste, when `autoSend` is `shift`.
- The menu bar item shows Idle, Listening, Working, or an error.

## Configuration

`~/.config/fennec/config.json`:

- `hotkey`: `rightOption` (default), `rightCommand`, `fn`, or a function key from f13 up
- `autoSend`: `off` (default), `shift`, `always`
- `fillerRemoval`, `punctuation`, `capitalization`: booleans
- `punctuationCommands`: optional map of command to replacement, e.g. `{"period": "!"}`
- `maxDurationSeconds`, `minDurationSeconds`, `preRollSeconds`: numbers
- `dictionaryPath`: path to the dev-term dictionary
- `debugLogging`: writes timings to `~/Library/Logs/Fennec/fennec.log`

## Dictionary

`~/.config/fennec/dictionary.txt`, one entry per line:

```
kubectl = cube control, cube cuddle
opencode = open code
```

The canonical casing wins. Matching ignores spaces, hyphens, and underscores, and only
matches words spoken close together.

## Permissions

Microphone (recording), Input Monitoring (hotkey), Accessibility (pasting). The app signs
with a stable local identity so grants survive rebuilds.

## Limitations

- Voz is a batch model: no live word-by-word preview; text appears when you release the key.
- The first transcription after a cold start pays a model load, a few seconds in release
  builds. The app keeps the model warm afterwards.
- Filler words are removed by a conservative pause-gated rule, not a model. Uhm measured
  about 140 ms per utterance against a 50 ms budget, so it is parked; see docs/sdk-notes.md.
- Secure Input (password prompts, terminal Secure Keyboard Entry) blocks pasting by design;
  the transcript goes to the clipboard instead.

Powered by Desert Ant Labs.
