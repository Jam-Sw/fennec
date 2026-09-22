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
