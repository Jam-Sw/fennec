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
