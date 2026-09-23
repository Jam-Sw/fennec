# Fennec: system-wide push-to-talk dictation for macOS

Status: approved design, ready for implementation planning
Date: 2026-09-22

## Summary

Fennec is a personal menu-bar app for macOS that turns speech into text in whatever input field is focused, including terminals, tmux, and TUI apps such as opencode. Hold Right Option, speak, release; the transcript is pasted at the cursor in under half a second. Recognition runs fully on device with Desert Ant Labs' Voz model (Parakeet TDT 0.6B v3 on the Apple Neural Engine), so no audio or text leaves the machine.

## Goals

- Dictate into any focused input: terminals (Terminal.app, iTerm2, Ghostty, tmux), AI coding CLIs (opencode, Codex CLI, Claude Code, Hermes, Antigravity, CommandCode), editors, browsers.
- On-device transcription, no cloud calls at any point.
- Release-to-text latency of 500 ms p95 or better.
- Deterministic post-processing: filler-word removal, a small set of spoken punctuation commands, and a user-editable dev-term dictionary.
- Review before submit. Auto-send is available but off by default.

## Non-goals (v1)

- Live or streaming partial transcription. Voz is a batch model; Fennec commits on release.
- LLM rewriting or summarizing of transcripts. The agent must see verbatim text.
- Per-app behavior profiles, transcript history, floating HUD overlays.
- Launch at login, auto-update, distribution to other machines, notarization.
- Languages beyond Voz's 25 European languages; English is the target.

## Constraints and decisions

- Engine: Desert Ant Labs Voz via the desert-ant-core Swift package. Batch only, 15 second encoder windows, no partials, no microphone code. Fennec owns capture, silence trimming, and insertion.
- Filler removal: Desert Ant Uhm when its API is usable; a pause-gated word list is the fallback and stays available as an escape hatch.
- Injection: clipboard write plus synthetic Cmd+V. This is the only method observed to work reliably in TUI apps; synthetic typing fragments and duplicates text in Codex and Claude Code TUIs (Handy issue #692).
- Platform: macOS 26 on Apple Silicon. Build requires Swift 6.2+; verified working with the Command Line Tools toolchain (Swift 6.3.3), so full Xcode is not needed. Tests use the swift-testing package because CLT bundles no Testing module. (Updated 2026-09-22: Xcode 26 will not be installed.)
- License: Desert Ant's Source-Available License is free below 100k monthly active devices per model. Attribution "Powered by Desert Ant Labs" appears in About and README. Fennec is a personal tool.

## Architecture

Repo: `~/Documents/tools/fennec`, a SwiftPM package.

Targets:

- `FennecCore` (library): config loading, dictionary matching, transcript pipeline, Voz and Uhm wrappers behind protocols, decision logic for clipboard restore and focus guard. Pure where possible, fully unit tested.
- `FennecApp` (executable, product name `Fennec`): menu bar presence, hotkey tap, audio recording, injection, app state machine.
- `FennecCLI` (executable, product name `fennec`): headless `fennec transcribe <file>` for testing and scripting.
- `FennecCoreTests`: unit tests.

Target names avoid case-only collisions because APFS is case-insensitive.

Components:

1. Menu bar app: LSUIElement, no Dock icon. Status states: idle, listening, working, blocked. Menu: Copy last transcript, Edit dictionary, Edit config, Permissions, Reload config, Reveal log, About, Quit.
2. Hotkey listener: CGEventTap watching `flagsChanged` for a modifier hold (default Right Option) and Escape during recording. Modifier-only keys keep flowing under Secure Input, so the app can surface a blocked state rather than failing silently. Hotkey is configurable.
3. Recorder: AVAudioEngine input tap converted to 16 kHz mono Float32, with a 0.5 s pre-roll ring buffer and a hard duration cap (default 120 s).
4. Engine: one resident Voz actor, kept warm after the first download (467 MB, downloaded on first run with progress shown in the menu). First-use ANE specialization is a one-time cost per machine.
5. Text pipeline: deterministic stages described below.
6. Injector: tagged clipboard write, synthetic Cmd+V via CGEventSource, focus guard, Secure Input check, conditional clipboard restore, and an optional real Return keystroke for auto-send.
7. CLI: `fennec transcribe <file> [--cleanup] [--dictionary] [--json]`.

## Dictation flow

1. keyDown (Right Option): record the frontmost app identity, start audio capture, icon to listening.
2. Escape while listening: discard the buffer, icon to idle.
3. keyUp: stop capture. If held less than `minDurationSeconds`, discard as too short. If the cap was reached, stop early and mark truncated.
4. Trim leading and trailing silence.
5. Voz transcribes the buffer (warm model, expected 100 to 300 ms). Empty result: re-run once on the same buffer, then report no speech.
6. Pipeline: filler removal, dictionary substitution, punctuation, capitalization.
7. If the result is empty or whitespace, report no speech and stop.
8. Focus guard: if the frontmost app changed since keyDown, do not paste. Copy the transcript to the clipboard and notify.
9. Secure Input check: if active, do not paste. Copy the transcript to the clipboard, set blocked state.
10. Inject: clipboard write, 100 ms settle, then Cmd+V as spaced CGEvent key downs and ups. Restore the previous clipboard only if it is unchanged since the write; otherwise leave it.
11. Auto-send: when armed (Shift held on release, or `always`), post a real Return keystroke 150 ms after the paste.
12. Icon to idle. Debug logging records keyUp, ready, and pasted timestamps.

Latency budget: release to ready at most 350 ms (Voz), ready to pasted at most 150 ms (paste settle plus key events). Target 500 ms p95, measured from the debug log.

## Text pipeline

Input: the Voz word list (text, start, end) plus config and dictionary. Output: the final string, possibly empty. Stage order is fixed: fillers, dictionary, punctuation, capitalization. Each stage is a pure function over words and config, so it is unit testable without audio.

Filler removal:

- Primary: Uhm filler spans. Words whose time range overlaps a span are removed.
- Decision rule: if Uhm integration is not viable in v1 (API gaps, or more than 50 ms added latency per utterance), ship the pause-gated word list instead. The stage is otherwise unchanged.
- Fallback definition: remove words in {uh, um, hmm, erm} only when pause-isolated (gaps of at least 250 ms on both sides, or at utterance edges).
- Disable with `fillerRemoval: false`.

Spoken punctuation:

- A command word counts only when isolated by at least 250 ms of silence before and after, or at an utterance edge. "for a period of time" stays intact; a standalone "period" becomes ".".
- Default commands: period and full stop -> "."; comma -> ","; question mark -> "?"; exclamation mark and exclamation point -> "!"; colon -> ":"; semicolon -> ";"; new line -> "\n"; new paragraph -> "\n\n"; open paren and open parenthesis -> "("; close paren and close parenthesis -> ")"; dash and hyphen -> "-".
- Extendable in config.json; the whole stage toggles with `punctuation: false`.

Dictionary:

- Path: `~/.config/fennec/dictionary.txt`. One entry per line: `canonical`, or `canonical = alias, alias`. Lines starting with `#` are comments.
- Matching: normalize by lowercasing and removing spaces, hyphens, and underscores. Slide a window of up to 4 words over the transcript, longest first. A window matches an alias only if the words are contiguous in time (inter-word gaps under 400 ms). On match, replace the window with the canonical string and mark the span protected. Partial words never match.
- Canonical casing always wins. Protected spans are not modified by capitalization.
- Starter entries: opencode, tmux, kubectl, GitHub, kCGEventTap, NSPasteboard, AVAudioEngine, Voz, Parakeet, Uhm, Fennec, Homebrew, Xcode, macOS, iTerm2, Ghostty, WezTerm, Codex, Hermes, Antigravity, CommandCode, Claude Code, Desert Ant.

Capitalization:

- Capitalize the first character of the transcript and the first letter after sentence-ending punctuation (. ! ?), when that character is a lowercase letter and the word is not a protected span.
- Toggle with `capitalization: false`.

## Config

Path: `~/.config/fennec/config.json`, created with defaults on first run. Reloaded from the menu; changes apply to the next dictation.

```json
{
  "hotkey": "rightOption",
  "autoSend": "off",
  "fillerRemoval": true,
  "punctuation": true,
  "capitalization": true,
  "maxDurationSeconds": 120,
  "minDurationSeconds": 0.3,
  "preRollSeconds": 0.5,
  "dictionaryPath": "~/.config/fennec/dictionary.txt",
  "debugLogging": false
}
```

- `hotkey`: rightOption | rightCommand | fn, or a function key from f13 up. Validated at load; unknown values fall back to rightOption and log a warning.
- `autoSend`: off | shift | always. Shift means Shift held while releasing the hotkey arms a Return.

## Error handling and states

| Condition | Behavior |
| --- | --- |
| Secure Input active | No paste. Transcript copied to clipboard. Blocked state and notification. |
| Frontmost app changed during recording | No paste. Transcript copied to clipboard. Notification. |
| Held under minDurationSeconds | Discard. Brief "too short" status. |
| Empty after retry | Nothing pasted. "No speech" status. |
| Max duration reached | Stop, transcribe what exists, mark "truncated" in the status. |
| Model not downloaded | Push-to-talk disabled until download completes; progress in the menu. |
| Voz throws | Nothing pasted. Error state with message in the menu and log. |
| Clipboard changed since our write | Do not restore; leave the current clipboard contents. |

## Permissions and signing

- Microphone (capture), Input Monitoring (hotkey tap), Accessibility (posting events).
- `scripts/build-app.sh`: runs `swift build -c release`, assembles `Fennec.app` (Contents/MacOS plus Info.plist with LSUIElement, NSMicrophoneUsageDescription, CFBundleIdentifier `com.jam.fennec`, version 0.1.0), and signs with a stable self-signed identity named `Fennec Local Signing`, created once in the login keychain (openssl plus `security import`) so TCC grants survive rebuilds. If identity creation fails, fall back to ad-hoc signing with a printed warning. Optional `--install` copies the app to /Applications.
- The menu shows permission status and opens the relevant System Settings panes.

## Testing

- Unit tests on pure functions: pipeline stages and ordering, pause gating, dictionary matching (aliases, casing, gap rejection), clipboard restore decision, focus guard decision, config parsing and validation.
- Integration: fixture WAVs generated with macOS `say`, plus silence and short-tap fixtures, run through `fennec transcribe --cleanup --dictionary` with expected outputs.
- Manual matrix: Terminal.app, tmux, VS Code integrated terminal, opencode, codex, hermes, TextEdit, a browser field. Results recorded in `docs/manual-test-matrix.md`.
- Latency: the debug log captures keyUp, ready, and pasted. Verify p50 and p95 across 20 dictations.

## Repo layout

```
fennec/
  Package.swift
  Sources/FennecCore/
  Sources/FennecApp/
  Sources/FennecCLI/
  Tests/FennecCoreTests/
  scripts/build-app.sh
  fixtures/
  docs/superpowers/specs/2026-09-22-fennec-design.md
  README.md
```

## Risks and validation order

1. Toolchain: confirm the Command Line Tools toolchain builds desert-ant-core and runs tests. Verified 2026-09-22: the SDK builds, the probe transcribes audio, and tests run once the swift-testing package dependency is present (CLT bundles no Testing module). Full Xcode 26 is not installed and is not required.
2. Voz latency and behavior on short utterances, including the documented 15 second window retry behavior. Validate with fixtures before building the app shell.
3. Uhm API usability for filler spans. If awkward, use the word-list fallback.
4. TCC grant persistence across rebuilds with the self-signed identity.
5. Hotkey reliability in terminals, tmux, and under Secure Input variants.

## Future work

- Streaming or near-live preview if Desert Ant ships partial results or the Cue voice activity model.
- Per-app rules (auto-send in opencode, never in a shell).
- Transcript history, floating HUD, launch at login, a preferences window.
- Optional engine swap (FluidAudio Parakeet) behind the Transcriber protocol if the Desert Ant SDK disappoints.

## Attribution

"Powered by Desert Ant Labs" appears in the About panel and README, per their source-available license. Voz and Uhm models are downloaded on first run and cached; they are not redistributed with the app.
