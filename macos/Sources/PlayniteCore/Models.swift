import Foundation

public enum Store: String, Codable, CaseIterable, Identifiable, Sendable {
    case local = "Mac", steam = "Steam", gog = "GOG", epic = "Epic", itch = "itch.io"
    public var id: String { rawValue }
}
public enum LaunchKind: String, Codable, Sendable { case application, store }
public struct Game: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var store: Store
    public var launchKind: LaunchKind
    public var launchTarget: String
    public var installPath: String
    public var storeID: String
    public var summary = ""
    public var developer = ""
    public var genres: [String] = []
    public var releaseDate = ""
    public var artwork = ""
    public var storeURL = ""
    public var metadataSource = ""
    public var metadataUpdated: Date?
    public var favorite = false
    public var lastPlayed: Date?
    public var addedAt = Date()
    public init(id: String, name: String, store: Store, launchKind: LaunchKind, launchTarget: String, installPath: String = "", storeID: String = "") {
        self.id = id; self.name = name; self.store = store; self.launchKind = launchKind
        self.launchTarget = launchTarget; self.installPath = installPath; self.storeID = storeID
    }
    public static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
public struct Metadata: Equatable, Sendable {
    public var name: String, summary: String, developer: String, releaseDate: String, artwork: String, url: String, source: String
    public var genres: [String]
    public init(name: String = "", summary: String = "", developer: String = "", releaseDate: String = "", artwork: String = "", url: String = "", source: String = "", genres: [String] = []) {
        self.name = name; self.summary = summary; self.developer = developer; self.releaseDate = releaseDate; self.artwork = artwork; self.url = url; self.source = source; self.genres = genres
    }
    public func applying(to original: Game) -> Game {
        var game = original
        if !summary.isEmpty { game.summary = summary }
        if !developer.isEmpty { game.developer = developer }
        if !releaseDate.isEmpty { game.releaseDate = releaseDate }
        if !artwork.isEmpty { game.artwork = artwork }
        if !url.isEmpty { game.storeURL = url }
        if !genres.isEmpty { game.genres = genres }
        game.metadataSource = source; game.metadataUpdated = Date()
        return game
    }
}
public enum LibraryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
public struct LibraryFile: Codable, Sendable {
    public var version = 1
    public var games: [Game]
    public var folders: [String]
    public init(games: [Game] = [], folders: [String] = []) { self.games = games; self.folders = folders }
}
public final class LibraryStorage {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> LibraryFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryFile() }
        let file = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: url))
        guard file.version == 1 else { throw LibraryError.invalid("Unsupported library version \(file.version).") }
        return file
    }
    public func save(_ file: LibraryFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

public enum VDF {
    public indirect enum Value { case text(String), object([String: Value]) }
    public static func parse(_ text: String) throws -> [String: Value] {
        let chars = Array(text); var index = 0
        func whitespace() {
            while index < chars.count {
                if chars[index].isWhitespace { index += 1 }
                else if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                    while index < chars.count && chars[index] != "\n" { index += 1 }
                } else { break }
            }
        }
        func token() throws -> String {
            whitespace()
            guard index < chars.count, chars[index] == "\"" else { throw LibraryError.invalid("Invalid VDF token at \(index).") }
            index += 1; var value = ""
            while index < chars.count {
                let c = chars[index]; index += 1
                if c == "\"" { return value }
                if c == "\\", index < chars.count {
                    let next = chars[index]
                    if next == "\\" || next == "\"" { value.append(next); index += 1 }
                    else { value.append(c) }
                } else { value.append(c) }
            }
            throw LibraryError.invalid("Unterminated VDF string.")
        }
        func object(nested: Bool) throws -> [String: Value] {
            var result: [String: Value] = [:]
            while true {
                whitespace()
                if index >= chars.count {
                    if nested { throw LibraryError.invalid("Unterminated VDF object.") }
                    return result
                }
                if chars[index] == "}" {
                    guard nested else { throw LibraryError.invalid("Unexpected VDF brace.") }
                    index += 1; return result
                }
                let key = try token(); whitespace()
                if index < chars.count && chars[index] == "{" { index += 1; result[key] = .object(try object(nested: true)) }
                else { result[key] = .text(try token()) }
            }
        }
        return try object(nested: false)
    }
    public static func string(_ object: [String: Value], _ key: String) -> String? {
        if case .text(let value) = object[key] { return value }; return nil
    }
    public static func object(_ object: [String: Value], _ key: String) -> [String: Value]? {
        if case .object(let value) = object[key] { return value }; return nil
    }
}
