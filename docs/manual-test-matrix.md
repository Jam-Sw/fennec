# Manual test matrix

Run each row with `/Applications/Fennec.app`. Record pass or fail and any notes.

| Target | Paste appears | Not auto-executed | Notes |
| --- | --- | --- | --- |
| TextEdit | pass | pass | 2026-09-22, synthetic Right Option plus `say` through the mic; ready 84 to 184 ms after release |
| Terminal.app | | | |
| tmux pane | | | |
| VS Code integrated terminal | | | |
| opencode TUI | | | |
| codex TUI | | | |
| Hermes | | | |
| Browser text field | | | |

## Latency

1. Create `~/.config/fennec/config.json` with `"debugLogging": true` (the menu's Edit config
   writes a default file first; set the flag, then use Reload config).
2. Dictate 20 short prompts (5 to 15 seconds each) into any app.
3. Run:

```bash
grep -o 'total_ms=[0-9]*' ~/Library/Logs/Fennec/fennec.log | cut -d= -f2 | sort -n | \
  awk '{a[NR]=$1} END {print "n="NR, "p50="a[int(NR*0.5)], "p95="a[int(NR*0.95)]}'
```

Target: p95 at or under 500.

## Long utterance

Automated: `./scripts/long-utterance-check.sh` (68 spoken words, expects at least 61 back,
no gap in the middle).

## Permission persistence

1. Grant Microphone, Input Monitoring, and Accessibility at first launch.
2. Dictate once to confirm it works.
3. Run `./scripts/build-app.sh --install` again.
4. Quit and relaunch the app, dictate again.

Expected: still works, no new permission prompts.

## Cancel and focus-change behaviour

- Hold Right Option, speak, press Escape, release. Expected: nothing pasted.
  2026-09-22: pass (synthetic keys; log shows `cancelRecording`, nothing pasted). Not yet
  checked by hand: that the Escape stays out of the focused app, e.g. Claude Code.
- Start holding in TextEdit, speak, click Terminal before releasing. Expected: no paste,
  transcript on the clipboard, and a notification.
