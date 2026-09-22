# Fennec Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Fennec, a macOS menu-bar push-to-talk dictation app that transcribes speech on device with Desert Ant Voz and pastes it into any focused input, including terminals and TUI agents.

**Architecture:** A SwiftPM package with four targets. FennecCore holds pure logic: config, dictionary, text pipeline, policy decisions. FennecEngine wraps the Desert Ant SDK (Voz, optionally Uhm) behind FennecCore protocols. FennecApp is the menu bar app: CGEventTap hotkey, AVAudioEngine capture, clipboard injection. FennecCLI is the headless test and scripting surface. Pure logic is built test-first; hardware and UI wiring is verified with explicit manual steps.

**Tech Stack:** Swift 6.2 (Xcode 26), SwiftPM, Swift Testing, AppKit, CoreGraphics, AVFoundation, IOKit, Desert Ant desert-ant-core 3.3.1+ (Voz, Uhm), macOS 26 on Apple Silicon.

**Spec:** `docs/superpowers/specs/2026-09-22-fennec-design.md`

## Global Constraints

- Repo root: `~/Documents/tools/fennec`. Every command in this plan runs from there.
- macOS 26 on Apple Silicon. Swift 6.2+ with full Xcode 26. As of 2026-09-22 Xcode is NOT installed yet, so Task 1 starts with that check.
- Desert Ant SDK: `desert-ant-core`, `.package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "3.3.1")`. Confirm the newest tag during Task 1.
- Everything runs on device. The only network use is the one-time model download from Hugging Face.
- Injection is clipboard plus synthetic Cmd+V only, never synthetic typing (synthetic typing fragments in TUI apps).
- No streaming partials. Voz is a batch model; Fennec commits on key release.
- Config path: `~/.config/fennec/config.json`. Dictionary path: `~/.config/fennec/dictionary.txt`.
- Tests use Swift Testing: `import Testing`, `@Test`, `#expect`, `#require`.
- Commits: conventional commits, lowercase, imperative, optional scope. Author `jamubc <150970140+jamubc@users.noreply.github.com>`. No AI attribution trailers. No em dashes in any file.
- "Powered by Desert Ant Labs" appears in README and the About item, per the Desert Ant license.
- Latency target: release to pasted at most 500 ms p95.

## Refinements vs the Spec (flagged for review)

1. Extra `FennecEngine` target so FennecCore and its tests never depend on the Desert Ant package. The spec's FennecCore description still holds; the SDK wrappers live in FennecEngine behind FennecCore protocols.
2. Config gains an optional `punctuationCommands` string map, implementing the spec line "Extendable in config.json".
3. Dictionary windows match up to 5 words so `k c g event tap` can map to `kCGEventTap` (the spec said 4).

## Review Focus

Five failure classes most likely to bite a user, and the task that pins each with a test:

1. The clipboard changes during the roughly 100 ms paste window; no clobbering the new contents. Test in Task 10.
2. Spoken command words used as ordinary words ("for a period of time", "add a comma here") stay literal. Tests in Task 3.
3. Silence or room noise must never paste hallucinated text. Tests in Task 7 plus the CLI silence check in Task 8.
4. Utterances over Voz's 15 second window can drop or truncate a middle window. Manual 30 second dictation check in Task 14.
5. Secure Input or a focus change mid-utterance must never paste into the wrong place. Policy tests in Task 10 plus manual checks in Task 14.

---

### Task 1: Scaffold the package and validate Desert Ant Voz

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `README.md`
- Create: `Sources/FennecCore/Version.swift`
- Create: `Sources/FennecEngine/EngineProbe.swift`
- Create: `Sources/FennecApp/main.swift`
- Create: `Sources/FennecCLI/main.swift`
- Create: `scripts/make-fixtures.sh`
- Create: `docs/sdk-notes.md`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: package targets `FennecCore`, `FennecEngine`, `FennecApp`, `FennecCLI`, `FennecCoreTests`; the `fennec probe <audio-file>` CLI command; `EngineProbe.transcribeFile(at:) async throws -> String`; fixture generation; `docs/sdk-notes.md` with the SDK's exact API.

- [ ] **Step 1: Verify Xcode 26 is installed and selected**

Run: `xcode-select -p && xcodebuild -version`
Expected: path starts with `/Applications/Xcode`, and a version line starting with `Xcode 26`.
If not: install Xcode from the App Store, then run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and `sudo xcodebuild -runFirstLaunch`.

- [ ] **Step 2: Check the newest desert-ant-core tag**

Run: `git ls-remote --tags https://github.com/Desert-Ant-Labs/desert-ant-core.git | tail -5`
Expected: tag list. Write down the newest version tag (for example `3.3.1` or higher). Use it in the next step.

- [ ] **Step 3: Create Package.swift**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fennec",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Fennec", targets: ["FennecApp"]),
        .executable(name: "fennec", targets: ["FennecCLI"]),
        .library(name: "FennecCore", targets: ["FennecCore"]),
        .library(name: "FennecEngine", targets: ["FennecEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "3.3.1"),
    ],
    targets: [
        .target(name: "FennecCore"),
        .target(name: "FennecEngine", dependencies: [
            "FennecCore",
            .product(name: "Voz", package: "desert-ant-core"),
        ]),
        .executableTarget(name: "FennecApp", dependencies: ["FennecCore", "FennecEngine"]),
        .executableTarget(name: "FennecCLI", dependencies: ["FennecCore", "FennecEngine"]),
        .testTarget(name: "FennecCoreTests", dependencies: ["FennecCore"]),
    ]
)
```

Replace `from: "3.3.1"` if the newest tag from Step 2 is higher.

- [ ] **Step 4: Create .gitignore**

```gitignore
.build/
.swiftpm/
.DS_Store
fixtures/*.aiff
fixtures/*.wav
*.p12
*.pem
```

- [ ] **Step 5: Create the README stub**

```markdown
# Fennec

Menu-bar push-to-talk dictation for macOS: hold Right Option, speak, release, and the
transcript is pasted into whatever input is focused, including terminals and TUI agents.
Recognition runs on device with Desert Ant Voz.

Powered by Desert Ant Labs.

Build and usage: see docs/superpowers/plans/2026-09-22-fennec-implementation.md
```

- [ ] **Step 6: Create the source stubs**

`Sources/FennecCore/Version.swift`:

```swift
import Foundation

public let fennecVersion = "0.1.0"
```

`Sources/FennecApp/main.swift`:

```swift
import Foundation

print("Fennec app scaffold. The menu bar app arrives in Task 12.")
```

`Sources/FennecEngine/EngineProbe.swift`:

```swift
import Foundation
import Voz

/// Minimal end-to-end check: file in, transcript out. Replaced by VozTranscriber in Task 8.
public enum EngineProbe {
    public static func transcribeFile(at url: URL) async throws -> String {
        let voz = try await Voz()
        let result = try await voz.transcribe(url)
        return result.text
    }
}
```

- [ ] **Step 7: Create the CLI with the probe command**

`Sources/FennecCLI/main.swift`:

```swift
import Foundation
import FennecEngine

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("usage: fennec <command> [options]\ncommands: probe <audio-file>", code: 64)
}

let command = arguments[1]
let rest = Array(arguments.dropFirst(2))

switch command {
case "probe":
    guard let path = rest.first else { fail("usage: fennec probe <audio-file>", code: 64) }
    do {
        let text = try await EngineProbe.transcribeFile(at: URL(fileURLWithPath: path))
        print(text)
    } catch {
        fail("\(error)")
    }
default:
    fail("unknown command '\(command)'", code: 64)
}
```

- [ ] **Step 8: Create the fixture script and generate fixtures**

`scripts/make-fixtures.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p fixtures

say -o fixtures/hello.aiff "Fennec dictation test. Send this to open code. [[slnc 500]] New line. Done."
afconvert -f WAVE -d LEI16@16000 -c 1 fixtures/hello.aiff fixtures/hello.wav

python3 - <<'PY'
import wave
with wave.open('fixtures/silence.wav', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(16000)
    w.writeframes(b'\x00\x00' * 16000 * 2)
PY

echo "wrote fixtures/hello.wav and fixtures/silence.wav"
```

Run: `chmod +x scripts/make-fixtures.sh && ./scripts/make-fixtures.sh`
Expected: `wrote fixtures/hello.wav and fixtures/silence.wav`

- [ ] **Step 9: Build**

Run: `swift build`
Expected: resolves desert-ant-core, compiles all targets. First run takes a few minutes.

- [ ] **Step 10: Run the probe against the fixture**

Run: `swift run fennec probe fixtures/hello.wav`
Expected: first run downloads the Voz model (467 MB) and takes a long time once for ANE specialization; then prints a transcript containing "Fennec", "open code" or "opencode", and "Done" (exact wording may vary slightly).
If the API in `EngineProbe.swift` does not match the SDK, fix only that file, then re-run.

- [ ] **Step 11: Record the exact SDK API in docs/sdk-notes.md**

Inspect `.build/checkouts/desert-ant-core/Sources/Voz/` and the package README, then write `docs/sdk-notes.md`:

```markdown
# Desert Ant SDK notes

Recorded from .build/checkouts/desert-ant-core at version <tag from Step 2>, 2026-09-22.

## Voz
- Init signature:
- Model download API:
- isDownloaded API:
- transcribe overloads:
- Result fields:
- Error cases:
- First-load and warm-load timings observed:
- Empty/silence behavior observed:

## Uhm (evaluated in Task 9)
- API surface:
- Latency observed:
```

Fill every line from the actual sources. Task 8 depends on these exact signatures.

- [ ] **Step 12: Commit**

```bash
git add Package.swift .gitignore README.md Sources scripts docs/sdk-notes.md
git commit -m "feat: scaffold swift package and validate voz transcription"
```

---

### Task 2: Core types and config

**Files:**
- Create: `Sources/FennecCore/Types.swift`
- Create: `Sources/FennecCore/Config.swift`
- Test: `Tests/FennecCoreTests/ConfigTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 except the package layout.
- Produces: `Word(text:start:end:)`, `Transcript(text:words:)`, `Token(text:start:end:isProtected:spacing:)`, `TokenSpacing` (`.normal`, `.attachBefore`, `.attachAfter`, `.ownLine`), `Word.token`, `Hotkey`, `AutoSendMode`, `Config` with defaults, `Config.defaultConfigURL`, `Config.dictionaryURL`, `Config.loadOrCreate(at:)`, `Config.decode(_:)`, `Config.write(_:to:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/ConfigTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func defaultConfigValues() {
    let config = Config()
    #expect(config.hotkey == .rightOption)
    #expect(config.autoSend == .off)
    #expect(config.fillerRemoval)
    #expect(config.punctuation)
    #expect(config.capitalization)
    #expect(config.maxDurationSeconds == 120)
    #expect(config.minDurationSeconds == 0.3)
    #expect(config.preRollSeconds == 0.5)
    #expect(config.dictionaryPath == "~/.config/fennec/dictionary.txt")
    #expect(config.debugLogging == false)
    #expect(config.punctuationCommands.isEmpty)
}

@Test func loadOrCreateWritesDefaultsOnFirstRun() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json")
    let (config, warnings) = try Config.loadOrCreate(at: url)
    #expect(config == Config())
    #expect(warnings.isEmpty)
    #expect(FileManager.default.fileExists(atPath: url.path))
    let (again, _) = try Config.loadOrCreate(at: url)
    #expect(again == config)
}

@Test func unknownHotkeyFallsBackWithWarning() throws {
    let (config, warnings) = try Config.decode(Data(#"{"hotkey": "leftShift"}"#.utf8))
    #expect(config.hotkey == .rightOption)
    #expect(warnings == ["unknown hotkey 'leftShift', falling back to rightOption"])
}

@Test func unknownAutoSendFallsBackWithWarning() throws {
    let (config, warnings) = try Config.decode(Data(#"{"autoSend": "sometimes"}"#.utf8))
    #expect(config.autoSend == .off)
    #expect(warnings == ["unknown autoSend 'sometimes', falling back to off"])
}

@Test func knownValuesAndOverridesParse() throws {
    let json = #"{"hotkey": "fn", "autoSend": "always", "punctuationCommands": {"period": "!"}, "debugLogging": true}"#
    let (config, warnings) = try Config.decode(Data(json.utf8))
    #expect(config.hotkey == .fn)
    #expect(config.autoSend == .always)
    #expect(config.punctuationCommands["period"] == "!")
    #expect(config.debugLogging)
    #expect(warnings.isEmpty)
}

@Test func dictionaryURLExpandsTilde() {
    #expect(Config().dictionaryURL.path.hasPrefix("/Users/"))
    #expect(Config().dictionaryURL.path.hasSuffix("/.config/fennec/dictionary.txt"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigTests`
Expected: compile failure, `cannot find 'Config' in scope`.

- [ ] **Step 3: Write Types.swift**

```swift
import Foundation

public struct Word: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }

    public var token: Token {
        Token(text: text, start: start, end: end)
    }
}

public struct Transcript: Equatable, Sendable {
    public var text: String
    public var words: [Word]

    public init(text: String, words: [Word]) {
        self.text = text
        self.words = words
    }
}

public enum TokenSpacing: Equatable, Sendable {
    case normal
    case attachBefore
    case attachAfter
    case ownLine
}

public struct Token: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var isProtected: Bool
    public var spacing: TokenSpacing

    public init(
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        isProtected: Bool = false,
        spacing: TokenSpacing = .normal
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.isProtected = isProtected
        self.spacing = spacing
    }
}
```

- [ ] **Step 4: Write Config.swift**

```swift
import Foundation

public enum Hotkey: String, Codable, CaseIterable, Sendable {
    case rightOption
    case rightCommand
    case fn
    case f13
}

public enum AutoSendMode: String, Codable, CaseIterable, Sendable {
    case off
    case shift
    case always
}

public struct Config: Codable, Equatable, Sendable {
    public var hotkey: Hotkey = .rightOption
    public var autoSend: AutoSendMode = .off
    public var fillerRemoval: Bool = true
    public var punctuation: Bool = true
    public var capitalization: Bool = true
    public var maxDurationSeconds: Double = 120
    public var minDurationSeconds: Double = 0.3
    public var preRollSeconds: Double = 0.5
    public var dictionaryPath: String = "~/.config/fennec/dictionary.txt"
    public var debugLogging: Bool = false
    public var punctuationCommands: [String: String] = [:]

    public static let `default` = Config()

    public init() {}

    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/fennec/config.json")
    }

    public var dictionaryURL: URL {
        URL(fileURLWithPath: (dictionaryPath as NSString).expandingTildeInPath)
    }

    public static func loadOrCreate(at url: URL = Config.defaultConfigURL) throws -> (config: Config, warnings: [String]) {
        if !FileManager.default.fileExists(atPath: url.path) {
            let config = Config()
            try write(config, to: url)
            return (config, [])
        }
        return try decode(Data(contentsOf: url))
    }

    public static func write(_ config: Config, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url)
    }

    public static func decode(_ data: Data) throws -> (config: Config, warnings: [String]) {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var warnings: [String] = []
        var config = Config()

        if let value = raw.hotkey {
            if let hotkey = Hotkey(rawValue: value) {
                config.hotkey = hotkey
            } else {
                warnings.append("unknown hotkey '\(value)', falling back to rightOption")
                config.hotkey = .rightOption
            }
        }
        if let value = raw.autoSend {
            if let mode = AutoSendMode(rawValue: value) {
                config.autoSend = mode
            } else {
                warnings.append("unknown autoSend '\(value)', falling back to off")
                config.autoSend = .off
            }
        }
        if let value = raw.fillerRemoval { config.fillerRemoval = value }
        if let value = raw.punctuation { config.punctuation = value }
        if let value = raw.capitalization { config.capitalization = value }
        if let value = raw.maxDurationSeconds { config.maxDurationSeconds = value }
        if let value = raw.minDurationSeconds { config.minDurationSeconds = value }
        if let value = raw.preRollSeconds { config.preRollSeconds = value }
        if let value = raw.dictionaryPath { config.dictionaryPath = value }
        if let value = raw.debugLogging { config.debugLogging = value }
        if let value = raw.punctuationCommands { config.punctuationCommands = value }

        return (config, warnings)
    }

    private struct Raw: Decodable {
        var hotkey: String?
        var autoSend: String?
        var fillerRemoval: Bool?
        var punctuation: Bool?
        var capitalization: Bool?
        var maxDurationSeconds: Double?
        var minDurationSeconds: Double?
        var preRollSeconds: Double?
        var dictionaryPath: String?
        var debugLogging: Bool?
        var punctuationCommands: [String: String]?
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ConfigTests`
Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FennecCore/Types.swift Sources/FennecCore/Config.swift Tests/FennecCoreTests/ConfigTests.swift
git commit -m "feat(core): add core types and config loading"
```

---

### Task 3: Pause rules and spoken punctuation

**Files:**
- Create: `Sources/FennecCore/Pauses.swift`
- Create: `Sources/FennecCore/Punctuation.swift`
- Test: `Tests/FennecCoreTests/PunctuationTests.swift`

**Interfaces:**
- Consumes: `Token`, `TokenSpacing`, `Word.token` (Task 2).
- Produces: `Pauses.defaultMinGap`, `Pauses.hasPauseBefore(_:in:minGap:)`, `Pauses.hasPauseAfter(_:in:minGap:)`, `PunctuationRule(replacement:spacing:)`, `Punctuation.defaultRules`, `Punctuation.rules(overrides:)`, `Punctuation.apply(to:rules:minPause:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/PunctuationTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func periodInsidePhraseIsKept() {
    let words = [
        Word(text: "for", start: 0.0, end: 0.3),
        Word(text: "a", start: 0.35, end: 0.5),
        Word(text: "period", start: 0.55, end: 0.95),
        Word(text: "of", start: 1.0, end: 1.2),
        Word(text: "time", start: 1.3, end: 1.7),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["for", "a", "period", "of", "time"])
}

@Test func standaloneTrailingPeriodBecomesSymbol() {
    let words = [
        Word(text: "ship", start: 0.0, end: 0.4),
        Word(text: "it", start: 0.45, end: 0.7),
        Word(text: "period", start: 1.2, end: 1.7),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["ship", "it", "."])
    #expect(tokens.last?.spacing == .attachBefore)
}

@Test func isolatedCommaBetweenWordsBecomesSymbol() {
    let words = [
        Word(text: "first", start: 0.0, end: 0.4),
        Word(text: "comma", start: 0.9, end: 1.2),
        Word(text: "second", start: 1.7, end: 2.0),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["first", ",", "second"])
}

@Test func commaInsideSentenceStaysAWord() {
    let words = [
        Word(text: "add", start: 0.0, end: 0.3),
        Word(text: "a", start: 0.35, end: 0.5),
        Word(text: "comma", start: 0.55, end: 0.9),
        Word(text: "here", start: 0.95, end: 1.2),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["add", "a", "comma", "here"])
}

@Test func multiwordNewLineCommand() {
    let words = [
        Word(text: "done", start: 0.0, end: 0.4),
        Word(text: "new", start: 0.9, end: 1.1),
        Word(text: "line", start: 1.15, end: 1.4),
        Word(text: "next", start: 1.5, end: 1.8),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["done", "\n", "next"])
    #expect(tokens[1].spacing == .ownLine)
}

@Test func overridesReplaceKnownAndAddNew() {
    let rules = Punctuation.rules(overrides: ["period": "!", "tick": "`"])
    #expect(rules["period"]?.replacement == "!")
    #expect(rules["period"]?.spacing == .attachBefore)
    #expect(rules["tick"]?.replacement == "`")
    #expect(rules["tick"]?.spacing == .normal)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PunctuationTests`
Expected: compile failure, `cannot find 'Punctuation' in scope`.

- [ ] **Step 3: Write Pauses.swift**

```swift
import Foundation

public enum Pauses {
    public static let defaultMinGap: TimeInterval = 0.25

    public static func hasPauseBefore(
        _ index: Int,
        in tokens: [Token],
        minGap: TimeInterval = defaultMinGap
    ) -> Bool {
        guard index > 0 else { return true }
        return tokens[index].start - tokens[index - 1].end >= minGap
    }

    public static func hasPauseAfter(
        _ index: Int,
        in tokens: [Token],
        minGap: TimeInterval = defaultMinGap
    ) -> Bool {
        guard index < tokens.count - 1 else { return true }
        return tokens[index + 1].start - tokens[index].end >= minGap
    }
}
```

- [ ] **Step 4: Write Punctuation.swift**

```swift
import Foundation

public struct PunctuationRule: Equatable, Sendable {
    public var replacement: String
    public var spacing: TokenSpacing

    public init(replacement: String, spacing: TokenSpacing) {
        self.replacement = replacement
        self.spacing = spacing
    }
}

public enum Punctuation {
    public static let defaultRules: [String: PunctuationRule] = [
        "period": PunctuationRule(replacement: ".", spacing: .attachBefore),
        "full stop": PunctuationRule(replacement: ".", spacing: .attachBefore),
        "comma": PunctuationRule(replacement: ",", spacing: .attachBefore),
        "question mark": PunctuationRule(replacement: "?", spacing: .attachBefore),
        "exclamation mark": PunctuationRule(replacement: "!", spacing: .attachBefore),
        "exclamation point": PunctuationRule(replacement: "!", spacing: .attachBefore),
        "colon": PunctuationRule(replacement: ":", spacing: .attachBefore),
        "semicolon": PunctuationRule(replacement: ";", spacing: .attachBefore),
        "new line": PunctuationRule(replacement: "\n", spacing: .ownLine),
        "new paragraph": PunctuationRule(replacement: "\n\n", spacing: .ownLine),
        "open paren": PunctuationRule(replacement: "(", spacing: .attachAfter),
        "open parenthesis": PunctuationRule(replacement: "(", spacing: .attachAfter),
        "close paren": PunctuationRule(replacement: ")", spacing: .attachBefore),
        "close parenthesis": PunctuationRule(replacement: ")", spacing: .attachBefore),
        "dash": PunctuationRule(replacement: "-", spacing: .normal),
        "hyphen": PunctuationRule(replacement: "-", spacing: .normal),
    ]

    public static func rules(overrides: [String: String]) -> [String: PunctuationRule] {
        var rules = defaultRules
        for (command, replacement) in overrides {
            let key = command.lowercased()
            if let existing = rules[key] {
                rules[key] = PunctuationRule(replacement: replacement, spacing: existing.spacing)
            } else {
                rules[key] = PunctuationRule(replacement: replacement, spacing: .normal)
            }
        }
        return rules
    }

    public static func apply(
        to tokens: [Token],
        rules: [String: PunctuationRule] = defaultRules,
        minPause: TimeInterval = Pauses.defaultMinGap
    ) -> [Token] {
        let maxWindow = rules.keys
            .map { $0.split(separator: " ").count }
            .max() ?? 1
        var result: [Token] = []
        var index = 0
        while index < tokens.count {
            var matched = false
            let window = min(maxWindow, tokens.count - index)
            for size in stride(from: window, through: 1, by: -1) {
                let slice = Array(tokens[index ..< index + size])
                let phrase = slice.map { $0.text.lowercased() }.joined(separator: " ")
                guard let rule = rules[phrase] else { continue }
                let contiguous = zip(slice, slice.dropFirst())
                    .allSatisfy { $1.start - $0.end < minPause }
                guard contiguous else { continue }
                guard Pauses.hasPauseBefore(index, in: tokens, minGap: minPause),
                      Pauses.hasPauseAfter(index + size - 1, in: tokens, minGap: minPause) else { continue }
                result.append(Token(
                    text: rule.replacement,
                    start: slice.first?.start ?? 0,
                    end: slice.last?.end ?? 0,
                    isProtected: true,
                    spacing: rule.spacing
                ))
                index += size
                matched = true
                break
            }
            if !matched {
                result.append(tokens[index])
                index += 1
            }
        }
        return result
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PunctuationTests`
Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FennecCore/Pauses.swift Sources/FennecCore/Punctuation.swift Tests/FennecCoreTests/PunctuationTests.swift
git commit -m "feat(core): pause-gated spoken punctuation"
```

---

### Task 4: Filler detection and removal

**Files:**
- Create: `Sources/FennecCore/FillerDetector.swift`
- Create: `Sources/FennecCore/FillerRemoval.swift`
- Test: `Tests/FennecCoreTests/FillerRemovalTests.swift`

**Interfaces:**
- Consumes: `Word`, `Token`, `Word.token`, `Pauses` (Tasks 2 and 3).
- Produces: `FillerDetector` protocol (`fillerRanges(samples:sampleRate:words:) async throws -> [Range<TimeInterval>]`), `HeuristicFillerDetector(fillers:minPause:)`, `FillerRemoval.remove(tokens:overlapping:)`. The samples parameter exists so Task 9's Uhm detector can work from audio; the heuristic ignores it. Task 9 adds a second `FillerDetector` implementation.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/FillerRemovalTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func isolatedFillerIsDetected() async throws {
    let words = [
        Word(text: "send", start: 0.0, end: 0.4),
        Word(text: "it", start: 0.45, end: 0.7),
        Word(text: "uh", start: 1.2, end: 1.5),
    ]
    let ranges = try await HeuristicFillerDetector().fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges == [1.2 ..< 1.5])
}

@Test func fillerInsideAPhraseIsKept() async throws {
    let words = [
        Word(text: "this", start: 0.0, end: 0.3),
        Word(text: "is", start: 0.35, end: 0.5),
        Word(text: "uh", start: 0.55, end: 0.8),
        Word(text: "fine", start: 0.85, end: 1.1),
    ]
    let ranges = try await HeuristicFillerDetector().fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges.isEmpty)
}

@Test func leadingFillerIsDetected() async throws {
    let words = [
        Word(text: "um", start: 0.0, end: 0.3),
        Word(text: "deploy", start: 0.8, end: 1.2),
    ]
    let ranges = try await HeuristicFillerDetector().fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges == [0.0 ..< 0.3])
}

@Test func removalDropsOverlappingTokens() {
    let tokens = [
        Token(text: "send", start: 0.0, end: 0.4),
        Token(text: "uh", start: 0.9, end: 1.2),
        Token(text: "now", start: 1.7, end: 2.0),
    ]
    let result = FillerRemoval.remove(tokens: tokens, overlapping: [0.9 ..< 1.2])
    #expect(result.map(\.text) == ["send", "now"])
}

@Test func customFillerSetIsHonored() async throws {
    let words = [
        Word(text: "like", start: 0.0, end: 0.3),
        Word(text: "go", start: 0.8, end: 1.0),
    ]
    let ranges = try await HeuristicFillerDetector(fillers: ["like"]).fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges == [0.0 ..< 0.3])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FillerRemovalTests`
Expected: compile failure, `cannot find 'HeuristicFillerDetector' in scope`.

- [ ] **Step 3: Write FillerDetector.swift**

```swift
import Foundation

public protocol FillerDetector: Sendable {
    func fillerRanges(
        samples: [Float],
        sampleRate: Double,
        words: [Word]
    ) async throws -> [Range<TimeInterval>]
}

public struct HeuristicFillerDetector: FillerDetector {
    public var fillers: Set<String>
    public var minPause: TimeInterval

    public init(
        fillers: Set<String> = ["uh", "um", "hmm", "erm"],
        minPause: TimeInterval = Pauses.defaultMinGap
    ) {
        self.fillers = fillers
        self.minPause = minPause
    }

    public func fillerRanges(
        samples: [Float],
        sampleRate: Double,
        words: [Word]
    ) async throws -> [Range<TimeInterval>] {
        let tokens = words.map(\.token)
        var ranges: [Range<TimeInterval>] = []
        for index in words.indices {
            let text = words[index].text
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            guard fillers.contains(text) else { continue }
            guard Pauses.hasPauseBefore(index, in: tokens, minGap: minPause),
                  Pauses.hasPauseAfter(index, in: tokens, minGap: minPause) else { continue }
            ranges.append(words[index].start ..< words[index].end)
        }
        return ranges
    }
}
```

- [ ] **Step 4: Write FillerRemoval.swift**

```swift
import Foundation

public enum FillerRemoval {
    public static func remove(tokens: [Token], overlapping spans: [Range<TimeInterval>]) -> [Token] {
        guard !spans.isEmpty else { return tokens }
        return tokens.filter { token in
            !spans.contains { span in
                token.start < span.upperBound && span.lowerBound < token.end
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter FillerRemovalTests`
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FennecCore/FillerDetector.swift Sources/FennecCore/FillerRemoval.swift Tests/FennecCoreTests/FillerRemovalTests.swift
git commit -m "feat(core): filler detection and removal"
```

---

### Task 5: Dev-term dictionary

**Files:**
- Create: `Sources/FennecCore/Dictionary.swift`
- Create: `Sources/FennecCore/DictionaryMatcher.swift`
- Test: `Tests/FennecCoreTests/DictionaryTests.swift`

**Interfaces:**
- Consumes: `Token` (Task 2).
- Produces: `DictionaryEntry(canonical:aliases:)`, `Dictionary(entries:)`, `Dictionary.parse(_:)`, `Dictionary.load(from:)`, `Dictionary.builtIn`, `DictionaryMatch(range:canonical:)`, `DictionaryMatcher.normalize(_:)`, `DictionaryMatcher.matches(in:dictionary:maxGap:maxWindow:)`, `DictionaryMatcher.apply(_:to:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/DictionaryTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func parsesEntriesCommentsAndAliases() {
    let text = """
    # dev terms
    kubectl = cube control, cube cuddle
    opencode

    tmux
    """
    let dictionary = Dictionary.parse(text)
    #expect(dictionary.entries.count == 3)
    #expect(dictionary.entries[0].canonical == "kubectl")
    #expect(dictionary.entries[0].aliases == ["kubectl", "cube control", "cube cuddle"])
    #expect(dictionary.entries[1].aliases == ["opencode"])
}

@Test func multiwordAliasMatchesAndApplyProtects() {
    let words = [
        Word(text: "open", start: 0, end: 0.3),
        Word(text: "code", start: 0.35, end: 0.7),
    ]
    let tokens = words.map(\.token)
    let matches = DictionaryMatcher.matches(in: tokens, dictionary: .builtIn)
    #expect(matches.count == 1)
    #expect(matches[0].canonical == "opencode")
    let applied = DictionaryMatcher.apply(matches, to: tokens)
    #expect(applied.map(\.text) == ["opencode"])
    #expect(applied[0].isProtected)
    #expect(applied[0].start == 0)
    #expect(applied[0].end == 0.7)
}

@Test func gapBreaksMatch() {
    let words = [
        Word(text: "open", start: 0, end: 0.3),
        Word(text: "code", start: 0.9, end: 1.3),
    ]
    let matches = DictionaryMatcher.matches(in: words.map(\.token), dictionary: .builtIn)
    #expect(matches.isEmpty)
}

@Test func longestMatchWins() {
    let dictionary = Dictionary(entries: [
        DictionaryEntry(canonical: "code"),
        DictionaryEntry(canonical: "opencode", aliases: ["open code"]),
    ])
    let words = [
        Word(text: "open", start: 0, end: 0.3),
        Word(text: "code", start: 0.35, end: 0.7),
    ]
    let matches = DictionaryMatcher.matches(in: words.map(\.token), dictionary: dictionary)
    #expect(matches.count == 1)
    #expect(matches[0].canonical == "opencode")
}

@Test func partialWordIsNotMatched() {
    let words = [Word(text: "opencodes", start: 0, end: 0.5)]
    let matches = DictionaryMatcher.matches(in: words.map(\.token), dictionary: .builtIn)
    #expect(matches.isEmpty)
}

@Test func missingFileFallsBackToBuiltIn() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let dictionary = try Dictionary.load(from: url)
    #expect(dictionary.entries.count == Dictionary.builtIn.entries.count)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DictionaryTests`
Expected: compile failure, `cannot find 'Dictionary' in scope`.

- [ ] **Step 3: Write Dictionary.swift**

```swift
import Foundation

public struct DictionaryEntry: Equatable, Sendable {
    public var canonical: String
    public var aliases: [String]

    public init(canonical: String, aliases: [String] = []) {
        self.canonical = canonical
        self.aliases = [canonical] + aliases.filter { $0 != canonical }
    }
}

public struct Dictionary: Equatable, Sendable {
    public var entries: [DictionaryEntry]

    public init(entries: [DictionaryEntry]) {
        self.entries = entries
    }

    public static func parse(_ text: String) -> Dictionary {
        var entries: [DictionaryEntry] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let canonical = parts[0]
            let aliases = parts.count > 1
                ? parts[1].split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                : []
            entries.append(DictionaryEntry(canonical: canonical, aliases: aliases))
        }
        return Dictionary(entries: entries)
    }

    public static func load(from url: URL) throws -> Dictionary {
        guard FileManager.default.fileExists(atPath: url.path) else { return .builtIn }
        return parse(try String(contentsOf: url, encoding: .utf8))
    }

    public static let builtIn = Dictionary(entries: [
        DictionaryEntry(canonical: "opencode", aliases: ["open code"]),
        DictionaryEntry(canonical: "tmux"),
        DictionaryEntry(canonical: "kubectl", aliases: ["cube control", "cube cuddle"]),
        DictionaryEntry(canonical: "GitHub", aliases: ["git hub"]),
        DictionaryEntry(canonical: "kCGEventTap", aliases: ["k c g event tap"]),
        DictionaryEntry(canonical: "NSPasteboard"),
        DictionaryEntry(canonical: "AVAudioEngine", aliases: ["a v audio engine"]),
        DictionaryEntry(canonical: "Voz"),
        DictionaryEntry(canonical: "Parakeet"),
        DictionaryEntry(canonical: "Uhm"),
        DictionaryEntry(canonical: "Fennec"),
        DictionaryEntry(canonical: "Homebrew"),
        DictionaryEntry(canonical: "Xcode"),
        DictionaryEntry(canonical: "macOS", aliases: ["mac o s"]),
        DictionaryEntry(canonical: "iTerm2", aliases: ["i term 2", "i term two"]),
        DictionaryEntry(canonical: "Ghostty"),
        DictionaryEntry(canonical: "WezTerm"),
        DictionaryEntry(canonical: "Codex"),
        DictionaryEntry(canonical: "Hermes"),
        DictionaryEntry(canonical: "Antigravity"),
        DictionaryEntry(canonical: "CommandCode", aliases: ["command code"]),
        DictionaryEntry(canonical: "Claude Code", aliases: ["cloud code"]),
        DictionaryEntry(canonical: "Desert Ant"),
    ])
}
```

- [ ] **Step 4: Write DictionaryMatcher.swift**

```swift
import Foundation

public struct DictionaryMatch: Equatable, Sendable {
    public var range: Range<Int>
    public var canonical: String

    public init(range: Range<Int>, canonical: String) {
        self.range = range
        self.canonical = canonical
    }
}

public enum DictionaryMatcher {
    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    public static func matches(
        in tokens: [Token],
        dictionary: Dictionary,
        maxGap: TimeInterval = 0.4,
        maxWindow: Int = 5
    ) -> [DictionaryMatch] {
        var lookup: [String: String] = [:]
        for entry in dictionary.entries {
            for alias in entry.aliases {
                lookup[normalize(alias)] = entry.canonical
            }
        }

        var result: [DictionaryMatch] = []
        var index = 0
        while index < tokens.count {
            var matched = false
            let window = min(maxWindow, tokens.count - index)
            for size in stride(from: window, through: 1, by: -1) {
                let slice = Array(tokens[index ..< index + size])
                if size > 1 {
                    let contiguous = zip(slice, slice.dropFirst())
                        .allSatisfy { $1.start - $0.end < maxGap }
                    guard contiguous else { continue }
                }
                let key = normalize(slice.map(\.text).joined())
                guard let canonical = lookup[key] else { continue }
                result.append(DictionaryMatch(range: index ..< (index + size), canonical: canonical))
                index += size
                matched = true
                break
            }
            if !matched { index += 1 }
        }
        return result
    }

    public static func apply(_ matches: [DictionaryMatch], to tokens: [Token]) -> [Token] {
        guard !matches.isEmpty else { return tokens }
        var output: [Token] = []
        var cursor = 0
        for match in matches {
            if cursor < match.range.lowerBound {
                output.append(contentsOf: tokens[cursor ..< match.range.lowerBound])
            }
            let slice = tokens[match.range]
            output.append(Token(
                text: match.canonical,
                start: slice.first?.start ?? 0,
                end: slice.last?.end ?? 0,
                isProtected: true
            ))
            cursor = match.range.upperBound
        }
        if cursor < tokens.count {
            output.append(contentsOf: tokens[cursor...])
        }
        return output
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter DictionaryTests`
Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FennecCore/Dictionary.swift Sources/FennecCore/DictionaryMatcher.swift Tests/FennecCoreTests/DictionaryTests.swift
git commit -m "feat(core): dev-term dictionary matching"
```

---

### Task 6: Renderer, capitalization, and the pipeline

**Files:**
- Create: `Sources/FennecCore/TokenRenderer.swift`
- Create: `Sources/FennecCore/Capitalization.swift`
- Create: `Sources/FennecCore/Pipeline.swift`
- Test: `Tests/FennecCoreTests/PipelineTests.swift`

**Interfaces:**
- Consumes: `Word`, `Token`, `Punctuation`, `FillerRemoval`, `Dictionary(Matcher)`, `Config` (Tasks 2 through 5).
- Produces: `TokenRenderer.render(_:)`, `Capitalization.apply(to:)`, `PipelineConfig(fillerRemoval:punctuation:capitalization:punctuationRules:)`, `PipelineConfig.from(_:)`, `TextPipeline.process(words:config:dictionary:fillerSpans:)`. Tasks 8, 12, and 13 call `TextPipeline.process`.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/PipelineTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func rendererAppliesSpacingRules() {
    let tokens = [
        Token(text: "hello", start: 0, end: 0.3),
        Token(text: ",", start: 0.4, end: 0.4, isProtected: true, spacing: .attachBefore),
        Token(text: "world", start: 0.5, end: 0.8),
        Token(text: "\n", start: 1.2, end: 1.2, isProtected: true, spacing: .ownLine),
        Token(text: "(", start: 1.3, end: 1.3, isProtected: true, spacing: .attachAfter),
        Token(text: "again", start: 1.4, end: 1.8),
        Token(text: ")", start: 1.9, end: 1.9, isProtected: true, spacing: .attachBefore),
    ]
    #expect(TokenRenderer.render(tokens) == "hello, world\n(again)")
}

@Test func capitalizationAtStartAndAfterSentence() {
    let tokens = [
        Token(text: "hello", start: 0, end: 0.3),
        Token(text: "there", start: 0.35, end: 0.6),
        Token(text: ".", start: 0.7, end: 0.7, isProtected: true, spacing: .attachBefore),
        Token(text: "next", start: 0.8, end: 1.0),
    ]
    #expect(Capitalization.apply(to: tokens).map(\.text) == ["Hello", "there", ".", "Next"])
}

@Test func protectedTokensKeepCanonicalCasing() {
    let tokens = [
        Token(text: "claude", start: 0, end: 0.3),
        Token(text: "code", start: 0.35, end: 0.7),
    ]
    let matches = [DictionaryMatch(range: 0 ..< 2, canonical: "Claude Code")]
    let applied = DictionaryMatcher.apply(matches, to: tokens)
    #expect(Capitalization.apply(to: applied).map(\.text) == ["Claude Code"])
}

@Test func fullPipelineEndToEnd() {
    let words = [
        Word(text: "open", start: 0.0, end: 0.3),
        Word(text: "code", start: 0.35, end: 0.65),
        Word(text: "is", start: 0.7, end: 0.85),
        Word(text: "ready", start: 0.9, end: 1.2),
        Word(text: "uh", start: 1.7, end: 1.9),
        Word(text: "new", start: 2.3, end: 2.5),
        Word(text: "line", start: 2.55, end: 2.8),
        Word(text: "k", start: 3.3, end: 3.4),
        Word(text: "c", start: 3.45, end: 3.55),
        Word(text: "g", start: 3.6, end: 3.7),
        Word(text: "event", start: 3.75, end: 4.05),
        Word(text: "tap", start: 4.1, end: 4.35),
    ]
    let text = TextPipeline.process(
        words: words,
        config: PipelineConfig(),
        dictionary: .builtIn,
        fillerSpans: [1.7 ..< 1.9]
    )
    #expect(text == "opencode is ready\nkCGEventTap")
}

@Test func disabledStagesKeepRawText() {
    let words = [
        Word(text: "hello", start: 0.0, end: 0.3),
        Word(text: "open", start: 0.9, end: 1.1),
        Word(text: "code", start: 1.15, end: 1.4),
    ]
    let config = PipelineConfig(fillerRemoval: false, punctuation: false, capitalization: false)
    let text = TextPipeline.process(words: words, config: config, dictionary: .builtIn, fillerSpans: [])
    #expect(text == "hello open code")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PipelineTests`
Expected: compile failure, `cannot find 'TokenRenderer' in scope`.

- [ ] **Step 3: Write TokenRenderer.swift**

```swift
import Foundation

public enum TokenRenderer {
    public static func render(_ tokens: [Token]) -> String {
        var output = ""
        var previous: Token?
        for token in tokens {
            if let previous {
                let tight = token.spacing == .ownLine
                    || previous.spacing == .ownLine
                    || token.spacing == .attachBefore
                    || previous.spacing == .attachAfter
                if !tight { output += " " }
            }
            output += token.text
            previous = token
        }
        return output.trimmingCharacters(in: .whitespaces)
    }
}
```

- [ ] **Step 4: Write Capitalization.swift**

```swift
import Foundation

public enum Capitalization {
    public static func apply(to tokens: [Token]) -> [Token] {
        var result = tokens
        var capitalizeNext = true
        for index in result.indices {
            let token = result[index]
            if token.spacing == .ownLine {
                capitalizeNext = true
                continue
            }
            let endsSentence = token.text.hasSuffix(".")
                || token.text.hasSuffix("!")
                || token.text.hasSuffix("?")
            if capitalizeNext,
               !token.isProtected,
               let first = token.text.first,
               first.isLetter,
               first.isLowercase {
                result[index].text = token.text.prefix(1).uppercased() + token.text.dropFirst()
            }
            capitalizeNext = endsSentence
        }
        return result
    }
}
```

- [ ] **Step 5: Write Pipeline.swift**

```swift
import Foundation

public struct PipelineConfig: Equatable, Sendable {
    public var fillerRemoval: Bool
    public var punctuation: Bool
    public var capitalization: Bool
    public var punctuationRules: [String: PunctuationRule]

    public init(
        fillerRemoval: Bool = true,
        punctuation: Bool = true,
        capitalization: Bool = true,
        punctuationRules: [String: PunctuationRule] = Punctuation.defaultRules
    ) {
        self.fillerRemoval = fillerRemoval
        self.punctuation = punctuation
        self.capitalization = capitalization
        self.punctuationRules = punctuationRules
    }

    public static func from(_ config: Config) -> PipelineConfig {
        PipelineConfig(
            fillerRemoval: config.fillerRemoval,
            punctuation: config.punctuation,
            capitalization: config.capitalization,
            punctuationRules: Punctuation.rules(overrides: config.punctuationCommands)
        )
    }
}

public enum TextPipeline {
    public static func process(
        words: [Word],
        config: PipelineConfig,
        dictionary: Dictionary,
        fillerSpans: [Range<TimeInterval>]
    ) -> String {
        var tokens = words.map(\.token)
        if config.fillerRemoval {
            tokens = FillerRemoval.remove(tokens: tokens, overlapping: fillerSpans)
        }
        let matches = DictionaryMatcher.matches(in: tokens, dictionary: dictionary)
        tokens = DictionaryMatcher.apply(matches, to: tokens)
        if config.punctuation {
            tokens = Punctuation.apply(to: tokens, rules: config.punctuationRules)
        }
        if config.capitalization {
            tokens = Capitalization.apply(to: tokens)
        }
        return TokenRenderer.render(tokens)
    }
}
```

- [ ] **Step 6: Run the full test suite**

Run: `swift test`
Expected: all tests from Tasks 2 through 6 pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/FennecCore/TokenRenderer.swift Sources/FennecCore/Capitalization.swift Sources/FennecCore/Pipeline.swift Tests/FennecCoreTests/PipelineTests.swift
git commit -m "feat(core): token renderer, capitalization, and pipeline"
```

---

### Task 7: Silence trimming and pre-roll buffer

**Files:**
- Create: `Sources/FennecCore/SilenceTrimmer.swift`
- Create: `Sources/FennecCore/PreRollBuffer.swift`
- Test: `Tests/FennecCoreTests/AudioTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `SilenceTrimmer.trim(_:sampleRate:threshold:pad:)`, `PreRollBuffer(capacity:)`, `PreRollBuffer.append(_:)`, `PreRollBuffer.drain()`. Task 12 (recorder) uses both.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/AudioTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func silenceTrimsToEmpty() {
    let silence = [Float](repeating: 0, count: 16000)
    #expect(SilenceTrimmer.trim(silence, sampleRate: 16000).isEmpty)
}

@Test func leadingAndTrailingSilenceAreTrimmed() {
    var samples = [Float](repeating: 0, count: 8000)
    samples += [Float](repeating: 0.5, count: 16000)
    samples += [Float](repeating: 0, count: 8000)
    let trimmed = SilenceTrimmer.trim(samples, sampleRate: 16000)
    #expect(trimmed.count >= 16000)
    #expect(trimmed.count <= 17600)
    #expect(trimmed.contains(0.5))
}

@Test func interiorSilenceIsKept() {
    var samples = [Float](repeating: 0.5, count: 8000)
    samples += [Float](repeating: 0, count: 8000)
    samples += [Float](repeating: 0.5, count: 8000)
    let trimmed = SilenceTrimmer.trim(samples, sampleRate: 16000, pad: 0)
    #expect(trimmed.count == 24000)
}

@Test func preRollKeepsOnlyTheNewestSamples() {
    var buffer = PreRollBuffer(capacity: 4)
    buffer.append([1, 2, 3])
    #expect(buffer.drain() == [1, 2, 3])
    buffer.append([1, 2, 3, 4, 5])
    #expect(buffer.drain() == [2, 3, 4, 5])
    #expect(buffer.drain().isEmpty)
}

@Test func preRollWithZeroCapacityIsEmpty() {
    var buffer = PreRollBuffer(capacity: 0)
    buffer.append([1, 2, 3])
    #expect(buffer.drain().isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AudioTests`
Expected: compile failure, `cannot find 'SilenceTrimmer' in scope`.

- [ ] **Step 3: Write SilenceTrimmer.swift**

```swift
import Foundation

public enum SilenceTrimmer {
    public static func trim(
        _ samples: [Float],
        sampleRate: Double,
        threshold: Float = 0.008,
        pad: TimeInterval = 0.05
    ) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let frameLength = max(1, Int(0.02 * sampleRate))

        var frames: [(start: Int, length: Int, rms: Float)] = []
        var index = 0
        while index < samples.count {
            let end = min(index + frameLength, samples.count)
            var sum: Float = 0
            for sampleIndex in index ..< end {
                sum += samples[sampleIndex] * samples[sampleIndex]
            }
            let rms = (sum / Float(end - index)).squareRoot()
            frames.append((index, end - index, rms))
            index = end
        }

        guard let first = frames.first(where: { $0.rms >= threshold }),
              let last = frames.last(where: { $0.rms >= threshold }) else {
            return []
        }
        let padSamples = Int(pad * sampleRate)
        let start = max(0, first.start - padSamples)
        let end = min(samples.count, last.start + last.length + padSamples)
        return Array(samples[start ..< end])
    }
}
```

- [ ] **Step 4: Write PreRollBuffer.swift**

```swift
import Foundation

public struct PreRollBuffer: Sendable {
    public let capacity: Int
    private var storage: [Float] = []

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public mutating func append(_ samples: [Float]) {
        guard capacity > 0, !samples.isEmpty else { return }
        storage.append(contentsOf: samples)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    public mutating func drain() -> [Float] {
        defer { storage.removeAll(keepingCapacity: true) }
        return storage
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AudioTests`
Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/FennecCore/SilenceTrimmer.swift Sources/FennecCore/PreRollBuffer.swift Tests/FennecCoreTests/AudioTests.swift
git commit -m "feat(core): silence trimming and pre-roll buffer"
```

---

### Task 8: Transcriber protocol, Voz adapter, and the transcribe command

**Files:**
- Create: `Sources/FennecCore/Transcriber.swift`
- Create: `Sources/FennecCore/AudioFileLoader.swift`
- Create: `Sources/FennecEngine/VozTranscriber.swift`
- Create: `Sources/FennecEngine/FillerDetectorFactory.swift`
- Modify: `Sources/FennecCLI/main.swift`
- Delete: `Sources/FennecEngine/EngineProbe.swift`

**Interfaces:**
- Consumes: `Transcript`, `Word`, `Config`, `Dictionary`, `TextPipeline`, `FillerDetector` (Tasks 2 through 6); SDK signatures recorded in `docs/sdk-notes.md` (Task 1).
- Produces: `Transcriber` protocol, `TranscriberError`, `AudioFileLoader.loadSamples(at:sampleRate:)`, `VozTranscriber`, `FillerDetectorFactory.make()`, CLI commands `probe`, `transcribe` with `--cleanup`, `--dictionary`, `--json`, `--timings`. Tasks 9, 12, and 13 build on these.

- [ ] **Step 1: Write Transcriber.swift**

```swift
import Foundation

public protocol Transcriber: Sendable {
    func prepare(progress: (@Sendable (Double) -> Void)?) async throws
    func isReady() async -> Bool
    func transcribe(samples: [Float], sampleRate: Double) async throws -> Transcript
}

public enum TranscriberError: Error, Equatable {
    case notPrepared
    case emptyResult
    case sampleRateMismatch(expected: Double, got: Double)
}
```

- [ ] **Step 2: Write AudioFileLoader.swift**

```swift
import AVFoundation
import Foundation

public enum AudioFileLoaderError: Error {
    case unsupportedFormat
    case conversionFailed
}

public enum AudioFileLoader {
    public static let defaultSampleRate: Double = 16000

    public static func loadSamples(
        at url: URL,
        sampleRate: Double = defaultSampleRate
    ) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioFileLoaderError.unsupportedFormat
        }
        try file.read(into: inputBuffer)

        if inputFormat.sampleRate == sampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32,
           let channel = inputBuffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(inputBuffer.frameLength)))
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioFileLoaderError.conversionFailed
        }
        let capacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * sampleRate / inputFormat.sampleRate
        ) + 512
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioFileLoaderError.conversionFailed
        }

        var conversionError: NSError?
        var suppliedInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
            if suppliedInput {
                outputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outputStatus.pointee = .haveData
            return inputBuffer
        }
        if status == .error {
            throw conversionError ?? AudioFileLoaderError.conversionFailed
        }
        guard let channel = outputBuffer.floatChannelData?[0] else {
            throw AudioFileLoaderError.conversionFailed
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
    }
}
```

- [ ] **Step 3: Write VozTranscriber.swift**

```swift
import FennecCore
import Foundation
import Voz

public actor VozTranscriber: Transcriber {
    private var voz: Voz?

    public init() {}

    public func isReady() async -> Bool {
        voz != nil
    }

    public func prepare(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard voz == nil else { return }
        if !Voz.isDownloaded() {
            _ = try await Voz.download { download in
                progress?(download.fraction)
            }
        }
        let instance = try await Voz()
        voz = instance
        // Warm the ANE graph so the first real utterance does not pay the specialization cost.
        let silence = [Float](repeating: 0, count: 16000)
        _ = try? await instance.transcribe(samples: silence, sampleRate: 16000)
    }

    public func transcribe(samples: [Float], sampleRate: Double) async throws -> Transcript {
        guard let voz else { throw TranscriberError.notPrepared }
        guard sampleRate == voz.sampleRate else {
            throw TranscriberError.sampleRateMismatch(expected: voz.sampleRate, got: sampleRate)
        }
        let result = try await voz.transcribe(samples: samples)
        let words = result.words.map { Word(text: $0.text, start: $0.start, end: $0.end) }
        return Transcript(text: result.text, words: words)
    }
}
```

Compare every SDK call against `docs/sdk-notes.md` before building. If a name differs, adjust only this file.

- [ ] **Step 4: Write FillerDetectorFactory.swift**

```swift
import FennecCore

public enum FillerDetectorFactory {
    public static func make() -> any FillerDetector {
        HeuristicFillerDetector()
    }
}
```

Task 9 swaps the body to Uhm if the evaluation passes.

- [ ] **Step 5: Replace the CLI main.swift**

```swift
import Foundation
import FennecCore
import FennecEngine

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func jsonEscape(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
          let encoded = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return String(encoded.dropFirst().dropLast())
}

func milliseconds(since start: CFAbsoluteTime) -> String {
    String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("""
    usage: fennec <command> [options]
    commands:
      probe <audio-file>
      transcribe <audio-file> [--cleanup] [--dictionary <path>] [--json] [--timings]
    """, code: 64)
}

let command = arguments[1]
let rest = Array(arguments.dropFirst(2))

switch command {
case "probe", "transcribe":
    guard let path = rest.first else { fail("usage: fennec \(command) <audio-file>", code: 64) }
    let wantsCleanup = rest.contains("--cleanup")
    let wantsJSON = rest.contains("--json")
    let wantsTimings = rest.contains("--timings")

    do {
        let transcriber = VozTranscriber()
        let prepareStart = CFAbsoluteTimeGetCurrent()
        try await transcriber.prepare { fraction in
            FileHandle.standardError.write(Data("model download: \(Int(fraction * 100))%\n".utf8))
        }
        let prepareMS = milliseconds(since: prepareStart)

        let loadStart = CFAbsoluteTimeGetCurrent()
        let samples = try AudioFileLoader.loadSamples(at: URL(fileURLWithPath: path))
        let loadMS = milliseconds(since: loadStart)

        let transcribeStart = CFAbsoluteTimeGetCurrent()
        let transcript = try await transcriber.transcribe(samples: samples, sampleRate: 16000)
        let transcribeMS = milliseconds(since: transcribeStart)

        var text = transcript.text
        var fillerMS = "0"
        var pipelineMS = "0"

        if command == "transcribe", wantsCleanup {
            let config: Config
            do { config = try Config.loadOrCreate().config } catch { config = Config() }

            let dictionary: Dictionary
            if let flagIndex = rest.firstIndex(of: "--dictionary"),
               rest.indices.contains(flagIndex + 1) {
                dictionary = (try? Dictionary.load(from: URL(fileURLWithPath: rest[flagIndex + 1]))) ?? .builtIn
            } else {
                dictionary = (try? Dictionary.load(from: config.dictionaryURL)) ?? .builtIn
            }

            let fillerStart = CFAbsoluteTimeGetCurrent()
            let spans = (try? await FillerDetectorFactory.make().fillerRanges(
                samples: samples,
                sampleRate: 16000,
                words: transcript.words
            )) ?? []
            fillerMS = milliseconds(since: fillerStart)

            let pipelineStart = CFAbsoluteTimeGetCurrent()
            text = TextPipeline.process(
                words: transcript.words,
                config: .from(config),
                dictionary: dictionary,
                fillerSpans: spans
            )
            pipelineMS = milliseconds(since: pipelineStart)
        }

        if wantsJSON {
            print("{\"text\": \(jsonEscape(text))}")
        } else {
            print(text)
        }

        if wantsTimings {
            let timings = "timings_ms prepare=\(prepareMS) load=\(loadMS) transcribe=\(transcribeMS) filler=\(fillerMS) pipeline=\(pipelineMS)\n"
            FileHandle.standardError.write(Data(timings.utf8))
        }
    } catch {
        fail("\(error)")
    }

default:
    fail("unknown command '\(command)'", code: 64)
}
```

- [ ] **Step 6: Delete the probe and build**

```bash
git rm Sources/FennecEngine/EngineProbe.swift
swift build
```

Expected: build succeeds.

- [ ] **Step 7: Verify transcription from the command line**

Run: `swift run fennec transcribe fixtures/hello.wav`
Expected: a transcript containing "Fennec" and "Done".

Run: `swift run fennec transcribe fixtures/hello.wav --cleanup --timings`
Expected: output contains `opencode` (dictionary replaces "open code") and a newline; stderr shows `timings_ms` with `transcribe` well under 1000 ms once warm.

Run: `swift run fennec transcribe fixtures/silence.wav`
Expected: prints an empty line and exits 0 (silence is not hallucinated, per Review Focus item 3).

- [ ] **Step 8: Commit**

```bash
git add Sources/FennecCore/Transcriber.swift Sources/FennecCore/AudioFileLoader.swift Sources/FennecEngine/VozTranscriber.swift Sources/FennecEngine/FillerDetectorFactory.swift Sources/FennecCLI/main.swift
git commit -m "feat(engine): voz transcriber and headless transcribe command"
```

---

### Task 9: Uhm filler evaluation (may end as: keep the heuristic)

**Files:**
- Modify (only if the evaluation passes): `Package.swift`, `Sources/FennecEngine/FillerDetectorFactory.swift`
- Create (only if the evaluation passes): `Sources/FennecEngine/UhmFillerDetector.swift`
- Modify (always): `docs/sdk-notes.md`

**Interfaces:**
- Consumes: `FillerDetector` (Task 4), `VozTranscriber` as the adapter pattern (Task 8), the CLI `--timings` output (Task 8).
- Produces: either `UhmFillerDetector` wired through `FillerDetectorFactory.make()`, or a documented decision to keep `HeuristicFillerDetector`. Acceptance bar: filler detection adds less than 50 ms per utterance.

- [ ] **Step 1: Read the Uhm API**

Read `.build/checkouts/desert-ant-core/docs/models/uhm.md` and the sources in `.build/checkouts/desert-ant-core/Sources/Uhm/`. Record the exact API in `docs/sdk-notes.md` under "Uhm".

- [ ] **Step 2: Decide go/no-go**

Go requires: a callable API that returns filler spans (or labels) with timestamps; usable on a 16 kHz mono Float32 buffer held in memory; no per-call model load (a resident object is fine). If any of these is missing, this is a no-go: skip to Step 6.

- [ ] **Step 3 (go only): Add the dependency and the adapter**

Add to `Package.swift` in the `FennecEngine` dependencies: `.product(name: "Uhm", package: "desert-ant-core")`.

`Sources/FennecEngine/UhmFillerDetector.swift`. Implement against the API recorded in Step 1, using this shape (adjust only the Uhm calls):

```swift
import FennecCore
import Foundation
import Uhm

public actor UhmFillerDetector: FillerDetector {
    private var model: Uhm?

    public init() {}

    public func fillerRanges(
        samples: [Float],
        sampleRate: Double,
        words: [Word]
    ) async throws -> [Range<TimeInterval>] {
        if model == nil {
            model = try await Uhm()
        }
        guard let model else { return [] }
        // Run the model on `samples` and map each filler span to Range<TimeInterval>.
        // Use the exact API from docs/sdk-notes.md. Return [] when the model reports no fillers.
    }
}
```

The body is completed at execution time against the API recorded in Step 1. That is this task's deliverable; if the API cannot support it, Step 6 applies.

- [ ] **Step 4 (go only): Wire the factory and measure**

`Sources/FennecEngine/FillerDetectorFactory.swift`:

```swift
import FennecCore

public enum FillerDetectorFactory {
    public static func make() -> any FillerDetector {
        UhmFillerDetector()
    }
}
```

Run: `swift build && swift run -c release fennec transcribe fixtures/hello.wav --cleanup --timings`
Expected: `filler_ms` under 50. If it is over, treat as no-go (Step 6).

- [ ] **Step 5 (go only): Verify the pipeline still behaves**

Run: `swift run fennec transcribe fixtures/hello.wav --cleanup`
Expected: same output as Task 8 Step 7. Run `swift test`; expected: all tests still pass.

Commit: `git add -A && git commit -m "feat(engine): use uhm for filler detection"`

- [ ] **Step 6 (no-go): Revert and document**

If Steps 3 to 5 did not happen or the latency bar failed:

```bash
git checkout Package.swift Sources/FennecEngine/FillerDetectorFactory.swift
```

Record in `docs/sdk-notes.md` under "Uhm": the API found, why it was not usable (or the measured latency), and the decision to keep `HeuristicFillerDetector`. Commit: `git add docs/sdk-notes.md && git commit -m "docs: record uhm evaluation and keep heuristic filler removal"`

---

### Task 10: Injection policy, clipboard guard, and injector

**Files:**
- Create: `Sources/FennecCore/InjectionPolicy.swift`
- Create: `Sources/FennecCore/ClipboardGuard.swift`
- Create: `Sources/FennecCore/Injector.swift`
- Test: `Tests/FennecCoreTests/InjectionTests.swift`
- Modify: `Sources/FennecCLI/main.swift` (add the `paste` command)

**Interfaces:**
- Consumes: nothing new beyond Task 2 types.
- Produces: `InjectionOutcome`, `InjectionBlockReason`, `InjectionPolicy.decide(hasText:focusChanged:secureInput:autoSend:)`, `ClipboardGuard.shouldRestore(ourChangeCount:ourString:currentChangeCount:currentString:)`, `Injector.paste(_:autoSend:)`. Task 12 calls `Injector` and `InjectionPolicy`.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/InjectionTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func policyPastesWhenEverythingIsFine() {
    let outcome = InjectionPolicy.decide(hasText: true, focusChanged: false, secureInput: false, autoSend: true)
    #expect(outcome == .paste(autoSend: true))
}

@Test func policyWithholdsOnEmptyText() {
    let outcome = InjectionPolicy.decide(hasText: false, focusChanged: false, secureInput: false, autoSend: false)
    #expect(outcome == .clipboardOnly(reason: .noSpeech))
}

@Test func policyWithholdsOnSecureInput() {
    let outcome = InjectionPolicy.decide(hasText: true, focusChanged: false, secureInput: true, autoSend: false)
    #expect(outcome == .clipboardOnly(reason: .secureInput))
}

@Test func policyWithholdsOnFocusChange() {
    let outcome = InjectionPolicy.decide(hasText: true, focusChanged: true, secureInput: false, autoSend: false)
    #expect(outcome == .clipboardOnly(reason: .focusChanged))
}

@Test func clipboardGuardRestoresOnlyWhenUnchanged() {
    #expect(ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 10, currentString: "fennec"
    ))
    #expect(!ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 11, currentString: "fennec"
    ))
    #expect(!ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 10, currentString: "something else"
    ))
    #expect(!ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 10, currentString: nil
    ))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter InjectionTests`
Expected: compile failure, `cannot find 'InjectionPolicy' in scope`.

- [ ] **Step 3: Write InjectionPolicy.swift and ClipboardGuard.swift**

```swift
import Foundation

public enum InjectionOutcome: Equatable, Sendable {
    case paste(autoSend: Bool)
    case clipboardOnly(reason: InjectionBlockReason)
}

public enum InjectionBlockReason: Equatable, Sendable {
    case noSpeech
    case focusChanged
    case secureInput
}

public enum InjectionPolicy {
    public static func decide(
        hasText: Bool,
        focusChanged: Bool,
        secureInput: Bool,
        autoSend: Bool
    ) -> InjectionOutcome {
        if !hasText { return .clipboardOnly(reason: .noSpeech) }
        if secureInput { return .clipboardOnly(reason: .secureInput) }
        if focusChanged { return .clipboardOnly(reason: .focusChanged) }
        return .paste(autoSend: autoSend)
    }
}
```

```swift
import Foundation

public enum ClipboardGuard {
    public static func shouldRestore(
        ourChangeCount: Int,
        ourString: String,
        currentChangeCount: Int,
        currentString: String?
    ) -> Bool {
        currentChangeCount == ourChangeCount && currentString == ourString
    }
}
```

- [ ] **Step 4: Write Injector.swift**

```swift
import AppKit
import CoreGraphics
import Foundation

public actor Injector {
    private static let transientTypes = [
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.fennec.transient",
    ]

    public init() {}

    public func paste(_ text: String, autoSend: Bool) async {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for type in Self.transientTypes {
            item.setData(Data(), forType: NSPasteboard.PasteboardType(type))
        }
        pasteboard.writeObjects([item])
        let ourChangeCount = pasteboard.changeCount

        try? await Task.sleep(nanoseconds: 100_000_000)
        postKey(keyCode: 9, flags: .maskCommand)
        if autoSend {
            try? await Task.sleep(nanoseconds: 150_000_000)
            postKey(keyCode: 36, flags: [])
        }
        try? await Task.sleep(nanoseconds: 150_000_000)

        let restore = ClipboardGuard.shouldRestore(
            ourChangeCount: ourChangeCount,
            ourString: text,
            currentChangeCount: pasteboard.changeCount,
            currentString: pasteboard.string(forType: .string)
        )
        if restore {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter InjectionTests`
Expected: 5 tests pass.

- [ ] **Step 6: Add the paste command to the CLI**

In `Sources/FennecCLI/main.swift`, add `paste --text "..." [--auto-send]` to the usage text and add this case before `default:`:

```swift
case "paste":
    guard let textIndex = rest.firstIndex(of: "--text"), rest.indices.contains(textIndex + 1) else {
        fail("usage: fennec paste --text \"...\" [--auto-send]", code: 64)
    }
    await Injector().paste(rest[textIndex + 1], autoSend: rest.contains("--auto-send"))
```

Run: `swift build`
Expected: builds.

- [ ] **Step 7: Verify real paste behavior manually**

The terminal app running the command needs Accessibility permission for this test (System Settings, Privacy and Security, Accessibility). Note that the bundled app gets its own grant later.

Run: `swift run fennec paste --text "fennec paste check"` with TextEdit focused.
Expected: the text appears at the cursor.

Run the same with a terminal focused.
Expected: the text appears on the command line but is not executed.

Run: `swift run fennec paste --text "echo fennec-auto-send-check" --auto-send` with a shell prompt focused.
Expected: the command runs. This is the only path that sends Return.

- [ ] **Step 8: Commit**

```bash
git add Sources/FennecCore/InjectionPolicy.swift Sources/FennecCore/ClipboardGuard.swift Sources/FennecCore/Injector.swift Tests/FennecCoreTests/InjectionTests.swift Sources/FennecCLI/main.swift
git commit -m "feat(core): injection policy and clipboard injector"
```

---

### Task 11: Hotkey state machine

**Files:**
- Create: `Sources/FennecCore/HotkeyStateMachine.swift`
- Test: `Tests/FennecCoreTests/HotkeyStateMachineTests.swift`

**Interfaces:**
- Consumes: `AutoSendMode` (Task 2).
- Produces: `HotkeyStateMachine.Event` (`.startRequested`, `.stopRequested(shiftHeld:)`, `.cancelRequested`), `HotkeyStateMachine.Action` (`.beginRecording`, `.finishRecording(autoSend:)`, `.cancelRecording`, `.ignore`), `handle(_:autoSend:)`. Task 12 wires raw CGEventTap input into these events.

- [ ] **Step 1: Write the failing tests**

`Tests/FennecCoreTests/HotkeyStateMachineTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func startThenStopOrdersEvents() {
    var machine = HotkeyStateMachine()
    #expect(machine.handle(.startRequested, autoSend: .off) == .beginRecording)
    #expect(machine.isRecording)
    #expect(machine.handle(.startRequested, autoSend: .off) == .ignore)
    #expect(machine.handle(.stopRequested(shiftHeld: false), autoSend: .off) == .finishRecording(autoSend: false))
    #expect(!machine.isRecording)
}

@Test func shiftModeArmsAutoSendOnRelease() {
    var machine = HotkeyStateMachine()
    _ = machine.handle(.startRequested, autoSend: .shift)
    #expect(machine.handle(.stopRequested(shiftHeld: true), autoSend: .shift) == .finishRecording(autoSend: true))

    _ = machine.handle(.startRequested, autoSend: .shift)
    #expect(machine.handle(.stopRequested(shiftHeld: false), autoSend: .shift) == .finishRecording(autoSend: false))
}

@Test func alwaysModeIgnoresShift() {
    var machine = HotkeyStateMachine()
    _ = machine.handle(.startRequested, autoSend: .always)
    #expect(machine.handle(.stopRequested(shiftHeld: false), autoSend: .always) == .finishRecording(autoSend: true))
}

@Test func cancelOnlyAppliesWhileRecording() {
    var machine = HotkeyStateMachine()
    #expect(machine.handle(.cancelRequested, autoSend: .off) == .ignore)
    _ = machine.handle(.startRequested, autoSend: .off)
    #expect(machine.handle(.cancelRequested, autoSend: .off) == .cancelRecording)
    #expect(!machine.isRecording)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotkeyStateMachineTests`
Expected: compile failure, `cannot find 'HotkeyStateMachine' in scope`.

- [ ] **Step 3: Write HotkeyStateMachine.swift**

```swift
import Foundation

public struct HotkeyStateMachine: Sendable {
    public enum Event: Equatable, Sendable {
        case startRequested
        case stopRequested(shiftHeld: Bool)
        case cancelRequested
    }

    public enum Action: Equatable, Sendable {
        case beginRecording
        case finishRecording(autoSend: Bool)
        case cancelRecording
        case ignore
    }

    public private(set) var isRecording = false

    public init() {}

    public mutating func handle(_ event: Event, autoSend mode: AutoSendMode) -> Action {
        switch event {
        case .startRequested:
            guard !isRecording else { return .ignore }
            isRecording = true
            return .beginRecording
        case .stopRequested(let shiftHeld):
            guard isRecording else { return .ignore }
            isRecording = false
            switch mode {
            case .off: return .finishRecording(autoSend: false)
            case .shift: return .finishRecording(autoSend: shiftHeld)
            case .always: return .finishRecording(autoSend: true)
            }
        case .cancelRequested:
            guard isRecording else { return .ignore }
            isRecording = false
            return .cancelRecording
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HotkeyStateMachineTests`
Expected: 4 tests pass. Then run `swift test`; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FennecCore/HotkeyStateMachine.swift Tests/FennecCoreTests/HotkeyStateMachineTests.swift
git commit -m "feat(core): hotkey state machine"
```

---

### Task 12: Menu-bar app, permissions, and recording

**Files:**
- Create: `Sources/FennecCore/DebugLog.swift`
- Create: `Sources/FennecApp/main.swift` (replaces the stub)
- Create: `Sources/FennecApp/AppController.swift`
- Create: `Sources/FennecApp/MenuBar.swift`
- Create: `Sources/FennecApp/HotkeyTap.swift`
- Create: `Sources/FennecApp/Recorder.swift`
- Create: `Sources/FennecApp/Permissions.swift`
- Create: `Sources/FennecApp/Notifier.swift`
- Test: `Tests/FennecCoreTests/DebugLogTests.swift`

**Interfaces:**
- Consumes: `HotkeyStateMachine`, `InjectionPolicy`, `Injector`, `SilenceTrimmer`, `PreRollBuffer`, `TextPipeline`, `FillerDetector`, `VozTranscriber`, `FillerDetectorFactory`, `Config`, `Dictionary` (Tasks 2 through 11).
- Produces: a runnable menu bar app, `DebugLog(enabled:url:)`, `DebugLog.record(_:)`.

- [ ] **Step 1: Write the failing DebugLog tests**

`Tests/FennecCoreTests/DebugLogTests.swift`:

```swift
import Foundation
import Testing
@testable import FennecCore

@Test func debugLogWritesWhenEnabled() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("fennec.log")
    DebugLog(enabled: true, url: url).record("hello")
    let contents = try String(contentsOf: url, encoding: .utf8)
    #expect(contents.contains("hello"))
}

@Test func debugLogIsSilentWhenDisabled() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    DebugLog(enabled: false, url: url).record("hello")
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DebugLogTests`
Expected: compile failure, `cannot find 'DebugLog' in scope`.

- [ ] **Step 3: Write DebugLog.swift**

```swift
import Foundation

public struct DebugLog: Sendable {
    public var enabled: Bool
    public var url: URL

    public init(
        enabled: Bool,
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Fennec/fennec.log")
    ) {
        self.enabled = enabled
        self.url = url
    }

    public func record(_ message: String) {
        guard enabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DebugLogTests`
Expected: 2 tests pass.

- [ ] **Step 5: Write Permissions.swift**

```swift
import AppKit
import AVFoundation
import IOKit.hid

enum Permissions {
    static func microphoneGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 6: Write HotkeyTap.swift**

```swift
import CoreGraphics
import FennecCore

final class HotkeyTap {
    var onEvent: ((HotkeyStateMachine.Event) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var optionIsDown = false

    private static let rightOptionKeyCode: Int64 = 61
    private static let escapeKeyCode: Int64 = 53

    func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
            tap.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged where keyCode == Self.rightOptionKeyCode:
            let isDown = event.flags.contains(.maskAlternate)
            if isDown, !optionIsDown {
                optionIsDown = true
                onEvent?(.startRequested)
            } else if !isDown, optionIsDown {
                optionIsDown = false
                onEvent?(.stopRequested(shiftHeld: event.flags.contains(.maskShift)))
            }
        case .keyDown where keyCode == Self.escapeKeyCode:
            onEvent?(.cancelRequested)
        default:
            break
        }
    }
}
```

- [ ] **Step 7: Write Recorder.swift**

```swift
import AVFoundation
import FennecCore
import Foundation

enum RecorderError: Error {
    case formatUnavailable
}

final class Recorder {
    static let sampleRate: Double = 16000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var preRoll: PreRollBuffer
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var running = false

    init(preRollSeconds: Double) {
        preRoll = PreRollBuffer(capacity: Int(preRollSeconds * Self.sampleRate))
    }

    func start() throws {
        lock.lock()
        samples = preRoll.drain()
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ), let audioConverter = AVAudioConverter(from: inputFormat, to: target) else {
            throw RecorderError.formatUnavailable
        }
        converter = audioConverter
        targetFormat = target

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() -> [Float] {
        finish()
    }

    func cancel() {
        _ = finish()
    }

    private func finish() -> [Float] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
        }
        lock.lock()
        let result = samples
        samples = []
        lock.unlock()
        return result
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }
        var error: NSError?
        var supplied = false
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }
}
```

Note: capture starts on key down, so the pre-roll buffer is drained empty for now. It becomes meaningful if a future task keeps the engine warm; keeping it costs nothing.

- [ ] **Step 8: Write Notifier.swift and MenuBar.swift**

`Sources/FennecApp/Notifier.swift`:

```swift
import Foundation
import UserNotifications

enum Notifier {
    static func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
}
```

`Sources/FennecApp/MenuBar.swift`:

```swift
import AppKit
import FennecCore

final class MenuBar {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")

    var onCopyLastTranscript: (() -> Void)?
    var onEditDictionary: (() -> Void)?
    var onEditConfig: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onRevealLog: (() -> Void)?
    var onRequestPermissions: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        add(menu, "Copy last transcript", #selector(copyLast))
        add(menu, "Edit dictionary", #selector(editDictionary))
        add(menu, "Edit config", #selector(editConfig))
        add(menu, "Reload config", #selector(reloadConfig))
        menu.addItem(.separator())
        add(menu, "Permissions", #selector(permissions))
        add(menu, "Reveal log", #selector(revealLog))
        menu.addItem(.separator())
        add(menu, "About Fennec", #selector(about))
        add(menu, "Quit Fennec", #selector(quit))
        statusItem.menu = menu
        statusItem.button?.title = "Fennec"
    }

    func update(state: String) {
        statusMenuItem.title = state
        statusItem.button?.toolTip = "Fennec: \(state)"
    }

    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func copyLast() { onCopyLastTranscript?() }
    @objc private func editDictionary() { onEditDictionary?() }
    @objc private func editConfig() { onEditConfig?() }
    @objc private func reloadConfig() { onReloadConfig?() }
    @objc private func permissions() { onRequestPermissions?() }
    @objc private func revealLog() { onRevealLog?() }
    @objc private func quit() { onQuit?() }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Fennec \(fennecVersion)"
        alert.informativeText = "On-device push-to-talk dictation. Hold Right Option, speak, release.\n\nPowered by Desert Ant Labs."
        alert.runModal()
    }
}
```

`fennecVersion` comes from FennecCore; add `import FennecCore` to MenuBar.swift.

- [ ] **Step 9: Write AppController.swift**

```swift
import AppKit
import Carbon
import FennecCore
import FennecEngine
import Foundation

final class AppController {
    private let hotkeyState = HotkeyStateMachine()
    private let transcriber = VozTranscriber()
    private let injector = Injector()
    private let detector: any FillerDetector = FillerDetectorFactory.make()
    private let menu = MenuBar()

    private var tap: HotkeyTap?
    private var recorder: Recorder?
    private var config = Config()
    private var dictionary = Dictionary.builtIn
    private var lastTranscript = ""
    private var targetPID: pid_t = 0
    private var recordingStarted: CFAbsoluteTime = 0
    private var maxDurationTask: Task<Void, Never>?

    private var debugLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Fennec/fennec.log")
    }

    func start() {
        loadConfiguration()

        menu.onCopyLastTranscript = { [weak self] in
            guard let self, !self.lastTranscript.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.lastTranscript, forType: .string)
        }
        menu.onEditDictionary = { [weak self] in self?.openDictionary() }
        menu.onEditConfig = { [weak self] in self?.openConfig() }
        menu.onReloadConfig = { [weak self] in self?.loadConfiguration() }
        menu.onRevealLog = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.selectFile(
                self.debugLogURL.path,
                inFileViewerRootedAtPath: self.debugLogURL.deletingLastPathComponent().path
            )
        }
        menu.onRequestPermissions = { [weak self] in self?.requestPermissions() }
        menu.onQuit = { NSApp.terminate(nil) }

        menu.update(state: "Starting")
        if !Permissions.accessibilityGranted() || !Permissions.inputMonitoringGranted() {
            requestPermissions()
        }
        tap = HotkeyTap()
        tap?.onEvent = { [weak self] event in self?.handle(event) }
        tap?.start()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.transcriber.prepare { _ in }
                self.log("engine ready")
                self.menu.update(state: "Idle")
            } catch {
                self.menu.update(state: "Engine error: \(error)")
            }
        }
    }

    private func handle(_ event: HotkeyStateMachine.Event) {
        let action = hotkeyState.handle(event, autoSend: config.autoSend)
        switch action {
        case .beginRecording:
            beginRecording()
        case .finishRecording(let autoSend):
            Task { await finishRecording(autoSend: autoSend) }
        case .cancelRecording:
            cancelRecording()
        case .ignore:
            break
        }
    }

    private func beginRecording() {
        guard Permissions.microphoneGranted() else {
            Task { _ = await Permissions.requestMicrophone() }
            menu.update(state: "Microphone permission needed")
            return
        }
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        recordingStarted = CFAbsoluteTimeGetCurrent()
        do {
            let recorder = Recorder(preRollSeconds: config.preRollSeconds)
            try recorder.start()
            self.recorder = recorder
            menu.update(state: "Listening")
            log("beginRecording")
            let maxSeconds = config.maxDurationSeconds
            maxDurationTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(maxSeconds * 1_000_000_000))
                guard let self, self.recorder != nil else { return }
                self.log("max duration reached")
                await self.finishRecording(autoSend: false)
            }
        } catch {
            menu.update(state: "Recorder error: \(error)")
        }
    }

    private func cancelRecording() {
        maxDurationTask?.cancel()
        recorder?.cancel()
        recorder = nil
        menu.update(state: "Idle")
        log("cancelRecording")
    }

    private func finishRecording(autoSend: Bool) async {
        maxDurationTask?.cancel()
        guard let recorder else { return }
        let raw = recorder.stop()
        self.recorder = nil
        let keyUp = CFAbsoluteTimeGetCurrent()
        log("keyUp duration_ms=\(Int((keyUp - recordingStarted) * 1000))")
        menu.update(state: "Working")

        let samples = SilenceTrimmer.trim(raw, sampleRate: Recorder.sampleRate)
        guard samples.count >= Int(config.minDurationSeconds * Recorder.sampleRate) else {
            menu.update(state: "Idle")
            log("too short")
            return
        }

        do {
            let transcript = try await transcribeWithRetry(samples)
            let spans = (try? await detector.fillerRanges(
                samples: samples,
                sampleRate: Recorder.sampleRate,
                words: transcript.words
            )) ?? []
            let text = TextPipeline.process(
                words: transcript.words,
                config: .from(config),
                dictionary: dictionary,
                fillerSpans: spans
            )
            log("ready total_ms=\(Int((CFAbsoluteTimeGetCurrent() - keyUp) * 1000))")

            let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            let outcome = InjectionPolicy.decide(
                hasText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                focusChanged: currentPID != targetPID,
                secureInput: IsSecureEventInputEnabled(),
                autoSend: autoSend
            )

            switch outcome {
            case .paste(let send):
                await injector.paste(text, autoSend: send)
                lastTranscript = text
                log("pasted autoSend=\(send)")
            case .clipboardOnly(let reason):
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    lastTranscript = text
                }
                Notifier.post(title: "Fennec", body: Self.message(for: reason))
                log("clipboardOnly reason=\(reason)")
            }
        } catch {
            menu.update(state: "Transcribe error: \(error)")
            log("transcribe error \(error)")
            return
        }
        menu.update(state: "Idle")
    }

    private func transcribeWithRetry(_ samples: [Float]) async throws -> Transcript {
        var transcript = try await transcriber.transcribe(samples: samples, sampleRate: Recorder.sampleRate)
        if transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log("empty transcription, retrying once")
            transcript = try await transcriber.transcribe(samples: samples, sampleRate: Recorder.sampleRate)
        }
        return transcript
    }

    private func loadConfiguration() {
        do {
            let result = try Config.loadOrCreate()
            config = result.config
            for warning in result.warnings { log("config warning: \(warning)") }
            dictionary = (try? Dictionary.load(from: config.dictionaryURL)) ?? .builtIn
            log("config loaded hotkey=\(config.hotkey.rawValue) autoSend=\(config.autoSend.rawValue)")
        } catch {
            config = Config()
            dictionary = .builtIn
            menu.update(state: "Config error: \(error)")
        }
    }

    private func openConfig() {
        if !FileManager.default.fileExists(atPath: Config.defaultConfigURL.path) {
            try? Config.write(Config(), to: Config.defaultConfigURL)
        }
        NSWorkspace.shared.open(Config.defaultConfigURL)
    }

    private func openDictionary() {
        let url = config.dictionaryURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let starter = "# one entry per line: canonical = alias, alias\n"
            try? starter.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private func requestPermissions() {
        Task {
            if !Permissions.microphoneGranted() {
                _ = await Permissions.requestMicrophone()
            }
            if !Permissions.accessibilityGranted() {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
            if !Permissions.inputMonitoringGranted() {
                Permissions.requestInputMonitoring()
                Permissions.openInputMonitoringSettings()
            }
        }
    }

    private func log(_ message: String) {
        DebugLog(enabled: config.debugLogging, url: debugLogURL).record(message)
    }

    private static func message(for reason: InjectionBlockReason) -> String {
        switch reason {
        case .noSpeech:
            return "No speech detected."
        case .focusChanged:
            return "Focus changed mid-dictation. Transcript copied to the clipboard."
        case .secureInput:
            return "Secure input is active. Transcript copied to the clipboard."
        }
    }
}
```

- [ ] **Step 10: Write main.swift**

```swift
import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = AppController()
controller.start()
application.run()
```

- [ ] **Step 11: Build and run**

Run: `swift build`
Expected: builds. If `kAXTrustedCheckOptionPrompt.takeUnretainedValue()` complains, confirm the `import AppKit` is present in Permissions.swift.

Run: `swift run Fennec`
Expected: a "Fennec" item appears in the menu bar, permission prompts appear on first run, and the menu shows "Idle" once the engine is ready.

- [ ] **Step 12: Manual verification**

1. Focus TextEdit, hold Right Option, say "hello from fennec period", release.
   Expected: "Hello from fennec." appears about half a second after release.
2. Hold Right Option, speak, press Escape, release.
   Expected: nothing is pasted.
3. Focus Terminal, hold Right Option, say "echo hello", release.
   Expected: the text appears on the command line, not executed.
4. Start in TextEdit, hold Right Option, speak, click Terminal before releasing.
   Expected: no paste; a notification says the transcript is on the clipboard.
5. Enable `debugLogging` in the config, restart, do one dictation, then `tail -5 ~/Library/Logs/Fennec/fennec.log`.
   Expected: lines for beginRecording, keyUp, ready, pasted.

Note: launched via `swift run`, the binary does not own TCC grants or the notification bundle identity, so permission prompts and notifications can behave oddly. Treat those two checks as provisional; Tasks 13 and 14 repeat them against the signed bundle.

- [ ] **Step 13: Commit**

```bash
git add Sources/FennecCore/DebugLog.swift Sources/FennecApp Tests/FennecCoreTests/DebugLogTests.swift
git commit -m "feat(app): menu bar push-to-talk dictation"
```

---

### Task 13: Packaging, signing, and README

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/Info.plist`
- Modify: `README.md`

**Interfaces:**
- Consumes: the built `Fennec` executable (Task 12).
- Produces: `Fennec.app` signed with a stable identity, optional `/Applications` install.

- [ ] **Step 1: Write scripts/Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Fennec</string>
  <key>CFBundleIdentifier</key><string>com.jam.fennec</string>
  <key>CFBundleName</key><string>Fennec</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Fennec records your voice only while you hold the dictation key, and transcribes it on device.</string>
</dict>
</plist>
```

- [ ] **Step 2: Write scripts/build-app.sh**

```zsh
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Fennec"
BUNDLE_ID="com.jam.fennec"
VERSION="0.1.0"
IDENTITY="Fennec Local Signing"
APP_DIR=".build/release/$APP_NAME.app"

echo "==> Building"
swift build -c release --product "$APP_NAME"

echo "==> Assembling bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp scripts/Info.plist "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "==> Creating signing identity '$IDENTITY' (one time; macOS may ask for keychain access)"
  TMP="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes \
    -subj "/CN=$IDENTITY" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:false"
  openssl pkcs12 -export -out "$TMP/cert.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:
  security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" -T /usr/bin/codesign
  security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem" || true
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$HOME/Library/Keychains/login.keychain-db" || true
  rm -rf "$TMP"
fi

echo "==> Signing"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP_DIR"

echo "==> Verifying"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | grep -E "Identifier|Authority"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  echo "==> Installed /Applications/$APP_NAME.app"
fi
```

If automated certificate creation fails, the fallback is manual: Keychain Access, Certificate Assistant, Create a Certificate, name `Fennec Local Signing`, type Code Signing, self-signed, then trust it for code signing. The script then finds the identity on the next run.

- [ ] **Step 3: Build and install the app**

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh --install
```

Expected: builds, creates the identity the first time (keychain may prompt; approve it), signs, prints the identifier and authority, installs to /Applications.

- [ ] **Step 4: Verify TCC persistence across rebuilds**

1. Launch `/Applications/Fennec.app`, grant Microphone, Input Monitoring, and Accessibility when prompted.
2. Dictate into TextEdit once to confirm it works.
3. Run `./scripts/build-app.sh --install` again.
4. Quit and relaunch the app, dictate again.

Expected: it still works with no new permission prompts. If prompts return, the signature identity changed, and Step 2's fallback path needs to be used.

- [ ] **Step 5: Write the final README**

Replace `README.md`:

```markdown
# Fennec

Menu-bar push-to-talk dictation for macOS: hold Right Option, speak, release, and the
transcript is pasted into whatever input is focused, including terminals and TUI agents
like opencode, Codex CLI, and Claude Code.

Recognition runs fully on device with [Desert Ant Voz](https://desertant.com/models/voz/),
a Parakeet TDT 0.6B v3 build for the Apple Neural Engine. Nothing is uploaded.

## Requirements

- macOS 26 on Apple Silicon
- Xcode 26 (build only)

## Build and install

```bash
./scripts/build-app.sh --install
```

## Use

- Hold **Right Option** and speak; release to insert the text.
- Press **Escape** while holding to cancel.
- Hold **Shift** when releasing to press Return after the paste (when `autoSend` is `shift`).
- The menu bar item shows Idle, Listening, Working, or an error.

## Configuration

`~/.config/fennec/config.json`:

- `hotkey`: `rightOption` (default), `rightCommand`, `fn`, `f13`
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

- Voz is a batch model: no live word-by-word preview.
- The first run downloads a 467 MB model and warms up once (about 20 seconds).
- Secure Input (password prompts, terminal Secure Keyboard Entry) blocks pasting by design;
  the transcript goes to the clipboard instead.

Powered by Desert Ant Labs.
```

- [ ] **Step 6: Commit**

```bash
git add scripts/build-app.sh scripts/Info.plist README.md
git commit -m "chore: package and sign the app bundle"
```

---

### Task 14: Manual matrix, latency verification, and fixes

**Files:**
- Create: `docs/manual-test-matrix.md`
- Modify: any file a failed check points at

**Interfaces:**
- Consumes: the installed app (Task 13).
- Produces: recorded results; the p50 and p95 numbers for the release to pasted path.

- [ ] **Step 1: Create the matrix document**

`docs/manual-test-matrix.md`:

```markdown
# Manual test matrix

Run each row with the installed app. Record pass or fail and any notes.

| Target | Paste appears | Not auto-executed | Notes |
| --- | --- | --- | --- |
| TextEdit | | | |
| Terminal.app | | | |
| tmux pane | | | |
| VS Code integrated terminal | | | |
| opencode TUI | | | |
| codex TUI | | | |
| Hermes | | | |
| Browser text field | | | |

## Latency

1. Set `debugLogging: true` in the config and restart the app.
2. Dictate 20 short prompts (5 to 15 seconds each) into any app.
3. Run:

```bash
grep -o 'total_ms=[0-9]*' ~/Library/Logs/Fennec/fennec.log | cut -d= -f2 | sort -n | \
  awk '{a[NR]=$1} END {print "n="NR, "p50="a[int(NR*0.5)], "p95="a[int(NR*0.95)]}'
```

Target: p95 at or under 500.

## Long utterance

Spoken text must survive Voz's 15 second windowing (Review Focus item 4).

1. Create `fixtures/long-paragraph.txt` containing this 68 word paragraph:

```
This paragraph exists to verify that a long dictation survives the transcription window.
Fennec splits audio into fifteen second chunks, transcribes each chunk, and rejoins them
using the words that neighboring windows agree on. If a middle window were dropped we would
see a sudden gap here, roughly in the center of the sentence, and the final word count would
come up short. Count the words and compare.
```

2. Run:

```bash
say -f fixtures/long-paragraph.txt -o fixtures/long.aiff
afconvert -f WAVE -d LEI16@16000 -c 1 fixtures/long.aiff fixtures/long.wav
swift run fennec transcribe fixtures/long.wav --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)['text'].split()))"
```

3. Expected: 61 words or more (90 percent or better), with no visible gap in the middle. Record the number.
```

- [ ] **Step 2: Run the matrix**

Launch the installed app, work through every row with a short spoken sentence, and fill in results. Use `--auto-send` behavior only in the shell row for the Return check, and confirm that no other row auto-executes.

- [ ] **Step 3: Run the latency measurement**

Follow the Latency section. If p95 is over 500, check `timings_ms` lines in the log to find the slow stage (transcribe versus filler versus injection) and fix that stage before re-measuring.

- [ ] **Step 4: Fix whatever failed, re-run**

Every fix gets committed with a conventional message, for example `fix(app): keep focus guard from firing on same-app window changes`.

- [ ] **Step 5: Commit the results**

```bash
git add docs/manual-test-matrix.md
git commit -m "docs: record manual test matrix and latency results"
```

---

## Appendix: Spec coverage map

| Spec section | Tasks |
| --- | --- |
| Goals, on-device transcription | 1, 8 |
| Non-goals (no streaming, no LLM rewriting) | Global Constraints; Tasks 6, 8 |
| Constraints and decisions (Voz, Uhm, clipboard injection) | 1, 8, 9, 10 |
| Architecture (targets and components) | 1, 8, 10, 11, 12 |
| Dictation flow | 8, 11, 12 |
| Text pipeline (fillers, dictionary, punctuation, capitalization) | 3, 4, 5, 6 |
| Config | 2 |
| Error handling and states | 10, 12 |
| Permissions and signing | 12, 13 |
| Testing (unit, integration, manual, latency) | Every task; 8, 14 |
| Repo layout | 1; Files blocks throughout |
| Risks and validation order | 1, 8, 9, 13 |
| Future work | Explicitly out of scope |
| Attribution | 1, 12, 13 |

