import Foundation

public struct Store: RawRepresentable, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    public let rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    public static let local = Self(rawValue: "Mac"), genericLocal = Self(rawValue: "Local"), steam = Self(rawValue: "Steam"), gog = Self(rawValue: "GOG"), epic = Self(rawValue: "Epic"), itch = Self(rawValue: "itch.io")
    public static let allCases: [Self] = [.local, .genericLocal, .steam, .gog, .epic, .itch]
}
public struct LaunchKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    public static let application = Self(rawValue: "application"), store = Self(rawValue: "store"), compatibility = Self(rawValue: "compatibility"), executable = Self(rawValue: "executable"), desktop = Self(rawValue: "desktop")
}
public struct CompatibilityLaunch: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String
    public var label: String
    public init(executable: String, arguments: [String], environment: [String: String], workingDirectory: String, label: String) { self.executable = executable; self.arguments = arguments; self.environment = environment; self.workingDirectory = workingDirectory; self.label = label }
}
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
    public var backgroundArtwork: String?
    public var cachedArtwork: String?
    public var cachedBackground: String?
    public var cachedLandscape: String?
    public var compatibility: CompatibilityLaunch?
    public var metadataOverrides: [String: String]?
    public var automaticMetadata: [String: String]?
    public var customArtwork: String?
    public var customLandscape: String?
    public var customBackground: String?
    public var hidden: Bool?
    public var pendingUninstall: Bool?
    public var storeURL = ""
    public var metadataSource = ""
    public var metadataSteamId: String?
    public var metadataUpdated: Date?
    public var favorite = false
    public var launchCount: UInt32?
    public var lastPlayed: Date?
    public var extra: [String: JSONValue] = [:]
    public var addedAt = Date()
    public init(id: String, name: String, store: Store, launchKind: LaunchKind, launchTarget: String, installPath: String = "", storeID: String = "") {
        self.id = id; self.name = name; self.store = store; self.launchKind = launchKind
        self.launchTarget = launchTarget; self.installPath = installPath; self.storeID = storeID
    }
    public mutating func recordLaunch(at date: Date = Date()) {
        let count = launchCount ?? 0
        launchCount = count == UInt32.max ? count : count + 1
        lastPlayed = date
    }
    public var metadataValues: [String: String] {
        ["name": name, "summary": summary, "developer": developer, "releaseDate": releaseDate, "genres": genres.joined(separator: ", "), "source": metadataSource]
    }
    public mutating func applyMetadataValues(_ values: [String: String]) {
        if let value = values["name"] { name = value }
        if let value = values["summary"] { summary = value }
        if let value = values["developer"] { developer = value }
        if let value = values["releaseDate"] { releaseDate = value }
        if let value = values["genres"] { genres = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    }
    public mutating func applyCustomMetadata(changes: [String: String], reset: Bool = false) {
        if automaticMetadata == nil { automaticMetadata = metadataValues }
        var overrides = reset ? [:] : metadataOverrides ?? [:]
        for (key, value) in changes where ["name", "summary", "developer", "releaseDate", "genres"].contains(key) { overrides[key] = value }
        metadataOverrides = overrides
        applyMetadataValues(automaticMetadata ?? [:]); applyMetadataValues(overrides)
        refreshMetadataSource()
        metadataUpdated = Date()
    }
    public mutating func refreshMetadataSource() {
        let base = automaticMetadata?["source"] ?? ""
        let custom = !(metadataOverrides ?? [:]).isEmpty || customArtwork != nil || customLandscape != nil || customBackground != nil
        metadataSource = custom ? (base.isEmpty ? "Custom" : base + " + custom") : base
    }
    public static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
public struct Metadata: Equatable, Sendable {
    public var name: String, summary: String, developer: String, releaseDate: String, artwork: String, url: String, source: String
    public var genres: [String]
    public var background: String
    public var steamID: String
    public init(name: String = "", summary: String = "", developer: String = "", releaseDate: String = "", artwork: String = "", url: String = "", source: String = "", genres: [String] = [], background: String = "", steamID: String = "") {
        self.name = name; self.summary = summary; self.developer = developer; self.releaseDate = releaseDate; self.artwork = artwork; self.url = url; self.source = source; self.genres = genres; self.background = background; self.steamID = steamID
    }
    public var incomplete: Bool { summary.isEmpty || developer.isEmpty || releaseDate.isEmpty || genres.isEmpty || artwork.isEmpty || background.isEmpty }
    public mutating func fillMissing(from fallback: Metadata) {
        let before = self
        if name.isEmpty { name = fallback.name }
        if summary.isEmpty { summary = fallback.summary }
        if developer.isEmpty { developer = fallback.developer }
        if releaseDate.isEmpty { releaseDate = fallback.releaseDate }
        if artwork.isEmpty { artwork = fallback.artwork }
        if background.isEmpty { background = fallback.background }
        if url.isEmpty { url = fallback.url }
        if genres.isEmpty { genres = fallback.genres }
        if steamID.isEmpty { steamID = fallback.steamID }
        if self != before, !fallback.source.isEmpty, !source.contains(fallback.source) {
            source = source.isEmpty ? fallback.source : source + " + " + fallback.source
        }
    }
    public func applying(to original: Game) -> Game {
        var game = original
        var automatic = game.automaticMetadata ?? game.metadataValues
        if !summary.isEmpty { automatic["summary"] = summary }
        if !developer.isEmpty { automatic["developer"] = developer }
        if !releaseDate.isEmpty { automatic["releaseDate"] = releaseDate }
        if !genres.isEmpty { automatic["genres"] = genres.joined(separator: ", ") }
        automatic["source"] = source
        game.automaticMetadata = automatic
        game.applyMetadataValues(automatic); game.applyMetadataValues(game.metadataOverrides ?? [:])
        if !artwork.isEmpty { game.artwork = artwork }
        if !background.isEmpty { game.backgroundArtwork = background }
        if !url.isEmpty { game.storeURL = url }
        game.metadataSteamId = steamID.isEmpty ? nil : steamID
        game.refreshMetadataSource(); game.metadataUpdated = Date()
        return game
    }
}
public enum LibraryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
public struct LibraryFile: Codable, Equatable, Sendable {
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
    public func replacing(_ game: Game, in library: LibraryFile) throws -> LibraryFile {
        guard let index = library.games.firstIndex(where: { $0.id == game.id }) else { throw LibraryError.invalid("Game no longer exists.") }
        var next = library; next.games[index] = game
        try save(next)
        return next
    }
    public func removing(_ id: String, from library: LibraryFile) throws -> LibraryFile {
        var next = library
        next.games.removeAll { $0.id == id }
        try save(next)
        return next
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
