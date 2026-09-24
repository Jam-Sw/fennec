import AppKit
import Carbon
import FennecCore
import FennecEngine
import Foundation

@MainActor
final class AppController {
    private var hotkeyState = HotkeyStateMachine()
    private let transcriber = VozTranscriber()
    private let injector = Injector()
    private let detector = HeuristicFillerDetector()
    private let menu = MenuBar()

    private var tap: HotkeyTap?
    private let recorder = Recorder(preRollSeconds: Config().preRollSeconds)
    private var isRecording = false
    private var config = Config()
    private var dictionary = TermDictionary.builtIn
    private var lastTranscript = ""
    private var target = DictationTarget.capture(frontmostPID: nil)
    private var recordingStarted: CFAbsoluteTime = 0
    private var maxDurationTask: Task<Void, Never>?
    private var engineReady = false
    private var clipboardToken: ClipboardSnapshotToken?
    private var lastDictationEnded: CFAbsoluteTime = 0
    private var liveTask: Task<Void, Never>?
    private var live = LiveCommitter()
    private var liveTyped = ""
    private var liveBlocked = false

    /// How often live typing re-transcribes the recording so far.
    private static let livePassInterval: UInt64 = 600_000_000

    /// Below this gap since the last dictation, the ANE/weights are still
    /// warm from that transcription, so a fresh warm-up pass would just add
    /// actor-queue contention for no benefit.
    private static let warmUpSkipWindow: CFAbsoluteTime = 30

    private var debugLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Fennec/fennec.log")
    }

    func start() {
        loadConfiguration()
        recorder.onLog = { [weak self] message in
            Task { @MainActor in self?.log(message) }
        }
        // Deferred to the next run-loop turn: `start()` runs before
        // `NSApplication.run()` (see FennecApp.main()), and engine.prepare()
        // resolving the default input/output device needs the run loop
        // already pumping - calling it inline here crashes intermittently
        // with "inputNode != nullptr || outputNode != nullptr".
        DispatchQueue.main.async { [weak self] in
            guard let self, Permissions.microphoneGranted() else { return }
            self.recorder.warmUp()
        }

        menu.onCopyLastTranscript = { [weak self] in
            guard let self, !self.lastTranscript.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.lastTranscript, forType: .string)
        }
        menu.onEditDictionary = { [weak self] in self?.openDictionary() }
        menu.onEditConfig = { [weak self] in self?.openConfig() }
        menu.onReloadConfig = { [weak self] in
            guard let self else { return }
            let hotkey = self.config.hotkey
            let preRollSeconds = self.config.preRollSeconds
            self.loadConfiguration()
            if self.config.hotkey != hotkey { self.installHotkeyTap() }
            if self.config.preRollSeconds != preRollSeconds {
                self.recorder.updatePreRoll(seconds: self.config.preRollSeconds)
            }
        }
        menu.onRevealLog = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.selectFile(
                self.debugLogURL.path,
                inFileViewerRootedAtPath: self.debugLogURL.deletingLastPathComponent().path
            )
        }
        menu.onRequestPermissions = { [weak self] in self?.requestPermissions() }
        menu.onQuit = { NSApp.terminate(nil) }

        log(
            "permissions microphone=\(Permissions.microphoneGranted()) accessibility=\(AXIsProcessTrusted()) "
                + "postEvents=\(CGPreflightPostEventAccess()) inputMonitoring=\(Permissions.inputMonitoringGranted())"
        )
        if !Permissions.canPostKeys() || !Permissions.inputMonitoringGranted() {
            requestPermissions()
        }
        installHotkeyTap()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.transcriber.prepare(progress: { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, !self.engineReady else { return }
                        self.menu.update(fraction < 1 ? .downloading(percent: Int(fraction * 100)) : .starting)
                    }
                })
                self.engineReady = true
                await self.detector.prepare()
                self.log("engine ready")
                self.menu.update(.idle)
                self.welcomeOnFirstRun()
            } catch {
                self.menu.update(.problem("Speech engine error: \(error)"))
            }
        }
    }

    private func installHotkeyTap() {
        tap?.stop()
        let tap = HotkeyTap(hotkey: config.hotkey)
        tap.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.tap = tap
        startHotkeyTap(tap)
    }
    private func startHotkeyTap(_ tap: HotkeyTap) {
        guard tap === self.tap else { return }
        if tap.start() { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.startHotkeyTap(tap)
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
            menu.update(.problem("Microphone access needed. Open Permissions…"))
            return
        }
        target = DictationTarget.capture(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        recordingStarted = CFAbsoluteTimeGetCurrent()
        clipboardToken = nil
        Task { [weak self, injector] in
            let token = await injector.snapshotToken()
            self?.clipboardToken = token
        }
        do {
            try recorder.start()
            isRecording = true
            menu.update(.listening)
            log("beginRecording")
            if engineReady, recordingStarted - lastDictationEnded > Self.warmUpSkipWindow {
                Task { [transcriber] in await transcriber.warmUp() }
            }
            if config.liveTyping, engineReady { startLiveTyping() }
            let maxSeconds = config.maxDurationSeconds
            maxDurationTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(maxSeconds * 1_000_000_000))
                guard let self, self.isRecording else { return }
                self.log("max duration reached")
                await self.finishRecording(autoSend: false)
            }
        } catch {
            menu.update(.problem("Recorder error: \(error)"))
        }
    }

    private func cancelRecording() {
        maxDurationTask?.cancel()
        liveTask?.cancel()
        liveTask = nil
        recorder.cancel()
        isRecording = false
        menu.update(.idle)
        log("cancelRecording")
    }

    private func finishRecording(autoSend: Bool) async {
        maxDurationTask?.cancel()
        guard isRecording else { return }
        isRecording = false
        let target = self.target
        let config = self.config
        let dictionary = self.dictionary
        let stopStart = CFAbsoluteTimeGetCurrent()
        let liveTask = self.liveTask
        self.liveTask = nil
        liveTask?.cancel()
        let raw = await recorder.stopCapture()
        recorder.stopEngineDeferred()
        let keyUp = CFAbsoluteTimeGetCurrent()
        lastDictationEnded = keyUp
        log("stage stop_ms=\(Int((keyUp - stopStart) * 1000))")
        log("keyUp duration_ms=\(Int((keyUp - recordingStarted) * 1000))")
        menu.update(.working)

        await liveTask?.value
        let liveWasTyping = !liveTyped.isEmpty

        let trimStart = CFAbsoluteTimeGetCurrent()
        let samples = liveWasTyping ? raw : SilenceTrimmer.trim(raw, sampleRate: Recorder.sampleRate)
        log("stage trim_ms=\(Int((CFAbsoluteTimeGetCurrent() - trimStart) * 1000))")
        guard liveWasTyping || samples.count >= Int(config.minDurationSeconds * Recorder.sampleRate) else {
            menu.update(.idle)
            log("too short")
            return
        }

        do {
            let transcribeStart = CFAbsoluteTimeGetCurrent()
            let transcript = try await transcribeWithRetry(samples)
            log("stage transcribe_ms=\(Int((CFAbsoluteTimeGetCurrent() - transcribeStart) * 1000))")
            let words = liveWasTyping ? live.finalWords(from: transcript.words) : transcript.words
            var spans = (try? await detector.fillerRanges(
                samples: samples,
                sampleRate: Recorder.sampleRate,
                words: words
            )) ?? []
            if liveWasTyping {
                let committedEnd = live.committedEnd
                spans = spans.filter { $0.lowerBound >= committedEnd }
            }
            let full = TextPipeline.process(
                words: words,
                config: .from(config),
                dictionary: dictionary,
                fillerSpans: spans
            )
            log("ready total_ms=\(Int((CFAbsoluteTimeGetCurrent() - keyUp) * 1000))")

            var text = full
            if liveWasTyping {
                lastTranscript = full
                if let delta = LiveTyping.delta(typed: liveTyped, rendered: full) {
                    text = delta
                } else {
                    let tail = Array(words.dropFirst(live.committed.count))
                    let tailText = TextPipeline.process(
                        words: tail, config: .from(config), dictionary: dictionary, fillerSpans: spans
                    )
                    text = tailText.isEmpty ? "" : " " + tailText
                    log("live mismatch typed=\(liveTyped.count) full=\(full.count)")
                }
                log("live final delta=\(text.count) typed=\(liveTyped.count)")
                liveTyped = ""
                if text.isEmpty {
                    if autoSend, liveTypingAllowed() {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        await injector.pressReturn()
                    }
                    menu.update(.idle)
                    return
                }
            }

            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let focusChanged = !target.stillFocused(currentPID: currentPID)
            let secureInput = IsSecureEventInputEnabled()
            let canPostKeys = Permissions.canPostKeys()
            log("decide focusChanged=\(focusChanged) secureInput=\(secureInput) canPostKeys=\(canPostKeys)")
            let outcome = InjectionPolicy.decide(
                hasText: hasText,
                focusChanged: focusChanged,
                secureInput: secureInput,
                canPostKeys: canPostKeys,
                autoSend: autoSend
            )

            let verify: @Sendable () async -> Bool = {
                await MainActor.run {
                    target.stillFocused(
                        currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
                    )
                }
            }

            switch outcome {
            case .paste(let send):
                let posted = await injector.paste(
                    text,
                    autoSend: send,
                    verifyTarget: verify,
                    priorSnapshot: clipboardToken,
                    settleSeconds: config.pasteSettleSeconds,
                    since: keyUp,
                    onStage: { [debugLogURL, debugLogging = config.debugLogging] stage, ms in
                        DebugLog(enabled: debugLogging, url: debugLogURL).record("stage \(stage) elapsed_ms=\(ms)")
                    }
                )
                if hasText {
                    lastTranscript = full
                }
                if posted {
                    log("pasted autoSend=\(send)")
                } else {
                    Notifier.post(title: "Fennec", body: Self.message(for: .focusChanged))
                    log("paste skipped: target moved during the settle window")
                }
            case .clipboardOnly(let reason):
                if hasText {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(full, forType: .string)
                    lastTranscript = full
                }
                Notifier.post(title: "Fennec", body: Self.message(for: reason))
                log("clipboardOnly reason=\(reason)")
                if reason == .notTrusted {
                    menu.update(.problem("Accessibility access needed to paste. Open Permissions…"))
                    return
                }
            }
        } catch {
            menu.update(.problem("Transcription error: \(error)"))
            log("transcribe error \(error)")
            return
        }
        menu.update(.idle)
    }

    private func startLiveTyping() {
        live = LiveCommitter()
        liveTyped = ""
        liveBlocked = false
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.livePassInterval)
                guard let self, !Task.isCancelled else { return }
                await self.livePass()
            }
        }
    }

    /// Transcribes recording 
    private func livePass() async {
        let samples = recorder.snapshot()
        let duration = Double(samples.count) / Recorder.sampleRate
        guard duration >= 1.0 else { return }
        let passStart = CFAbsoluteTimeGetCurrent()
        guard let transcript = try? await transcriber.transcribe(
            samples: samples,
            sampleRate: Recorder.sampleRate
        ) else { return }
        guard isRecording, !Task.isCancelled else { return }
        let fresh = live.update(words: transcript.words, duration: duration)
        log("live pass audio_ms=\(Int(duration * 1000)) pass_ms=\(Int((CFAbsoluteTimeGetCurrent() - passStart) * 1000)) committed=\(live.committed.count)")
        guard !fresh.isEmpty, liveTypingAllowed() else { return }
        let rendered = TextPipeline.process(
            words: live.committed,
            config: .from(config),
            dictionary: dictionary,
            fillerSpans: []
        )
        guard let delta = LiveTyping.delta(typed: liveTyped, rendered: rendered), !delta.isEmpty else { return }
        Injector.typeToSystem(delta)
        liveTyped += delta
    }

    private func liveTypingAllowed() -> Bool {
        guard !liveBlocked else { return false }
        let focused = target.stillFocused(
            currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        if focused, !IsSecureEventInputEnabled(), Permissions.canPostKeys() { return true }
        liveBlocked = true
        log("live typing stopped focused=\(focused)")
        return false
    }

    private func transcribeWithRetry(_ samples: [Float]) async throws -> Transcript {
        try await transcriber.transcribeWithRetry(
            samples: samples,
            sampleRate: Recorder.sampleRate
        ) { [weak self] in
            await self?.log("empty transcription, retrying once")
        }
    }

    private func loadConfiguration() {
        do {
            let result = try Config.loadOrCreate()
            config = result.config
            for warning in result.warnings { log("config warning: \(warning)") }
            dictionary = (try? TermDictionary.load(from: config.dictionaryURL)) ?? .builtIn
            menu.hotkeyName = config.hotkey.displayName
            log("config loaded hotkey=\(config.hotkey.rawValue) autoSend=\(config.autoSend.rawValue)")
        } catch {
            config = Config()
            dictionary = .builtIn
            menu.update(.problem("Config error: \(error)"))
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
            let starter = """
                # One entry per line: canonical = alias, alias
                # Aliases are what you say; the canonical spelling is what gets typed.
                # This file replaces the built-in list, which is copied below.

                """ + TermDictionary.builtIn.serialized()
            try? starter.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private func requestPermissions() {
        Task {
            if !Permissions.microphoneGranted() {
                if await Permissions.requestMicrophone() {
                    self.recorder.warmUp()
                }
            }
            if !Permissions.canPostKeys() {
                Permissions.requestAccessibility()
                Permissions.requestPostKeys()
                Permissions.openAccessibilitySettings()
            }
            if !Permissions.inputMonitoringGranted() {
                Permissions.requestInputMonitoring()
                Permissions.openInputMonitoringSettings()
            }
        }
    }

    private func welcomeOnFirstRun() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Notifier.post(
            title: "Fennec is ready",
            body: "Hold \(config.hotkey.displayName), speak, and release to type."
        )
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
        case .notTrusted:
            return "Fennec needs Accessibility access to paste. Transcript copied to the clipboard; choose Permissions… in the menu."
        }
    }
}
