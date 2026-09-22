# Desert Ant SDK notes

Recorded from `.build/checkouts/desert-ant-core` at v3.3.0 (Package.resolved), 2026-09-22.
Machine: macOS 26.6.2, Apple M4 Pro, Swift 6.3.3 (Command Line Tools; Xcode 26 not installed yet).
Model cache after the first run: `~/Library/Caches/desert-ant-models/desert-ant-labs/voz/v0.1.0/`.

## Voz

- Package: `desert-ant-core`, pinned `from: "3.3.0"` (newest tag on 2026-09-22; the README asks for 3.3.1, which is not tagged yet).
- Init, downloads on demand:
  `public init(directory: String? = nil, cacheRoot: String? = nil, progress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }) async throws`
- Init from files you manage:
  `public init(modelDirectory: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws`
- Download: `@discardableResult public static func download(directory: String? = nil, cacheRoot: String? = nil, progress: @Sendable @escaping (DownloadProgress) -> Void = { _ in }) async throws -> String`
- Is downloaded: `public static func isDownloaded(directory: String? = nil, cacheRoot: String? = nil) -> Bool`
- `DownloadProgress`: `completedBytes: Int64`, `totalBytes: Int64`, `fraction: Double` (0...1). Not a bare Double.
- Transcribe, samples: `public func transcribe(samples: [Float], progress: @Sendable (Progress) -> Void = { _ in }) async throws -> Result`
  The samples must be mono at the instance's `sampleRate`. There is no `sampleRate` parameter; passing samples at another rate silently mis-times the audio.
- Transcribe, file: `public func transcribe(_ url: URL, progress: ...) async throws -> Result` (Voz+Audio.swift). Used by the Task 1 probe.
- `Result`: `text: String`, `words: [Word]`, `duration: TimeInterval`, `processingTime: TimeInterval`, `realtimeFactor: Double`.
- `Word`: `text: String`, `start: TimeInterval`, `end: TimeInterval`, `duration: TimeInterval`.
- Errors: `VozError.unsupportedPlatform`, `.invalidModel(String)`, `.invalidAudio(String)`.
- `sampleRate` is read at runtime; the downloaded v0.1.0 model reports 16000 (`meta.json: sample_rate = 16000`), which matches the recorder's 16 kHz target.
- Languages: `Voz.supportedLanguages`, 25 ISO 639-1 codes. No language detection; a language outside the set produces confident nonsense. Pair with Ear if that matters.
- Concurrency: the actor queues concurrent `transcribe` calls in order instead of rejecting them.
- Timings observed: the first probe run downloaded the model and transcribed `fixtures/hello.wav` to "Fennec dictation test. Send this to open code. New line. Done". Per-stage numbers arrive with `--timings` in Task 8.
- Empty and silence behavior: the silence fixture check runs in Task 8 Step 7. The runtime retries windows that produce nothing, so one retry on an empty result is the app-side rule.

## Uhm (evaluated in Task 9)

- Sources: `Sources/Uhm/` (Uhm.swift, Detector.swift, Filler.swift, Labeler.swift, WordReconciliation.swift).
- Docs: `docs/models/uhm.md`.
- API surface and latency get recorded here during Task 9, along with the go/no-go decision.

## Toolchain note

The SDK compiles and runs under the Command Line Tools toolchain (Swift 6.3.3) even though the README names Xcode 26. One transient SwiftPM "Applying" codesign failure appeared while the build state was damaged by an experiment and did not recur across clean and incremental builds. If a task hits a toolchain wall, installing Xcode 26 is the fix.
