import Foundation
import FennecCore
import FennecEngine

@main
struct FennecCLI {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fail("""
            usage: fennec <command> [options]
            commands:
              probe <audio-file>
              transcribe <audio-file> [--cleanup] [--dictionary <path>] [--json] [--timings]
              paste --text "..." [--auto-send]
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
                try await transcriber.prepare(progress: { fraction in
                    FileHandle.standardError.write(Data("model download: \(Int(fraction * 100))%\n".utf8))
                })
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

                    let dictionary: TermDictionary
                    if let flagIndex = rest.firstIndex(of: "--dictionary"),
                       rest.indices.contains(flagIndex + 1) {
                        dictionary = (try? TermDictionary.load(from: URL(fileURLWithPath: rest[flagIndex + 1]))) ?? .builtIn
                    } else {
                        dictionary = (try? TermDictionary.load(from: config.dictionaryURL)) ?? .builtIn
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

        case "paste":
            guard let textIndex = rest.firstIndex(of: "--text"), rest.indices.contains(textIndex + 1) else {
                fail("usage: fennec paste --text \"...\" [--auto-send]", code: 64)
            }
            await Injector().paste(rest[textIndex + 1], autoSend: rest.contains("--auto-send"))

        default:
            fail("unknown command '\(command)'", code: 64)
        }
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(code)
    }

    static func jsonEscape(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }

    static func milliseconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}
