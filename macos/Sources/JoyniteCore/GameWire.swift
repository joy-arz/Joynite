import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), string(String), integer(Int64), unsigned(UInt64), number(Double), array([JSONValue]), object([String: JSONValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(UInt64.self) { self = .unsigned(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .unsigned(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
private struct WireKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}
extension Game {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: WireKey.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: WireKey("id")) ?? "", name: try c.decodeIfPresent(String.self, forKey: WireKey("name")) ?? "", store: try c.decodeIfPresent(Store.self, forKey: WireKey("store")) ?? .local, launchKind: try c.decodeIfPresent(LaunchKind.self, forKey: WireKey("launchKind")) ?? .application, launchTarget: try c.decodeIfPresent(String.self, forKey: WireKey("launchTarget")) ?? "")
        installPath = try c.decodeIfPresent(String.self, forKey: WireKey("installPath")) ?? ""
        let legacystoreID = try c.decodeIfPresent(String.self, forKey: WireKey("storeId"))
        storeID = try (legacystoreID.flatMap { $0.isEmpty ? nil : $0 } ?? c.decodeIfPresent(String.self, forKey: WireKey("storeID"))) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: WireKey("summary")) ?? ""
        developer = try c.decodeIfPresent(String.self, forKey: WireKey("developer")) ?? ""
        genres = try c.decodeIfPresent([String].self, forKey: WireKey("genres")) ?? []
        releaseDate = try c.decodeIfPresent(String.self, forKey: WireKey("releaseDate")) ?? ""
        artwork = try c.decodeIfPresent(String.self, forKey: WireKey("artwork")) ?? ""
        backgroundArtwork = try c.decodeIfPresent(String.self, forKey: WireKey("backgroundArtwork"))
        cachedArtwork = try c.decodeIfPresent(String.self, forKey: WireKey("cachedArtwork"))
        cachedBackground = try c.decodeIfPresent(String.self, forKey: WireKey("cachedBackground"))
        cachedLandscape = try c.decodeIfPresent(String.self, forKey: WireKey("cachedLandscape"))
        compatibility = try c.decodeIfPresent(CompatibilityLaunch.self, forKey: WireKey("compatibility"))
        metadataOverrides = try c.decodeIfPresent([String: String].self, forKey: WireKey("metadataOverrides"))
        automaticMetadata = try c.decodeIfPresent([String: String].self, forKey: WireKey("automaticMetadata"))
        customArtwork = try c.decodeIfPresent(String.self, forKey: WireKey("customArtwork"))
        customLandscape = try c.decodeIfPresent(String.self, forKey: WireKey("customLandscape"))
        customBackground = try c.decodeIfPresent(String.self, forKey: WireKey("customBackground"))
        hidden = try c.decodeIfPresent(Bool.self, forKey: WireKey("hidden"))
        pendingUninstall = try c.decodeIfPresent(Bool.self, forKey: WireKey("pendingUninstall"))
        let legacystoreURL = try c.decodeIfPresent(String.self, forKey: WireKey("storeUrl"))
        storeURL = try (legacystoreURL.flatMap { $0.isEmpty ? nil : $0 } ?? c.decodeIfPresent(String.self, forKey: WireKey("storeURL"))) ?? ""
        metadataSource = try c.decodeIfPresent(String.self, forKey: WireKey("metadataSource")) ?? ""
        metadataSteamId = try c.decodeIfPresent(String.self, forKey: WireKey("metadataSteamId"))
        metadataUpdated = try c.decodeIfPresent(Date.self, forKey: WireKey("metadataUpdated"))
        favorite = try c.decodeIfPresent(Bool.self, forKey: WireKey("favorite")) ?? false
        launchCount = try c.decodeIfPresent(UInt32.self, forKey: WireKey("launchCount"))
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: WireKey("lastPlayed"))
        addedAt = try c.decodeIfPresent(Date.self, forKey: WireKey("addedAt")) ?? Date()
        let known = Set(["id", "name", "store", "launchKind", "launchTarget", "installPath", "storeID", "summary", "developer", "genres", "releaseDate", "artwork", "backgroundArtwork", "cachedArtwork", "cachedBackground", "cachedLandscape", "compatibility", "metadataOverrides", "automaticMetadata", "customArtwork", "customLandscape", "customBackground", "hidden", "pendingUninstall", "storeURL", "metadataSource", "metadataSteamId", "metadataUpdated", "favorite", "launchCount", "lastPlayed", "addedAt", "storeId", "storeUrl"])
        for key in c.allKeys where !known.contains(key.stringValue) { extra[key.stringValue] = try c.decode(JSONValue.self, forKey: key) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: WireKey.self)
        let known = Set(["id", "name", "store", "launchKind", "launchTarget", "installPath", "storeID", "summary", "developer", "genres", "releaseDate", "artwork", "backgroundArtwork", "cachedArtwork", "cachedBackground", "cachedLandscape", "compatibility", "metadataOverrides", "automaticMetadata", "customArtwork", "customLandscape", "customBackground", "hidden", "pendingUninstall", "storeURL", "metadataSource", "metadataSteamId", "metadataUpdated", "favorite", "launchCount", "lastPlayed", "addedAt", "storeId", "storeUrl"])
        for (key, value) in extra where !known.contains(key) { try c.encode(value, forKey: WireKey(key)) }
        try c.encode(id, forKey: WireKey("id"))
        try c.encode(name, forKey: WireKey("name"))
        try c.encode(store, forKey: WireKey("store"))
        try c.encode(launchKind, forKey: WireKey("launchKind"))
        try c.encode(launchTarget, forKey: WireKey("launchTarget"))
        try c.encode(installPath, forKey: WireKey("installPath"))
        try c.encode(storeID, forKey: WireKey("storeID"))
        try c.encode(summary, forKey: WireKey("summary"))
        try c.encode(developer, forKey: WireKey("developer"))
        try c.encode(genres, forKey: WireKey("genres"))
        try c.encode(releaseDate, forKey: WireKey("releaseDate"))
        try c.encode(artwork, forKey: WireKey("artwork"))
        try c.encodeIfPresent(backgroundArtwork, forKey: WireKey("backgroundArtwork"))
        try c.encodeIfPresent(cachedArtwork, forKey: WireKey("cachedArtwork"))
        try c.encodeIfPresent(cachedBackground, forKey: WireKey("cachedBackground"))
        try c.encodeIfPresent(cachedLandscape, forKey: WireKey("cachedLandscape"))
        try c.encodeIfPresent(compatibility, forKey: WireKey("compatibility"))
        try c.encodeIfPresent(metadataOverrides, forKey: WireKey("metadataOverrides"))
        try c.encodeIfPresent(automaticMetadata, forKey: WireKey("automaticMetadata"))
        try c.encodeIfPresent(customArtwork, forKey: WireKey("customArtwork"))
        try c.encodeIfPresent(customLandscape, forKey: WireKey("customLandscape"))
        try c.encodeIfPresent(customBackground, forKey: WireKey("customBackground"))
        try c.encodeIfPresent(hidden, forKey: WireKey("hidden"))
        try c.encodeIfPresent(pendingUninstall, forKey: WireKey("pendingUninstall"))
        try c.encode(storeURL, forKey: WireKey("storeURL"))
        try c.encode(metadataSource, forKey: WireKey("metadataSource"))
        try c.encodeIfPresent(metadataSteamId, forKey: WireKey("metadataSteamId"))
        try c.encodeIfPresent(metadataUpdated, forKey: WireKey("metadataUpdated"))
        try c.encode(favorite, forKey: WireKey("favorite"))
        try c.encodeIfPresent(launchCount, forKey: WireKey("launchCount"))
        try c.encodeIfPresent(lastPlayed, forKey: WireKey("lastPlayed"))
        try c.encode(addedAt, forKey: WireKey("addedAt"))
    }
}
