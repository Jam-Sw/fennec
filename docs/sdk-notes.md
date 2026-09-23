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

## Uhm (evaluated 2026-09-22, no-go for v1)

- Public API: `Uhm()` (cheap to construct), `Uhm.Options` (`bias`, `includeTypes`, `minConfidence`, `minDurationSec`), `download(progress:)`, `analyze(samples:sampleRate:options:progressHandler:) -> Result` with `Result.fillers: [Detection{start, end, confidence, type}]`.
- Measured on the 5.1 s fixture, steady state after a warm-up call: 143.7 ms with the type labeler, 136.3 ms without. The bar was under 50 ms per utterance. The cost is the model itself (DistilHuBERT at a 20 ms hop, roughly 27x realtime), not the labeler.
- Decision: ship the pause-gated `HeuristicFillerDetector`. The adapter, its dependency, and the measurement test were reverted; they live in git history between commits 21ceff7 and the evaluation commit. If filler precision ever matters more than about 140 ms, flip `FillerDetectorFactory.make()` back to Uhm and re-add the product.

## Usage reporting

Recorded 2026-09-22 from `Sources/Usage` and `Sources/Voz/UsageTracking.swift` at v3.3.0.

- Every `Voz` opens a usage turnstile when the model loads and records one call per
  transcription. A debounced flush (3 s) POSTs to `https://platform.desertant.ai/api/v1/ingest`.
- Payload (`Usage/Wire.swift`): platform, SDK name and version, app id (the bundle id,
  `com.jam.fennec`), a random device id persisted by the SDK, call counts, and timestamps.
  No audio, text, or timings.
- `DAL_USAGE_DISABLED=1` switches it off. The SDK comments say it exists for CI and
  short-lived test processes, and that core "deliberately leaves no untracked path" for
  shipped apps; the license meters its free tier by monthly active devices. Fennec leaves
  reporting on and discloses it in the README.

## License terms that bind Fennec

Read from https://license.desertant.com/1.0.txt on 2026-09-22. Check the source before
relying on this summary.

- Paid apps may embed and ship the models. Free below 100,000 monthly active devices per
  model per platform; above that, a commercial license. Apps under common control count
  together.
- Attribution: credit such as "Powered by Desert Ant Labs" with a link to
  https://desertant.com, in an about, credits, or legal screen, or the store listing.
  Fennec has it in the About box (with a link button) and the README.
- The models and SDKs may not be sold or redistributed on their own.
- Section 6: do not tamper with the usage telemetry or interfere with its reporting.
- No restriction on how Fennec licenses its own code.
