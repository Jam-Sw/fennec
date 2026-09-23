# Changelog

## 0.1.0 (unreleased)

First public release, source-available under the PolyForm Strict License 1.0.0.

- Push-to-talk dictation from the menu bar: hold Right Option, speak, release, and the
  transcript is pasted at the cursor, including terminals and TUI coding agents.
- On-device recognition with Desert Ant Voz on the Neural Engine.
- Spoken punctuation, filler removal, and a dev-term dictionary, all configurable.
- One-line installer that builds from source and signs with a local identity so
  permission grants survive updates; uninstaller with `--all`.
- Fennec the fox: app icon and a menu bar glyph that shows ready, listening, working, and
  needs-attention states. Model download progress in the menu. Launch at login.
- Checks Accessibility before pasting and keeps the transcript on the clipboard, with a
  notification, instead of losing it when macOS would drop the keystrokes.
- Escape that cancels a dictation no longer reaches the focused app.
- ⌘V follows the active keyboard layout, so pasting works on Dvorak, AZERTY, and others.
- Editing the dictionary starts from the built-in terms instead of replacing them with an
  empty file.
- Reloading the config applies a new hotkey without a relaunch.
