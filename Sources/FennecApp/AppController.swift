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
    private let detector: any FillerDetector = FillerDetectorFactory.make()
    private let menu = MenuBar()

    private var tap: HotkeyTap?
    private var recorder: Recorder?
    private var config = Config()
    private var dictionary = TermDictionary.builtIn
    private var lastTranscript = ""
    private var target = DictationTarget.capture(frontmostPID: nil)
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
        tap = HotkeyTap(hotkey: config.hotkey)
        tap?.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        tap?.start()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.transcriber.prepare(progress: nil)
                await self.detector.prepare()
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
        target = DictationTarget.capture(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
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
        let target = self.target
        let config = self.config
        let dictionary = self.dictionary
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

            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let outcome = InjectionPolicy.decide(
                hasText: hasText,
                focusChanged: !target.stillFocused(currentPID: currentPID),
                secureInput: IsSecureEventInputEnabled(),
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
                let posted = await injector.paste(text, autoSend: send, verifyTarget: verify)
                if hasText {
                    lastTranscript = text
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
            dictionary = (try? TermDictionary.load(from: config.dictionaryURL)) ?? .builtIn
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
