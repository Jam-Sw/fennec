<p align="center">
  <img src="assets/app-icon.png" width="160" alt="Fennec, a fennec fox with enormous ears">
</p>

<h1 align="center">Fennec</h1>

<p align="center">
  <b>Hold a key, speak, release. Your words land wherever the cursor is, including the terminal.</b><br>
  Push-to-talk dictation for macOS that runs entirely on your Mac.
</p>

<p align="center">
  <img alt="macOS 26" src="https://img.shields.io/badge/macOS-26-1C1838?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-required-3B2A5E?style=flat-square">
  <img alt="On device" src="https://img.shields.io/badge/speech-on%20device-E8854A?style=flat-square">
  <img alt="PolyForm Strict license" src="https://img.shields.io/badge/license-PolyForm%20Strict-F9BA6E?style=flat-square">
</p>

---

Fennec sits in your menu bar. Hold **Right Option**, say what you want, let go, and the
text is pasted into whatever has focus: a terminal, tmux, an AI coding agent like Claude
Code, Codex CLI, or opencode, your editor, or a browser field.

Speech recognition runs on the Apple Neural Engine with
[Desert Ant Voz](https://desertant.com/models/voz/), a Parakeet TDT 0.6B v3 build. Your
audio and your words never leave your Mac.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Jam-Sw/fennec/main/install.sh | zsh
```

That's the whole setup. The installer checks your Mac, builds Fennec from source, installs
it to `/Applications`, and opens it. Run the same command again to update.

<details>
<summary>What the installer does, and why it builds from source</summary>

1. Checks for an Apple Silicon Mac, macOS 15 or later, 5 GB of free space, and an
   internet connection, and says exactly what to do if one is missing.
2. Makes sure Apple's Command Line Tools with Swift 6.2 or later are there. If they're
   missing or too old, it installs the newest version from Apple's update server; macOS
   asks for your login password (an administrator account is needed). Full Xcode is not
   needed.
3. Clones this repo to `~/.local/share/fennec/src` and runs `swift build -c release`.
   The first build takes a few minutes. If a build fails, the log is at
   `~/Library/Logs/Fennec/install.log`.
4. Creates a local code signing certificate named "Fennec Local Signing", trusted only for
   code signing. macOS asks for your password once to trust it. A stable signature is what
   lets macOS remember your Microphone, Input Monitoring, and Accessibility grants when you
   update. Ad-hoc signed builds lose them on every update.
5. Copies `Fennec.app` to `/Applications` (or `~/Applications` if that isn't writable) and
   opens it.

Building on your own machine means there's no downloaded binary for Gatekeeper to
quarantine, and you can read every line of what you're running first. Prefer to read the
script before running it? `curl -fsSL https://raw.githubusercontent.com/Jam-Sw/fennec/main/install.sh | less`

</details>

### First launch

1. Allow **Microphone**, **Input Monitoring**, and **Accessibility** when macOS asks.
   *Permissions…* in the menu opens the right settings panes if you skip one.
2. Fennec downloads the speech model once, about 470 MB. The menu shows progress.
3. When the fox in your menu bar turns solid, you're ready.

## Use

| Do this | To |
| --- | --- |
| Hold **Right Option**, speak, release | Paste the transcript at the cursor |
| Press **Escape** while holding | Cancel; nothing is pasted |
| Hold **Shift** as you release | Paste, then press Return (needs `"autoSend": "shift"`) |

Fennec never presses Return unless you ask it to, so you can read what an agent is about
to receive before you send it.

The menu bar fox shows what's happening:

| Fox | Meaning |
| --- | --- |
| Solid | Ready |
| Orange | Listening |
| Faded | Loading the model or transcribing |
| With a dot | Needs attention; open the menu to see why |

### Talking to it

- **Punctuation**: pause briefly, then say *period*, *comma*, *question mark*,
  *exclamation mark*, *colon*, *semicolon*, *dash*, *open paren*, *close paren*,
  *new line*, or *new paragraph*. The pause keeps "a comma-separated list" from turning
  into punctuation.
- **Fillers**: a lone *uh*, *um*, *erm*, or *hmm* between pauses is dropped.
- **Dev words**: "cube control" becomes `kubectl`, "cloud code" becomes `Claude Code`, and
  so on. Add your own in the dictionary.

## Configure

*Edit config…* in the menu opens `~/.config/fennec/config.json`. After saving, choose
*Reload config*.

```json
{
  "hotkey": "rightOption",
  "autoSend": "off",
  "fillerRemoval": true,
  "punctuation": true,
  "capitalization": true,
  "punctuationCommands": { "arrow": "->" },
  "maxDurationSeconds": 120,
  "minDurationSeconds": 0.3,
  "dictionaryPath": "~/.config/fennec/dictionary.txt",
  "debugLogging": false
}
```

| Key | Values |
| --- | --- |
| `hotkey` | `rightOption` (default), `rightCommand`, `fn`, `f13` |
| `autoSend` | `off` (default), `shift` (Shift on release sends), `always` |
| `punctuationCommands` | Extra spoken commands, or new replacements for built-in ones |
| `maxDurationSeconds` | Recording stops and transcribes after this long |
| `minDurationSeconds` | Shorter presses are ignored, so a stray tap does nothing |
| `debugLogging` | Writes timings and paste decisions to `~/Library/Logs/Fennec/fennec.log` |

### Dictionary

*Edit dictionary…* opens `~/.config/fennec/dictionary.txt`, prefilled with the built-in
terms. One entry per line: the spelling you want, then what you say.

```
kubectl = cube control, cube cuddle
opencode = open code
PostgreSQL = postgres q l, post gress
```

Matching ignores case, spaces, hyphens, and underscores, and only joins words you say close
together.

## Privacy

- Audio is recorded only while you hold the key, kept in memory, and discarded after
  transcription. Audio and transcripts are never sent anywhere.
- Transcription runs on the Neural Engine. The first launch downloads the model.
- The speech engine, Desert Ant's SDK, reports anonymous usage counts to Desert Ant Labs:
  a random device ID, the app's bundle ID, and how many transcriptions ran. That's how its
  free license tier is metered. No audio or text is included.
- Pasting goes through the clipboard. Fennec puts your previous clipboard back afterwards,
  unless something else changed it in the meantime.
- Nothing is logged unless you turn on `debugLogging`, and the log holds timings and
  decisions, never your text.

**Why each permission:** Microphone to hear you. Input Monitoring to notice the hotkey
while another app is focused. Accessibility to press ⌘V (and Return, if you enable it) for
you.

## Troubleshooting

**Holding the key does nothing.** Check *System Settings → Privacy & Security → Input
Monitoring* and make sure Fennec is on. Fennec retries every couple of seconds, so it
should start working once the grant lands; if it doesn't, quit and reopen Fennec.

**I get "Transcript copied to the clipboard" instead of a paste.** Either focus moved to
another app while you were talking, or Secure Input is on (a password field, or *Secure
Keyboard Entry* in Terminal or iTerm2). Paste with ⌘V yourself, or turn Secure Keyboard
Entry off.

**"Fennec needs Accessibility access to paste."** macOS silently ignores keystrokes from
apps it doesn't trust, so Fennec checks first and leaves the transcript on the clipboard
instead. Turn Fennec on in *Privacy & Security → Accessibility*. If it's already on, remove
it with the minus button, add it back, and reopen Fennec; an old grant can belong to an
earlier build.

**Still stuck?** Set `"debugLogging": true`, quit and reopen Fennec, dictate once, and
look at `~/Library/Logs/Fennec/fennec.log`. It records permissions at launch and why
each dictation was pasted or not.

**The first dictation after launch is slow.** The model loads onto the Neural Engine on
first use, which takes a few seconds. It stays warm afterwards.

**Permissions reset after an update.** The signing certificate was probably removed from
your keychain. Run the installer again; it recreates the certificate, and you grant the
permissions one more time.

## Limitations

- Voz transcribes after you release the key, not word by word as you speak.
- 25 European languages are supported; English gets the most testing. There's no language
  detection, so other languages come out as confident nonsense.
- Filler removal is a conservative rule, not a model, so fillers said mid-sentence without
  a pause are kept.

## Build from source

```bash
git clone https://github.com/Jam-Sw/fennec.git && cd fennec
swift test                          # unit tests
./scripts/build-app.sh --install    # build, sign, and install the app
```

There's also a command line tool for transcribing files:

```bash
swift run -c release fennec transcribe recording.wav --cleanup
```

Code map: `FennecCore` holds the pure logic (text pipeline, dictionary, config, hotkey
state, paste policy) and all the tests. `FennecEngine` wraps Voz. `FennecApp` is the menu
bar app. Design notes are in [`docs/`](docs/).

## Uninstall

```bash
zsh ~/.local/share/fennec/src/uninstall.sh          # removes the app
zsh ~/.local/share/fennec/src/uninstall.sh --all    # also config, model, certificate, and grants
```

## License

Fennec is source-available under the [PolyForm Strict License 1.0.0](LICENSE). You can
read the code and use Fennec for personal, noncommercial purposes. Using it for work,
redistributing it, or publishing modified versions needs a commercial license from
[Jam-Sw](https://github.com/Jam-Sw).

Speech recognition uses Desert Ant Labs' `desert-ant-core` package and Voz model under the
[Desert Ant Labs Source-Available License](https://license.desertant.com/1.0), free below
100,000 monthly active devices per model. **Powered by
[Desert Ant Labs](https://desertant.com).**
