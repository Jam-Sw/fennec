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
