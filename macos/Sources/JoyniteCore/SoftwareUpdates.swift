import Foundation

public struct SoftwareVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let parts: [Int]
    public init?(_ raw: String) {
        let text = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        guard !text.contains("-"), text.count <= 80 else { return nil }
        let base = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let components = base.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count), components.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0") && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let values = components.compactMap { Int($0) }
        guard values.count == components.count else { return nil }
        parts = values + Array(repeating: 0, count: 3 - values.count)
    }
    public var description: String { parts.map(String.init).joined(separator: ".") }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
public struct UpdateReminder: Codable, Equatable, Sendable {
    public var skippedVersion: String?
    public var postponedVersion: String?
    public var postponedUntil: Date?
    public init() {}
    public func allows(_ version: String, now: Date = Date()) -> Bool {
        guard SoftwareVersion(skippedVersion ?? "") != SoftwareVersion(version) else { return false }
        return postponedVersion != version || (postponedUntil ?? .distantPast) <= now
    }
    public mutating func skip(_ version: String) { skippedVersion = version; postponedVersion = nil; postponedUntil = nil }
    public mutating func postpone(_ version: String, now: Date = Date()) { postponedVersion = version; postponedUntil = now.addingTimeInterval(24 * 60 * 60) }
}
public struct SoftwareRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browser_download_url: String
        public let size: Int64
    }
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    public var version: SoftwareVersion? { SoftwareVersion(tag_name) }
    public func nativeUpdate(after current: String, architecture: String) -> SoftwareVersion? {
        guard !draft, !prerelease, let version, let installed = SoftwareVersion(current), version > installed else { return nil }
        let name = "Joynite-\(version)-\(architecture).zip"
        func valid(_ name: String) -> Bool {
            assets.contains { asset in
                guard asset.name == name, asset.size > 0, asset.size <= 300_000_000,
                      let url = URLComponents(string: asset.browser_download_url) else { return false }
                return url.scheme == "https" && url.host == "github.com" && url.port == nil && url.user == nil && url.password == nil && url.path == "/joy-arz/Joynite/releases/download/\(tag_name)/\(name)"
            }
        }
        return valid(name) && valid("appcast.xml") ? version : nil
    }
}
public enum SoftwareReleaseClient {
    public static let endpoint = URL(string: "https://api.github.com/repos/joy-arz/Joynite/releases/latest")!
    public static func latest(session: URLSession = .shared) async throws -> SoftwareRelease {
        var request = URLRequest(url: endpoint); request.timeoutInterval = 8; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Joynite-update-check", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == "api.github.com", http.url?.scheme == "https",
              (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2_000_000 else { throw LibraryError.invalid("Update service is unavailable.") }
        return try JSONDecoder().decode(SoftwareRelease.self, from: Data(contentsOf: file))
    }
}
