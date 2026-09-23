import Foundation

public struct DictionaryEntry: Equatable, Sendable {
    public var canonical: String
    public var aliases: [String]

    public init(canonical: String, aliases: [String] = []) {
        self.canonical = canonical
        self.aliases = [canonical] + aliases.filter { $0 != canonical }
    }
}

public struct TermDictionary: Equatable, Sendable {
    public var entries: [DictionaryEntry]

    public init(entries: [DictionaryEntry]) {
        self.entries = entries
    }

    public static func parse(_ text: String) -> TermDictionary {
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
        return TermDictionary(entries: entries)
    }

    /// The file form `parse` reads: one `canonical = alias, alias` line per entry.
    public func serialized() -> String {
        entries.map { entry in
            let aliases = entry.aliases.filter { $0 != entry.canonical }
            return aliases.isEmpty ? entry.canonical : "\(entry.canonical) = \(aliases.joined(separator: ", "))"
        }
        .joined(separator: "\n") + "\n"
    }

    public static func load(from url: URL) throws -> TermDictionary {
        guard FileManager.default.fileExists(atPath: url.path) else { return .builtIn }
        return parse(try String(contentsOf: url, encoding: .utf8))
    }

    public static let builtIn = TermDictionary(entries: [
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
