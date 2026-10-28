import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public enum CachedImageRole: String, Sendable { case any, portrait, landscape, background
    public func fits(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let ratio = Double(width) / Double(height)
        switch self { case .portrait: return (0.52...0.85).contains(ratio); case .landscape: return (1.3...2.7).contains(ratio); default: return true }
    }
    public var maximum: Int { self == .portrait ? 1200 : self == .landscape ? 1200 : 1600 }
}
public actor MediaCache {
    public nonisolated let root: URL
    private let session: URLSession
    public init(root: URL, session: URLSession = .shared) { self.root = root; self.session = session }
    public nonisolated static func identifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public nonisolated static func portraitURL(for game: Game) -> String? {
        var id = game.store == .steam ? game.storeID : ""
        if id.isEmpty, let url = URL(string: game.storeURL), url.host == "store.steampowered.com" {
            let components = url.pathComponents
            if let index = components.firstIndex(of: "app"), index + 1 < components.count { id = components[index + 1] }
        }
        guard let number = UInt64(id), number > 0 else { return nil }
        return "https://cdn.akamai.steamstatic.com/steam/apps/\(number)/library_600x900.jpg"
    }
    public nonisolated static func portraitCandidates(for game: Game) -> [String] {
        guard let standard = portraitURL(for: game) else { return [] }
        return [standard.replacingOccurrences(of: "library_600x900.jpg", with: "library_600x900_2x.jpg"), standard]
    }
    public nonisolated func directory(for gameID: String) -> URL { root.appendingPathComponent(Self.identifier(gameID), isDirectory: true) }
    public nonisolated func file(gameID: String, key: String?) -> URL? {
        guard let key, key.range(of: "^[a-f0-9]{64}\\.png$", options: .regularExpression) != nil else { return nil }
        let url = directory(for: gameID).appendingPathComponent(key)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    public func cache(_ remote: String, gameID: String, role: CachedImageRole = .any) async throws -> String {
        guard let url = URL(string: remote), url.scheme == "https", url.host != nil else { throw LibraryError.invalid("Artwork must use HTTPS.") }
        let key = Self.identifier(remote) + ".png"
        if let existing = file(gameID: gameID, key: key), let source = CGImageSourceCreateWithURL(existing as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int, role.fits(width: width, height: height) { return key }
        guard ProcessInfo.processInfo.environment["PLAYNITE_OFFLINE"] != "1" else { throw LibraryError.invalid("Offline mode: cached artwork remains available.") }
        var request = URLRequest(url: url); request.timeoutInterval = 18
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), http.url?.scheme == "https" else { throw LibraryError.invalid("Artwork download failed.") }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 24_000_000 else { throw LibraryError.invalid("Artwork exceeds the 24 MB limit.") }
        return try store(Data(contentsOf: temporary), gameID: gameID, key: key, role: role)
    }
    @discardableResult public func store(_ data: Data, gameID: String, key: String, role: CachedImageRole = .any) throws -> String {
        guard key.range(of: "^[a-f0-9]{64}\\.png$", options: .regularExpression) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: role.maximum, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw LibraryError.invalid("Artwork is not a supported image.") }
        guard role.fits(width: image.width, height: image.height) else { throw LibraryError.invalid("Artwork does not fit the \(role.rawValue) aspect ratio.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw LibraryError.invalid("Cannot encode cached artwork.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.invalid("Cannot finish cached artwork.") }
        let folder = directory(for: gameID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (output as Data).write(to: folder.appendingPathComponent(key), options: .atomic)
        return key
    }
    public func remove(gameID: String) throws {
        let folder = directory(for: gameID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}
